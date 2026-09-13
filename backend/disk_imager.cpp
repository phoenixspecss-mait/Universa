#include "disk_imager.h"
#include "constants.h"
#include "utils.h"

#include <fstream>
#include <vector>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <iostream>
#include <openssl/evp.h>

namespace universa {

AcquisitionResult DiskImager::acquire(
    const std::string& sourceDeviceOrFile,
    const std::string& destinationImagePath,
    ProgressCallback progress
) {
    AcquisitionResult res;
    res.source_path = sourceDeviceOrFile;
    res.destination_path = destinationImagePath;
    res.start_time_utc = currentUtcIso();

    auto startTime = std::chrono::steady_clock::now();

    std::ifstream src(sourceDeviceOrFile, std::ios::binary);
    if (!src.is_open()) {
        res.error_message = "Failed to open source device/file for raw reading: " + sourceDeviceOrFile;
        res.end_time_utc = currentUtcIso();
        return res;
    }

    std::ofstream dst(destinationImagePath, std::ios::binary | std::ios::trunc);
    if (!dst.is_open()) {
        res.error_message = "Failed to open destination image file for writing: " + destinationImagePath;
        res.end_time_utc = currentUtcIso();
        return res;
    }

    // Determine file size if regular file (if block device, this may be 0 or EOF-based)
    src.seekg(0, std::ios::end);
    uint64_t totalEstimate = static_cast<uint64_t>(src.tellg());
    src.seekg(0, std::ios::beg);

    EVP_MD_CTX* shaCtx = EVP_MD_CTX_new();
    EVP_MD_CTX* md5Ctx = EVP_MD_CTX_new();

    if (!shaCtx || !md5Ctx ||
        EVP_DigestInit_ex(shaCtx, EVP_sha256(), nullptr) != 1 ||
        EVP_DigestInit_ex(md5Ctx, EVP_md5(), nullptr) != 1) {
        if (shaCtx) EVP_MD_CTX_free(shaCtx);
        if (md5Ctx) EVP_MD_CTX_free(md5Ctx);
        res.error_message = "Failed to initialize OpenSSL hashing contexts for acquisition";
        res.end_time_utc = currentUtcIso();
        return res;
    }

    std::vector<char> buffer(DISK_IMAGER_BUFFER_SIZE);
    uint64_t bytesCopied = 0;

    while (src.read(buffer.data(), buffer.size()) || src.gcount() > 0) {
        std::streamsize count = src.gcount();
        if (count <= 0) break;

        dst.write(buffer.data(), count);
        if (!dst.good()) {
            res.error_message = "Write error encountered at byte offset " + std::to_string(bytesCopied);
            break;
        }

        EVP_DigestUpdate(shaCtx, buffer.data(), count);
        EVP_DigestUpdate(md5Ctx, buffer.data(), count);

        bytesCopied += static_cast<uint64_t>(count);
        if (progress) {
            progress(bytesCopied, totalEstimate);
        }
    }

    dst.flush();
    dst.close();
    src.close();

    // Finalize SHA-256
    unsigned char shaHash[EVP_MAX_MD_SIZE];
    unsigned int shaLen = 0;
    if (EVP_DigestFinal_ex(shaCtx, shaHash, &shaLen) == 1) {
        std::ostringstream oss;
        for (unsigned int i = 0; i < shaLen; ++i) {
            oss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(shaHash[i]);
        }
        res.sha256_hash = oss.str();
    }
    EVP_MD_CTX_free(shaCtx);

    // Finalize MD5
    unsigned char md5Hash[EVP_MAX_MD_SIZE];
    unsigned int md5Len = 0;
    if (EVP_DigestFinal_ex(md5Ctx, md5Hash, &md5Len) == 1) {
        std::ostringstream oss;
        for (unsigned int i = 0; i < md5Len; ++i) {
            oss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(md5Hash[i]);
        }
        res.md5_hash = oss.str();
    }
    EVP_MD_CTX_free(md5Ctx);

    auto endTime = std::chrono::steady_clock::now();
    res.duration_seconds = std::chrono::duration<double>(endTime - startTime).count();
    res.end_time_utc = currentUtcIso();
    res.bytes_acquired = bytesCopied;
    res.success = res.error_message.empty();

    return res;
}

} // namespace universa
