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
        public let targetTriple: String
        public let sdkPath: String
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

    public struct Summary: Sendable, Codable {
        public let totalSlugs: Int
        public let okCount: Int
        public let failedCount: Int
        public let skippedCount: Int
        public let totalBytes: Int
        /// `(target triple → number of slugs resolved under this target)`.
        public let bytesPerTarget: [String: Int]
        public let slugsPerTarget: [String: Int]
    }

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
