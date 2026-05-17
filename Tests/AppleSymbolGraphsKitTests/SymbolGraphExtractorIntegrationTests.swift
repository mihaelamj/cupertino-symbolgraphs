@testable import AppleSymbolGraphsKit
import Foundation
import Testing

/// End-to-end tests that actually invoke `xcrun swift symbolgraph-extract`.
/// These take a few seconds each (real Process spawn + Apple's tool); kept
/// in a focused suite so a regression in shell-arg construction or
/// short-circuit logic fails loudly instead of waiting for the full
/// regenerator run.
///
/// Skip when xcrun isn't on PATH (a sub-set of CI environments).
@Suite("SymbolGraphExtractor — end-to-end against real SDK")
struct SymbolGraphExtractorIntegrationTests {
    private static let xcrunAvailable: Bool = FileManager.default.fileExists(atPath: "/usr/bin/xcrun")

    private func makeTempDir(label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sg-extract-test-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Status.skipped is returned without spawning xcrun for knownNonExtractable",
          .enabled(if: xcrunAvailable))
    func skippedShortCircuit() async throws {
        // Use a deliberately bogus SDK path. If the short-circuit works,
        // the call never spawns xcrun, so the bad path is irrelevant.
        let outputRoot = try makeTempDir(label: "skip")
        defer { try? FileManager.default.removeItem(at: outputRoot) }
        let extractor = SymbolGraphExtractor(
            targets: [ExtractionTarget(sdkPath: "/var/empty/fake-sdk", targetTriple: "arm64-apple-macos15")],
            outputRoot: outputRoot
        )
        let result = try extractor.extract(slug: "sirikit") // in knownNonExtractable
        #expect(result.status == .skipped)
        #expect(result.sizeBytes == 0)
        #expect(result.fileCount == 0)
        #expect(result.errorMessage?.contains("deprecated") == true)
        // Most important: no output dir was created (the short-circuit
        // returns before mkdir).
        let slugDir = outputRoot.appendingPathComponent("sirikit")
        #expect(!FileManager.default.fileExists(atPath: slugDir.path),
                "skipped slug should not create an output dir")
    }

    @Test("Extracting Foundation against the active macOS SDK produces non-empty output",
          .enabled(if: xcrunAvailable))
    func foundationExtractsOK() async throws {
        let sdk = try await SDKModuleEnumerator.activeSDKPath()
        let outputRoot = try makeTempDir(label: "foundation")
        defer { try? FileManager.default.removeItem(at: outputRoot) }
        let extractor = SymbolGraphExtractor(
            sdkPath: sdk,
            targetTriple: "arm64-apple-macos15",
            outputRoot: outputRoot
        )
        let result = try extractor.extract(slug: "foundation")
        #expect(result.status == .ok, "Foundation extraction failed: \(result.errorMessage ?? "unknown")")
        #expect(result.moduleName == "Foundation")
        #expect(result.targetTriple == "arm64-apple-macos15")
        #expect(result.sizeBytes > 100_000, "Foundation symbolgraph should be > 100 KB, got \(result.sizeBytes)")
        #expect(result.fileCount >= 1)
        #expect(result.errorMessage == nil)
        // Output dir holds the file(s).
        let slugDir = outputRoot.appendingPathComponent("foundation")
        let contents = try FileManager.default.contentsOfDirectory(atPath: slugDir.path)
        #expect(contents.contains(where: { $0.hasPrefix("Foundation") && $0.hasSuffix(".symbols.json") }))
    }

    @Test("A bogus slug fails cleanly with .failed + non-nil errorMessage + no leftover dir",
          .enabled(if: xcrunAvailable))
    func bogusSlugFailsCleanly() async throws {
        let sdk = try await SDKModuleEnumerator.activeSDKPath()
        let outputRoot = try makeTempDir(label: "bogus")
        defer { try? FileManager.default.removeItem(at: outputRoot) }
        let extractor = SymbolGraphExtractor(
            sdkPath: sdk,
            targetTriple: "arm64-apple-macos15",
            outputRoot: outputRoot
        )
        // Use a slug definitely not in curated, knownNonExtractable, or any SDK.
        // Single-character + numbers is a safe sentinel: PascalCase fallback gives
        // a one-char module name that no SDK ships.
        let result = try extractor.extract(slug: "xq42")
        #expect(result.status == .failed)
        #expect(result.errorMessage != nil)
        #expect(result.sizeBytes == 0)
        // The extractor must rmdir the slug dir on failure so the
        // measure step doesn't get confused on the next pass.
        let slugDir = outputRoot.appendingPathComponent("xq42")
        #expect(!FileManager.default.fileExists(atPath: slugDir.path),
                "failed slug must clean up its output dir")
    }

    @Test("Multi-target chain: macOS-fail + watchOS-OK lands status=.ok on watchOS",
          .enabled(if: xcrunAvailable))
    func multiTargetFallback() async throws {
        // WatchKit doesn't exist on macOS SDK; it exists on watchOS.
        // The fallback chain should rescue it.
        let macos = try await SDKModuleEnumerator.activeSDKPath()
        guard let watchos = try? await SDKModuleEnumerator.activeSDKPath(sdk: "watchos") else {
            // Skip when watchOS SDK isn't available.
            return
        }
        let outputRoot = try makeTempDir(label: "watchkit")
        defer { try? FileManager.default.removeItem(at: outputRoot) }
        let extractor = SymbolGraphExtractor(
            targets: [
                ExtractionTarget(sdkPath: macos,   targetTriple: "arm64-apple-macos15"),
                ExtractionTarget(sdkPath: watchos, targetTriple: "arm64_32-apple-watchos11"),
            ],
            outputRoot: outputRoot
        )
        let result = try extractor.extract(slug: "watchkit")
        #expect(result.status == .ok, "WatchKit extraction failed across both targets: \(result.errorMessage ?? "?")")
        #expect(result.moduleName == "WatchKit")
        #expect(result.targetTriple == "arm64_32-apple-watchos11", "WatchKit should resolve under the watchOS fallback, got \(result.targetTriple)")
        #expect(result.sizeBytes > 0)
    }

    @Test("Playgrounds rescue: LiveExecutionResultsRuntime extracts only with -F playgrounds path",
          .enabled(if: xcrunAvailable))
    func playgroundsRescueRequired() async throws {
        let sdk = try await SDKModuleEnumerator.activeSDKPath()
        let withoutRescue = try makeTempDir(label: "lerr-without")
        defer { try? FileManager.default.removeItem(at: withoutRescue) }
        let withRescue = try makeTempDir(label: "lerr-with")
        defer { try? FileManager.default.removeItem(at: withRescue) }

        let extractorNoF = SymbolGraphExtractor(
            targets: [ExtractionTarget(sdkPath: sdk, targetTriple: "arm64-apple-macos15")],
            outputRoot: withoutRescue
        )
        let extractorWithF = SymbolGraphExtractor(
            targets: [ExtractionTarget(
                sdkPath: sdk,
                targetTriple: "arm64-apple-macos15",
                extraFrameworkSearchPaths: ["\(sdk)/usr/lib/swift/playgrounds"]
            )],
            outputRoot: withRescue
        )

        let noF = try extractorNoF.extract(slug: "liveexecutionresultsruntime")
        let withF = try extractorWithF.extract(slug: "liveexecutionresultsruntime")

        #expect(noF.status == .failed, "without -F playgrounds, LiveExecutionResultsRuntime should fail")
        #expect(withF.status == .ok, "with -F playgrounds, LiveExecutionResultsRuntime should extract: \(withF.errorMessage ?? "?")")
        #expect(withF.sizeBytes > 0)
    }
}
