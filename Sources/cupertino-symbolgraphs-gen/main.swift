import AppleSymbolGraphsKit
import ArgumentParser
import Foundation

/// `cupertino-symbolgraphs-gen` — regenerate the Apple SDK symbolgraph
/// corpus from the active Swift toolchain.
///
/// Run when:
/// - Xcode / CommandLineTools updates to a new Swift version
/// - macOS SDK changes (new framework added, deprecated)
/// - The slug → module mapping in `FrameworkModuleMap` is extended
///
/// Output layout (under `--output`):
///   <output>/
///     manifest.json         (generation metadata + per-slug results)
///     <slug>/               (one dir per OK extraction, e.g. swiftui/)
///       <Module>.symbols.json
///       <Module>@<Other>.symbols.json     (cross-module extensions)
///
/// Usage:
///   cupertino-symbolgraphs-gen --output /Volumes/Code/cupertino-symbolgraphs/corpus
@main
struct Tool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cupertino-symbolgraphs-gen",
        abstract: "Regenerate the Apple SDK symbolgraph corpus for cupertino's AppleConstraintsKit."
    )

    @Option(name: .shortAndLong, help: "Output directory for the corpus + manifest.json.")
    var output: String

    @Option(name: .long, help: "Override the SDK path (defaults to `xcrun --show-sdk-path`).")
    var sdkPath: String?

    @Option(name: .long, help: "Target triple (default arm64-apple-macos15).")
    var target: String = "arm64-apple-macos15"

    @Flag(name: .long, inversion: .prefixedNo, help: "Validate the result against the SDK's .swiftmodule ground truth and surface drift (default: on).")
    var validate: Bool = true

    func run() async throws {
        let fm = FileManager.default
        let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Resolve SDK.
        let resolvedSDK: String
        if let sdkPath {
            resolvedSDK = sdkPath
        } else {
            resolvedSDK = try await SDKModuleEnumerator.activeSDKPath()
        }
        print("SDK: \(resolvedSDK)")
        print("Target: \(target)")
        print("Output: \(outputURL.path)")
        print()

        // Extract per slug.
        let extractor = SymbolGraphExtractor(
            sdkPath: resolvedSDK,
            targetTriple: target,
            outputRoot: outputURL
        )
        let slugs = FrameworkModuleMap.allCuratedSlugs
        print("Extracting \(slugs.count) curated slugs...")
        var results: [ExtractionResult] = []
        for (i, slug) in slugs.enumerated() {
            let result = try extractor.extract(slug: slug)
            results.append(result)
            if (i + 1) % 25 == 0 {
                let ok = results.filter { $0.status == .ok }.count
                let fail = results.count - ok
                print("  \(i + 1)/\(slugs.count) processed (OK: \(ok), FAIL: \(fail))")
            }
        }
        let okCount = results.filter { $0.status == .ok }.count
        let failCount = results.count - okCount
        print()
        print("Extraction complete: \(okCount) OK, \(failCount) FAIL")

        // Validate against ground truth.
        if validate {
            print()
            print("Validating against SDK .swiftmodule ground truth...")
            let groundTruth = Set(try SDKModuleEnumerator.swiftModules(at: resolvedSDK))
            let extractedModules = Set(results.filter { $0.status == .ok }.map { $0.moduleName })
            let missing = groundTruth.subtracting(extractedModules)
                .filter { !$0.hasPrefix("_") } // skip private/internal
            if missing.isEmpty {
                print("  ✅ All user-facing SDK Swift modules extracted")
            } else {
                print("  ⚠️  SDK has \(missing.count) Swift module(s) not in our extraction:")
                for module in missing.sorted() {
                    print("    - \(module)")
                }
                print("  Consider adding entries to FrameworkModuleMap.curated for these.")
            }
        }

        // Write manifest.
        let manifest = Manifest(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            swiftVersion: (try? await runCapture("/usr/bin/xcrun", ["swift", "--version"])) ?? "unknown",
            sdkVersion: (try? await runCapture("/usr/bin/xcrun", ["--show-sdk-version"])) ?? "unknown",
            sdkPath: resolvedSDK,
            targetTriple: target,
            results: results
        )
        let manifestURL = outputURL.appendingPathComponent("manifest.json")
        try manifest.encodedJSON().write(to: manifestURL)
        print()
        print("Manifest: \(manifestURL.path)")
        print("Summary: \(manifest.summary.totalSlugs) slugs / \(manifest.summary.okCount) OK / \(manifest.summary.failedCount) FAIL / \(manifest.summary.totalBytes / 1_024 / 1_024) MB")
    }

    private func runCapture(_ executable: String, _ args: [String]) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
    }
}
