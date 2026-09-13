#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <random>
#include <cstdlib>
#include <iomanip>
#include <sstream>
#include <filesystem>

namespace fs = std::filesystem;

struct GroundTruthEntry {
    uint64_t offset;
    uint64_t length;
    std::string status;
    std::string type;
};

static std::vector<uint8_t> generateMp4Clip(int id) {
    std::string tempPath = "/tmp/syn_tmp_" + std::to_string(id) + ".mp4";
    std::string filter = (id % 2 == 0) ? "testsrc" : "testsrc2";
    std::string cmd = "ffmpeg -y -f lavfi -i " + filter +
                      "=duration=1:size=160x120:rate=10 -pix_fmt yuv420p -c:v libx264 -movflags +faststart " +
                      tempPath + " > /dev/null 2>&1";
    int ret = std::system(cmd.c_str());
    if (ret == 0 && fs::exists(tempPath)) {
        std::ifstream file(tempPath, std::ios::binary | std::ios::ate);
        std::streamsize size = file.tellg();
        file.seekg(0, std::ios::beg);
        std::vector<uint8_t> buffer(size);
        if (file.read(reinterpret_cast<char*>(buffer.data()), size)) {
            fs::remove(tempPath);
            return buffer;
        }
        fs::remove(tempPath);
    }

    std::vector<uint8_t> fallback(1024, 0);
    const char ftypBox[] = "\x00\x00\x00\x18\x66\x74\x79\x70\x69\x73\x6f\x6d\x00\x00\x02\x00\x69\x73\x6f\x6d\x69\x73\x6f\x32";
    std::memcpy(fallback.data(), ftypBox, sizeof(ftypBox) - 1);
    return fallback;
}

int main(int argc, char* argv[]) {
    std::string outputPath = (argc > 1) ? argv[1] : "synthetic_disk.img";
    uint64_t totalSize = 20 * 1024 * 1024;

    if (argc > 2) {
        uint64_t val = std::stoull(argv[2]);
        if (val < 1024) {
            totalSize = val * 1024 * 1024;
        } else {
            totalSize = val;
        }
    }

    std::ofstream out(outputPath, std::ios::binary | std::ios::trunc);
    if (!out.is_open()) {
        std::cerr << "Failed to open output file: " << outputPath << "\n";
        return 1;
    }

    std::mt19937_64 rng(1337);
    std::uniform_int_distribution<uint64_t> dist;

    const size_t blockSize = 65536;
    std::vector<uint8_t> randomBlock(blockSize);
    uint64_t written = 0;
    while (written < totalSize) {
        size_t currentWrite = std::min((uint64_t)blockSize, totalSize - written);
        for (size_t i = 0; i < currentWrite; i += 8) {
            uint64_t r = dist(rng);
            size_t bytesToCopy = std::min((size_t)8, currentWrite - i);
            std::memcpy(randomBlock.data() + i, &r, bytesToCopy);
        }
        out.write(reinterpret_cast<const char*>(randomBlock.data()), currentWrite);
        written += currentWrite;
    }

    auto clip1 = generateMp4Clip(1);
    auto clip2 = generateMp4Clip(2);
    auto clip3 = generateMp4Clip(3);

    std::vector<GroundTruthEntry> manifest;

    auto writePayload = [&](uint64_t offset, const std::vector<uint8_t>& data, const std::string& status, const std::string& type) {
        out.seekp(offset, std::ios::beg);
        out.write(reinterpret_cast<const char*>(data.data()), data.size());
        manifest.push_back({offset, (uint64_t)data.size(), status, type});
    };

    uint64_t offset1 = 65536;
    writePayload(offset1, clip1, "INTACT", "MP4");

    uint64_t offset2 = 2097152;
    size_t frag1Len = std::min((size_t)1200, clip1.size() / 2);
    std::vector<uint8_t> frag1(clip1.begin(), clip1.begin() + frag1Len);
    writePayload(offset2, frag1, "CORRUPTED", "MP4 (Fragment < 4KB)");

    uint64_t offset3 = offset2 + 2048;
    size_t frag2Len = std::min((size_t)1800, clip2.size() / 2);
    std::vector<uint8_t> frag2(clip2.begin(), clip2.begin() + frag2Len);
    writePayload(offset3, frag2, "CORRUPTED", "MP4 (Fragment < 4KB)");

    uint64_t offset4 = offset3 + 2048;
    std::string mockContent = "DVR-MOCK-CH01-TEST-FRAME-DATA-STREAM-SIMULATOR";
    std::vector<uint8_t> mockData(mockContent.begin(), mockContent.end());
    writePayload(offset4, mockData, "INTACT", "DVR-MOCK");

    uint64_t offset5 = 6291456;
    writePayload(offset5, clip2, "INTACT", "MP4");

    uint64_t offset6 = 12582912;
    writePayload(offset6, clip3, "INTACT", "MP4");

    out.close();

    std::cout << "========================================================================\n";
    std::cout << "               SYNTHETIC DVR DISK IMAGE MANIFEST (GROUND TRUTH)         \n";
    std::cout << "========================================================================\n";
    std::cout << "Disk Image: " << outputPath << "\n";
    std::cout << "Total Size: " << totalSize << " bytes (" << (totalSize / (1024 * 1024)) << " MB)\n\n";

    std::cout << std::left
              << std::setw(14) << "Offset (Dec)"
              << std::setw(14) << "Offset (Hex)"
              << std::setw(16) << "Length (Bytes)"
              << std::setw(14) << "Status"
              << "Type\n";
    std::cout << "------------------------------------------------------------------------\n";

    for (const auto& entry : manifest) {
        std::stringstream hexStream;
        hexStream << "0x" << std::hex << std::uppercase << std::setfill('0') << std::setw(8) << entry.offset;
        std::cout << std::left
                  << std::setw(14) << entry.offset
                  << std::setw(14) << hexStream.str()
                  << std::setw(16) << entry.length
                  << std::setw(14) << entry.status
                  << entry.type << "\n";
    }
    std::cout << "========================================================================\n";

    return 0;
}
