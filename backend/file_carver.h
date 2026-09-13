#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include <cstddef>

enum class CarverSignature {
    MP4_MOV,
    H264_ANNEX_B,
    DVR_MOCK,
    UNKNOWN
};

struct CarvedChunk {
    uint64_t offset = 0;
    uint64_t length = 0;
    CarverSignature signature = CarverSignature::UNKNOWN;
    std::string signature_name;
    std::string output_path;
    bool is_fragment = false;
};

class FileCarver {
public:
    FileCarver(size_t maxChunkSize = 50 * 1024 * 1024, size_t minChunkSize = 4 * 1024);

    void setMaxChunkSize(size_t size);
    void setMinChunkSize(size_t size);

    std::vector<CarvedChunk> carve(const std::string& diskImagePath, const std::string& outputDir);

private:
    size_t maxChunkSize;
    size_t minChunkSize;

    static std::string signatureToString(CarverSignature sig);
    static std::string extensionForSignature(CarverSignature sig);
};

