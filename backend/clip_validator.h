#pragma once

#include <string>

struct ValidationResult {
    bool is_valid = false;
    double duration_seconds = 0.0;
    std::string codec_name;
    int width = 0;
    int height = 0;
    std::string error_message;
};

class ClipValidator {
public:
    ClipValidator();
    ~ClipValidator();

    ValidationResult validate(const std::string& filePath);
};

