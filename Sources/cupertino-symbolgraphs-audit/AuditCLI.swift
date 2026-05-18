import ArgumentParser
import Foundation

/// `cupertino-symbolgraphs-audit` — diagnostic CLI for the symbolgraphs
/// corpus + framework module map. Root command groups subcommands that
/// do one focused diagnostic each (validate the corpus shape, cross-
/// reference the brew DB framework list, probe a slug, stats on one
/// `.symbols.json` file, summarize a manifest).
///
/// Exists because the project rule is "Swift everywhere"; before this
/// target landed, the same checks were done as ad-hoc Python heredocs
/// in bash sessions, which violated that rule. Every audit operation
/// the project might re-run lives here as a documented subcommand
/// with --help + unit tests, instead of as throwaway shell.
@main
struct AuditCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cupertino-symbolgraphs-audit",
        abstract: "Diagnostic CLI for the cupertino-symbolgraphs corpus + module map.",
        subcommands: [
            ValidateCorpus.self,
            FrameworkStats.self,
            CountByStatus.self,
        ]
    )
}
