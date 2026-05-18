import ArgumentParser
import Foundation

/// Decode every `.symbols.json` under `--directory`, assert each is
/// valid JSON with the expected Apple symbol-graph top-level shape
/// (at least one of `symbols`, `relationships`, `metadata`).
/// Reports `<valid> / <total>` + lists invalid files.
///
/// Exit code: 0 if all valid, 1 if any invalid (useful in CI).
///
/// Replaces the previously ad-hoc Python JSON-validity sweep.
struct ValidateCorpus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate-corpus",
        abstract: "Decode every .symbols.json under <directory> + assert valid shape."
    )

    @Option(name: .shortAndLong, help: "Corpus directory (e.g. the unpacked corpus-v0.1.0.zip).")
    var directory: String

    @Flag(name: .long, help: "Suppress per-file output; only print the summary + any failures.")
    var quiet: Bool = false

    func run() throws {
        let url = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError("Not a directory: \(url.path)")
        }

        let files = try Self.findSymbolsJSONs(at: url)
        if !quiet {
            print("Found \(files.count) .symbols.json files under \(url.path)")
        }

        var invalid: [(URL, String)] = []
        var totalBytes: Int64 = 0
        for file in files {
            let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
            if let size = attrs?[.size] as? Int64 { totalBytes += size }
            do {
                let data = try Data(contentsOf: file)
                let obj = try JSONSerialization.jsonObject(with: data)
                guard let dict = obj as? [String: Any] else {
                    invalid.append((file, "top level is not a JSON object"))
                    continue
                }
                if dict["symbols"] == nil, dict["relationships"] == nil, dict["metadata"] == nil {
                    invalid.append((file, "missing all of top-level keys: symbols / relationships / metadata"))
                }
            } catch {
                invalid.append((file, "decode error: \(error.localizedDescription)"))
            }
        }

        print()
        print("Total .symbols.json files: \(files.count)")
        print("Total bytes:               \(totalBytes / 1_024 / 1_024) MB")
        print("Valid:                     \(files.count - invalid.count)")
        print("Invalid:                   \(invalid.count)")
        if !invalid.isEmpty {
            print()
            print("Invalid files:")
            for (url, reason) in invalid.prefix(50) {
                print("  \(url.path): \(reason)")
            }
            if invalid.count > 50 {
                print("  ... and \(invalid.count - 50) more")
            }
            throw ExitCode.failure
        }
    }

    /// Walk `root` recursively and return every regular file ending in
    /// `.symbols.json`. Order is undefined; caller can sort.
    static func findSymbolsJSONs(at root: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var out: [URL] = []
        for case let item as URL in enumerator {
            guard item.lastPathComponent.hasSuffix(".symbols.json") else { continue }
            let isRegular = (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isRegular { out.append(item) }
        }
        return out
    }
}
