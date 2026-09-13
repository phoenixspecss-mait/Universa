#include "httplib.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <random>
#include <chrono>
#include <iomanip>
#include <vector>
#include "file_carver.h"
#include "clip_validator.h"
#include "custody_log.h"
#include "timeline_normalizer.h"
#include "report_generator.h"
#include "ai_detector.h"

namespace fs = std::filesystem;

enum class VendorType { HIKVISION, GODREJ_DAHUA, CUSTOM_MOCK, UNKNOWN };

static VendorType detectBrand(const std::string& filePath) {
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

static std::string brandToString(VendorType brand) {
    switch (brand) {
        case VendorType::GODREJ_DAHUA: return "Godrej/Dahua (.dav)";
        case VendorType::HIKVISION:    return "Hikvision";
        case VendorType::CUSTOM_MOCK:  return "Custom MOCK System";
        default:                       return "Unknown / Raw Disk Image";
    }
}

static bool convertToMP4(const std::string& inputFile, const std::string& outputFile) {
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

static std::string generateUuid() {
    std::random_device rd;
    std::mt19937_64 gen(rd());
    std::uniform_int_distribution<uint64_t> dis;
    uint64_t part1 = dis(gen);
    uint64_t part2 = dis(gen);

    part1 = (part1 & 0xFFFFFFFFFFFF0FFFULL) | 0x0000000000004000ULL;
    part2 = (part2 & 0x3FFFFFFFFFFFFFFFULL) | 0x8000000000000000ULL;

    char buf[37];
    std::snprintf(buf, sizeof(buf), "%08x-%04x-%04x-%04x-%012llx",
                  static_cast<uint32_t>(part1 >> 32),
                  static_cast<uint16_t>(part1 >> 16),
                  static_cast<uint16_t>(part1),
                  static_cast<uint16_t>(part2 >> 48),
                  static_cast<unsigned long long>(part2 & 0xFFFFFFFFFFFFULL));
    return std::string(buf);
}

static std::string currentUtcIso() {
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

static std::string escapeJsonString(const std::string& str) {
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

static std::string readFileContents(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) return "";
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static std::string processSingleFile(const std::string& caseId,
                                    const std::string& originalFilename,
                                    const std::string& diskImagePath) {
    fs::path caseDir = fs::path("cases") / caseId;
    fs::create_directories(caseDir);

    std::string custodyPath = (caseDir / "custody_log.jsonl").string();
    CustodyLog custodyLog(custodyPath);

    std::string inputHash = CustodyLog::computeFileSha256(diskImagePath);
    custodyLog.addEntry("ingestion", "Input disk image received and hashed", "", inputHash);

    VendorType brand = detectBrand(diskImagePath);
    std::string brandStr = brandToString(brand);
    custodyLog.addEntry("brand_detection", "Detected brand signature: " + brandStr, inputHash, brandStr);

    std::string strippedMp4 = (caseDir / "extracted_wrapped.mp4").string();
    std::string strippedHash;
    if (brand != VendorType::UNKNOWN) {
        if (convertToMP4(diskImagePath, strippedMp4)) {
            strippedHash = CustodyLog::computeFileSha256(strippedMp4);
            custodyLog.addEntry("wrapper_stripping", "Stripped proprietary container to MP4", inputHash, strippedHash);
        }
    }

    std::string carveOutputDir = (caseDir / "carved").string();
    FileCarver carver;
    auto chunks = carver.carve(diskImagePath, carveOutputDir);

    std::string carvedHashSummary;
    if (!chunks.empty()) {
        std::string concatHashes;
        for (const auto& ch : chunks) {
            concatHashes += CustodyLog::computeFileSha256(ch.output_path);
        }
        carvedHashSummary = CustodyLog::computeSha256(concatHashes);
    }
    custodyLog.addEntry("carving", "Carved " + std::to_string(chunks.size()) + " candidate streams",
                        inputHash, carvedHashSummary);

    ClipValidator validator;
    std::vector<ValidationResult> validations;
    validations.reserve(chunks.size());
    int validCount = 0;
    for (const auto& ch : chunks) {
        auto val = validator.validate(ch.output_path);
        if (val.is_valid) validCount++;
        validations.push_back(val);
    }

    custodyLog.addEntry("validation", "Validated " + std::to_string(validCount) + " / " +
                        std::to_string(chunks.size()) + " playable clips",
                        carvedHashSummary, std::to_string(validCount));

    AIDetector aiDetector;
    std::vector<ClipAIDetection> aiResults;
    if (aiDetector.is_available()) {
        for (size_t i = 0; i < chunks.size(); ++i) {
            const auto& ch = chunks[i];
            const auto& val = validations[i];
            if (val.is_valid && !ch.is_fragment) {
                auto aiDet = aiDetector.analyzeClip(ch.output_path);
                std::string clipHash = CustodyLog::computeFileSha256(ch.output_path);
                custodyLog.addEntry("ai_analysis",
                                    "Detected " + std::to_string(aiDet.total_detections) + " objects in " + ch.output_path,
                                    clipHash,
                                    std::to_string(aiDet.total_detections));
                aiResults.push_back(std::move(aiDet));
            }
        }
    }

    TimelineNormalizer normalizer;
    auto timeline = normalizer.estimateRelativeTimestamp(chunks, validations);
    custodyLog.addEntry("timeline", "Derived chronological capture windows for " +
                        std::to_string(timeline.size()) + " clips", "", "");

    int mismatchIdx = -1;
    bool chainOk = custodyLog.verifyChain(&mismatchIdx);

    ReportData repData;
    repData.source_file = originalFilename;
    repData.detected_brand = brandStr;
    repData.source_file_hash = inputHash;
    repData.generated_at_utc = currentUtcIso();
    repData.chain_verification_passed = chainOk;
    repData.chain_mismatch_index = mismatchIdx;
    repData.chunks = chunks;
    repData.validations = validations;
    repData.custody_entries = custodyLog.getEntries();
    repData.timeline = timeline;
    repData.ai_detections = aiResults;

    ReportGenerator reportGen(repData);
    std::string jsonPath = (caseDir / "report.json").string();
    std::string csvPath = (caseDir / "report.csv").string();
    std::string pdfPath = (caseDir / "report.pdf").string();

    reportGen.exportJSON(jsonPath);
    reportGen.exportCSV(csvPath);
    reportGen.exportPDF(pdfPath);

    std::ofstream aiSummaryFile(caseDir / "ai_summary.json");
    aiSummaryFile << "[\n";
    for (size_t i = 0; i < aiResults.size(); ++i) {
        const auto& a = aiResults[i];
        aiSummaryFile << "  {\n"
                      << "    \"clip_path\": \"" << escapeJsonString(a.clip_path) << "\",\n"
                      << "    \"total_detections\": " << a.total_detections << ",\n"
                      << "    \"distinct_classes\": [";
        for (size_t k = 0; k < a.distinct_classes.size(); ++k) {
            aiSummaryFile << "\"" << escapeJsonString(a.distinct_classes[k]) << "\""
                          << (k + 1 < a.distinct_classes.size() ? ", " : "");
        }
        aiSummaryFile << "]\n"
                      << "  }" << (i + 1 < aiResults.size() ? ",\n" : "\n");
    }
    aiSummaryFile << "]\n";

    std::ofstream metaFile(caseDir / "case_meta.json");
    metaFile << "{\n"
             << "  \"case_id\": \"" << caseId << "\",\n"
             << "  \"source_filename\": \"" << escapeJsonString(originalFilename) << "\",\n"
             << "  \"created_at\": \"" << currentUtcIso() << "\",\n"
             << "  \"status\": \"SUCCESS\",\n"
             << "  \"carved_chunks\": " << chunks.size() << ",\n"
             << "  \"valid_clips\": " << validCount << ",\n"
             << "  \"chain_verified\": " << (chainOk ? "true" : "false") << "\n"
             << "}\n";

    std::string jsonContent = readFileContents(jsonPath);
    if (!jsonContent.empty() && jsonContent.front() == '{') {
        std::string inject = "{\n  \"case_id\": \"" + caseId + "\",\n";
        jsonContent.replace(0, 2, inject);
    }
    return jsonContent;
}

int main(int argc, char* argv[]) {
    int port = 8080;
    std::string host = "0.0.0.0";

    if (argc > 1) {
        std::string arg1 = argv[1];
        auto colPos = arg1.find(':');
        if (colPos != std::string::npos) {
            host = arg1.substr(0, colPos);
            port = std::stoi(arg1.substr(colPos + 1));
        } else {
            try {
                port = std::stoi(arg1);
            } catch (...) {
                host = arg1;
            }
        }
    }
    if (argc > 2) {
        host = argv[2];
    }

    httplib::Server svr;

    auto applyCors = [](const httplib::Request&, httplib::Response& res) {
        res.set_header("Access-Control-Allow-Origin", "*");
        res.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        res.set_header("Access-Control-Allow-Headers", "*");
    };

    svr.set_post_routing_handler([applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
    });

    svr.Options(".*", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        res.status = 204;
    });

    svr.Get("/api/cases", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        fs::path casesRoot("cases");
        if (!fs::exists(casesRoot)) {
            res.set_content("[]", "application/json");
            return;
        }

        std::ostringstream oss;
        oss << "[\n";
        bool first = true;
        for (const auto& entry : fs::directory_iterator(casesRoot)) {
            if (entry.is_directory()) {
                fs::path metaPath = entry.path() / "case_meta.json";
                if (fs::exists(metaPath)) {
                    std::string metaContent = readFileContents(metaPath.string());
                    if (!metaContent.empty()) {
                        if (!first) oss << ",\n";
                        oss << metaContent;
                        first = false;
                    }
                }
            }
        }
        oss << "\n]";
        res.set_content(oss.str(), "application/json");
    });

    svr.Get(R"(/api/cases/([^/]+)/status)", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string caseId = req.matches[1];
        fs::path caseDir = fs::path("cases") / caseId;
        if (!fs::exists(caseDir)) {
            res.status = 404;
            res.set_content("{\"error\":\"Case not found\"}", "application/json");
            return;
        }

        std::ostringstream oss;
        oss << "{\n"
            << "  \"case_id\": \"" << caseId << "\",\n"
            << "  \"stage\": \"complete\",\n"
            << "  \"percent_complete\": 100,\n"
            << "  \"error\": null\n"
            << "}\n";
        res.set_content(oss.str(), "application/json");
    });

    svr.Get(R"(/api/cases/([^/]+)/ai_summary)", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string caseId = req.matches[1];
        fs::path p = fs::path("cases") / caseId / "ai_summary.json";
        if (!fs::exists(p)) {
            res.status = 404;
            res.set_content("[]", "application/json");
            return;
        }
        res.set_content(readFileContents(p.string()), "application/json");
    });

    svr.Get(R"(/api/cases/([^/]+)/report\.json)", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string caseId = req.matches[1];
        fs::path p = fs::path("cases") / caseId / "report.json";
        if (!fs::exists(p)) {
            res.status = 404;
            res.set_content("{\"error\":\"Report not found\"}", "application/json");
            return;
        }
        res.set_content(readFileContents(p.string()), "application/json");
    });

    svr.Get(R"(/api/cases/([^/]+)/report\.csv)", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string caseId = req.matches[1];
        fs::path p = fs::path("cases") / caseId / "report.csv";
        if (!fs::exists(p)) {
            res.status = 404;
            res.set_content("Report not found\n", "text/plain");
            return;
        }
        res.set_content(readFileContents(p.string()), "text/csv");
    });

    svr.Get(R"(/api/cases/([^/]+)/report\.pdf)", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string caseId = req.matches[1];
        fs::path p = fs::path("cases") / caseId / "report.pdf";
        if (!fs::exists(p)) {
            res.status = 404;
            res.set_content("Report not found\n", "text/plain");
            return;
        }
        res.set_content(readFileContents(p.string()), "application/pdf");
    });

    struct IncomingFile {
        std::string caseId;
        std::string filename;
        std::string diskPath;
        std::ofstream fileStream;
    };

    svr.Post("/api/analyze", [applyCors](const httplib::Request& req, httplib::Response& res, const httplib::ContentReader& content_reader) {
        applyCors(req, res);
        if (!req.is_multipart_form_data()) {
            res.status = 400;
            res.set_content("{\"error\":\"Expected multipart/form-data\"}", "application/json");
            return;
        }

        std::vector<IncomingFile> incomingFiles;

        content_reader(
            [&incomingFiles](const httplib::FormData& file) {
                std::string fname = file.filename.empty() ? "uploaded_disk.img" : file.filename;
                std::string caseId = generateUuid();
                fs::path caseDir = fs::path("cases") / caseId;
                fs::create_directories(caseDir);
                std::string path = (caseDir / fname).string();

                IncomingFile item;
                item.caseId = caseId;
                item.filename = fname;
                item.diskPath = path;
                item.fileStream.open(path, std::ios::binary);
                incomingFiles.push_back(std::move(item));
                return true;
            },
            [&incomingFiles](const char* data, size_t data_length) {
                if (!incomingFiles.empty() && incomingFiles.back().fileStream.is_open()) {
                    incomingFiles.back().fileStream.write(data, data_length);
                }
                return true;
            }
        );

        for (auto& item : incomingFiles) {
            if (item.fileStream.is_open()) {
                item.fileStream.close();
            }
        }

        if (incomingFiles.empty()) {
            res.status = 400;
            res.set_content("{\"error\":\"No files uploaded\"}", "application/json");
            return;
        }

        std::vector<std::string> perFileJsonReports;
        for (const auto& item : incomingFiles) {
            std::string reportJson = processSingleFile(item.caseId, item.filename, item.diskPath);
            perFileJsonReports.push_back(reportJson);
        }

        if (perFileJsonReports.size() == 1) {
            res.set_content(perFileJsonReports[0], "application/json");
        } else {
            std::ostringstream oss;
            oss << "[\n";
            for (size_t i = 0; i < perFileJsonReports.size(); ++i) {
                oss << perFileJsonReports[i] << (i + 1 < perFileJsonReports.size() ? ",\n" : "\n");
            }
            oss << "]";
            res.set_content(oss.str(), "application/json");
        }
    });

    std::cout << "API server running on http://" << host << ":" << port << "\n";
    svr.listen(host.c_str(), port);

    return 0;
}
