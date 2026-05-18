import AppleSymbolGraphsKit
import ArgumentParser
import Foundation

/// `cupertino-symbolgraphs-gen`; regenerate the Apple SDK symbolgraph
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

    @Option(name: .long, help: "macOS SDK path (defaults to `xcrun --show-sdk-path`).")
    var macosSdkPath: String?

    @Option(name: .long, help: "macOS target triple (default arm64-apple-macos15).")
    var macosTarget: String = "arm64-apple-macos15"

    @Option(name: .long, help: "iPhoneOS SDK path (defaults to `xcrun --sdk iphoneos --show-sdk-path`). Set empty to disable the iOS fallback.")
    var iosSdkPath: String?

    @Option(name: .long, help: "iOS target triple (default arm64-apple-ios18).")
    var iosTarget: String = "arm64-apple-ios18"

    @Option(name: .long, help: "WatchOS SDK path (defaults to `xcrun --sdk watchos --show-sdk-path`). Set empty to disable the watchOS fallback.")
    var watchosSdkPath: String?

    @Option(name: .long, help: "watchOS target triple (default arm64_32-apple-watchos11).")
    var watchosTarget: String = "arm64_32-apple-watchos11"

    @Option(name: .long, help: "XROS (visionOS) SDK path (defaults to `xcrun --sdk xros --show-sdk-path`). Set empty to disable the visionOS fallback.")
    var xrosSdkPath: String?

    @Option(name: .long, help: "visionOS target triple (default arm64-apple-xros2).")
    var xrosTarget: String = "arm64-apple-xros2"

    @Flag(name: .long, inversion: .prefixedNo, help: "Validate the result against the SDK's .swiftmodule ground truth and surface drift (default: on).")
    var validate: Bool = true

    func run() async throws {
        // Disable stdout block buffering so progress prints land in the
        // log immediately (otherwise prints buffer until process exit
        // when stdout is redirected to a file).
        setbuf(stdout, nil)

        let fm = FileManager.default
        let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Resolve SDKs. macOS is required; iOS/watchOS/visionOS are
        // best-effort fallbacks. `??` autoclosure can't host `await`,
        // so resolve explicitly.
        let macosSDK: String
        if let macosSdkPath {
            macosSDK = macosSdkPath
        } else {
            macosSDK = try await SDKModuleEnumerator.activeSDKPath()
        }
        func resolveOptional(arg: String?, sdkName: String) async -> String? {
            if let arg { return arg.isEmpty ? nil : arg }
            return try? await SDKModuleEnumerator.activeSDKPath(sdk: sdkName)
        }
        let iosSDK     = await resolveOptional(arg: iosSdkPath,     sdkName: "iphoneos")
        let watchosSDK = await resolveOptional(arg: watchosSdkPath, sdkName: "watchos")
        let xrosSDK    = await resolveOptional(arg: xrosSdkPath,    sdkName: "xros")

        // The `playgrounds/` framework dir under each SDK holds
        // LiveExecutionResultsRuntime, which isn't on the default
        // module search path. Passing it as -F rescues that one
        // extraction (and any future modules Apple drops in there).
        func playgroundsPath(for sdk: String) -> String { "\(sdk)/usr/lib/swift/playgrounds" }

        var targets: [ExtractionTarget] = [
            ExtractionTarget(sdkPath: macosSDK, targetTriple: macosTarget,
                             extraFrameworkSearchPaths: [playgroundsPath(for: macosSDK)]),
        ]
        if let iosSDK {
            targets.append(ExtractionTarget(sdkPath: iosSDK, targetTriple: iosTarget,
                                            extraFrameworkSearchPaths: [playgroundsPath(for: iosSDK)]))
        }
        if let watchosSDK {
            targets.append(ExtractionTarget(sdkPath: watchosSDK, targetTriple: watchosTarget,
                                            extraFrameworkSearchPaths: [playgroundsPath(for: watchosSDK)]))
        }
        if let xrosSDK {
            targets.append(ExtractionTarget(sdkPath: xrosSDK, targetTriple: xrosTarget,
                                            extraFrameworkSearchPaths: [playgroundsPath(for: xrosSDK)]))
        }
        print("Output: \(outputURL.path)")
        for (i, t) in targets.enumerated() {
            print("Target \(i + 1): \(t.targetTriple)  sdk=\(t.sdkPath)")
        }
        print()

        // Extract per slug.
        let extractor = SymbolGraphExtractor(
            targets: targets,
            outputRoot: outputURL
        )
        // Input = every slug we know about: extractable (curated) +
        // intentionally-non-extractable (short-circuited to .skipped so
        // consumers see them in the manifest with a reason).
        let slugs = (Set(FrameworkModuleMap.allCuratedSlugs)
            .union(FrameworkModuleMap.knownNonExtractable.keys)).sorted()
        print("Extracting \(slugs.count) slugs (\(FrameworkModuleMap.allCuratedSlugs.count) curated + \(FrameworkModuleMap.knownNonExtractable.count) known-non-extractable)…")
        var results: [ExtractionResult] = []
        for (i, slug) in slugs.enumerated() {
            let result = try extractor.extract(slug: slug)
            results.append(result)
            if (i + 1) % 25 == 0 {
                let ok = results.filter { $0.status == .ok }.count
                let skipped = results.filter { $0.status == .skipped }.count
                let fail = results.count - ok - skipped
                print("  \(i + 1)/\(slugs.count) processed (OK: \(ok), SKIP: \(skipped), FAIL: \(fail))")
            }
        }
        let okCount = results.filter { $0.status == .ok }.count
        let skippedCount = results.filter { $0.status == .skipped }.count
        let failCount = results.count - okCount - skippedCount
        print()
        print("Extraction complete: \(okCount) OK, \(skippedCount) SKIP (non-SDK), \(failCount) FAIL")
        if failCount > 0 {
            print("Unexplained failures:")
            for r in results where r.status == .failed {
                print("  - \(r.slug)  (tried \(r.moduleName) on \(r.targetTriple))  \(r.errorMessage ?? "")")
            }
        }

        // Validate against ground truth (each SDK separately; a module
        // is "covered" if extracted under any target OR explicitly listed
        // in FrameworkModuleMap.knownNonExtractable with a documented reason).
        if validate {
            let extractedModules = Set(results.filter { $0.status == .ok }.map { $0.moduleName })
            // Module names corresponding to slugs we've intentionally classified
            // as non-extractable (the .skipped path). Computed via curated
            // (no entry here means we strip-route by canonical PascalCase form).
            let skippedModules = Set(
                FrameworkModuleMap.knownNonExtractable.keys.compactMap { slug -> String? in
                    if let curated = FrameworkModuleMap.curated[slug] { return curated }
                    return FrameworkModuleMap.pascalCaseFallback(slug)
                }
            )
                .union(["MapKitSwiftBridge"])
            let internalPrefixes = ["_", "Swift"]
            // Curate the "real" private-module names we explicitly want
            // to silence; they exist as .swiftmodule but aren't user-facing
            // and aren't part of cupertino's apple-docs corpus.
            let silencedModules: Set<String> = [
                "SwiftOnoneSupport", "SwiftShims", "Runtime", "SwiftUICore",
                "DeveloperToolsSupport", "AppleArchivePrivate", "Concurrency",
            ]
            for target in targets {
                print()
                print("Validating against \(target.targetTriple) (.swiftmodule ground truth)…")
                let groundTruth = Set((try? SDKModuleEnumerator.swiftModules(at: target.sdkPath)) ?? [])
                let missing = groundTruth.subtracting(extractedModules)
                    .subtracting(skippedModules)
                    .filter { name in
                        !silencedModules.contains(name)
                            && !internalPrefixes.contains(where: { name.hasPrefix($0) && name != "Swift" })
                    }
                if missing.isEmpty {
                    print("  ✅ All user-facing modules covered")
                } else {
                    print("  ⚠️  \(missing.count) module(s) present in SDK but not extracted:")
                    for module in missing.sorted() {
                        print("    - \(module)")
                    }
                    print("  Consider adding entries to FrameworkModuleMap.curated for these.")
                }
            }
        }

        // Write manifest.
        let targetEntries: [Manifest.TargetEntry] = targets.map {
            Manifest.TargetEntry(
                targetTriple: $0.targetTriple,
                sdkPath: $0.sdkPath,
                sdkVersion: readSDKVersion(at: $0.sdkPath) ?? "unknown"
            )
        }
        let manifest = Manifest(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            swiftVersion: (try? await runCapture("/usr/bin/xcrun", ["swift", "--version"])) ?? "unknown",
            targets: targetEntries,
            results: results
        )
        let manifestURL = outputURL.appendingPathComponent("manifest.json")
        try manifest.encodedJSON().write(to: manifestURL)
        print()
        print("Manifest: \(manifestURL.path)")
        print("Summary: \(manifest.summary.totalSlugs) slugs / \(manifest.summary.okCount) OK / \(manifest.summary.failedCount) FAIL / \(manifest.summary.totalBytes / 1_024 / 1_024) MB")
    }

    /// Read the SDK version directly from `<sdk>/SDKSettings.plist`.
    /// More robust than `xcrun --show-sdk-version`, which depends on
    /// `xcode-select` pointing at a working developer dir.
    private func readSDKVersion(at sdkPath: String) -> String? {
        let plistURL = URL(fileURLWithPath: sdkPath).appendingPathComponent("SDKSettings.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let version = plist["Version"] as? String
        else {
            return nil
        }
        return version
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
