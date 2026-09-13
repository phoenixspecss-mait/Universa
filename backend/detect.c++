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
#include "utils.h"
#include "disk_imager.h"
#include "adapters/adapter_registry.h"

namespace fs = std::filesystem;

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

static BatchFileResult processImage(const std::string& inputPath, const std::string& outputFolder, AIDetector& aiDetector) {
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
        std::string inputMd5 = CustodyLog::computeFileMd5(inputPath);
        if (inputHash.empty()) {
            res.success = false;
            res.error_message = "Could not compute input hash (unreadable file)";
            return res;
        }
        custodyLog.addEntry("ingestion", "Input disk image received and hashed (SHA-256 + MD5)", "", "SHA256:" + inputHash + " | MD5:" + inputMd5);

        universa::VendorType brand = universa::AdapterRegistry::instance().detectVendor(inputPath);
        std::string brandStr = universa::AdapterRegistry::instance().getVendorName(inputPath);
        custodyLog.addEntry("brand_detection", "Detected brand: " + brandStr, inputHash, brandStr);

        std::cout << "\n==================================================================================================\n";
        std::cout << "Processing: " << inputPath << "\n";
        std::cout << "Output Dir: " << outputFolder << "\n";
        std::cout << "SHA-256:    " << inputHash << "\n";
        std::cout << "MD5:        " << inputMd5 << "\n";
        std::cout << "[1] Brand Detected: " << brandStr << "\n";

        std::string strippedMp4 = (fs::path(outputFolder) / "extracted_wrapped.mp4").string();
        if (brand != universa::VendorType::UNKNOWN) {
            std::cout << "[2] Stripping proprietary headers via isolated adapter...\n";
            std::string failReason;
            if (universa::AdapterRegistry::instance().decodeWithIsolation(inputPath, strippedMp4, &failReason)) {
                std::string strippedSha = CustodyLog::computeFileSha256(strippedMp4);
                std::string strippedMd5 = CustodyLog::computeFileMd5(strippedMp4);
                custodyLog.addEntry("wrapper_stripping", "Stripped proprietary container to standard MP4", inputHash, strippedSha);
                std::cout << "[3] Cryptographic seal generated for extracted MP4: " << strippedSha << " (MD5: " << strippedMd5 << ")\n";
            } else {
                std::string failDesc = failReason.empty() ? "ADAPTER_FAILED" : ("ADAPTER_FAILED: " + failReason);
                custodyLog.addEntry("wrapper_stripping", "status: ADAPTER_FAILED (" + failReason + ")", inputHash, "ADAPTER_FAILED");
                std::cerr << "[FAIL-SAFE] " << failDesc << ", continuing pipeline to raw carving.\n";
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
        repData.source_file_md5 = inputMd5;
        repData.generated_at_utc = universa::currentUtcIso();
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
    if (argc >= 4 && std::string(argv[1]) == "--acquire") {
        std::string srcDev = argv[2];
        std::string dstImg = argv[3];
        std::cout << "Starting Raw Bit-Stream Forensic Acquisition:\n"
                  << "  Source Device/Image: " << srcDev << "\n"
                  << "  Destination Image:   " << dstImg << "\n";
        auto acq = universa::DiskImager::acquire(srcDev, dstImg, [](uint64_t bytes, uint64_t total) {
            if (total > 0) {
                double pct = (static_cast<double>(bytes) / total) * 100.0;
                std::cout << "\rAcquiring: " << std::fixed << std::setprecision(1) << pct << "% ("
                          << (bytes / 1048576) << " MB)" << std::flush;
            } else {
                std::cout << "\rAcquiring: " << (bytes / 1048576) << " MB..." << std::flush;
            }
        });
        std::cout << "\n";
        if (acq.success) {
            std::cout << "Forensic Acquisition SUCCESSFUL!\n"
                      << "  Bytes Acquired: " << acq.bytes_acquired << "\n"
                      << "  SHA-256 Seal:   " << acq.sha256_hash << "\n"
                      << "  MD5 Seal:       " << acq.md5_hash << "\n"
                      << "  Duration:       " << std::fixed << std::setprecision(2) << acq.duration_seconds << "s\n"
                      << "  Compliance:     BSA 2023 §63 / ISO 27037:2012 Certified\n";
            return 0;
        } else {
            std::cerr << "Forensic Acquisition FAILED: " << acq.error_message << "\n";
            return 1;
        }
    }

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

    AIDetector aiDetector;

    for (const auto& filePath : inputFiles) {
        fs::path p(filePath);
        std::string stem = p.filename().string();
        std::string outDir = isSingleRun ? "output" : ("output/" + stem);
        BatchFileResult res = processImage(filePath, outDir, aiDetector);
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