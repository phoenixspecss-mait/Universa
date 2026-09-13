#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <algorithm>
#include <iomanip>
#include <sstream>
#include <filesystem>
#include <chrono>
#include <ctime>
#include <openssl/sha.h>
#include "file_carver.h"
#include "clip_validator.h"
#include "custody_log.h"
#include "timeline_normalizer.h"
#include "report_generator.h"
#include "ai_detector.h"

namespace fs = std::filesystem;

enum class VendorType { HIKVISION, GODREJ_DAHUA, CUSTOM_MOCK, UNKNOWN };

class AIPreprocessor {
public:
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

    bool convertToMP4(const std::string& inputFile, const std::string& outputFile, VendorType) {
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

    std::string generateHash(const std::string& filePath) {
        std::ifstream file(filePath, std::ios::binary);
        if (!file.is_open()) return "";

        SHA256_CTX sha256;
        SHA256_Init(&sha256);

        char buffer[8192];
        while (file.read(buffer, sizeof(buffer)) || file.gcount() > 0) {
            SHA256_Update(&sha256, buffer, file.gcount());
        }

        unsigned char hash[SHA256_DIGEST_LENGTH];
        SHA256_Final(hash, &sha256);

        std::stringstream ss;
        for (int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
            ss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
        }
        return ss.str();
    }
};

struct BatchFileResult {
    std::string input_file;
    size_t total_carved = 0;
    size_t valid_count = 0;
    size_t invalid_count = 0;
    size_t fragment_count = 0;
    bool chain_verified = false;
    bool success = false;
    std::string error_message;
    std::string json_report_path;
    std::string csv_report_path;
    std::string pdf_report_path;
};

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

static BatchFileResult processImage(const std::string& inputPath, const std::string& outputFolder) {
    BatchFileResult res;
    res.input_file = inputPath;

    try {
        if (!fs::exists(inputPath) || fs::is_directory(inputPath)) {
            res.success = false;
            res.error_message = "File does not exist or is a directory";
            return res;
        }

        fs::create_directories(outputFolder);

        std::string custodyPath = (fs::path(outputFolder) / "custody_log.jsonl").string();
        CustodyLog custodyLog(custodyPath);

        std::string inputHash = CustodyLog::computeFileSha256(inputPath);
        if (inputHash.empty()) {
            res.success = false;
            res.error_message = "Could not compute input hash (unreadable file)";
            return res;
        }
        custodyLog.addEntry("ingestion", "Input disk image received and hashed", "", inputHash);

        AIPreprocessor engine;
        VendorType brand = engine.detectBrand(inputPath);
        std::string brandStr = "Unknown / Raw Disk Image";
        switch (brand) {
            case VendorType::GODREJ_DAHUA: brandStr = "Godrej/Dahua (.dav)"; break;
            case VendorType::HIKVISION:    brandStr = "Hikvision"; break;
            case VendorType::CUSTOM_MOCK:  brandStr = "Custom MOCK System"; break;
            default:                       break;
        }
        custodyLog.addEntry("brand_detection", "Detected brand: " + brandStr, inputHash, brandStr);

        std::cout << "\n==================================================================================================\n";
        std::cout << "Processing: " << inputPath << "\n";
        std::cout << "Output Dir: " << outputFolder << "\n";
        std::cout << "SHA-256:    " << inputHash << "\n";
        std::cout << "[1] Brand Detected: " << brandStr << "\n";

        std::string strippedMp4 = (fs::path(outputFolder) / "extracted_wrapped.mp4").string();
        if (brand != VendorType::UNKNOWN) {
            std::cout << "[2] Stripping proprietary headers...\n";
            if (engine.convertToMP4(inputPath, strippedMp4, brand)) {
                std::string strippedHash = engine.generateHash(strippedMp4);
                custodyLog.addEntry("wrapper_stripping", "Stripped proprietary container to standard MP4", inputHash, strippedHash);
                std::cout << "[3] Cryptographic seal generated for extracted MP4: " << strippedHash << "\n";
            }
        }

        std::cout << "[4] Carving binary disk image...\n";
        std::string carveDir = (fs::path(outputFolder) / "carved").string();
        FileCarver carver;
        auto chunks = carver.carve(inputPath, carveDir);
        res.total_carved = chunks.size();

        std::string concatHashes;
        for (const auto& ch : chunks) {
            if (ch.is_fragment) res.fragment_count++;
            concatHashes += CustodyLog::computeFileSha256(ch.output_path);
        }
        std::string carvedHashSummary = CustodyLog::computeSha256(concatHashes);
        custodyLog.addEntry("carving", "Carved " + std::to_string(chunks.size()) + " candidate streams", inputHash, carvedHashSummary);

        std::cout << "[5] Validating Carved Chunks...\n";
        ClipValidator validator;
        std::vector<ValidationResult> validations;
        validations.reserve(chunks.size());

        std::cout << "------------------------------------------------------------------------------------------------------------------\n";
        std::cout << std::left
                  << std::setw(14) << "Offset(Dec)"
                  << std::setw(14) << "Offset(Hex)"
                  << std::setw(18) << "Signature"
                  << std::setw(12) << "Carve"
                  << std::setw(10) << "Valid"
                  << std::setw(10) << "Codec"
                  << std::setw(12) << "Resolution"
                  << std::setw(12) << "Duration"
                  << "Output Path\n";
        std::cout << "------------------------------------------------------------------------------------------------------------------\n";

        for (const auto& chunk : chunks) {
            std::stringstream hexStream;
            hexStream << "0x" << std::hex << std::uppercase << std::setfill('0') << std::setw(8) << chunk.offset;

            ValidationResult val = validator.validate(chunk.output_path);
            if (val.is_valid) res.valid_count++;
            else res.invalid_count++;
            validations.push_back(val);

            std::string resStr = (val.width > 0 && val.height > 0)
                ? (std::to_string(val.width) + "x" + std::to_string(val.height))
                : "-";
            std::string durStr = (val.duration_seconds > 0.0)
                ? (std::to_string(val.duration_seconds).substr(0, 4) + "s")
                : "-";
            std::string codecStr = val.codec_name.empty() ? "-" : val.codec_name;

            std::cout << std::left
                      << std::setw(14) << chunk.offset
                      << std::setw(14) << hexStream.str()
                      << std::setw(18) << chunk.signature_name
                      << std::setw(12) << (chunk.is_fragment ? "Fragment" : "Intact")
                      << std::setw(10) << (val.is_valid ? "VALID" : "INVALID")
                      << std::setw(10) << codecStr
                      << std::setw(12) << resStr
                      << std::setw(12) << durStr
                      << chunk.output_path << "\n";
        }
        std::cout << "------------------------------------------------------------------------------------------------------------------\n";

        custodyLog.addEntry("validation", "Validated " + std::to_string(res.valid_count) + " / " +
                            std::to_string(chunks.size()) + " playable clips",
                            carvedHashSummary, std::to_string(res.valid_count));

        AIDetector aiDetector;
        std::vector<ClipAIDetection> aiResults;
        if (aiDetector.is_available()) {
            std::cout << "[6] Running AI Object Detection (YOLOv4-tiny)...\n";
            for (size_t i = 0; i < chunks.size(); ++i) {
                const auto& chunk = chunks[i];
                const auto& val = validations[i];
                if (val.is_valid && !chunk.is_fragment) {
                    std::cout << "    Scanning " << chunk.output_path << "...\n";
                    auto aiDet = aiDetector.analyzeClip(chunk.output_path);
                    std::string clipHash = CustodyLog::computeFileSha256(chunk.output_path);
                    custodyLog.addEntry("ai_analysis",
                                        "Detected " + std::to_string(aiDet.total_detections) + " objects across " +
                                        std::to_string(aiDet.frames.size()) + " sampled frames in " + chunk.output_path,
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
        res.chain_verified = chainOk;

        std::string jsonPath = (fs::path(outputFolder) / "report.json").string();
        std::string csvPath = (fs::path(outputFolder) / "report.csv").string();
        std::string pdfPath = (fs::path(outputFolder) / "report.pdf").string();

        ReportData repData;
        repData.source_file = inputPath;
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
        reportGen.exportJSON(jsonPath);
        reportGen.exportCSV(csvPath);
        reportGen.exportPDF(pdfPath);

        res.json_report_path = jsonPath;
        res.csv_report_path = csvPath;
        res.pdf_report_path = pdfPath;
        res.success = true;

        std::cout << "Chain of custody verification: " << (chainOk ? "PASSED" : "FAILED")
                  << " (" << custodyLog.getEntries().size() << " entries)\n";
        std::cout << "Reports generated: " << jsonPath << ", " << csvPath << ", " << pdfPath << "\n";

    } catch (const std::exception& e) {
        res.success = false;
        res.error_message = e.what();
        std::cerr << "Error processing file " << inputPath << ": " << e.what() << "\n";
    } catch (...) {
        res.success = false;
        res.error_message = "Unknown fatal error occurred";
        std::cerr << "Unknown fatal error processing " << inputPath << "\n";
    }

    return res;
}

int main(int argc, char* argv[]) {
    std::vector<std::string> inputFiles;

    if (argc > 1) {
        std::string firstArg = argv[1];
        if (fs::is_directory(firstArg)) {
            for (const auto& entry : fs::directory_iterator(firstArg)) {
                if (entry.is_regular_file()) {
                    inputFiles.push_back(entry.path().string());
                }
            }
            std::sort(inputFiles.begin(), inputFiles.end());
        } else {
            for (int i = 1; i < argc; ++i) {
                inputFiles.push_back(argv[i]);
            }
        }
    } else {
        inputFiles.push_back("mock_dvr_ch01.dav");
    }

    if (inputFiles.empty()) {
        std::cerr << "No input files found to process.\n";
        return 1;
    }

    bool isSingleRun = (inputFiles.size() == 1);
    std::vector<BatchFileResult> results;

    for (const auto& filePath : inputFiles) {
        fs::path p(filePath);
        std::string stem = p.filename().string();
        std::string outDir = isSingleRun ? "output" : ("output/" + stem);
        BatchFileResult res = processImage(filePath, outDir);
        results.push_back(res);
    }

    if (!isSingleRun) {
        std::cout << "\n==================================================================================================\n";
        std::cout << "                                AGGREGATE BATCH SUMMARY                                           \n";
        std::cout << "==================================================================================================\n";
        std::cout << std::left
                  << std::setw(28) << "Input File"
                  << std::setw(14) << "Total Carved"
                  << std::setw(12) << "Valid"
                  << std::setw(12) << "Invalid"
                  << std::setw(12) << "Fragments"
                  << std::setw(16) << "Custody Chain"
                  << "Status\n";
        std::cout << "--------------------------------------------------------------------------------------------------\n";

        for (const auto& r : results) {
            std::string filename = fs::path(r.input_file).filename().string();
            std::string chainStr = r.success ? (r.chain_verified ? "PASSED" : "FAILED") : "N/A";
            std::string statusStr = r.success ? "SUCCESS" : ("FAILED: " + r.error_message);

            std::cout << std::left
                      << std::setw(28) << filename
                      << std::setw(14) << r.total_carved
                      << std::setw(12) << r.valid_count
                      << std::setw(12) << r.invalid_count
                      << std::setw(12) << r.fragment_count
                      << std::setw(16) << chainStr
                      << statusStr << "\n";
        }
        std::cout << "==================================================================================================\n";
    }

    return 0;
}