#pragma once

#include <string>
#include <cstdint>
#include <functional>

namespace universa {

struct AcquisitionResult {
    bool success = false;
    std::string source_path;
    std::string destination_path;
    uint64_t bytes_acquired = 0;
    std::string sha256_hash;
    std::string md5_hash;
    double duration_seconds = 0.0;
    std::string start_time_utc;
    std::string end_time_utc;
    std::string error_message;
};

class DiskImager {
public:
    using ProgressCallback = std::function<void(uint64_t bytesDone, uint64_t totalEstimate)>;

    /// Performs bit-stream forensic disk acquisition with on-the-fly SHA-256 and MD5 hashing.
    static AcquisitionResult acquire(
        const std::string& sourceDeviceOrFile,
        const std::string& destinationImagePath,
        ProgressCallback progress = nullptr
    );
};

} // namespace universa
