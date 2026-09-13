#pragma once

#include <vector>
#include <memory>
#include <string>
#include "vendor_adapter.h"

namespace universa {

class AdapterRegistry {
public:
    AdapterRegistry();

    /// Registers a custom or plug-in vendor adapter.
    void registerAdapter(std::unique_ptr<VendorAdapter> adapter);

    /// Identifies the vendor adapter matching the input file's signature.
    VendorAdapter* findAdapter(const std::string& filePath) const;

    /// Returns the detected VendorType.
    VendorType detectVendor(const std::string& filePath) const;

    /// Executes decoding with fail-safe isolation (process boundary protection).
    /// If an adapter encounters a fatal fault or crashes, this returns false
    /// without terminating the main daemon.
    bool decodeWithIsolation(const std::string& inputFile,
                             const std::string& outputFile,
                             std::string* failureReason = nullptr);

    /// Gets human-readable vendor name for a file.
    std::string getVendorName(const std::string& filePath) const;

    /// Singleton instance accessor.
    static AdapterRegistry& instance();

private:
    std::vector<std::unique_ptr<VendorAdapter>> adapters;
};

} // namespace universa
