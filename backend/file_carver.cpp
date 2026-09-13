#include "file_carver.h"

#include <fstream>
#include <vector>
#include <cstring>
#include <algorithm>
#include <filesystem>
#include <iomanip>
#include <sstream>

namespace fs = std::filesystem;

struct RawMatch {
    uint64_t offset;
    CarverSignature signature;
};

FileCarver::FileCarver(size_t maxChunkSize, size_t minChunkSize)
    : maxChunkSize(maxChunkSize), minChunkSize(minChunkSize) {}

void FileCarver::setMaxChunkSize(size_t size) {
    maxChunkSize = size;
}

void FileCarver::setMinChunkSize(size_t size) {
    minChunkSize = size;
}

std::string FileCarver::signatureToString(CarverSignature sig) {
    switch (sig) {
        case CarverSignature::MP4_MOV: return "MP4/MOV";
        case CarverSignature::H264_ANNEX_B: return "H.264 Annex-B";
        case CarverSignature::DVR_MOCK: return "DVR-MOCK";
        default: return "UNKNOWN";
    }
}

std::string FileCarver::extensionForSignature(CarverSignature sig) {
    switch (sig) {
        case CarverSignature::MP4_MOV: return ".mp4";
        case CarverSignature::H264_ANNEX_B: return ".h264";
        case CarverSignature::DVR_MOCK: return ".dav";
        default: return ".bin";
    }
}

static inline bool isValidH264NalByte(uint8_t byte) {
    if (byte & 0x80) return false;
    uint8_t type = byte & 0x1F;
    return type == 7 || type == 9;
}

static uint64_t getMp4BoxLength(std::ifstream& in, uint64_t offset, uint64_t maxLimit) {
    in.clear();
    std::streampos orig = in.tellg();
    static const char* validBoxes[] = {
        "ftyp", "moov", "mdat", "free", "skip", "wide", "meta", "pdin",
        "styp", "sidx", "moof", "traf", "mfra"
    };

    uint64_t pos = offset;
    uint64_t total = 0;
    while (pos + 8 <= maxLimit) {
        in.seekg(pos, std::ios::beg);
        uint8_t hdr[8];
        in.read(reinterpret_cast<char*>(hdr), 8);
        if (in.gcount() < 8) break;

        uint32_t bsize = ((uint32_t)hdr[0] << 24) |
                         ((uint32_t)hdr[1] << 16) |
                         ((uint32_t)hdr[2] << 8)  |
                         (uint32_t)hdr[3];

        char btype[5] = {0};
        std::memcpy(btype, hdr + 4, 4);

        bool isValid = false;
        for (const char* vb : validBoxes) {
            if (std::memcmp(btype, vb, 4) == 0) {
                isValid = true;
                break;
            }
        }
        if (!isValid || bsize < 8) break;

        uint64_t actualSize = bsize;
        if (bsize == 1) {
            uint8_t ext[8];
            in.read(reinterpret_cast<char*>(ext), 8);
            if (in.gcount() < 8) break;
            actualSize = 0;
            for (int k = 0; k < 8; ++k) actualSize = (actualSize << 8) | ext[k];
        }

        if (pos + actualSize > maxLimit) break;

        if (actualSize > 64) {
            uint64_t checkLen = std::min((uint64_t)4096, actualSize - 8);
            std::vector<char> checkBuf(checkLen);
            in.read(checkBuf.data(), checkLen);
            std::streamsize readBytes = in.gcount();
            std::string checkStr(checkBuf.data(), readBytes);
            if (checkStr.find("ftyp") != std::string::npos || checkStr.find("DVR-MOCK") != std::string::npos) {
                break;
            }
        }

        pos += actualSize;
        total = pos - offset;
    }

    in.clear();
    in.seekg(orig, std::ios::beg);
    return total;
}

std::vector<CarvedChunk> FileCarver::carve(const std::string& diskImagePath, const std::string& outputDir) {
    std::ifstream in(diskImagePath, std::ios::binary);
    if (!in.is_open()) return {};

    in.seekg(0, std::ios::end);
    uint64_t totalSize = in.tellg();
    in.seekg(0, std::ios::beg);

    if (totalSize == 0) return {};

    std::vector<RawMatch> matches;
    std::vector<uint8_t> window;
    const size_t chunkSize = 65536;
    const size_t overlapMargin = 32;
    std::vector<char> readBuffer(chunkSize);
    uint64_t windowBaseOffset = 0;

    while (true) {
        in.read(readBuffer.data(), readBuffer.size());
        std::streamsize bytesRead = in.gcount();
        if (bytesRead > 0) {
            window.insert(window.end(), readBuffer.data(), readBuffer.data() + bytesRead);
        }

        bool atEof = (bytesRead == 0);
        size_t scanLimit = atEof ? window.size() : (window.size() > overlapMargin ? window.size() - overlapMargin : 0);

        size_t i = 0;
        bool jumped = false;
        while (i < scanLimit) {
            if (i + 8 <= window.size() && std::memcmp(&window[i], "DVR-MOCK", 8) == 0) {
                uint64_t absOffset = windowBaseOffset + i;
                if (matches.empty() || absOffset > matches.back().offset) {
                    matches.push_back({absOffset, CarverSignature::DVR_MOCK});
                }
                i += 8;
                continue;
            }

            if (i + 4 <= window.size() && std::memcmp(&window[i], "ftyp", 4) == 0) {
                if (i >= 4) {
                    uint32_t boxSize = ((uint32_t)window[i - 4] << 24) |
                                       ((uint32_t)window[i - 3] << 16) |
                                       ((uint32_t)window[i - 2] << 8)  |
                                       (uint32_t)window[i - 1];
                    if (boxSize >= 8) {
                        uint64_t absOffset = (windowBaseOffset + i) - 4;
                        if (matches.empty() || absOffset > matches.back().offset) {
                            matches.push_back({absOffset, CarverSignature::MP4_MOV});
                        }
                        uint64_t mp4Len = getMp4BoxLength(in, absOffset, totalSize);
                        if (mp4Len > 0) {
                            uint64_t targetOffset = absOffset + mp4Len;
                            if (targetOffset > windowBaseOffset && targetOffset < windowBaseOffset + window.size()) {
                                i = targetOffset - windowBaseOffset;
                                continue;
                            } else if (targetOffset >= windowBaseOffset + window.size()) {
                                window.clear();
                                windowBaseOffset = targetOffset;
                                in.clear();
                                in.seekg(targetOffset, std::ios::beg);
                                jumped = true;
                                break;
                            }
                        }
                        i += 4;
                        continue;
                    }
                }
            }

            if (i + 5 <= window.size() &&
                window[i] == 0x00 && window[i + 1] == 0x00 && window[i + 2] == 0x00 && window[i + 3] == 0x01) {
                if (isValidH264NalByte(window[i + 4])) {
                    uint64_t absOffset = windowBaseOffset + i;
                    if (matches.empty() || absOffset > matches.back().offset) {
                        matches.push_back({absOffset, CarverSignature::H264_ANNEX_B});
                    }
                    i += 4;
                    continue;
                }
            }

            if (i + 4 <= window.size() &&
                window[i] == 0x00 && window[i + 1] == 0x00 && window[i + 2] == 0x01) {
                if (isValidH264NalByte(window[i + 3])) {
                    uint64_t absOffset = windowBaseOffset + i;
                    if (matches.empty() || absOffset > matches.back().offset) {
                        matches.push_back({absOffset, CarverSignature::H264_ANNEX_B});
                    }
                    i += 3;
                    continue;
                }
            }

            i++;
        }

        if (jumped) continue;
        if (atEof) break;

        window.erase(window.begin(), window.begin() + scanLimit);
        windowBaseOffset += scanLimit;
    }

    if (matches.empty()) return {};

    fs::path outDir(outputDir);
    fs::path fragDir = outDir / "fragments";
    fs::create_directories(outDir);
    fs::create_directories(fragDir);

    std::vector<CarvedChunk> carvedChunks;
    carvedChunks.reserve(matches.size());

    for (size_t k = 0; k < matches.size(); ++k) {
        uint64_t chunkStart = matches[k].offset;
        uint64_t nextStart = (k + 1 < matches.size()) ? matches[k + 1].offset : totalSize;
        uint64_t chunkLen = (nextStart > chunkStart) ? (nextStart - chunkStart) : 0;

        if (matches[k].signature == CarverSignature::MP4_MOV) {
            uint64_t boxLen = getMp4BoxLength(in, chunkStart, totalSize);
            if (boxLen >= minChunkSize && boxLen <= chunkLen) {
                chunkLen = boxLen;
            }
        }

        if (chunkLen > maxChunkSize) {
            chunkLen = maxChunkSize;
        }

        bool isFragment = (chunkLen < minChunkSize);

        std::ostringstream filenameStream;
        filenameStream << "carved_" << std::setw(4) << std::setfill('0') << (k + 1)
                       << extensionForSignature(matches[k].signature);
        std::string filename = filenameStream.str();

        fs::path targetFilePath = isFragment ? (fragDir / filename) : (outDir / filename);

        in.clear();
        in.seekg(chunkStart, std::ios::beg);
        std::ofstream outFile(targetFilePath, std::ios::binary);

        uint64_t remaining = chunkLen;
        std::vector<char> transferBuffer(65536);
        while (remaining > 0) {
            size_t toRead = std::min((uint64_t)transferBuffer.size(), remaining);
            in.read(transferBuffer.data(), toRead);
            std::streamsize bytes = in.gcount();
            if (bytes <= 0) break;
            outFile.write(transferBuffer.data(), bytes);
            remaining -= bytes;
        }
        outFile.close();

        CarvedChunk chunk;
        chunk.offset = chunkStart;
        chunk.length = chunkLen - remaining;
        chunk.signature = matches[k].signature;
        chunk.signature_name = signatureToString(matches[k].signature);
        chunk.output_path = targetFilePath.string();
        chunk.is_fragment = isFragment;
        carvedChunks.push_back(chunk);
    }

    return carvedChunks;
}
