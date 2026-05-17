import Foundation

/// Per-corpus metadata file emitted alongside the extracted .symbols.json
/// files. Consumers (e.g. cupertino's AppleConstraintsKit) read this to
/// know what they have, when it was generated, and what to re-fetch
/// when the active SDK changes.
public struct Manifest: Sendable, Codable {
    /// Schema version of this manifest format. Bump when fields change.
    public let manifestVersion: Int
    /// ISO8601 UTC timestamp of generation start.
    public let generatedAt: String
    /// Output of `xcrun swift --version` at generation time, single line.
    public let swiftVersion: String
    /// Output of `xcrun --show-sdk-version` at generation time.
    public let sdkVersion: String
    /// Resolved SDK path used during extraction.
    public let sdkPath: String
    /// Target triple passed via `-target`.
    public let targetTriple: String
    /// Per-slug extraction outcomes, sorted by slug.
    public let results: [ExtractionResult]
    /// Convenience aggregates.
    public let summary: Summary

    public struct Summary: Sendable, Codable {
        public let totalSlugs: Int
        public let okCount: Int
        public let failedCount: Int
        public let totalBytes: Int
    }

    public static let currentVersion: Int = 1

    public init(
        generatedAt: String,
        swiftVersion: String,
        sdkVersion: String,
        sdkPath: String,
        targetTriple: String,
        results: [ExtractionResult]
    ) {
        manifestVersion = Self.currentVersion
        self.generatedAt = generatedAt
        self.swiftVersion = swiftVersion
        self.sdkVersion = sdkVersion
        self.sdkPath = sdkPath
        self.targetTriple = targetTriple
        self.results = results.sorted { $0.slug < $1.slug }
        let ok = self.results.filter { $0.status == .ok }
        summary = Summary(
            totalSlugs: results.count,
            okCount: ok.count,
            failedCount: results.count - ok.count,
            totalBytes: ok.reduce(0) { $0 + $1.sizeBytes }
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
