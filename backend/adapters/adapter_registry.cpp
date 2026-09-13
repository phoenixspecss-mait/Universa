#include "adapter_registry.h"
#include "dahua_adapter.h"
#include "hikvision_adapter.h"
#include "generic_mp4_adapter.h"

#include <iostream>
#include <system_error>

#if defined(__unix__) || defined(__APPLE__)
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#endif

namespace universa {

AdapterRegistry::AdapterRegistry() {
    registerAdapter(std::make_unique<DahuaAdapter>());
    registerAdapter(std::make_unique<HikvisionAdapter>());
    registerAdapter(std::make_unique<GenericMp4Adapter>());
}

AdapterRegistry& AdapterRegistry::instance() {
    static AdapterRegistry reg;
    return reg;
}

void AdapterRegistry::registerAdapter(std::unique_ptr<VendorAdapter> adapter) {
    if (adapter) {
        adapters.push_back(std::move(adapter));
    }
}

VendorAdapter* AdapterRegistry::findAdapter(const std::string& filePath) const {
    for (const auto& adp : adapters) {
        if (adp->matchesSignature(filePath)) {
            return adp.get();
        }
    }
    return nullptr;
}

VendorType AdapterRegistry::detectVendor(const std::string& filePath) const {
    VendorAdapter* adp = findAdapter(filePath);
    return adp ? adp->vendorType() : VendorType::UNKNOWN;
}

std::string AdapterRegistry::getVendorName(const std::string& filePath) const {
    VendorAdapter* adp = findAdapter(filePath);
    return adp ? adp->vendorName() : "Unknown / Raw Stream";
}

bool AdapterRegistry::decodeWithIsolation(const std::string& inputFile,
                                         const std::string& outputFile,
                                         std::string* failureReason) {
    VendorAdapter* adapter = findAdapter(inputFile);
    if (!adapter) {
        if (failureReason) *failureReason = "NO_MATCHING_ADAPTER";
        return false;
    }

#if defined(__unix__) || defined(__APPLE__)
    // Subprocess isolation: fork child worker to protect core daemon from memory corruption/crashes
    pid_t pid = fork();
    if (pid < 0) {
        // Fallback to in-process execution if fork fails
        try {
            return adapter->decode(inputFile, outputFile);
        } catch (const std::exception& ex) {
            if (failureReason) *failureReason = std::string("ADAPTER_FAILED: ") + ex.what();
            return false;
        }
    } else if (pid == 0) {
        // Child worker process
        try {
            bool success = adapter->decode(inputFile, outputFile);
            _exit(success ? 0 : 1);
        } catch (...) {
            _exit(2);
        }
    } else {
        // Parent process waits for child completion
        int status = 0;
        waitpid(pid, &status, 0);

        if (WIFEXITED(status)) {
            int exitCode = WEXITSTATUS(status);
            if (exitCode == 0) {
                return true;
            } else {
                if (failureReason) *failureReason = "ADAPTER_FAILED";
                return false;
            }
        } else if (WIFSIGNALED(status)) {
            // Child crashed (e.g. SIGSEGV, SIGABRT)
            if (failureReason) *failureReason = "ADAPTER_FAILED: CRASH_SIGNAL_" + std::to_string(WTERMSIG(status));
            std::cerr << "[FAIL-SAFE] Vendor adapter crashed with signal " << WTERMSIG(status)
                      << " on " << inputFile << ". Isolated successfully.\n";
            return false;
        }
        if (failureReason) *failureReason = "ADAPTER_FAILED";
        return false;
    }
#else
    try {
        return adapter->decode(inputFile, outputFile);
    } catch (const std::exception& ex) {
        if (failureReason) *failureReason = std::string("ADAPTER_FAILED: ") + ex.what();
        return false;
    }
#endif
}

} // namespace universa
