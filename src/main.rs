use codec_engine::{BackpressurePolicy, CodecError, ExtractorConfig, FrameExtractor};
use std::env;

fn main() -> Result<(), CodecError> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!("Codec Engine Frame Extractor Test Utility");
        println!("Usage: cargo run -- <path-to-video-file>");
        println!("Example: cargo run -- sample.mp4\n");
        println!("No input file specified. Pass a video file path to run frame extraction.");
        return Ok(());
    }

    let video_path = &args[1];
    println!("Starting frame extraction pipeline for: {}", video_path);

    let config = ExtractorConfig {
        channel_capacity: 128,
        prefer_hw_accel: true,
        backpressure: BackpressurePolicy::DropNewest,
        max_consecutive_errors: 64,
        seek_retry_backoff_ticks: 1,
    };

    let (rx, handle) = match FrameExtractor::spawn(video_path, config) {
        Ok(res) => res,
        Err(e) => {
            eprintln!("Error opening video source '{video_path}': {e}");
            return Err(e);
        }
    };

    let mut total_frames = 0u64;
    let mut total_bytes = 0usize;

    for frame in rx.iter() {
        total_frames += 1;
        total_bytes += frame.rgb.len();

        if total_frames <= 5 || total_frames.is_multiple_of(50) {
            println!(
                "[Frame #{}] {}x{} | PTS: {} | Keyframe: {} | Buffer Size: {} KB",
                frame.frame_index,
                frame.width,
                frame.height,
                frame.pts,
                frame.is_keyframe,
                frame.rgb.len() / 1024
            );
        }
    }

    println!("\nExtraction complete.");
    println!("Total Frames Extracted: {total_frames}");
    println!(
        "Total RGB Data Transferred: {:.2} MB",
        total_bytes as f64 / (1024.0 * 1024.0)
    );

    match handle.join() {
        Ok(Ok(())) => println!("Decode thread finished cleanly (EOF reached)."),
        Ok(Err(e)) => eprintln!("Decode thread stopped with error: {e}"),
        Err(_) => eprintln!("Decode thread panicked!"),
    }

    Ok(())
}
