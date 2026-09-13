#pragma once

#include <string>
#include <vector>

#ifdef ENABLE_AI_DETECTION
#include <opencv2/opencv.hpp>
#include <opencv2/dnn.hpp>
#endif

struct BoundingBox {
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
};

struct Detection {
    std::string class_name;
    float confidence = 0.0f;
    BoundingBox bounding_box;
};

struct DetectionFrame {
    double timestamp_in_clip_seconds = 0.0;
    std::vector<Detection> detections;
};

struct ClipAIDetection {
    std::string clip_path;
    bool analyzed = false;
    std::vector<std::string> distinct_classes;
    size_t total_detections = 0;
    std::vector<DetectionFrame> frames;
    std::string error_message;
};

class AIDetector {
public:
    explicit AIDetector(const std::string& cfgPath = "models/yolov4-tiny.cfg",
                        const std::string& weightsPath = "models/yolov4-tiny.weights",
                        const std::string& namesPath = "models/coco.names",
                        float confThresh = 0.5f,
                        float nmsThresh = 0.4f,
                        double sampleIntervalSeconds = 2.0);

    bool is_available() const;
    void setConfidenceThreshold(float thresh);
    void setNmsThreshold(float thresh);
    void setSampleInterval(double seconds);

    ClipAIDetection analyzeClip(const std::string& clipPath);

private:
    bool available = false;
    float confThreshold = 0.5f;
    float nmsThreshold = 0.4f;
    double sampleInterval = 2.0;
    std::vector<std::string> classNames;

#ifdef ENABLE_AI_DETECTION
    cv::dnn::Net net;
    std::vector<std::string> outNames;
    std::vector<Detection> detectInMat(const cv::Mat& frame);
#endif
};

