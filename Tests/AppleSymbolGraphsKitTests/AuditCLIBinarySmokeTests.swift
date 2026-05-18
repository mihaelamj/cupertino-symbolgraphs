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

    @Test("count-by-status on a real synthetic manifest prints expected sections + counts",
          .enabled(if: binAvailable))
    func countByStatusRealData() throws {
        // Build a tiny but realistic manifest.json on disk; run the
        // binary against it; assert the actual stdout includes the
        // sections + numbers we expect. Catches format-string crashes
        // (we had a %s-with-Swift-String crash that ONLY surfaced when
        // the subcommand had data to format; the --help-only test
        // missed it).
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-countbystatus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let manifestJSON = """
        {
          "manifestVersion": 3,
          "generatedAt": "2026-05-18T00:00:00Z",
          "swiftVersion": "Apple Swift version 6.3.2",
          "targets": [
            { "targetTriple": "arm64-apple-macos15", "sdkPath": "/M", "sdkVersion": "26.5" },
            { "targetTriple": "arm64-apple-ios18",   "sdkPath": "/I", "sdkVersion": "26.5" }
          ],
          "results": [
            { "slug": "alpha",   "moduleName": "Alpha",   "targetTriple": "arm64-apple-macos15", "status": "ok",      "sizeBytes": 4096,  "fileCount": 1, "errorMessage": null },
            { "slug": "beta",    "moduleName": "Beta",    "targetTriple": "arm64-apple-ios18",   "status": "ok",      "sizeBytes": 8192,  "fileCount": 2, "errorMessage": null },
            { "slug": "skipper", "moduleName": "Skipper", "targetTriple": "arm64-apple-macos15", "status": "skipped", "sizeBytes": 0,     "fileCount": 0, "errorMessage": "test reason" }
          ],
          "summary": {
            "totalSlugs": 3,
            "okCount": 2,
            "failedCount": 0,
            "skippedCount": 1,
            "totalBytes": 12288,
            "bytesPerTarget": { "arm64-apple-macos15": 4096, "arm64-apple-ios18": 8192 },
            "slugsPerTarget": { "arm64-apple-macos15": 1,    "arm64-apple-ios18": 1 }
          }
        }
        """
        let manifestPath = tmp.appendingPathComponent("manifest.json")
        try manifestJSON.write(to: manifestPath, atomically: true, encoding: .utf8)

        let r = try run(["count-by-status", "--manifest", manifestPath.path, "--top-n", "5"])
        #expect(r.exitCode == 0, "should succeed on valid manifest; got \(r.exitCode); stderr: \(r.stderr)")

        // Assert section headers + key numbers all present (catches
        // format-string crashes that produced no output or partial output).
        let expected = [
            "Manifest schema: v3",
            "ok:             2",
            "skipped:        1",
            "failed:         0",
            "Per target:",
            "arm64-apple-macos15",
            "arm64-apple-ios18",
            "Top 5 largest extractions:",
            "Beta",
            "Alpha",
        ]
        for needle in expected {
            #expect(r.stdout.contains(needle), "count-by-status output missing '\(needle)'; got:\n\(r.stdout)")
        }
    }

    @Test("framework-stats on a real synthetic .symbols.json prints expected counts",
          .enabled(if: binAvailable))
    func frameworkStatsRealData() throws {
        // Same model: a tiny realistic .symbols.json fixture, assert
        // the binary computes + prints the right counts.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-frameworkstats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 4 symbols: 1 with constraints, 1 with generics but no constraints, 2 plain.
        let symbolsJSON = """
        {
          "metadata": { "module": { "name": "TestModule" } },
          "symbols": [
            { "names": { "title": "alpha" }, "kind": { "identifier": "swift.func" } },
            { "names": { "title": "beta" },  "kind": { "identifier": "swift.struct" } },
            { "names": { "title": "gamma" }, "kind": { "identifier": "swift.func" },
              "swiftGenerics": { "parameters": [{"name":"T"}], "constraints": [] } },
            { "names": { "title": "delta" }, "kind": { "identifier": "swift.func" },
              "swiftGenerics": { "parameters": [{"name":"T"}], "constraints": [{"lhs":"T","kind":"conformance","rhs":"Equatable"}] } }
          ]
        }
        """
        let path = tmp.appendingPathComponent("TestModule.symbols.json")
        try symbolsJSON.write(to: path, atomically: true, encoding: .utf8)

        let r = try run(["framework-stats", "--file", path.path])
        #expect(r.exitCode == 0, "should succeed; got \(r.exitCode); stderr: \(r.stderr)")
        #expect(r.stdout.contains("Framework: TestModule"))
        // Whitespace-tolerant: collapse runs of whitespace, then match.
        let normalized = r.stdout.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        #expect(normalized.contains("Total symbols: 4"))
        #expect(normalized.contains("With swiftGenerics: 2"))
        #expect(normalized.contains("With generic constraints: 1"))
        #expect(normalized.contains("50.0%"), "expected 50% generics for 2/4")
        #expect(normalized.contains("25.0%"), "expected 25% constraints for 1/4")
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
