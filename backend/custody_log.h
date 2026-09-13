#pragma once

#include <string>
#include <vector>
#include <cstdint>

struct CustodyEntry {
    uint64_t sequence_number = 0;
    std::string timestamp_utc;
    std::string stage_name;
    std::string action_description;
    std::string input_hash;
    std::string output_hash;
    std::string prev_entry_hash;
    std::string this_entry_hash;
};

class CustodyLog {
public:
    explicit CustodyLog(const std::string& logFilePath = "custody_log.jsonl");

    const CustodyEntry& addEntry(const std::string& stageName,
                                 const std::string& actionDescription,
                                 const std::string& inputHash = "",
                                 const std::string& outputHash = "");

    bool verifyChain(int* firstMismatchIndex = nullptr) const;

    const std::vector<CustodyEntry>& getEntries() const;
    const std::string& getLogFilePath() const;

    static std::string computeSha256(const std::string& data);
    static std::string computeFileSha256(const std::string& filePath);

private:
    std::string logFilePath;
    std::vector<CustodyEntry> entries;

    static std::string currentUtcTimestamp();
    static std::string serializeForHash(const CustodyEntry& entry);
    static std::string escapeJson(const std::string& str);
    void appendJsonLine(const CustodyEntry& entry);
};

