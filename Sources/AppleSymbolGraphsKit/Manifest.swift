import Foundation

/// Per-corpus metadata file emitted alongside the extracted .symbols.json
/// files. Consumers (e.g. cupertino's AppleConstraintsKit) read this to
/// know what they have, when it was generated, and what to re-fetch
/// when the active SDK changes.
public struct Manifest: Sendable, Codable {
    /// One entry per `(SDK, target)` pair the extractor tried, in
    /// priority order. The first entry is the primary platform; later
    /// entries are fallbacks for platform-specific modules
    /// (iOS-only frameworks, etc.).
    public struct TargetEntry: Sendable, Codable {
        /// Compiler target triple (e.g. `arm64-apple-macos15`,
        /// `arm64-apple-ios18`). Passed to `swift symbolgraph-extract`
        /// as the `-target` argument.
        public let targetTriple: String
        /// Absolute path to the SDK that backs this target. Passed to
        /// `swift symbolgraph-extract` as the `-sdk` argument.
        public let sdkPath: String
        /// SDK version string read from the SDK's `SDKSettings.plist`
        /// (e.g. `26.4`). Lets consumers detect when the corpus was
        /// generated against an outdated SDK.
        public let sdkVersion: String

        public init(targetTriple: String, sdkPath: String, sdkVersion: String) {
            self.targetTriple = targetTriple
            self.sdkPath = sdkPath
            self.sdkVersion = sdkVersion
        }
    }

    /// Schema version of this manifest format. Bump when fields change.
    public let manifestVersion: Int
    /// ISO8601 UTC timestamp of generation start.
    public let generatedAt: String
    /// Output of `xcrun swift --version` at generation time, single line.
    public let swiftVersion: String
    /// Ordered list of `(SDK, target)` pairs used during extraction.
    public let targets: [TargetEntry]
    /// Per-slug extraction outcomes, sorted by slug.
    public let results: [ExtractionResult]
    /// Convenience aggregates.
    public let summary: Summary

    /// Convenience aggregates over `results`, computed at init time.
    /// Lets consumers skim the corpus shape without scanning every row.
    public struct Summary: Sendable, Codable {
        /// Total number of slugs the generator attempted
        /// (curated + knownNonExtractable + any SDK-drift overflows).
        public let totalSlugs: Int
        /// Number of slugs that extracted to at least one
        /// `.symbols.json` file with non-zero size.
        public let okCount: Int
        /// Number of slugs that failed extraction across every
        /// `(variant, target)` combination tried.
        public let failedCount: Int
        /// Number of slugs short-circuited to `Status.skipped` because
        /// they appear in `FrameworkModuleMap.knownNonExtractable`.
        public let skippedCount: Int
        /// Sum of `sizeBytes` across all OK results. The on-disk
        /// `.symbols.json` total under the output root.
        public let totalBytes: Int
        /// `[target-triple: total-sizeBytes-resolved-under-this-target]`
        /// across all OK results. Lets consumers see which platforms
        /// carried the bulk of the corpus.
        public let bytesPerTarget: [String: Int]
        /// `[target-triple: number-of-slugs-resolved-under-this-target]`
        /// across all OK results. Companion to `bytesPerTarget`.
        public let slugsPerTarget: [String: Int]
    }

    /// Schema version that `init` writes. Bump in lockstep with
    /// changes to the `Manifest` shape; downstream consumers compare
    /// against this when deciding whether their decoder still applies.
    public static let currentVersion: Int = 3

    public init(
        generatedAt: String,
        swiftVersion: String,
        targets: [TargetEntry],
        results: [ExtractionResult]
    ) {
        manifestVersion = Self.currentVersion
        self.generatedAt = generatedAt
        self.swiftVersion = swiftVersion
        self.targets = targets
        self.results = results.sorted { $0.slug < $1.slug }
        let ok = self.results.filter { $0.status == .ok }
        let skipped = self.results.filter { $0.status == .skipped }
        var bytesPerTarget: [String: Int] = [:]
        var slugsPerTarget: [String: Int] = [:]
        for r in ok {
            bytesPerTarget[r.targetTriple, default: 0] += r.sizeBytes
            slugsPerTarget[r.targetTriple, default: 0] += 1
        }
        summary = Summary(
            totalSlugs: results.count,
            okCount: ok.count,
            failedCount: results.count - ok.count - skipped.count,
            skippedCount: skipped.count,
            totalBytes: ok.reduce(0) { $0 + $1.sizeBytes },
            bytesPerTarget: bytesPerTarget,
            slugsPerTarget: slugsPerTarget
        )
    }

    /// Encode pretty-printed JSON (sorted keys for stable diffs) for
    /// writing to disk + committing to git.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
