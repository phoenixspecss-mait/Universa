#include "custody_log.h"
#include "constants.h"

#include <fstream>
#include <sstream>
#include <iomanip>
#include <vector>
#include <chrono>
#include <ctime>
#include <openssl/evp.h>

std::string CustodyLog::currentUtcTimestamp() {
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

std::string CustodyLog::computeSha256(const std::string& data) {
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx) return "";

    const EVP_MD* md = EVP_sha256();
    if (EVP_DigestInit_ex(ctx, md, nullptr) != 1 ||
        EVP_DigestUpdate(ctx, data.data(), data.size()) != 1) {
        EVP_MD_CTX_free(ctx);
        return "";
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

static std::string evpFileHash(const std::string& filePath, const EVP_MD* md) {
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) return "";

    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx) return "";

    if (EVP_DigestInit_ex(ctx, md, nullptr) != 1) {
        EVP_MD_CTX_free(ctx);
        return "";
    }

    std::vector<char> buffer(universa::HASH_BUFFER_SIZE);
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

std::string CustodyLog::computeFileSha256(const std::string& filePath) {
    return evpFileHash(filePath, EVP_sha256());
}

std::string CustodyLog::computeFileMd5(const std::string& filePath) {
    return evpFileHash(filePath, EVP_md5());
}

std::string CustodyLog::escapeJson(const std::string& str) {
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

std::string CustodyLog::serializeForHash(const CustodyEntry& entry) {
    std::ostringstream oss;
    oss << entry.sequence_number << "|"
        << entry.timestamp_utc << "|"
        << entry.stage_name << "|"
        << entry.action_description << "|"
        << entry.input_hash << "|"
        << entry.output_hash << "|"
        << entry.prev_entry_hash;
    return oss.str();
}

void CustodyLog::appendJsonLine(const CustodyEntry& entry) {
    std::ofstream file(logFilePath, std::ios::app);
    if (!file.is_open()) return;

    file << "{"
         << "\"sequence_number\":" << entry.sequence_number << ","
         << "\"timestamp_utc\":\"" << escapeJson(entry.timestamp_utc) << "\","
         << "\"stage_name\":\"" << escapeJson(entry.stage_name) << "\","
         << "\"action_description\":\"" << escapeJson(entry.action_description) << "\","
         << "\"input_hash\":\"" << escapeJson(entry.input_hash) << "\","
         << "\"output_hash\":\"" << escapeJson(entry.output_hash) << "\","
         << "\"prev_entry_hash\":\"" << escapeJson(entry.prev_entry_hash) << "\","
         << "\"this_entry_hash\":\"" << escapeJson(entry.this_entry_hash) << "\""
         << "}\n";
    file.flush();
}

CustodyLog::CustodyLog(const std::string& logFilePath)
    : logFilePath(logFilePath) {}

const CustodyEntry& CustodyLog::addEntry(const std::string& stageName,
                                        const std::string& actionDescription,
                                        const std::string& inputHash,
                                        const std::string& outputHash) {
    CustodyEntry entry;
    entry.sequence_number = entries.size();
    entry.timestamp_utc = currentUtcTimestamp();
    entry.stage_name = stageName;
    entry.action_description = actionDescription;
    entry.input_hash = inputHash;
    entry.output_hash = outputHash;
    entry.prev_entry_hash = entries.empty() ? std::string(64, '0') : entries.back().this_entry_hash;
    entry.this_entry_hash = computeSha256(serializeForHash(entry));

    entries.push_back(entry);
    appendJsonLine(entry);
    return entries.back();
}

bool CustodyLog::verifyChain(int* firstMismatchIndex) const {
    for (size_t i = 0; i < entries.size(); ++i) {
        const auto& entry = entries[i];
        if (entry.sequence_number != i) {
            if (firstMismatchIndex) *firstMismatchIndex = static_cast<int>(i);
            return false;
        }

        std::string expectedPrev = (i == 0) ? std::string(64, '0') : entries[i - 1].this_entry_hash;
        if (entry.prev_entry_hash != expectedPrev) {
            if (firstMismatchIndex) *firstMismatchIndex = static_cast<int>(i);
            return false;
        }

        std::string recomputedHash = computeSha256(serializeForHash(entry));
        if (recomputedHash != entry.this_entry_hash) {
            if (firstMismatchIndex) *firstMismatchIndex = static_cast<int>(i);
            return false;
        }
    }
    return true;
}

const std::vector<CustodyEntry>& CustodyLog::getEntries() const {
    return entries;
}

const std::string& CustodyLog::getLogFilePath() const {
    return logFilePath;
}

