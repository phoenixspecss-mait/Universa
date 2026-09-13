#include "utils.h"
#include "constants.h"

#include <fstream>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <chrono>
#include <ctime>
#include <openssl/evp.h>

namespace universa {

VendorType detectBrand(const std::string& filePath) {
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) return VendorType::UNKNOWN;

    std::vector<char> buffer(512);
    file.read(buffer.data(), buffer.size());
    std::string header(buffer.begin(), buffer.end());

    if (header.find("DHAV") != std::string::npos) return VendorType::GODREJ_DAHUA;
    if (header.find("DVR-MOCK") != std::string::npos) return VendorType::CUSTOM_MOCK;
    if (header.find("ftypisom") != std::string::npos) return VendorType::HIKVISION;

    return VendorType::UNKNOWN;
}

std::string brandToString(VendorType brand) {
    switch (brand) {
        case VendorType::GODREJ_DAHUA: return "Godrej/Dahua (.dav)";
        case VendorType::HIKVISION:    return "Hikvision";
        case VendorType::CUSTOM_MOCK:  return "Custom MOCK System";
        default:                       return "Unknown / Raw Disk Image";
    }
}

bool convertToMP4(const std::string& inputFile, const std::string& outputFile) {
    std::ifstream inFile(inputFile, std::ios::binary);
    if (!inFile) return false;

    std::vector<char> headerBuffer(2048);
    inFile.read(headerBuffer.data(), headerBuffer.size());
    std::streamsize bytesRead = inFile.gcount();

    std::string searchStr = "ftyp";
    auto it = std::search(headerBuffer.begin(), headerBuffer.begin() + bytesRead, searchStr.begin(), searchStr.end());

    if (it == headerBuffer.begin() + bytesRead) {
        return false;
    }

    std::size_t ftypOffset = std::distance(headerBuffer.begin(), it);
    std::size_t startOffset = (ftypOffset >= 4) ? ftypOffset - 4 : ftypOffset;

    std::ofstream outFile(outputFile, std::ios::binary);
    if (!outFile) return false;

    inFile.clear();
    inFile.seekg(startOffset, std::ios::beg);

    char buffer[8192];
    while (inFile.read(buffer, sizeof(buffer)) || inFile.gcount() > 0) {
        outFile.write(buffer, inFile.gcount());
    }
    return true;
}

static std::string evpFileHash(const std::string& filePath, const EVP_MD* md) {
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) return "";

    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx) return "";

    if (EVP_DigestInit_ex(ctx, md, nullptr) != 1) {
        EVP_MD_CTX_free(ctx);
        return "";
    }

    std::vector<char> buffer(HASH_BUFFER_SIZE);
    while (file.read(buffer.data(), buffer.size()) || file.gcount() > 0) {
        if (EVP_DigestUpdate(ctx, buffer.data(), file.gcount()) != 1) {
            EVP_MD_CTX_free(ctx);
            return "";
        }
    }

    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int hashLen = 0;
    if (EVP_DigestFinal_ex(ctx, hash, &hashLen) != 1) {
        EVP_MD_CTX_free(ctx);
        return "";
    }
    EVP_MD_CTX_free(ctx);

    std::ostringstream oss;
    for (unsigned int i = 0; i < hashLen; ++i) {
        oss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(hash[i]);
    }
    return oss.str();
}

std::string computeFileSha256(const std::string& filePath) {
    return evpFileHash(filePath, EVP_sha256());
}

std::string computeFileMd5(const std::string& filePath) {
    return evpFileHash(filePath, EVP_md5());
}

std::string currentUtcIso() {
    auto now = std::chrono::system_clock::now();
    std::time_t tt = std::chrono::system_clock::to_time_t(now);
    std::tm gmt{};
#if defined(_WIN32)
    gmtime_s(&gmt, &tt);
#else
    gmtime_r(&tt, &gmt);
#endif
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &gmt);
    return std::string(buf);
}

std::string escapeJsonString(const std::string& str) {
    std::ostringstream oss;
    for (char c : str) {
        switch (c) {
            case '"': oss << "\\\""; break;
            case '\\': oss << "\\\\"; break;
            case '\b': oss << "\\b"; break;
            case '\f': oss << "\\f"; break;
            case '\n': oss << "\\n"; break;
            case '\r': oss << "\\r"; break;
            case '\t': oss << "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    oss << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(c);
                } else {
                    oss << c;
                }
                break;
        }
    }
    return oss.str();
}

} // namespace universa

