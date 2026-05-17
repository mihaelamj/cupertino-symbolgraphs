import Foundation

/// Per-framework result of one extraction attempt.
public struct ExtractionResult: Sendable, Codable {
    public enum Status: String, Sendable, Codable {
        case ok
        case failed
    }

    /// Lowercase docs-corpus framework slug (key into FrameworkModuleMap).
    public let slug: String
    /// Swift module name that succeeded, or the last-tried name on failure.
    public let moduleName: String
    public let status: Status
    public let sizeBytes: Int
    public let fileCount: Int
    /// First line of stderr from the last attempt — populated only on failure.
    public let errorMessage: String?

    public init(
        slug: String,
        moduleName: String,
        status: Status,
        sizeBytes: Int,
        fileCount: Int,
        errorMessage: String?
    ) {
        self.slug = slug
        self.moduleName = moduleName
        self.status = status
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
        self.errorMessage = errorMessage
    }
}

/// Wraps `xcrun swift symbolgraph-extract` for one slug at a time and
/// returns a structured ExtractionResult. The bulk-extraction loop
/// lives in `cupertino-symbolgraphs-gen` so this stays single-call.
public struct SymbolGraphExtractor {
    public let sdkPath: String
    public let targetTriple: String
    public let outputRoot: URL

    public init(sdkPath: String, targetTriple: String = "arm64-apple-macos15", outputRoot: URL) {
        self.sdkPath = sdkPath
        self.targetTriple = targetTriple
        self.outputRoot = outputRoot
    }

    /// Run extraction for one slug; tries the curated module name first,
    /// then PascalCase fallback, then the slug as-is, then all-uppercase.
    /// Returns the first variant that produced output (status=.ok), or
    /// failure carrying the last error message (status=.failed).
    public func extract(slug: String) throws -> ExtractionResult {
        let outputDir = outputRoot.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let variants = Self.variantsToTry(for: slug)
        var lastError: String?

        for moduleName in variants {
            let (succeeded, stderr) = runOnce(moduleName: moduleName, outputDir: outputDir)
            if succeeded {
                let (count, size) = measure(outputDir: outputDir)
                if count > 0 {
                    return ExtractionResult(
                        slug: slug,
                        moduleName: moduleName,
                        status: .ok,
                        sizeBytes: size,
                        fileCount: count,
                        errorMessage: nil
                    )
                }
            }
            lastError = stderr
        }

        // All variants failed; rmdir + return failure.
        try? FileManager.default.removeItem(at: outputDir)
        return ExtractionResult(
            slug: slug,
            moduleName: variants.last ?? slug,
            status: .failed,
            sizeBytes: 0,
            fileCount: 0,
            errorMessage: lastError.map { Self.firstLine($0) }
        )
    }

    // MARK: - Internals

    /// Ordered list of module-name variants to try per slug:
    /// curated → PascalCase → slug → ALL-UPPERCASE.
    static func variantsToTry(for slug: String) -> [String] {
        var variants: [String] = []
        if let curated = FrameworkModuleMap.curated[slug] {
            variants.append(curated)
        }
        let pascal = FrameworkModuleMap.pascalCaseFallback(slug)
        if !variants.contains(pascal) { variants.append(pascal) }
        if !variants.contains(slug) { variants.append(slug) }
        let upper = slug.uppercased()
        if !variants.contains(upper) { variants.append(upper) }
        return variants
    }

    /// Invoke `xcrun swift symbolgraph-extract` once for the given
    /// module name; return (success, stderr-tail). Success is defined
    /// as exit status 0; the caller checks output-dir contents
    /// separately because the tool exits 0 even on some no-op runs.
    private func runOnce(moduleName: String, outputDir: URL) -> (Bool, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = [
            "swift", "symbolgraph-extract",
            "-module-name", moduleName,
            "-target", targetTriple,
            "-sdk", sdkPath,
            "-output-dir", outputDir.path,
        ]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        do {
            try proc.run()
        } catch {
            return (false, "spawn failed: \(error)")
        }
        proc.waitUntilExit()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errString = String(decoding: errData, as: UTF8.self)
        return (proc.terminationStatus == 0, errString)
    }

    /// Sum-of-file-sizes + file-count for everything in outputDir.
    private func measure(outputDir: URL) -> (count: Int, size: Int) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return (0, 0)
        }
        var total = 0
        for url in contents {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
            }
        }
        return (contents.count, total)
    }

    private static func firstLine(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
    }
}
