#include "dahua_adapter.h"
#include "../utils.h"
#include <fstream>
#include <vector>

namespace universa {

bool DahuaAdapter::matchesSignature(const std::string& filePath) const {
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) return false;

    std::vector<char> buffer(512);
    file.read(buffer.data(), buffer.size());
    std::string header(buffer.begin(), buffer.begin() + file.gcount());
    return header.find("DHAV") != std::string::npos;
}

std::string DahuaAdapter::vendorName() const {
    return "Godrej / Dahua (.dav)";
}

VendorType DahuaAdapter::vendorType() const {
    return VendorType::GODREJ_DAHUA;
}

bool DahuaAdapter::decode(const std::string& inputFile, const std::string& outputFile) {
    // Attempt standard MP4 container conversion if ftyp atom present,
    // otherwise fallback to copy/stream passthrough.
    if (convertToMP4(inputFile, outputFile)) {
        return true;
    }
    // Direct stream copy fallback
    std::ifstream src(inputFile, std::ios::binary);
    std::ofstream dst(outputFile, std::ios::binary);
    if (!src || !dst) return false;
    dst << src.rdbuf();
    return true;
}

} // namespace universa
