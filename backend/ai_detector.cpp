#include "ai_detector.h"
#include <iostream>
#include <fstream>
#include <filesystem>
#include <set>
#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace fs = std::filesystem;

static std::string resolveModelPath(const std::string& explicitPath, const char* envVar, const std::string& defaultSubpath) {
    if (const char* env = std::getenv(envVar)) {
        if (fs::exists(env)) return std::string(env);
    }
    if (const char* dir = std::getenv("UNIVERSA_MODELS_DIR")) {
        fs::path p = fs::path(dir) / defaultSubpath;
        if (fs::exists(p)) return p.string();
    }
    if (fs::exists(explicitPath)) {
        return explicitPath;
    }
    // Fallback relative paths
    std::vector<std::string> searchPaths = {
        defaultSubpath,
        "backend/" + defaultSubpath,
        "../" + defaultSubpath,
        "../../" + defaultSubpath
    };
    for (const auto& sp : searchPaths) {
        if (fs::exists(sp)) return sp;
    }
    return explicitPath;
}

AIDetector::AIDetector(const std::string& cfgPath,
                       const std::string& weightsPath,
                       const std::string& namesPath,
                       float confThresh,
                       float nmsThresh,
                       double sampleIntervalSeconds)
    : confThreshold(confThresh),
      nmsThreshold(nmsThresh),
      sampleInterval(sampleIntervalSeconds) {

#ifdef ENABLE_AI_DETECTION
    std::string actualCfg = resolveModelPath(cfgPath, "UNIVERSA_YOLO_CFG", "models/yolov4-tiny.cfg");
    std::string actualWeights = resolveModelPath(weightsPath, "UNIVERSA_YOLO_WEIGHTS", "models/yolov4-tiny.weights");
    std::string actualNames = resolveModelPath(namesPath, "UNIVERSA_YOLO_NAMES", "models/coco.names");

    if (!fs::exists(actualCfg) || !fs::exists(actualWeights) || !fs::exists(actualNames)) {
        std::cout << "AI model not found at " << actualWeights << ", skipping detection\n";
        available = false;
        return;
    }

    try {
        std::ifstream ifs(actualNames);
        if (!ifs.is_open()) {
            std::cout << "AI model not found at " << actualNames << ", skipping detection\n";
            available = false;
            return;
        }
        std::string line;
        while (std::getline(ifs, line)) {
            while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) {
                line.pop_back();
            }
            if (!line.empty()) {
                classNames.push_back(line);
            }
        }

        net = cv::dnn::readNetFromDarknet(actualCfg, actualWeights);
        if (net.empty()) {
            std::cout << "AI model failed to load from " << actualWeights << ", skipping detection\n";
            available = false;
            return;
        }

        net.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
        net.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
        outNames = net.getUnconnectedOutLayersNames();
        available = true;
    } catch (const std::exception& e) {
        std::cout << "AI model failed to load: " << e.what() << ", skipping detection\n";
        available = false;
    } catch (...) {
        std::cout << "AI model failed to load, skipping detection\n";
        available = false;
    }
#else
    std::cout << "AI detection disabled at compile time, skipping detection\n";
    available = false;
#endif
}

bool AIDetector::is_available() const {
    return available;
}

void AIDetector::setConfidenceThreshold(float thresh) {
    confThreshold = thresh;
}

void AIDetector::setNmsThreshold(float thresh) {
    nmsThreshold = thresh;
}

void AIDetector::setSampleInterval(double seconds) {
    sampleInterval = (seconds > 0.0) ? seconds : 2.0;
}

#ifdef ENABLE_AI_DETECTION
std::vector<Detection> AIDetector::detectInMat(const cv::Mat& frame) {
    if (frame.empty() || net.empty()) return {};

    cv::Mat blob = cv::dnn::blobFromImage(frame, 1.0 / 255.0, cv::Size(416, 416), cv::Scalar(), true, false);
    net.setInput(blob);

    std::vector<cv::Mat> outs;
    net.forward(outs, outNames);

    std::vector<int> classIds;
    std::vector<float> confidences;
    std::vector<cv::Rect> boxes;

    for (const auto& out : outs) {
        float* data = reinterpret_cast<float*>(out.data);
        for (int i = 0; i < out.rows; ++i, data += out.cols) {
            float objectness = data[4];
            if (objectness < confThreshold) continue;

            cv::Mat scores = out.row(i).colRange(5, out.cols);
            cv::Point classIdPoint;
            double maxScore;
            cv::minMaxLoc(scores, nullptr, &maxScore, nullptr, &classIdPoint);

            float conf = static_cast<float>(maxScore) * objectness;
            if (conf >= confThreshold) {
                int centerX = static_cast<int>(data[0] * frame.cols);
                int centerY = static_cast<int>(data[1] * frame.rows);
                int width = static_cast<int>(data[2] * frame.cols);
                int height = static_cast<int>(data[3] * frame.rows);
                int left = centerX - width / 2;
                int top = centerY - height / 2;

                boxes.push_back(cv::Rect(left, top, width, height));
                confidences.push_back(conf);
                classIds.push_back(classIdPoint.x);
            }
        }
    }

    std::vector<int> indices;
    cv::dnn::NMSBoxes(boxes, confidences, confThreshold, nmsThreshold, indices);

    std::vector<Detection> results;
    results.reserve(indices.size());
    for (int idx : indices) {
        Detection d;
        int cid = classIds[idx];
        d.class_name = (cid >= 0 && cid < static_cast<int>(classNames.size()))
                           ? classNames[cid]
                           : ("class_" + std::to_string(cid));
        d.confidence = confidences[idx];
        d.bounding_box = { boxes[idx].x, boxes[idx].y, boxes[idx].width, boxes[idx].height };
        results.push_back(d);
    }
    return results;
}
#endif

ClipAIDetection AIDetector::analyzeClip(const std::string& clipPath) {
    ClipAIDetection res;
    res.clip_path = clipPath;

    if (!available) {
        res.analyzed = false;
        res.error_message = "AI model not available";
        return res;
    }

#ifdef ENABLE_AI_DETECTION
    try {
        cv::VideoCapture cap(clipPath);
        if (!cap.isOpened()) {
            res.analyzed = false;
            res.error_message = "Failed to open video clip with OpenCV";
            return res;
        }

        double fps = cap.get(cv::CAP_PROP_FPS);
        if (fps <= 0.0 || std::isnan(fps) || std::isinf(fps)) {
            fps = 25.0;
        }

        int frameInterval = std::max(1, static_cast<int>(std::round(fps * sampleInterval)));
        cv::Mat frame;
        int frameIdx = 0;
        std::set<std::string> distinctSet;

        while (cap.read(frame)) {
            if (frame.empty()) break;

            if (frameIdx % frameInterval == 0) {
                double ts = static_cast<double>(frameIdx) / fps;
                auto detections = detectInMat(frame);
                for (const auto& det : detections) {
                    distinctSet.insert(det.class_name);
                    res.total_detections++;
                }
                res.frames.push_back({ ts, std::move(detections) });
            }
            frameIdx++;
        }

        res.distinct_classes.assign(distinctSet.begin(), distinctSet.end());
        res.analyzed = true;
        return res;
    } catch (const std::exception& e) {
        res.analyzed = false;
        res.error_message = e.what();
        return res;
    } catch (...) {
        res.analyzed = false;
        res.error_message = "Unknown exception during clip analysis";
        return res;
    }
#else
    res.analyzed = false;
    res.error_message = "OpenCV AI detection not enabled at compile time";
    return res;
#endif
}

