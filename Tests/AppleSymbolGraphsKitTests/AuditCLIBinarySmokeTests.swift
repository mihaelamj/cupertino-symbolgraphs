import Foundation
import Testing

/// Smoke tests for the `cupertino-symbolgraphs-audit` binary
/// (the diagnostic-CLI executable target, not the library).
///
/// Same model as `CLIBinarySmokeTests`: spawn the binary via Process,
/// assert on exit code + stdout shape. Requires the binary to have
/// been built first (`swift test` builds all targets up-front, so
/// `.build/debug/cupertino-symbolgraphs-audit` exists when these run).
@Suite("cupertino-symbolgraphs-audit; CLI binary smoke")
struct AuditCLIBinarySmokeTests {
    private static func binaryPath() -> String? {
        let fm = FileManager.default
        let candidates = [
            "\(fm.currentDirectoryPath)/.build/debug/cupertino-symbolgraphs-audit",
            "\(fm.currentDirectoryPath)/.build/release/cupertino-symbolgraphs-audit",
            "\(fm.currentDirectoryPath)/.build/arm64-apple-macosx/debug/cupertino-symbolgraphs-audit",
        ]
        return candidates.first(where: { fm.fileExists(atPath: $0) })
    }

    private static let binAvailable: Bool = binaryPath() != nil

    private func run(_ args: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        guard let bin = Self.binaryPath() else {
            throw NSError(domain: "AuditCLISmoke", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "cupertino-symbolgraphs-audit binary not found",
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
        return (
            proc.terminationStatus,
            String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    @Test("Root --help lists all 3 subcommands", .enabled(if: binAvailable))
    func rootHelpListsSubcommands() throws {
        let r = try run(["--help"])
        #expect(r.exitCode == 0, "exit \(r.exitCode); stderr: \(r.stderr)")
        for sub in ["validate-corpus", "framework-stats", "count-by-status"] {
            #expect(r.stdout.contains(sub), "--help missing subcommand '\(sub)'; got: \(r.stdout)")
        }
    }

    @Test("validate-corpus --help renders", .enabled(if: binAvailable))
    func validateCorpusHelp() throws {
        let r = try run(["validate-corpus", "--help"])
        #expect(r.exitCode == 0)
        #expect(r.stdout.contains("--directory"))
    }

    @Test("framework-stats --help renders", .enabled(if: binAvailable))
    func frameworkStatsHelp() throws {
        let r = try run(["framework-stats", "--help"])
        #expect(r.exitCode == 0)
        #expect(r.stdout.contains("--file"))
    }

    @Test("count-by-status --help renders", .enabled(if: binAvailable))
    func countByStatusHelp() throws {
        let r = try run(["count-by-status", "--help"])
        #expect(r.exitCode == 0)
        #expect(r.stdout.contains("--manifest"))
    }

    @Test("validate-corpus exits non-zero when directory is missing", .enabled(if: binAvailable))
    func validateCorpusBogusDirFails() throws {
        let r = try run(["validate-corpus", "--directory", "/var/empty/totally-fake-dir-xyz-\(UUID().uuidString)"])
        #expect(r.exitCode != 0)
    }

    @Test("framework-stats exits non-zero when file is missing", .enabled(if: binAvailable))
    func frameworkStatsBogusFileFails() throws {
        let r = try run(["framework-stats", "--file", "/var/empty/totally-fake-file-xyz.symbols.json"])
        #expect(r.exitCode != 0)
    }

    @Test("count-by-status exits non-zero when manifest is missing", .enabled(if: binAvailable))
    func countByStatusBogusManifestFails() throws {
        let r = try run(["count-by-status", "--manifest", "/var/empty/totally-fake.json"])
        #expect(r.exitCode != 0)
    }

    @Test("Unknown subcommand exits non-zero", .enabled(if: binAvailable))
    func unknownSubcommandFails() throws {
        let r = try run(["totally-fake-subcommand"])
        #expect(r.exitCode != 0)
    }

    @Test("validate-corpus on an empty temp dir reports 0 / 0 + exits 0",
          .enabled(if: binAvailable))
    func validateCorpusEmptyDir() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let r = try run(["validate-corpus", "--directory", tmp.path])
        #expect(r.exitCode == 0, "empty dir should pass; got exit \(r.exitCode); stderr: \(r.stderr)")
        #expect(r.stdout.contains("Total .symbols.json files: 0"))
        #expect(r.stdout.contains("Valid:                     0"))
    }

    @Test("validate-corpus catches an invalid .symbols.json + exits non-zero",
          .enabled(if: binAvailable))
    func validateCorpusCatchesInvalid() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-invalid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Write one valid + one invalid .symbols.json
        let validURL = tmp.appendingPathComponent("Foo.symbols.json")
        try #"{"symbols":[],"relationships":[]}"#.write(to: validURL, atomically: true, encoding: .utf8)
        let invalidURL = tmp.appendingPathComponent("Bar.symbols.json")
        try "{this is not valid json".write(to: invalidURL, atomically: true, encoding: .utf8)

        let r = try run(["validate-corpus", "--directory", tmp.path])
        #expect(r.exitCode != 0, "should fail on invalid JSON; got exit \(r.exitCode)")
        #expect(r.stdout.contains("Invalid:                   1"))
    }
}
