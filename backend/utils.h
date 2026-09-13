#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace universa {

/// Vendor types identified by hex signature scanning.
enum class VendorType { HIKVISION, GODREJ_DAHUA, CUSTOM_MOCK, UNKNOWN };

/// Detects DVR/NVR vendor from binary header signatures.
VendorType detectBrand(const std::string& filePath);

/// Returns a human-readable string for the vendor type.
std::string brandToString(VendorType brand);

/// Strips proprietary wrapper headers and extracts a standard MP4 stream.
bool convertToMP4(const std::string& inputFile, const std::string& outputFile);

/// Computes SHA-256 hash of a file. Returns hex string.
std::string computeFileSha256(const std::string& filePath);

/// Computes MD5 hash of a file. Returns hex string.
std::string computeFileMd5(const std::string& filePath);

/// Returns current UTC timestamp in ISO-8601 format.
std::string currentUtcIso();

/// Escapes a string for safe JSON embedding.
std::string escapeJsonString(const std::string& str);

} // namespace universa

