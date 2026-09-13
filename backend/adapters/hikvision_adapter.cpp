#include "hikvision_adapter.h"
#include "../utils.h"
#include <fstream>
#include <vector>

namespace universa {

bool HikvisionAdapter::matchesSignature(const std::string& filePath) const {
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) return false;

    std::vector<char> buffer(512);
    file.read(buffer.data(), buffer.size());
    std::string header(buffer.begin(), buffer.begin() + file.gcount());
    return (header.find("ftypisom") != std::string::npos) ||
           (header.find("HKVS") != std::string::npos);
}

std::string HikvisionAdapter::vendorName() const {
    return "Hikvision";
}

VendorType HikvisionAdapter::vendorType() const {
    return VendorType::HIKVISION;
}

bool HikvisionAdapter::decode(const std::string& inputFile, const std::string& outputFile) {
    if (convertToMP4(inputFile, outputFile)) {
        return true;
    }
    std::ifstream src(inputFile, std::ios::binary);
    std::ofstream dst(outputFile, std::ios::binary);
    if (!src || !dst) return false;
    dst << src.rdbuf();
    return true;
}

} // namespace universa
