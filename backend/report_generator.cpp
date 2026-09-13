#include "report_generator.h"

#include <fstream>
#include <sstream>
#include <iomanip>
#include <vector>
#include <algorithm>

ReportGenerator::ReportGenerator(ReportData data)
    : data(std::move(data)) {}

std::string ReportGenerator::escapeJson(const std::string& str) {
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

std::string ReportGenerator::escapeCsv(const std::string& str) {
    bool needQuotes = (str.find(',') != std::string::npos ||
                       str.find('"') != std::string::npos ||
                       str.find('\n') != std::string::npos);
    if (!needQuotes) return str;

    std::ostringstream oss;
    oss << '"';
    for (char c : str) {
        if (c == '"') oss << "\"\"";
        else oss << c;
    }
    oss << '"';
    return oss.str();
}

std::string ReportGenerator::escapePdfText(const std::string& str) {
    std::string out;
    for (char c : str) {
        if (c == '(' || c == ')' || c == '\\') {
            out.push_back('\\');
        }
        if (c >= 32 && c <= 126) {
            out.push_back(c);
        } else {
            out.push_back(' ');
        }
    }
    return out;
}

bool ReportGenerator::exportJSON(const std::string& outputPath) const {
    std::ofstream out(outputPath);
    if (!out.is_open()) return false;

    out << "{\n";
    out << "  \"case_summary\": {\n";
    out << "    \"source_file\": \"" << escapeJson(data.source_file) << "\",\n";
    out << "    \"detected_brand\": \"" << escapeJson(data.detected_brand) << "\",\n";
    out << "    \"source_file_sha256\": \"" << escapeJson(data.source_file_hash) << "\",\n";
    out << "    \"generated_at_utc\": \"" << escapeJson(data.generated_at_utc) << "\"\n";
    out << "  },\n";

    out << "  \"chain_of_custody\": {\n";
    out << "    \"verification_passed\": " << (data.chain_verification_passed ? "true" : "false") << ",\n";
    out << "    \"mismatch_index\": " << data.chain_mismatch_index << ",\n";
    out << "    \"total_entries\": " << data.custody_entries.size() << ",\n";
    out << "    \"entries\": [\n";
    for (size_t i = 0; i < data.custody_entries.size(); ++i) {
        const auto& e = data.custody_entries[i];
        out << "      {\n";
        out << "        \"sequence_number\": " << e.sequence_number << ",\n";
        out << "        \"timestamp_utc\": \"" << escapeJson(e.timestamp_utc) << "\",\n";
        out << "        \"stage_name\": \"" << escapeJson(e.stage_name) << "\",\n";
        out << "        \"action_description\": \"" << escapeJson(e.action_description) << "\",\n";
        out << "        \"input_hash\": \"" << escapeJson(e.input_hash) << "\",\n";
        out << "        \"output_hash\": \"" << escapeJson(e.output_hash) << "\",\n";
        out << "        \"prev_entry_hash\": \"" << escapeJson(e.prev_entry_hash) << "\",\n";
        out << "        \"this_entry_hash\": \"" << escapeJson(e.this_entry_hash) << "\"\n";
        out << "      }" << (i + 1 < data.custody_entries.size() ? "," : "") << "\n";
    }
    out << "    ]\n";
    out << "  },\n";

    out << "  \"carved_chunks\": [\n";
    for (size_t i = 0; i < data.chunks.size(); ++i) {
        const auto& c = data.chunks[i];
        ValidationResult v{};
        if (i < data.validations.size()) v = data.validations[i];

        const ClipAIDetection* aiDet = nullptr;
        for (const auto& a : data.ai_detections) {
            if (a.clip_path == c.output_path) {
                aiDet = &a;
                break;
            }
        }

        out << "      {\n";
        out << "        \"offset\": " << c.offset << ",\n";
        out << "        \"length\": " << c.length << ",\n";
        out << "        \"signature_type\": \"" << escapeJson(c.signature_name) << "\",\n";
        out << "        \"is_fragment\": " << (c.is_fragment ? "true" : "false") << ",\n";
        out << "        \"is_valid\": " << (v.is_valid ? "true" : "false") << ",\n";
        out << "        \"codec\": \"" << escapeJson(v.codec_name) << "\",\n";
        out << "        \"width\": " << v.width << ",\n";
        out << "        \"height\": " << v.height << ",\n";
        out << "        \"duration_seconds\": " << v.duration_seconds << ",\n";
        out << "        \"output_path\": \"" << escapeJson(c.output_path) << "\",\n";

        if (aiDet && aiDet->analyzed) {
            out << "        \"ai_analysis\": {\n";
            out << "          \"analyzed\": true,\n";
            out << "          \"total_detections\": " << aiDet->total_detections << ",\n";
            out << "          \"distinct_classes\": [";
            for (size_t k = 0; k < aiDet->distinct_classes.size(); ++k) {
                out << "\"" << escapeJson(aiDet->distinct_classes[k]) << "\"" << (k + 1 < aiDet->distinct_classes.size() ? ", " : "");
            }
            out << "],\n";
            out << "          \"sampled_frames\": [\n";
            for (size_t f = 0; f < aiDet->frames.size(); ++f) {
                const auto& fr = aiDet->frames[f];
                out << "            {\n";
                out << "              \"timestamp_seconds\": " << std::fixed << std::setprecision(2) << fr.timestamp_in_clip_seconds << ",\n";
                out << "              \"detections\": [\n";
                for (size_t d = 0; d < fr.detections.size(); ++d) {
                    const auto& det = fr.detections[d];
                    out << "                {\n";
                    out << "                  \"class_name\": \"" << escapeJson(det.class_name) << "\",\n";
                    out << "                  \"confidence\": " << std::fixed << std::setprecision(4) << det.confidence << ",\n";
                    out << "                  \"bounding_box\": {\"x\": " << det.bounding_box.x
                        << ", \"y\": " << det.bounding_box.y
                        << ", \"width\": " << det.bounding_box.width
                        << ", \"height\": " << det.bounding_box.height << "}\n";
                    out << "                }" << (d + 1 < fr.detections.size() ? "," : "") << "\n";
                }
                out << "              ]\n";
                out << "            }" << (f + 1 < aiDet->frames.size() ? "," : "") << "\n";
            }
            out << "          ]\n";
            out << "        }\n";
        } else {
            out << "        \"ai_analysis\": null\n";
        }

        out << "      }" << (i + 1 < data.chunks.size() ? "," : "") << "\n";
    }
    out << "  ],\n";

    out << "  \"timeline\": [\n";
    for (size_t i = 0; i < data.timeline.size(); ++i) {
        const auto& t = data.timeline[i];
        out << "      {\n";
        out << "        \"clip_path\": \"" << escapeJson(t.clip_path) << "\",\n";
        out << "        \"estimated_start_utc\": \"" << escapeJson(t.estimated_start_utc) << "\",\n";
        out << "        \"estimated_end_utc\": \"" << escapeJson(t.estimated_end_utc) << "\",\n";
        out << "        \"channel_guess\": " << t.channel_guess << ",\n";
        out << "        \"offset_in_image\": " << t.offset_in_image << ",\n";
        out << "        \"duration_seconds\": " << t.duration_seconds << "\n";
        out << "      }" << (i + 1 < data.timeline.size() ? "," : "") << "\n";
    }
    out << "  ]\n";
    out << "}\n";

    return true;
}

bool ReportGenerator::exportCSV(const std::string& outputPath) const {
    std::ofstream out(outputPath);
    if (!out.is_open()) return false;

    out << "offset,signature_type,is_fragment,is_valid,codec,resolution,duration,estimated_start_utc,ai_distinct_classes,ai_total_detections\n";

    for (size_t i = 0; i < data.chunks.size(); ++i) {
        const auto& c = data.chunks[i];
        ValidationResult v{};
        if (i < data.validations.size()) v = data.validations[i];

        const ClipAIDetection* aiDet = nullptr;
        for (const auto& a : data.ai_detections) {
            if (a.clip_path == c.output_path) {
                aiDet = &a;
                break;
            }
        }

        std::string startUtc = "-";
        for (const auto& t : data.timeline) {
            if (t.clip_path == c.output_path || t.offset_in_image == c.offset) {
                startUtc = t.estimated_start_utc;
                break;
            }
        }

        std::string resStr = (v.width > 0 && v.height > 0)
            ? (std::to_string(v.width) + "x" + std::to_string(v.height))
            : "-";
        std::string codecStr = v.codec_name.empty() ? "-" : v.codec_name;

        std::string distinctStr = "-";
        size_t totalDet = 0;
        if (aiDet && aiDet->analyzed) {
            totalDet = aiDet->total_detections;
            if (!aiDet->distinct_classes.empty()) {
                std::ostringstream ds;
                for (size_t k = 0; k < aiDet->distinct_classes.size(); ++k) {
                    ds << aiDet->distinct_classes[k] << (k + 1 < aiDet->distinct_classes.size() ? "; " : "");
                }
                distinctStr = ds.str();
            }
        }

        out << c.offset << ","
            << escapeCsv(c.signature_name) << ","
            << (c.is_fragment ? "true" : "false") << ","
            << (v.is_valid ? "true" : "false") << ","
            << escapeCsv(codecStr) << ","
            << escapeCsv(resStr) << ","
            << std::fixed << std::setprecision(2) << v.duration_seconds << ","
            << escapeCsv(startUtc) << ","
            << escapeCsv(distinctStr) << ","
            << totalDet << "\n";
    }

    return true;
}

struct PdfPageLine {
    std::string text;
    bool isHeader = false;
};

bool ReportGenerator::exportPDF(const std::string& outputPath) const {
    std::vector<PdfPageLine> lines;

    lines.push_back({"DVR/NVR FORENSIC INVESTIGATION REPORT", true});
    lines.push_back({"", false});
    lines.push_back({"1. CASE SUMMARY", true});
    lines.push_back({"Source Disk Image: " + data.source_file, false});
    lines.push_back({"Detected Brand:    " + data.detected_brand, false});
    lines.push_back({"SHA-256 Seal:      " + data.source_file_hash, false});
    lines.push_back({"Generated At:      " + data.generated_at_utc, false});
    lines.push_back({"", false});

    lines.push_back({"2. CHAIN OF CUSTODY VERIFICATION", true});
    std::string chainStatus = data.chain_verification_passed ? "PASSED (Cryptographic integrity verified)" : "FAILED (Tampering detected!)";
    lines.push_back({"Status:        " + chainStatus, false});
    lines.push_back({"Total Events:  " + std::to_string(data.custody_entries.size()), false});
    for (const auto& e : data.custody_entries) {
        std::string desc = "  [#" + std::to_string(e.sequence_number) + "] " + e.stage_name + ": " + e.action_description;
        lines.push_back({desc, false});
        lines.push_back({"      Hash: " + e.this_entry_hash.substr(0, 32) + "...", false});
    }
    lines.push_back({"", false});

    lines.push_back({"3. CARVED EVIDENCE TABLE", true});
    lines.push_back({"Offset       Type             Status    Valid    Codec   Res         Duration  Output", false});
    lines.push_back({"------------------------------------------------------------------------------------------------", false});
    for (size_t i = 0; i < data.chunks.size(); ++i) {
        const auto& c = data.chunks[i];
        ValidationResult v{};
        if (i < data.validations.size()) v = data.validations[i];

        char row[256];
        std::string res = (v.width > 0 && v.height > 0) ? (std::to_string(v.width) + "x" + std::to_string(v.height)) : "-";
        std::string codec = v.codec_name.empty() ? "-" : v.codec_name;
        std::string filename = c.output_path.substr(c.output_path.find_last_of("/\\") + 1);

        std::snprintf(row, sizeof(row), "%-12llu %-16s %-9s %-8s %-7s %-11s %-9.2f %s",
                      static_cast<unsigned long long>(c.offset),
                      c.signature_name.c_str(),
                      c.is_fragment ? "Fragment" : "Intact",
                      v.is_valid ? "VALID" : "INVALID",
                      codec.c_str(),
                      res.c_str(),
                      v.duration_seconds,
                      filename.c_str());
        lines.push_back({std::string(row), false});
    }
    lines.push_back({"", false});

    lines.push_back({"4. FORENSIC TIMELINE (ESTIMATED)", true});
    lines.push_back({"Offset       Start UTC            End UTC              Duration   Clip", false});
    lines.push_back({"------------------------------------------------------------------------------------------------", false});
    for (const auto& t : data.timeline) {
        char row[256];
        std::string filename = t.clip_path.substr(t.clip_path.find_last_of("/\\") + 1);
        std::snprintf(row, sizeof(row), "%-12llu %-20s %-20s %-10.2f %s",
                      static_cast<unsigned long long>(t.offset_in_image),
                      t.estimated_start_utc.c_str(),
                      t.estimated_end_utc.c_str(),
                      t.duration_seconds,
                      filename.c_str());
        lines.push_back({std::string(row), false});
    }
    lines.push_back({"", false});

    lines.push_back({"5. AI ANALYSIS SUMMARY (YOLOv4-TINY)", true});
    lines.push_back({"Clip                           Detections         Distinct Classes", false});
    lines.push_back({"------------------------------------------------------------------------------------------------", false});
    for (const auto& c : data.chunks) {
        const ClipAIDetection* aiDet = nullptr;
        for (const auto& a : data.ai_detections) {
            if (a.clip_path == c.output_path) {
                aiDet = &a;
                break;
            }
        }
        std::string filename = c.output_path.substr(c.output_path.find_last_of("/\\") + 1);
        char row[256];
        if (aiDet && aiDet->analyzed) {
            std::string classList;
            for (size_t k = 0; k < aiDet->distinct_classes.size(); ++k) {
                classList += aiDet->distinct_classes[k] + (k + 1 < aiDet->distinct_classes.size() ? ", " : "");
            }
            if (classList.empty()) classList = "None";
            std::snprintf(row, sizeof(row), "%-30s %-18zu %s",
                          filename.c_str(),
                          aiDet->total_detections,
                          classList.c_str());
        } else {
            std::snprintf(row, sizeof(row), "%-30s %-18s %s",
                          filename.c_str(),
                          "-",
                          "Not analyzed / skipped");
        }
        lines.push_back({std::string(row), false});
    }

    const size_t linesPerPage = 42;
    std::vector<std::vector<PdfPageLine>> pages;
    for (size_t i = 0; i < lines.size(); i += linesPerPage) {
        size_t end = std::min(lines.size(), i + linesPerPage);
        pages.emplace_back(lines.begin() + i, lines.begin() + end);
    }
    if (pages.empty()) pages.push_back({});

    std::ofstream pdf(outputPath, std::ios::binary);
    if (!pdf.is_open()) return false;

    std::vector<size_t> objectOffsets;
    auto startObject = [&]() -> size_t {
        objectOffsets.push_back(pdf.tellp());
        return objectOffsets.size();
    };

    pdf << "%PDF-1.4\n";

    size_t numPages = pages.size();
    std::vector<size_t> pageObjIds(numPages);
    std::vector<size_t> contentObjIds(numPages);

    for (size_t p = 0; p < numPages; ++p) {
        pageObjIds[p] = 4 + p * 2;
        contentObjIds[p] = 5 + p * 2;
    }

    startObject();
    pdf << "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n";

    startObject();
    pdf << "2 0 obj\n<< /Type /Pages /Kids [";
    for (size_t p = 0; p < numPages; ++p) {
        pdf << pageObjIds[p] << " 0 R ";
    }
    pdf << "] /Count " << numPages << " >>\nendobj\n";

    startObject();
    pdf << "3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n";

    for (size_t p = 0; p < numPages; ++p) {
        startObject();
        pdf << pageObjIds[p] << " 0 obj\n"
            << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            << "/Resources << /Font << /F1 3 0 R >> >> "
            << "/Contents " << contentObjIds[p] << " 0 R >>\nendobj\n";

        std::ostringstream streamContent;
        streamContent << "BT\n/F1 9 Tf\n12 TL\n";
        streamContent << "1 0 0 1 36 756 Tm\n";

        for (const auto& line : pages[p]) {
            streamContent << "(" << escapePdfText(line.text) << ") '\n";
        }
        streamContent << "ET\n";

        std::string streamStr = streamContent.str();
        startObject();
        pdf << contentObjIds[p] << " 0 obj\n"
            << "<< /Length " << streamStr.size() << " >>\nstream\n"
            << streamStr
            << "endstream\nendobj\n";
    }

    size_t xrefOffset = pdf.tellp();
    pdf << "xref\n";
    pdf << "0 " << (objectOffsets.size() + 1) << "\n";
    pdf << "0000000000 65535 f \n";
    for (size_t off : objectOffsets) {
        pdf << std::setw(10) << std::setfill('0') << off << " 00000 n \n";
    }

    pdf << "trailer\n"
        << "<< /Size " << (objectOffsets.size() + 1) << " /Root 1 0 R >>\n"
        << "startxref\n"
        << xrefOffset << "\n"
        << "%%EOF\n";

    return true;
}
