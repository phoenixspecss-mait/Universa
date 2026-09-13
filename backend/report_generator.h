#pragma once

#include <string>
#include <vector>
#include "file_carver.h"
#include "clip_validator.h"
#include "custody_log.h"
#include "timeline_normalizer.h"
#include "ai_detector.h"

struct ReportData {
    std::string source_file;
    std::string detected_brand;
    std::string source_file_hash;
    std::string source_file_md5;
    std::string compliance_standard = "BSA 2023 §63";
    std::string iso_standard = "ISO/IEC 27037:2012";
    std::string nist_guideline = "NIST SP 800-86";
    std::string examiner_name = "Forensic Analyst";
    std::string organization = "Universa Digital Forensics Lab";
    std::string generated_at_utc;
    bool chain_verification_passed = false;
    int chain_mismatch_index = -1;

    std::vector<CarvedChunk> chunks;
    std::vector<ValidationResult> validations;
    std::vector<CustodyEntry> custody_entries;
    std::vector<TimelineEntry> timeline;
    std::vector<ClipAIDetection> ai_detections;
};

class ReportGenerator {
public:
    explicit ReportGenerator(ReportData data);

    bool exportJSON(const std::string& outputPath) const;
    bool exportCSV(const std::string& outputPath) const;
    bool exportPDF(const std::string& outputPath) const;

private:
    ReportData data;

    static std::string escapeJson(const std::string& str);
    static std::string escapeCsv(const std::string& str);
    static std::string escapePdfText(const std::string& str);
};
