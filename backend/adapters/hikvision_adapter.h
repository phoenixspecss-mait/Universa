#pragma once

#include "vendor_adapter.h"

namespace universa {

class HikvisionAdapter : public VendorAdapter {
public:
    bool matchesSignature(const std::string& filePath) const override;
    std::string vendorName() const override;
    VendorType vendorType() const override;
    bool decode(const std::string& inputFile, const std::string& outputFile) override;
};

} // namespace universa
