#include "httplib.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <random>
#include <chrono>
#include <iomanip>
#include <vector>
#include <thread>
#include "file_carver.h"
#include "clip_validator.h"
#include "custody_log.h"
#include "timeline_normalizer.h"
#include "report_generator.h"
#include "ai_detector.h"

#include "utils.h"
#include "disk_imager.h"
#include "adapters/adapter_registry.h"

namespace fs = std::filesystem;

using universa::VendorType;
using universa::escapeJsonString;
using universa::currentUtcIso;
using universa::detectBrand;
using universa::brandToString;
using universa::convertToMP4;

// Single static AI Detector instance loaded once at startup
static AIDetector gAiDetector;

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

static std::string readFileContents(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) return "";
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static std::string processSingleFile(const std::string& caseId,
                                    const std::string& originalFilename,
                                    const std::string& diskImagePath,
                                    AIDetector& aiDetector = gAiDetector) {
    fs::path caseDir = fs::path("cases") / caseId;
    fs::create_directories(caseDir);

    std::string custodyPath = (caseDir / "custody_log.jsonl").string();
    CustodyLog custodyLog(custodyPath);

    std::string inputHash = CustodyLog::computeFileSha256(diskImagePath);
    std::string inputMd5 = CustodyLog::computeFileMd5(diskImagePath);
    custodyLog.addEntry("ingestion", "Input disk image received and hashed (SHA-256 + MD5)", "", "SHA256:" + inputHash + " | MD5:" + inputMd5);

    universa::VendorType brand = universa::AdapterRegistry::instance().detectVendor(diskImagePath);
    std::string brandStr = universa::AdapterRegistry::instance().getVendorName(diskImagePath);
    custodyLog.addEntry("brand_detection", "Detected brand signature: " + brandStr, inputHash, brandStr);

    std::string strippedMp4 = (caseDir / "extracted_wrapped.mp4").string();
    std::string strippedHash;
    if (brand != universa::VendorType::UNKNOWN) {
        std::string failureReason;
        if (universa::AdapterRegistry::instance().decodeWithIsolation(diskImagePath, strippedMp4, &failureReason)) {
            strippedHash = CustodyLog::computeFileSha256(strippedMp4);
            custodyLog.addEntry("wrapper_stripping", "Stripped proprietary container to MP4", inputHash, strippedHash);
        } else if (!failureReason.empty()) {
            custodyLog.addEntry("wrapper_stripping", "status: ADAPTER_FAILED (" + failureReason + ")", inputHash, "ADAPTER_FAILED");
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
    repData.source_file_md5 = inputMd5;
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

    // Interconnect: asynchronously notify Python Timeline & ML Engine (port 8000)
    std::thread([caseId]() {
        try {
            httplib::Client cli("127.0.0.1", 8000);
            cli.set_connection_timeout(1, 0);
            cli.set_read_timeout(15, 0);
            cli.Post(("/api/v1/cases/" + caseId + "/process-carved").c_str(), "", "application/json");
        } catch (...) {}
    }).detach();

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

    svr.Get(R"(/api/cases/([^/]+)/ml_summary)", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string caseId = req.matches[1];
        fs::path p = fs::path("cases") / caseId / "universa_ml_summary.json";
        if (!fs::exists(p)) {
            p = fs::path("cases") / caseId / "ai_summary.json";
        }
        if (!fs::exists(p)) {
            res.status = 404;
            res.set_content("{}", "application/json");
            return;
        }
        res.set_content(readFileContents(p.string()), "application/json");
    });

    svr.Get(R"(/api/cases/([^/]+)/timeline)", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string caseId = req.matches[1];
        try {
            httplib::Client cli("127.0.0.1", 8000);
            cli.set_connection_timeout(1, 0);
            cli.set_read_timeout(5, 0);
            auto resp = cli.Get(("/api/v1/timeline/" + caseId).c_str());
            if (resp && resp->status == 200) {
                res.set_content(resp->body, "application/json");
                return;
            }
        } catch (...) {}
        res.status = 404;
        res.set_content("{\"events\":[]}", "application/json");
    });

    svr.Get("/api/search", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string q = req.has_param("q") ? req.get_param_value("q") : "";
        try {
            httplib::Client cli("127.0.0.1", 8000);
            cli.set_connection_timeout(1, 0);
            cli.set_read_timeout(5, 0);
            auto resp = cli.Get(("/api/v1/search?q=" + httplib::encode_uri(q)).c_str());
            if (resp && resp->status == 200) {
                res.set_content(resp->body, "application/json");
                return;
            }
        } catch (...) {}
        res.set_content("[]", "application/json");
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

    svr.Post("/api/acquire", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string source;
        std::string destination;

        if (!req.body.empty()) {
            auto extractField = [](const std::string& json, const std::string& key) -> std::string {
                std::string pattern = "\"" + key + "\":";
                size_t pos = json.find(pattern);
                if (pos == std::string::npos) return "";
                size_t startQuote = json.find('"', pos + pattern.size());
                if (startQuote == std::string::npos) return "";
                size_t endQuote = json.find('"', startQuote + 1);
                if (endQuote == std::string::npos) return "";
                return json.substr(startQuote + 1, endQuote - startQuote - 1);
            };
            source = extractField(req.body, "source");
            destination = extractField(req.body, "destination");
        }
        if (source.empty() && req.has_param("source")) {
            source = req.get_param_value("source");
        }
        if (destination.empty() && req.has_param("destination")) {
            destination = req.get_param_value("destination");
        }

        if (source.empty() || destination.empty()) {
            res.status = 400;
            res.set_content("{\"error\":\"Both 'source' and 'destination' fields are required.\"}", "application/json");
            return;
        }

        auto acq = universa::DiskImager::acquire(source, destination);
        if (!acq.success) {
            res.status = 500;
            std::ostringstream err;
            err << "{\"status\":\"error\",\"error\":\"" << escapeJsonString(acq.error_message) << "\"}";
            res.set_content(err.str(), "application/json");
            return;
        }

        std::ostringstream json;
        json << "{\n"
             << "  \"status\": \"success\",\n"
             << "  \"source\": \"" << escapeJsonString(acq.source_path) << "\",\n"
             << "  \"destination\": \"" << escapeJsonString(acq.destination_path) << "\",\n"
             << "  \"bytes_acquired\": " << acq.bytes_acquired << ",\n"
             << "  \"sha256\": \"" << acq.sha256_hash << "\",\n"
             << "  \"md5\": \"" << acq.md5_hash << "\",\n"
             << "  \"duration_seconds\": " << std::fixed << std::setprecision(2) << acq.duration_seconds << ",\n"
             << "  \"start_time_utc\": \"" << acq.start_time_utc << "\",\n"
             << "  \"end_time_utc\": \"" << acq.end_time_utc << "\",\n"
             << "  \"compliance_standard\": \"BSA 2023 §63\",\n"
             << "  \"iso_standard\": \"ISO/IEC 27037:2012\"\n"
             << "}\n";
        res.set_content(json.str(), "application/json");
    });

    svr.Post(R"(/api/cases/([^/]+)/face_search)", [applyCors](const httplib::Request& req, httplib::Response& res) {
        applyCors(req, res);
        std::string caseId = req.matches[1];
        try {
            httplib::Client cli("127.0.0.1", 8000);
            cli.set_connection_timeout(1, 0);
            cli.set_read_timeout(10, 0);
            auto resp = cli.Post(("/api/v1/cases/" + caseId + "/face_search").c_str(), req.body, "application/json");
            if (resp && (resp->status == 200 || resp->status == 201)) {
                res.status = resp->status;
                res.set_content(resp->body, "application/json");
                return;
            }
        } catch (...) {}
        res.set_content("{\"case_id\":\"" + escapeJsonString(caseId) + "\",\"matches\":[],\"status\":\"ready\"}", "application/json");
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
            std::string reportJson = processSingleFile(item.caseId, item.filename, item.diskPath, gAiDetector);
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
