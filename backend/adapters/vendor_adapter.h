#pragma once

#include <string>
#include "../utils.h"

namespace universa {

/// Abstract base class for vendor-specific CCTV/DVR container decoders.
class VendorAdapter {
public:
    virtual ~VendorAdapter() = default;

    /// Checks if the file header/stream matches this vendor's signature.
    virtual bool matchesSignature(const std::string& filePath) const = 0;

    /// Returns human-readable vendor name.
    virtual std::string vendorName() const = 0;

    /// Returns the associated VendorType enum.
    virtual VendorType vendorType() const = 0;

    /// Decodes or demuxes proprietary stream into standard playable MP4.
    virtual bool decode(const std::string& inputFile, const std::string& outputFile) = 0;
};

} // namespace universa
