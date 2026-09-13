#pragma once
#include <cstddef>

namespace universa {
    constexpr size_t CARVER_BUFFER_SIZE = 65536;       // 64KB read buffer
    constexpr size_t CARVER_OVERLAP_MARGIN = 32;       // overlap for split signatures
    constexpr size_t FRAGMENT_THRESHOLD = 4096;        // chunks below this go to fragments/
    constexpr size_t HASH_BUFFER_SIZE = 65536;         // SHA/MD5 read buffer
    constexpr time_t FALLBACK_EPOCH = 1767225600;      // Jan 1 2026 UTC
    constexpr double AI_SAMPLE_INTERVAL = 2.0;         // seconds between AI frame samples
    constexpr float AI_CONFIDENCE_THRESHOLD = 0.4f;
    constexpr float AI_NMS_THRESHOLD = 0.4f;
    constexpr int AI_INPUT_WIDTH = 416;
    constexpr int AI_INPUT_HEIGHT = 416;
    constexpr size_t DISK_IMAGER_BUFFER_SIZE = 1048576; // 1MB block size for disk acquisition
    constexpr size_t FILE_READ_CHUNK_SIZE = 8192;      // 8KB standard I/O chunk
}
