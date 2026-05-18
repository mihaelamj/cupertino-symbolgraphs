import AppleSymbolGraphsKit
import ArgumentParser
import Foundation

/// Load a `manifest.json`, print per-status counts + per-target byte/slug
/// split + top-N largest extractions. Pure read of the file; doesn't
/// touch SDKs or run extractions.
///
/// Replaces the previously ad-hoc Python "summary peek" queries.
struct CountByStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "count-by-status",
        abstract: "Per-status counts + per-target byte/slug split from manifest.json."
    )

    @Option(name: .shortAndLong, help: "Path to a manifest.json produced by cupertino-symbolgraphs-gen.")
    var manifest: String

    @Option(name: .long, help: "How many largest extractions to list (default 10; pass 0 to skip).")
    var topN: Int = 10

    func run() throws {
        let url = URL(fileURLWithPath: (manifest as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(url.path)")
        }
        let data = try Data(contentsOf: url)
        let m = try JSONDecoder().decode(Manifest.self, from: data)

        print("Manifest:        \(url.path)")
        print("Manifest schema: v\(m.manifestVersion)")
        print("Generated at:    \(m.generatedAt)")
        print("Swift version:   \(m.swiftVersion)")
        print()
        print("Targets:")
        for t in m.targets {
            print("  \(t.targetTriple)  sdk=\(t.sdkPath)  sdkVersion=\(t.sdkVersion)")
        }
        print()
        print("Summary:")
        print("  total slugs:    \(m.summary.totalSlugs)")
        print("  ok:             \(m.summary.okCount)")
        print("  skipped:        \(m.summary.skippedCount)")
        print("  failed:         \(m.summary.failedCount)")
        let mb = m.summary.totalBytes / 1_024 / 1_024
        print("  total bytes:    \(mb) MB")
        print()
        if !m.summary.bytesPerTarget.isEmpty {
            print("Per target:")
            for triple in m.summary.bytesPerTarget.keys.sorted() {
                let bytes = m.summary.bytesPerTarget[triple] ?? 0
                let slugs = m.summary.slugsPerTarget[triple] ?? 0
                let mbStr = "\(bytes / 1_024 / 1_024) MB"
                let line = triple.padding(toLength: 32, withPad: " ", startingAt: 0)
                    + " \(slugs) slug(s)"
                    + " / " + mbStr
                print("  " + line)
            }
            print()
        }
        if topN > 0 {
            let okResults = m.results.filter { $0.status == .ok }
            let top = okResults.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(topN)
            print("Top \(topN) largest extractions:")
            for r in top {
                let kbStr = "\(r.sizeBytes / 1_024) KB"
                let moduleCol = r.moduleName.padding(toLength: 32, withPad: " ", startingAt: 0)
                print("  \(kbStr.padding(toLength: 10, withPad: " ", startingAt: 0))  \(moduleCol)  (\(r.fileCount) files, \(r.targetTriple))")
            }
        }
    }
}
