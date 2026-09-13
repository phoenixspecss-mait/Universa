#include "clip_validator.h"

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/error.h>
}

#include <exception>

ClipValidator::ClipValidator() = default;
ClipValidator::~ClipValidator() = default;

ValidationResult ClipValidator::validate(const std::string& filePath) {
    ValidationResult result;
    result.is_valid = false;
    result.duration_seconds = 0.0;
    result.width = 0;
    result.height = 0;

    try {
        av_log_set_level(AV_LOG_QUIET);

        AVFormatContext* formatContext = nullptr;
        int ret = avformat_open_input(&formatContext, filePath.c_str(), nullptr, nullptr);
        if (ret < 0) {
            char err[AV_ERROR_MAX_STRING_SIZE] = {0};
            av_strerror(ret, err, sizeof(err));
            result.error_message = err;
            return result;
        }

        ret = avformat_find_stream_info(formatContext, nullptr);
        if (ret < 0) {
            char err[AV_ERROR_MAX_STRING_SIZE] = {0};
            av_strerror(ret, err, sizeof(err));
            result.error_message = err;
            avformat_close_input(&formatContext);
            return result;
        }

        int videoStreamIndex = -1;
        for (unsigned int i = 0; i < formatContext->nb_streams; ++i) {
            if (formatContext->streams[i]->codecpar &&
                formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                videoStreamIndex = (int)i;
                break;
            }
        }

        if (videoStreamIndex == -1) {
            result.error_message = "No video stream found in container";
            avformat_close_input(&formatContext);
            return result;
        }

        AVStream* videoStream = formatContext->streams[videoStreamIndex];
        AVCodecParameters* codecPar = videoStream->codecpar;

        if (formatContext->duration != AV_NOPTS_VALUE && formatContext->duration > 0) {
            result.duration_seconds = static_cast<double>(formatContext->duration) / AV_TIME_BASE;
        } else if (videoStream->duration != AV_NOPTS_VALUE && videoStream->duration > 0) {
            result.duration_seconds = static_cast<double>(videoStream->duration) * av_q2d(videoStream->time_base);
        }

        const AVCodec* decoder = avcodec_find_decoder(codecPar->codec_id);
        if (!decoder) {
            result.error_message = "Unsupported video codec";
            avformat_close_input(&formatContext);
            return result;
        }
        result.codec_name = decoder->name ? decoder->name : "unknown";

        AVCodecContext* codecContext = avcodec_alloc_context3(decoder);
        if (!codecContext) {
            result.error_message = "Failed to allocate codec context";
            avformat_close_input(&formatContext);
            return result;
        }

        ret = avcodec_parameters_to_context(codecContext, codecPar);
        if (ret < 0) {
            char err[AV_ERROR_MAX_STRING_SIZE] = {0};
            av_strerror(ret, err, sizeof(err));
            result.error_message = err;
            avcodec_free_context(&codecContext);
            avformat_close_input(&formatContext);
            return result;
        }

        ret = avcodec_open2(codecContext, decoder, nullptr);
        if (ret < 0) {
            char err[AV_ERROR_MAX_STRING_SIZE] = {0};
            av_strerror(ret, err, sizeof(err));
            result.error_message = err;
            avcodec_free_context(&codecContext);
            avformat_close_input(&formatContext);
            return result;
        }

        AVPacket* packet = av_packet_alloc();
        AVFrame* frame = av_frame_alloc();
        int decodedFrames = 0;

        while (av_read_frame(formatContext, packet) >= 0) {
            if (packet->stream_index == videoStreamIndex) {
                int sendRet = avcodec_send_packet(codecContext, packet);
                if (sendRet >= 0) {
                    while (avcodec_receive_frame(codecContext, frame) >= 0) {
                        decodedFrames++;
                        if (decodedFrames >= 3) break;
                    }
                }
            }
            av_packet_unref(packet);
            if (decodedFrames >= 3) break;
        }

        if (decodedFrames > 0) {
            result.is_valid = true;
            result.width = codecContext->width;
            result.height = codecContext->height;
        } else {
            result.is_valid = false;
            result.error_message = "Failed to decode any video frames";
        }

        av_frame_free(&frame);
        av_packet_free(&packet);
        avcodec_free_context(&codecContext);
        avformat_close_input(&formatContext);
    } catch (const std::exception& e) {
        result.is_valid = false;
        result.error_message = e.what();
    } catch (...) {
        result.is_valid = false;
        result.error_message = "Unexpected failure during validation";
    }

    return result;
}

