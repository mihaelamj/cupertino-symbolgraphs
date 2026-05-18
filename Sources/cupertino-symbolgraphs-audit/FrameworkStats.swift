import ArgumentParser
import Foundation

/// Single-file diagnostic: load one `.symbols.json`, count total symbols,
/// how many carry `swiftGenerics`, how many carry generic constraints,
/// and print as a small table. Useful for comparing constraint density
/// across frameworks (UIKit ~8%, Combine ~47%, SwiftUI ~33%, …).
///
/// Replaces the previously ad-hoc Python-in-bash queries that computed
/// the same numbers.
struct FrameworkStats: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "framework-stats",
        abstract: "Per-framework symbol + constraint stats from one .symbols.json file."
    )

    @Option(name: .shortAndLong, help: "Path to a single .symbols.json file.")
    var file: String

    func run() throws {
        let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(url.path)")
        }
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw ValidationError("Top level is not a JSON object: \(url.path)")
        }
        let symbols = dict["symbols"] as? [[String: Any]] ?? []
        let total = symbols.count
        // A symbol "has generics" if it has a non-empty swiftGenerics object.
        let withGenerics = symbols.filter { ($0["swiftGenerics"] as? [String: Any]) != nil }
        // A symbol "has constraints" if its swiftGenerics.constraints array is non-empty.
        let withConstraints = symbols.filter {
            guard let sg = $0["swiftGenerics"] as? [String: Any],
                  let c = sg["constraints"] as? [[String: Any]],
                  !c.isEmpty
            else { return false }
            return true
        }

        // Optional metadata.module.name for the heading row.
        let moduleName = (dict["metadata"] as? [String: Any]).flatMap {
            ($0["module"] as? [String: Any])?["name"] as? String
        } ?? url.deletingPathExtension().deletingPathExtension().lastPathComponent

        print("Framework: \(moduleName)")
        print("Source:    \(url.path)")
        print()
        let pct = { (n: Int, d: Int) -> Double in d == 0 ? 0 : Double(n) * 100 / Double(d) }
        print(String(format: "  Total symbols:           %6d", total))
        print(String(format: "  With swiftGenerics:      %6d  (%.1f%%)", withGenerics.count, pct(withGenerics.count, total)))
        print(String(format: "  With generic constraints:%6d  (%.1f%%)", withConstraints.count, pct(withConstraints.count, total)))
    }
}
