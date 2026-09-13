//! =====================================================================================
//! frame_extractor.rs
//!
//! Enterprise-grade, panic-free video frame extraction pipeline built on `ffmpeg-next`.
//!
//! Pipeline:
//!   Demux (AVFormatContext) -> Decode (AVCodecContext, HW-accelerated w/ SW fallback)
//!     -> Bitstream fault recovery (seek-to-next-keyframe on corruption/EAGAIN storms)
//!     -> Colorspace conversion (libswscale -> RGB24)
//!     -> Lock-free bounded handoff (crossbeam_channel) to downstream consumers
//! =====================================================================================

use crossbeam_channel::{bounded, Receiver, Sender};
use ffmpeg::ffi as avffi;
use ffmpeg::format::context::input::Input;
use ffmpeg::format::{input as ff_input, Pixel};
use ffmpeg::media::Type as MediaType;
use ffmpeg::software::scaling::{context::Context as SwsContext, flag::Flags as SwsFlags};
use ffmpeg::util::frame::video::Video as VideoFrame;
use ffmpeg::{codec, decoder, Error as FfError, Packet, Rational};
use ffmpeg_next as ffmpeg;
use log::{debug, error, info, warn};
use std::path::Path;
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread::{self, JoinHandle};
use thiserror::Error;

// =====================================================================================
// Errors
// =====================================================================================

#[derive(Debug, Error)]
pub enum CodecError {
    #[error("failed to open input source: {0}")]
    OpenInput(#[source] FfError),

    #[error("no suitable video stream found in container")]
    NoVideoStream,

    #[error("failed to construct decoder: {0}")]
    DecoderInit(String),

    #[error("hardware accelerator init failed ({hw_type}): {reason}")]
    HwAccelInit { hw_type: String, reason: String },

    #[error("failed to (re)build swscale context: {0}")]
    ScalerInit(String),

    #[error("ffmpeg internal error: {0}")]
    Ffmpeg(#[from] FfError),

    #[error("seek operation failed while attempting stream recovery: {0}")]
    SeekFailed(String),

    #[error("downstream channel disconnected; consumer likely dropped")]
    ChannelClosed,

    #[error("exceeded maximum consecutive decode errors ({0}); aborting stream")]
    TooManyConsecutiveErrors(usize),
}

// =====================================================================================
// Public payload / config types
// =====================================================================================

/// A fully decoded, colorspace-converted frame ready for downstream consumption.
#[derive(Debug, Clone)]
pub struct FramePayload {
    /// Tightly packed RGB24 buffer (no stride padding), length == width * height * 3.
    pub rgb: Vec<u8>,
    pub pts: i64,
    pub dts: i64,
    pub frame_index: u64,
    pub width: u32,
    pub height: u32,
    pub is_keyframe: bool,
}

/// Behavior when the bounded output channel is full. Real-time pipelines typically
/// prefer to drop the oldest/newest frame rather than stall the decode thread.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackpressurePolicy {
    /// Block the decoder thread until space is available (lossless, higher latency).
    Block,
    /// Drop the frame being produced if the channel is full (lowest latency).
    DropNewest,
}

#[derive(Debug, Clone)]
pub struct ExtractorConfig {
    pub channel_capacity: usize,
    pub prefer_hw_accel: bool,
    pub backpressure: BackpressurePolicy,
    /// After this many consecutive corrupt-packet/decode errors without a successful
    /// frame, give up and return `TooManyConsecutiveErrors` instead of looping forever.
    pub max_consecutive_errors: usize,
    /// How far forward (in stream time_base units) to nudge the seek target on each
    /// successive recovery attempt if the first seek doesn't land on a clean keyframe.
    pub seek_retry_backoff_ticks: i64,
}

impl Default for ExtractorConfig {
    fn default() -> Self {
        Self {
            channel_capacity: 64,
            prefer_hw_accel: true,
            backpressure: BackpressurePolicy::Block,
            max_consecutive_errors: 32,
            seek_retry_backoff_ticks: 0,
        }
    }
}

// =====================================================================================
// HW device context wrapper (raw AVBufferRef is not Send/Sync by default)
// =====================================================================================

struct HwDeviceCtx(*mut avffi::AVBufferRef);

// SAFETY: We only ever touch this pointer from the single decoder thread that owns
// the `FrameExtractor`. It is created once, used to populate the codec context, and
// freed exactly once in `Drop`. No concurrent access occurs.
unsafe impl Send for HwDeviceCtx {}

impl Drop for HwDeviceCtx {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: `self.0` was obtained from `av_hwdevice_ctx_create` and has not
            // been freed elsewhere. `av_buffer_unref` is the documented teardown path.
            unsafe { avffi::av_buffer_unref(&mut self.0) };
        }
    }
}

/// Target hardware accelerator selection, resolved per-platform at compile time with
/// a runtime probe to confirm the driver/device is actually available.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
enum HwKind {
    VideoToolbox,
    Cuda,
    None,
}

#[cfg(target_os = "macos")]
const PLATFORM_HW: HwKind = HwKind::VideoToolbox;
#[cfg(all(
    not(target_os = "macos"),
    any(target_os = "linux", target_os = "windows")
))]
const PLATFORM_HW: HwKind = HwKind::Cuda;
#[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
const PLATFORM_HW: HwKind = HwKind::None;

impl HwKind {
    fn av_type(self) -> avffi::AVHWDeviceType {
        match self {
            HwKind::VideoToolbox => avffi::AVHWDeviceType::AV_HWDEVICE_TYPE_VIDEOTOOLBOX,
            HwKind::Cuda => avffi::AVHWDeviceType::AV_HWDEVICE_TYPE_CUDA,
            HwKind::None => avffi::AVHWDeviceType::AV_HWDEVICE_TYPE_NONE,
        }
    }

    fn label(self) -> &'static str {
        match self {
            HwKind::VideoToolbox => "videotoolbox",
            HwKind::Cuda => "cuda",
            HwKind::None => "none",
        }
    }
}

// =====================================================================================
// FrameExtractor
// =====================================================================================

pub struct FrameExtractor {
    input: Input,
    video_stream_index: usize,
    time_base: Rational,
    decoder: decoder::Video,
    scaler: Option<SwsContext>,
    scaler_src_fmt: Option<(Pixel, u32, u32)>,
    _hw_device: Option<HwDeviceCtx>,
    hw_active: bool,
    sender: Sender<FramePayload>,
    config: ExtractorConfig,
    frame_index: AtomicU64,
    last_good_pts: i64,
}

// SAFETY: `FrameExtractor` is owned uniquely by the dedicated decode thread spawned
// in `spawn()`. The `SwsContext` pointer contained within `scaler` is accessed solely
// by this single thread.
unsafe impl Send for FrameExtractor {}

pub type FrameReceiver = Receiver<FramePayload>;
pub type DecodeHandle = JoinHandle<Result<(), CodecError>>;

impl FrameExtractor {
    /// Opens `path` (file path or network URL -- anything `avformat_open_input` accepts)
    /// and spawns a dedicated decode thread. Returns a receiver for decoded frames and
    /// a join handle that resolves to `Ok(())` on clean EOF or `Err(CodecError)` on an
    /// unrecoverable failure (e.g. too many consecutive corrupt packets).
    pub fn spawn<P: AsRef<Path>>(
        path: P,
        config: ExtractorConfig,
    ) -> Result<(FrameReceiver, DecodeHandle), CodecError> {
        ffmpeg::init().map_err(CodecError::Ffmpeg)?;

        let (tx, rx) = bounded::<FramePayload>(config.channel_capacity.max(1));
        let mut extractor = Self::open(path, tx, config)?;

        let handle = thread::Builder::new()
            .name("frame-extractor-decode".into())
            .spawn(move || extractor.run())
            .map_err(|e| CodecError::DecoderInit(format!("failed to spawn decode thread: {e}")))?;

        Ok((rx, handle))
    }

    fn open<P: AsRef<Path>>(
        path: P,
        sender: Sender<FramePayload>,
        config: ExtractorConfig,
    ) -> Result<Self, CodecError> {
        let path_ref = path.as_ref();
        let input = ff_input(&path_ref).map_err(CodecError::OpenInput)?;

        let stream = input
            .streams()
            .best(MediaType::Video)
            .ok_or(CodecError::NoVideoStream)?;
        let video_stream_index = stream.index();
        let time_base = stream.time_base();

        let codec_params = stream.parameters();

        let (decoder, hw_device, hw_active) = if config.prefer_hw_accel {
            let ctx = codec::context::Context::from_parameters(codec_params.clone())
                .map_err(|e| CodecError::DecoderInit(format!("from_parameters failed: {e}")))?;
            match Self::try_open_hw_decoder(ctx) {
                Ok((dec, hw)) => {
                    info!(
                        "hardware decoder initialized successfully ({})",
                        PLATFORM_HW.label()
                    );
                    (dec, Some(hw), true)
                }
                Err(e) => {
                    warn!(
                        "hw accel init failed ({}), falling back to software decode: {e}",
                        PLATFORM_HW.label()
                    );
                    let ctx =
                        codec::context::Context::from_parameters(codec_params).map_err(|e| {
                            CodecError::DecoderInit(format!("from_parameters failed: {e}"))
                        })?;
                    let dec = Self::open_sw_decoder(ctx)?;
                    (dec, None, false)
                }
            }
        } else {
            let ctx = codec::context::Context::from_parameters(codec_params)
                .map_err(|e| CodecError::DecoderInit(format!("from_parameters failed: {e}")))?;
            let dec = Self::open_sw_decoder(ctx)?;
            (dec, None, false)
        };

        Ok(Self {
            input,
            video_stream_index,
            time_base,
            decoder,
            scaler: None,
            scaler_src_fmt: None,
            _hw_device: hw_device,
            hw_active,
            sender,
            config,
            frame_index: AtomicU64::new(0),
            last_good_pts: 0,
        })
    }

    fn open_sw_decoder(ctx: codec::context::Context) -> Result<decoder::Video, CodecError> {
        ctx.decoder()
            .video()
            .map_err(|e| CodecError::DecoderInit(format!("software decoder open failed: {e}")))
    }

    /// Attempts to attach a hardware device context to the decoder's `AVCodecContext`.
    /// Sets `hw_device_ctx` BEFORE opening the codec with `.video()` (`avcodec_open2`).
    fn try_open_hw_decoder(
        mut ctx: codec::context::Context,
    ) -> Result<(decoder::Video, HwDeviceCtx), CodecError> {
        if PLATFORM_HW == HwKind::None {
            return Err(CodecError::HwAccelInit {
                hw_type: "none".into(),
                reason: "no supported hw backend on this platform".into(),
            });
        }

        let mut hw_device_ctx: *mut avffi::AVBufferRef = ptr::null_mut();

        // SAFETY: `av_hwdevice_ctx_create` is the documented FFmpeg entry point for
        // probing/creating a hardware device of the given type.
        let ret = unsafe {
            avffi::av_hwdevice_ctx_create(
                &mut hw_device_ctx,
                PLATFORM_HW.av_type(),
                ptr::null(),
                ptr::null_mut(),
                0,
            )
        };

        if ret < 0 || hw_device_ctx.is_null() {
            return Err(CodecError::HwAccelInit {
                hw_type: PLATFORM_HW.label().into(),
                reason: format!("av_hwdevice_ctx_create returned {ret}"),
            });
        }

        let hw_guard = HwDeviceCtx(hw_device_ctx);

        // SAFETY: `hw_device_ctx` MUST be assigned to the `AVCodecContext` BEFORE
        // `avcodec_open2` is called. We populate `ctx.as_mut_ptr()->hw_device_ctx` first,
        // then invoke `.video()` which internally opens the codec context.
        unsafe {
            let raw = ctx.as_mut_ptr();
            if raw.is_null() {
                return Err(CodecError::HwAccelInit {
                    hw_type: PLATFORM_HW.label().into(),
                    reason: "null AVCodecContext pointer".into(),
                });
            }
            let refd = avffi::av_buffer_ref(hw_guard.0);
            if refd.is_null() {
                return Err(CodecError::HwAccelInit {
                    hw_type: PLATFORM_HW.label().into(),
                    reason: "av_buffer_ref returned null".into(),
                });
            }
            (*raw).hw_device_ctx = refd;
        }

        let decoder = ctx
            .decoder()
            .video()
            .map_err(|e| CodecError::DecoderInit(format!("video() failed: {e}")))?;

        Ok((decoder, hw_guard))
    }

    /// Main decode loop. Runs on the dedicated thread spawned by `spawn`. Never panics;
    /// every error path either recovers (log + skip + seek-to-keyframe) or returns a
    /// typed `CodecError` to the caller via the `JoinHandle`.
    fn run(&mut self) -> Result<(), CodecError> {
        let mut consecutive_errors: usize = 0;

        'outer: loop {
            let packet = match self
                .input
                .packets()
                .find(|(s, _)| s.index() == self.video_stream_index)
            {
                None => {
                    // Clean EOF at the demux level: flush remaining frames then finish.
                    self.flush_decoder()?;
                    info!("reached end of stream; flushed decoder, shutting down cleanly");
                    return Ok(());
                }
                Some((_, pkt)) => pkt,
            };

            match self.process_packet(&packet) {
                Ok(frames_emitted) => {
                    if frames_emitted > 0 {
                        consecutive_errors = 0;
                    }
                }
                Err(CodecError::ChannelClosed) => {
                    debug!("consumer dropped receiver; stopping decode thread gracefully");
                    return Ok(());
                }
                Err(e) => {
                    consecutive_errors += 1;
                    warn!(
                        "decode error on packet (dts={:?}): {e}. attempting bitstream recovery \
                         (attempt {consecutive_errors}/{})",
                        packet.dts(),
                        self.config.max_consecutive_errors
                    );

                    if consecutive_errors >= self.config.max_consecutive_errors {
                        error!(
                            "exceeded max consecutive decode errors ({}); aborting stream",
                            self.config.max_consecutive_errors
                        );
                        return Err(CodecError::TooManyConsecutiveErrors(
                            self.config.max_consecutive_errors,
                        ));
                    }

                    match self.recover_to_next_keyframe(consecutive_errors) {
                        Ok(()) => {
                            info!("bitstream recovery succeeded; resuming decode");
                            continue 'outer;
                        }
                        Err(seek_err) => {
                            warn!("seek-based recovery failed: {seek_err}; continuing linearly");
                        }
                    }
                }
            }
        }
    }

    /// Feeds one packet to the decoder and drains all frames it produces. Handles EAGAIN
    /// by draining available frames and retrying the *same* packet so data is not lost.
    fn process_packet(&mut self, packet: &Packet) -> Result<usize, CodecError> {
        let mut emitted = 0usize;
        let mut raw_frame = VideoFrame::empty();

        // 1. Send loop with EAGAIN retry logic
        loop {
            match self.decoder.send_packet(packet) {
                Ok(()) => break,
                Err(FfError::Other { errno }) if errno == avffi::EAGAIN => {
                    debug!("decoder returned EAGAIN on send_packet; draining output frames before retry");
                    let mut drained = 0;
                    loop {
                        match self.decoder.receive_frame(&mut raw_frame) {
                            Ok(()) => {
                                self.handle_decoded_frame(&raw_frame, packet.is_key())?;
                                emitted += 1;
                                drained += 1;
                            }
                            Err(FfError::Other { errno }) if errno == avffi::EAGAIN => break,
                            Err(FfError::Eof) => break,
                            Err(e) => return Err(CodecError::Ffmpeg(e)),
                        }
                    }
                    if drained == 0 {
                        // Prevent infinite loop if send_packet consistently yields EAGAIN without producing frames
                        break;
                    }
                }
                Err(FfError::Eof) => {
                    self.flush_decoder()?;
                    return Ok(emitted);
                }
                Err(e) => return Err(CodecError::Ffmpeg(e)),
            }
        }

        // 2. Receive loop: drain all frames available for the accepted packet
        loop {
            match self.decoder.receive_frame(&mut raw_frame) {
                Ok(()) => {
                    self.handle_decoded_frame(&raw_frame, packet.is_key())?;
                    emitted += 1;
                }
                Err(FfError::Other { errno }) if errno == avffi::EAGAIN => break,
                Err(FfError::Eof) => break,
                Err(e) => return Err(CodecError::Ffmpeg(e)),
            }
        }

        Ok(emitted)
    }

    fn flush_decoder(&mut self) -> Result<(), CodecError> {
        if self.decoder.send_eof().is_ok() {
            let mut raw_frame = VideoFrame::empty();
            while let Ok(()) = self.decoder.receive_frame(&mut raw_frame) {
                self.handle_decoded_frame(&raw_frame, false)?;
            }
        }
        Ok(())
    }

    /// Converts a decoded (possibly hardware-resident) frame to packed RGB24 and pushes
    /// it downstream.
    fn handle_decoded_frame(
        &mut self,
        frame: &VideoFrame,
        packet_is_key: bool,
    ) -> Result<(), CodecError> {
        let sw_frame_storage;
        let sw_frame: &VideoFrame = if self.hw_active && Self::is_hw_pixel_format(frame.format()) {
            sw_frame_storage = self.transfer_hw_frame(frame)?;
            &sw_frame_storage
        } else {
            frame
        };

        let (w, h) = (sw_frame.width(), sw_frame.height());
        if w == 0 || h == 0 {
            warn!("dropping frame with degenerate dimensions {w}x{h}");
            return Ok(());
        }

        self.ensure_scaler(sw_frame.format(), w, h)?;
        let scaler = self
            .scaler
            .as_mut()
            .ok_or_else(|| CodecError::ScalerInit("scaler unexpectedly absent".into()))?;

        let mut rgb_frame = VideoFrame::empty();
        scaler
            .run(sw_frame, &mut rgb_frame)
            .map_err(|e| CodecError::ScalerInit(format!("sws_scale failed: {e}")))?;

        let rgb_bytes = Self::pack_rgb24(&rgb_frame, w, h);

        let pts = sw_frame.pts().unwrap_or(self.last_good_pts);
        let dts = pts;
        self.last_good_pts = pts;

        let payload = FramePayload {
            rgb: rgb_bytes,
            pts,
            dts,
            frame_index: self.frame_index.fetch_add(1, Ordering::Relaxed),
            width: w,
            height: h,
            is_keyframe: packet_is_key || sw_frame.is_key(),
        };

        self.dispatch(payload)
    }

    fn dispatch(&self, payload: FramePayload) -> Result<(), CodecError> {
        match self.config.backpressure {
            BackpressurePolicy::Block => self
                .sender
                .send(payload)
                .map_err(|_| CodecError::ChannelClosed),
            BackpressurePolicy::DropNewest => match self.sender.try_send(payload) {
                Ok(()) => Ok(()),
                Err(crossbeam_channel::TrySendError::Full(_)) => {
                    debug!("output channel full; dropping newest frame per policy");
                    Ok(())
                }
                Err(crossbeam_channel::TrySendError::Disconnected(_)) => {
                    Err(CodecError::ChannelClosed)
                }
            },
        }
    }

    fn ensure_scaler(&mut self, fmt: Pixel, w: u32, h: u32) -> Result<(), CodecError> {
        let key = (fmt, w, h);
        if self.scaler_src_fmt == Some(key) && self.scaler.is_some() {
            return Ok(());
        }

        let ctx = SwsContext::get(fmt, w, h, Pixel::RGB24, w, h, SwsFlags::BILINEAR)
            .map_err(|e| CodecError::ScalerInit(format!("SwsContext::get failed: {e}")))?;

        self.scaler = Some(ctx);
        self.scaler_src_fmt = Some(key);
        debug!("rebuilt swscale context for {fmt:?} {w}x{h} -> RGB24");
        Ok(())
    }

    /// Strips row padding/stride from the scaler's output frame into a tightly packed
    /// `Vec<u8>` of length `width * height * 3`. Handles negative linesizes safely.
    fn pack_rgb24(frame: &VideoFrame, width: u32, height: u32) -> Vec<u8> {
        let stride = frame.stride(0) as isize;
        let data = frame.data(0);
        let row_bytes = (width as usize) * 3;
        let h = height as usize;
        let mut out = Vec::with_capacity(row_bytes * h);

        if stride >= row_bytes as isize {
            let stride = stride as usize;
            for row in 0..h {
                let start = row * stride;
                let end = start + row_bytes;
                if end <= data.len() {
                    out.extend_from_slice(&data[start..end]);
                } else {
                    out.resize(out.len() + row_bytes, 0);
                }
            }
        } else if stride < 0 {
            // Negative linesize (vertically flipped memory layout)
            let abs_stride = stride.unsigned_abs();
            if abs_stride >= row_bytes {
                for row in (0..h).rev() {
                    let start = row * abs_stride;
                    let end = start + row_bytes;
                    if end <= data.len() {
                        out.extend_from_slice(&data[start..end]);
                    } else {
                        out.resize(out.len() + row_bytes, 0);
                    }
                }
            } else {
                out.resize(row_bytes * h, 0);
            }
        } else {
            out.resize(row_bytes * h, 0);
        }
        out
    }

    fn is_hw_pixel_format(fmt: Pixel) -> bool {
        matches!(
            fmt,
            Pixel::VIDEOTOOLBOX | Pixel::CUDA | Pixel::D3D11 | Pixel::VAAPI
        )
    }

    /// Copies a hardware-resident frame into a newly allocated system-memory frame via
    /// `av_hwframe_transfer_data`, and copies metadata properties (PTS, DTS, duration).
    fn transfer_hw_frame(&self, hw_frame: &VideoFrame) -> Result<VideoFrame, CodecError> {
        let mut sw_frame = VideoFrame::empty();

        // SAFETY: `sw_frame` and `hw_frame` contain valid pointers. `av_hwframe_transfer_data`
        // transfers raw frame data from GPU memory to CPU system memory.
        let ret =
            unsafe { avffi::av_hwframe_transfer_data(sw_frame.as_mut_ptr(), hw_frame.as_ptr(), 0) };

        if ret < 0 {
            return Err(CodecError::Ffmpeg(FfError::Other { errno: -ret }));
        }

        // SAFETY: Copy frame properties (PTS, DTS, duration, flags) from HW frame to SW frame.
        unsafe {
            avffi::av_frame_copy_props(sw_frame.as_mut_ptr(), hw_frame.as_ptr());
        }

        Ok(sw_frame)
    }

    /// Seeks the demuxer forward to the nearest following keyframe and flushes decoder
    /// state, discarding packets until a clean keyframe packet is observed.
    fn recover_to_next_keyframe(&mut self, attempt: usize) -> Result<(), CodecError> {
        self.decoder.flush();

        let backoff = self.config.seek_retry_backoff_ticks.max(1) * attempt as i64;
        let stream_target_ts = self.last_good_pts.saturating_add(backoff.max(1));

        // Rescale stream time_base units to AV_TIME_BASE (microseconds) for global Input::seek
        let time_base_sec = f64::from(self.time_base);
        let target_micros = (stream_target_ts as f64 * time_base_sec * 1_000_000.0) as i64;

        self.input
            .seek(target_micros, target_micros..i64::MAX)
            .map_err(|e| CodecError::SeekFailed(format!("{e}")))?;

        const MAX_DISCARD_ATTEMPTS: usize = 256;
        for _ in 0..MAX_DISCARD_ATTEMPTS {
            match self
                .input
                .packets()
                .find(|(s, _)| s.index() == self.video_stream_index)
            {
                None => {
                    return Err(CodecError::SeekFailed(
                        "reached EOF while searching for resync keyframe".into(),
                    ))
                }
                Some((_, pkt)) => {
                    if pkt.is_key() {
                        match self.process_packet(&pkt) {
                            Ok(_) => return Ok(()),
                            Err(e) => {
                                warn!("keyframe packet post-seek also failed to decode: {e}");
                                continue;
                            }
                        }
                    }
                }
            }
        }

        Err(CodecError::SeekFailed(
            "exceeded max discard attempts searching for keyframe".into(),
        ))
    }
}

// =====================================================================================
// Tests
// =====================================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extractor_config_defaults() {
        let config = ExtractorConfig::default();
        assert_eq!(config.channel_capacity, 64);
        assert!(config.prefer_hw_accel);
        assert_eq!(config.backpressure, BackpressurePolicy::Block);
        assert_eq!(config.max_consecutive_errors, 32);
    }

    #[test]
    fn test_open_nonexistent_file_returns_error() {
        let config = ExtractorConfig::default();
        let result = FrameExtractor::spawn("non_existent_file_12345.mp4", config);
        assert!(result.is_err());
        match result {
            Err(CodecError::OpenInput(_)) => {}
            Err(e) => panic!("Expected CodecError::OpenInput, got: {:?}", e),
            Ok(_) => panic!("Expected error for non-existent file"),
        }
    }
}
