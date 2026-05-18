import Foundation
import Testing

/// Smoke tests for the `cupertino-symbolgraphs-gen` binary itself
/// (the executable target, not the library). These spawn the built
/// binary via Process and assert on stdout/stderr; the only way to
/// cover the ArgumentParser surface from inside the test target since
/// the executable's symbols aren't importable.
///
/// **Requires the binary to be built first.** `swift test` builds all
/// targets in the package up-front, so by the time these tests run the
/// debug binary exists at `.build/debug/cupertino-symbolgraphs-gen`.
/// CI runs `swift build` before `swift test` already.
///
/// Skipped if the binary isn't where we expect (caller may have built
/// elsewhere or only built the library target).
@Suite("cupertino-symbolgraphs-gen; CLI binary smoke")
struct CLIBinarySmokeTests {
    /// Resolve the path to the built binary. Try debug first, then
    /// release. Returns nil if neither exists.
    private static func binaryPath() -> String? {
        // Walk up from this source file's dir to the package root.
        // CWD during `swift test` is the package root.
        let fm = FileManager.default
        let candidates = [
            "\(fm.currentDirectoryPath)/.build/debug/cupertino-symbolgraphs-gen",
            "\(fm.currentDirectoryPath)/.build/release/cupertino-symbolgraphs-gen",
            "\(fm.currentDirectoryPath)/.build/arm64-apple-macosx/debug/cupertino-symbolgraphs-gen",
        ]
        return candidates.first(where: { fm.fileExists(atPath: $0) })
    }

    private static let binAvailable: Bool = binaryPath() != nil

    /// Spawn the binary with the given args; return (exit code, stdout, stderr).
    private func run(_ args: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        guard let bin = Self.binaryPath() else {
            throw NSError(domain: "CLISmoke", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "cupertino-symbolgraphs-gen binary not found; expected under .build/debug/ or .build/release/",
            ])
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        let outStr = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errStr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (proc.terminationStatus, outStr, errStr)
    }

    @Test("--help exits 0 and renders the documented options", .enabled(if: binAvailable))
    func helpRenders() throws {
        let r = try run(["--help"])
        #expect(r.exitCode == 0, "--help should exit 0, got \(r.exitCode); stderr: \(r.stderr)")
        let out = r.stdout
        // Must show command name + abstract:
        #expect(out.contains("cupertino-symbolgraphs-gen"))
        #expect(out.contains("Regenerate"), "abstract missing from --help output")
        // Must list the user-facing flags we shipped in v0.1.0:
        for flag in ["--output", "--macos-sdk-path", "--macos-target",
                     "--ios-sdk-path", "--ios-target",
                     "--watchos-sdk-path", "--watchos-target",
                     "--xros-sdk-path", "--xros-target",
                     "--validate", "--no-validate"] {
            #expect(out.contains(flag), "--help missing flag '\(flag)'")
        }
    }

    @Test("--version-equivalent behaviour: missing --output exits non-zero with a parse error",
          .enabled(if: binAvailable))
    func missingOutputFails() throws {
        let r = try run([])
        #expect(r.exitCode != 0, "expected non-zero exit when --output is missing, got 0")
        // ArgumentParser writes errors to stderr.
        let combined = r.stderr + r.stdout
        #expect(combined.lowercased().contains("output") || combined.lowercased().contains("required"),
                "expected an error mentioning the missing output arg; got stdout='\(r.stdout)' stderr='\(r.stderr)'")
    }

    @Test("--help twice produces the same output (deterministic)",
          .enabled(if: binAvailable))
    func helpDeterministic() throws {
        let r1 = try run(["--help"])
        let r2 = try run(["--help"])
        #expect(r1.exitCode == 0)
        #expect(r2.exitCode == 0)
        #expect(r1.stdout == r2.stdout, "--help output drifted between runs (non-deterministic)")
    }

    @Test("Unknown flag exits non-zero", .enabled(if: binAvailable))
    func unknownFlagFails() throws {
        let r = try run(["--no-such-flag"])
        #expect(r.exitCode != 0, "unknown flag should fail; got exit \(r.exitCode)")
    }

    @Test("--help advertises the playgrounds-rescue + dual-target default behaviour",
          .enabled(if: binAvailable))
    func helpDocumentsKeyBehaviour() throws {
        let r = try run(["--help"])
        let out = r.stdout.lowercased()
        // The watchOS + visionOS + macOS + iOS surface should all be mentioned
        // in the help so users know what extraction does by default.
        #expect(out.contains("macos"))
        #expect(out.contains("iphoneos") || out.contains("iphone"))
        #expect(out.contains("watchos"))
        #expect(out.contains("xros") || out.contains("visionos"))
    }

    @Test("--dry-run advertised in --help (cupertino-symbolgraphs#4)",
          .enabled(if: binAvailable))
    func dryRunInHelp() throws {
        let r = try run(["--help"])
        #expect(r.exitCode == 0)
        #expect(r.stdout.contains("--dry-run"), "--dry-run flag missing from --help output")
    }

    @Test("--dry-run prints routing for every slug + exits 0 + creates NO output dir",
          .enabled(if: binAvailable))
    func dryRunPrintsRoutingAndDoesNotCreateOutput() throws {
        // Use a unique output path so we can assert it wasn't created.
        let outputPath = "/tmp/sg-dryrun-test-\(UUID().uuidString)"
        let r = try run(["--output", outputPath, "--dry-run"])
        #expect(r.exitCode == 0, "dry-run should exit 0, got \(r.exitCode); stderr: \(r.stderr)")

        // Output dir must not exist (--dry-run short-circuits before createDirectory).
        #expect(!FileManager.default.fileExists(atPath: outputPath),
                "--dry-run created output dir at \(outputPath); should not")

        // Stdout shape:
        let out = r.stdout
        #expect(out.contains("--dry-run"), "header should mention --dry-run mode")
        #expect(out.contains("SLUG"), "should print SLUG/ROUTING header")
        #expect(out.contains("ROUTING"), "should print SLUG/ROUTING header")
        #expect(out.contains("Summary:"), "should print summary line")

        // At least one curated row (SwiftUI) + at least one skipped row (sirikit).
        #expect(out.contains("swiftui") && out.contains("curated:SwiftUI"),
                "expected 'swiftui' row to be routed as 'curated:SwiftUI'")
        #expect(out.contains("sirikit") && out.contains("skipped:"),
                "expected 'sirikit' row to be routed as 'skipped:'")
    }

    @Test("--dry-run output is deterministic (sorted by slug, no extraction noise)",
          .enabled(if: binAvailable))
    func dryRunDeterministic() throws {
        let r1 = try run(["--output", "/tmp/sg-dryrun-d1", "--dry-run"])
        let r2 = try run(["--output", "/tmp/sg-dryrun-d2", "--dry-run"])
        #expect(r1.exitCode == 0 && r2.exitCode == 0)
        #expect(r1.stdout == r2.stdout, "--dry-run output drifted between runs (non-deterministic)")
    }
}
