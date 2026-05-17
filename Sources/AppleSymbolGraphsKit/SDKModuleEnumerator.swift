import Foundation

/// Discovers the canonical list of Swift modules the active SDK
/// provides by walking the `.swiftmodule` directories Apple ships
/// inside the SDK. This is the ground-truth list against which the
/// `FrameworkModuleMap`-driven extraction is validated.
///
/// Three locations to walk per SDK:
/// 1. `<sdk>/usr/lib/swift/*.swiftmodule` — shared Swift modules
///    (Swift stdlib, Foundation, Concurrency, etc.)
/// 2. `<sdk>/System/Library/Frameworks/*.framework/Modules/*.swiftmodule` —
///    public framework modules
/// 3. `<sdk>/System/Library/{SubFrameworks,PrivateFrameworks}/...` —
///    sub-framework + private module overlays
///
/// The enumeration is the answer to "what does this SDK actually
/// have Swift symbols for?". A docs slug whose mapped module name
/// appears here is guaranteed extractable; absent slugs are either
/// Obj-C-only-with-Swift-overlay (extractable via headers/module
/// maps) or genuinely non-Swift.
public enum SDKModuleEnumerator {
    /// Path to the active SDK as reported by `xcrun --show-sdk-path`.
    public static func activeSDKPath() async throws -> String {
        let output = try await Self.runCapture("/usr/bin/xcrun", ["--show-sdk-path"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All Swift module names available in the SDK at `sdkPath`.
    /// Returns lowercase-sorted unique values; module names are
    /// case-sensitive on disk but the consumer typically does
    /// case-insensitive comparisons.
    public static func swiftModules(at sdkPath: String) throws -> [String] {
        let scanDirs = [
            "\(sdkPath)/usr/lib/swift",
            "\(sdkPath)/System/Library/Frameworks",
            "\(sdkPath)/System/Library/SubFrameworks",
            "\(sdkPath)/System/Library/PrivateFrameworks",
        ]
        var found = Set<String>()
        let fm = FileManager.default

        for dir in scanDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            // Walk for *.swiftmodule directories at any depth (cap at 6
            // to avoid arbitrary tree walks — Apple's layout is shallow).
            try Self.walk(directory: dir, maxDepth: 6, fileManager: fm) { url in
                guard url.hasDirectoryPath, url.lastPathComponent.hasSuffix(".swiftmodule") else {
                    return
                }
                let moduleName = String(url.lastPathComponent.dropLast(".swiftmodule".count))
                if !moduleName.isEmpty {
                    found.insert(moduleName)
                }
            }
        }
        return found.sorted()
    }

    // MARK: - Helpers

    private static func walk(
        directory path: String,
        maxDepth: Int,
        fileManager: FileManager,
        visit: (URL) throws -> Void
    ) throws {
        let url = URL(fileURLWithPath: path)
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for case let item as URL in enumerator {
            // Bound depth to avoid pathological traversal.
            let depth = item.pathComponents.count - url.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            try visit(item)
        }
    }

    private static func runCapture(_ executable: String, _ args: [String]) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
