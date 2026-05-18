import Foundation

/// A `(SDK path, target triple)` pair to try during extraction.
/// Most frameworks resolve under macOS; iOS-only frameworks
/// (UIKit, WatchKit, MessageUI, CarPlay, HealthKitUI, …) need an
/// iPhoneOS SDK + iOS target. The extractor walks `targets` in order
/// and returns on first success, so primary should be the platform
/// whose surface you care most about; fallbacks pick up the residue.
public struct ExtractionTarget: Sendable, Codable {
    /// Absolute path to the SDK that backs this target. Passed to
    /// `swift symbolgraph-extract` as the `-sdk` argument.
    public let sdkPath: String
    /// Compiler target triple (e.g. `arm64-apple-macos15`). Passed
    /// to `swift symbolgraph-extract` as the `-target` argument.
    public let targetTriple: String
    /// Extra `-F` framework search paths to pass to
    /// `symbolgraph-extract` for modules that live outside the
    /// standard SDK module search tree. Currently used to rescue
    /// `LiveExecutionResultsRuntime` from `<sdk>/usr/lib/swift/playgrounds/`.
    public let extraFrameworkSearchPaths: [String]

    public init(sdkPath: String, targetTriple: String, extraFrameworkSearchPaths: [String] = []) {
        self.sdkPath = sdkPath
        self.targetTriple = targetTriple
        self.extraFrameworkSearchPaths = extraFrameworkSearchPaths
    }
}

/// Per-framework result of one extraction attempt.
public struct ExtractionResult: Sendable, Codable {
    /// Outcome categories the extractor reports for one slug.
    public enum Status: String, Sendable, Codable {
        /// Extraction produced at least one non-empty `.symbols.json`
        /// file under the output dir.
        case ok
        /// Tried every variant against every target, none produced output.
        /// Usually means the framework is iOS/watchOS/visionOS-only and we
        /// don't have that SDK, or the slug is mapped to the wrong module
        /// name.
        case failed
        /// Intentionally not attempted; slug is in
        /// `FrameworkModuleMap.knownNonExtractable` because the framework
        /// isn't a Swift module in any SDK (server-side REST API, separate
        /// SPM package, Xcode-platform-only test framework, doc-only tool,
        /// deprecated framework whose code moved elsewhere).
        case skipped
    }

    /// Lowercase docs-corpus framework slug (key into FrameworkModuleMap).
    public let slug: String
    /// Swift module name that succeeded, or the last-tried name on failure.
    public let moduleName: String
    /// Target triple that produced the successful extraction (or the
    /// last-tried target on failure). Useful for downstream consumers
    /// that want to know "is this the iOS surface or the macOS surface?".
    public let targetTriple: String
    /// Categorical outcome (see `Status`).
    public let status: Status
    /// Sum-of-file-sizes across the slug's output directory. Zero for
    /// non-OK status; non-zero for OK.
    public let sizeBytes: Int
    /// Number of `.symbols.json` files produced (1 for the primary
    /// module, plus one per cross-module extension). Zero for non-OK.
    public let fileCount: Int
    /// First line of stderr from the last attempt; populated only on failure.
    public let errorMessage: String?

    public init(
        slug: String,
        moduleName: String,
        targetTriple: String,
        status: Status,
        sizeBytes: Int,
        fileCount: Int,
        errorMessage: String?
    ) {
        self.slug = slug
        self.moduleName = moduleName
        self.targetTriple = targetTriple
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
    /// Ordered list of (SDK, target) pairs to try per slug. The first
    /// pair that produces non-empty output wins. Typically [macOS, iOS].
    public let targets: [ExtractionTarget]
    /// Output root directory; the extractor writes one subdirectory
    /// per OK slug (`<outputRoot>/<slug>/<Module>.symbols.json`).
    public let outputRoot: URL

    public init(targets: [ExtractionTarget], outputRoot: URL) {
        precondition(!targets.isEmpty, "SymbolGraphExtractor requires at least one ExtractionTarget")
        self.targets = targets
        self.outputRoot = outputRoot
    }

    /// Convenience init for the legacy single-target case.
    public init(sdkPath: String, targetTriple: String = "arm64-apple-macos15", outputRoot: URL) {
        self.init(
            targets: [ExtractionTarget(sdkPath: sdkPath, targetTriple: targetTriple)],
            outputRoot: outputRoot
        )
    }

    /// Run extraction for one slug. For each `(sdk, target)` pair in
    /// `targets`, tries the curated module name first, then PascalCase
    /// fallback, then the slug as-is, then all-uppercase. Returns the
    /// first variant/target that produced non-empty output, or
    /// failure carrying the last stderr line.
    ///
    /// Short-circuits with `.skipped` when the slug is in
    /// `FrameworkModuleMap.knownNonExtractable`.
    public func extract(slug: String) throws -> ExtractionResult {
        // Short-circuit on known-non-Swift-module slugs.
        if let reason = FrameworkModuleMap.knownNonExtractable[slug] {
            return ExtractionResult(
                slug: slug,
                moduleName: FrameworkModuleMap.moduleName(for: slug) ?? slug,
                targetTriple: targets[0].targetTriple,
                status: .skipped,
                sizeBytes: 0,
                fileCount: 0,
                errorMessage: reason
            )
        }

        let outputDir = outputRoot.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let variants = Self.variantsToTry(for: slug)
        var lastError: String?
        var lastTarget: ExtractionTarget = targets[0]

        for target in targets {
            lastTarget = target
            for moduleName in variants {
                let (succeeded, stderr) = runOnce(moduleName: moduleName, target: target, outputDir: outputDir)
                if succeeded {
                    let (count, size) = measure(outputDir: outputDir)
                    if count > 0 {
                        return ExtractionResult(
                            slug: slug,
                            moduleName: moduleName,
                            targetTriple: target.targetTriple,
                            status: .ok,
                            sizeBytes: size,
                            fileCount: count,
                            errorMessage: nil
                        )
                    }
                }
                lastError = stderr
                // Clean any partial output between attempts so size measurement is honest.
                try? Self.emptyDirectoryContents(outputDir)
            }
        }

        // All variants × targets failed; rmdir + return failure.
        try? FileManager.default.removeItem(at: outputDir)
        return ExtractionResult(
            slug: slug,
            moduleName: variants.last ?? slug,
            targetTriple: lastTarget.targetTriple,
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
    /// module name + target; return (success, stderr-tail). Success
    /// is defined as exit status 0; the caller checks output-dir
    /// contents separately because the tool exits 0 even on some
    /// no-op runs.
    private func runOnce(moduleName: String, target: ExtractionTarget, outputDir: URL) -> (Bool, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        var args: [String] = [
            "swift", "symbolgraph-extract",
            "-module-name", moduleName,
            "-target", target.targetTriple,
            "-sdk", target.sdkPath,
            "-output-dir", outputDir.path,
        ]
        for fpath in target.extraFrameworkSearchPaths {
            args.append("-F")
            args.append(fpath)
        }
        proc.arguments = args
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

    /// Delete everything *inside* `dir` without removing `dir` itself.
    /// Used to discard partial output between failed extraction attempts
    /// so `measure` doesn't credit one variant for another's leftovers.
    static func emptyDirectoryContents(_ dir: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        for url in contents {
            try fm.removeItem(at: url)
        }
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
