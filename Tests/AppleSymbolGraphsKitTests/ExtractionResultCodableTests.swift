@testable import AppleSymbolGraphsKit
import Foundation
import Testing

@Suite("ExtractionResult; Codable round-trip across all 3 statuses")
struct ExtractionResultCodableTests {
    @Test("Status.ok round-trips through JSON unchanged")
    func okRoundTrip() throws {
        let original = ExtractionResult(
            slug: "swiftui",
            moduleName: "SwiftUI",
            targetTriple: "arm64-apple-macos15",
            status: .ok,
            sizeBytes: 1_234_567,
            fileCount: 7,
            errorMessage: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExtractionResult.self, from: data)
        #expect(decoded.slug == original.slug)
        #expect(decoded.moduleName == original.moduleName)
        #expect(decoded.targetTriple == original.targetTriple)
        #expect(decoded.status == .ok)
        #expect(decoded.sizeBytes == 1_234_567)
        #expect(decoded.fileCount == 7)
        #expect(decoded.errorMessage == nil)
    }

    @Test("Status.skipped round-trips with errorMessage carrying the reason")
    func skippedRoundTrip() throws {
        let original = ExtractionResult(
            slug: "sirikit",
            moduleName: "SiriKit",
            targetTriple: "arm64-apple-macos15",
            status: .skipped,
            sizeBytes: 0,
            fileCount: 0,
            errorMessage: "deprecated; functionality moved to Intents + IntentsUI"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExtractionResult.self, from: data)
        #expect(decoded.status == .skipped)
        #expect(decoded.errorMessage?.contains("Intents") == true)
        #expect(decoded.sizeBytes == 0)
    }

    @Test("Status.failed round-trips with errorMessage carrying the stderr tail")
    func failedRoundTrip() throws {
        let original = ExtractionResult(
            slug: "fakeframework",
            moduleName: "FakeFramework",
            targetTriple: "arm64-apple-ios18",
            status: .failed,
            sizeBytes: 0,
            fileCount: 0,
            errorMessage: "Couldn't load module 'FakeFramework'"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExtractionResult.self, from: data)
        #expect(decoded.status == .failed)
        #expect(decoded.errorMessage?.contains("Couldn't load") == true)
    }

    @Test("Status raw values are stable for consumers parsing the JSON")
    func statusRawValuesStable() {
        // Consumers may dispatch on status.rawValue without decoding into
        // the Swift enum (e.g. a non-Swift reader). Keep these stable.
        #expect(ExtractionResult.Status.ok.rawValue == "ok")
        #expect(ExtractionResult.Status.skipped.rawValue == "skipped")
        #expect(ExtractionResult.Status.failed.rawValue == "failed")
    }

    @Test("ExtractionTarget round-trips with extraFrameworkSearchPaths")
    func targetRoundTrip() throws {
        let original = ExtractionTarget(
            sdkPath: "/Applications/Xcode.app/.../MacOSX.sdk",
            targetTriple: "arm64-apple-macos15",
            extraFrameworkSearchPaths: ["/sdk/usr/lib/swift/playgrounds"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExtractionTarget.self, from: data)
        #expect(decoded.sdkPath == original.sdkPath)
        #expect(decoded.targetTriple == original.targetTriple)
        #expect(decoded.extraFrameworkSearchPaths == ["/sdk/usr/lib/swift/playgrounds"])
    }

    @Test("ExtractionTarget default init has empty extraFrameworkSearchPaths")
    func targetDefaultEmptyPaths() {
        let t = ExtractionTarget(sdkPath: "/x", targetTriple: "y")
        #expect(t.extraFrameworkSearchPaths.isEmpty)
    }
}
