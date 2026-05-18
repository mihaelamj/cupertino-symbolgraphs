# Changelog

All notable changes to `cupertino-symbolgraphs` are documented here.

The corpus itself is distributed via GitHub Releases as `corpus-vX.Y.Z.zip`; see https://github.com/mihaelamj/cupertino-symbolgraphs/releases. This file tracks the regenerator (`cupertino-symbolgraphs-gen`) source + the corpus's shape per release.

## [Unreleased]

## [0.1.1] - 2026-05-18

Empirically-immaculate corpus + tooling release. 100% brew-DB completeness coverage, 5 SDK targets including tvOS, audit CLI replaces ad-hoc Python diagnostics, CI on every push. Public repo flip done in this cycle so the corpus zip is now anonymously fetchable.

### Corpus shape

- 406 slugs total / **269 OK** / **137 SKIP** (non-SDK, documented reasons) / **0 FAIL**
- 1.5 GB raw / 92 MB zipped (`corpus-v0.1.1.zip`)
- 5 SDK targets: macOS 26.5 / iOS 26.5 / watchOS 26.5 / visionOS 26.5 / tvOS 26.5
- All 5 SDK validators report ✅ "All user-facing modules covered"
- Per-target split: 223 macOS / 41 iOS / 3 visionOS / 1 watchOS / 1 tvOS (TVUIKit)

### Added

- **`cupertino-symbolgraphs-audit` diagnostic CLI (3rd executable target, closes #10 / PR #11).** Three subcommands replace ad-hoc Python heredocs used during the v0.1.1 immaculate audit:
  - `validate-corpus --directory <dir>` — decode every `.symbols.json`, assert valid JSON + minimum shape; CI-friendly exit codes
  - `framework-stats --file <path>` — total symbols / with swiftGenerics / with constraints percentages from one `.symbols.json`
  - `count-by-status --manifest <path>` — per-status counts + per-target byte/slug split + top-N largest extractions
  - 10 smoke + real-data tests in `AuditCLIBinarySmokeTests`; numbers cross-verified against the v2-tvos corpus (UIKit 8.0% constrained, SwiftUI 33.0% constrained, validate 532/532 valid). Two deferred subcommands (`cross-ref-brew`, `probe-skipped`) tracked as follow-ups.
- **tvOS as 5th SDK target + `tvuikit` rescue** (closes #2 / PR #7). cupertino-symbolgraphs-gen now extracts under macOS → iOS → watchOS → visionOS → tvOS in that order; TVUIKit lands under `arm64-apple-tvos18` (340 KB). Final corpus shape: 269 OK / 137 SKIP / 0 FAIL across 5 SDKs / 406 slugs total.
- **GitHub Actions CI workflow** (closes #3 / PR #6). `.github/workflows/test.yml` on `macos-15`: checkout, build, test, separate release build of `cupertino-symbolgraphs-gen`, CLI smoke (`--help` renders). Concurrency cancellation, latest-Xcode selection. Runs on every push + PR to main.
- **`--dry-run` / routing-inspection flag** (closes #4 / PR #8). Prints the planned input list + per-slug routing decision (curated vs knownNonExtractable) without spawning xcrun or creating output files. 3 smoke tests including short-circuit verification.
- **DevDBParityTests** (PR #7 side-touch). New fixture `cupertino-dev-framework-slugs-v1.0.x.txt` captures the dev DB framework list; 3 tests cross-reference brew DB ↔ dev DB. Verified byte-identical at capture time.
- **100% brew DB completeness coverage** (398 / 398 cupertino apple-docs slugs routed).
  - 3 new curated entries (real Swift modules previously missing): `pushtotalk` → `PushToTalk` (iOS), `screensaver` → `ScreenSaver` (macOS), `touchcontroller` → `TouchController` (visionOS).
  - 129 new `knownNonExtractable` entries with categorized reasons (22 REST/server-side, 7 web JS SDKs, 12 DriverKit, 10 deprecated frameworks, 21 docs-only pages, 57 "no Swift module").
  - `BrewDBCoverageTests` suite: fixture-backed regression that asserts every cupertino brew-DB slug is routed via curated or knownNonExtractable. 5 tests; the headline one fails loudly if cupertino ships a new framework slug we don't yet route.
- **Expanded test coverage from 19 to 81 tests across 12 suites.** New surfaces tested: SDKModuleEnumerator (7 tests, incl. the Xcode-vs-CommandLineTools-SDK regression guard), ExtractionResult Codable round-trip across all 3 statuses (6), SymbolGraphExtractor end-to-end against real SDKs (5, including the WatchKit watchOS fallback + playgrounds rescue for LiveExecutionResultsRuntime), CLI binary smoke (5, spawning the actual built binary), Manifest edge cases + golden-file regression (12), helper invariants (8).
- Fixture: `Tests/AppleSymbolGraphsKitTests/Fixtures/cupertino-brew-framework-slugs-v1.0.2.txt` (398 slugs, captured from cupertino v1.0.2 brew DB). Declared as a `.copy(...)` test resource; loaded via `Bundle.module`.

### Changed

- All 86 em-dashes removed from source files, docstrings, README, and CHANGELOG (project-wide style rule).
- 18 previously-undocumented public symbols on `Manifest.TargetEntry`, `Manifest.Summary`, `ExtractionResult`, `ExtractionTarget`, and `SymbolGraphExtractor` now carry `///` doc comments.
- `Package.swift`: declared the brew-DB fixture as a test target resource (silences the "unhandled file" SwiftPM warning).

### Released artifacts

- v0.1.1 git tag.
- `corpus-v0.1.1.zip` (sha256 `a35fc1b9190e7e8ef39d639b54e5296b49b3aeea68c429307c756b149012307d`, 92 MB).
- `manifest.json` (sha256 `4862b01697c669251ff3f84fccff589ebe3b3dcc4ff6dd6ce26175ea933f2049`).
- v0.1.0 tag preserved at `de62a95`; the v0.1.0 zip + manifest remain byte-identical on GH releases (sha256 `f398c06d…3ee7` + `6042f166…b3f`).

## [0.1.0] - 2026-05-18

First release. Cupertino's apple-docs framework slugs extracted across four Apple SDKs (macOS / iOS / watchOS / visionOS) under Xcode 26.5 / Swift 6.3.2 / SDK 26.4.

### Added

- `AppleSymbolGraphsKit` library (Foundation-only):
  - `FrameworkModuleMap`; 225+ entry hand-curated slug → Swift module name table, plus `knownNonExtractable` table mapping 8 slugs that aren't Swift modules in any SDK (server-side REST, separate SPM packages, Xcode-bundled tools, deprecated frameworks) to human-readable reasons.
  - `SymbolGraphExtractor`; multi-target wrapper around `xcrun swift symbolgraph-extract`. Walks (module-name-variant × SDK-target) tuples until first non-empty output, returns structured `ExtractionResult`.
  - `SDKModuleEnumerator`; walks the SDK's `.swiftmodule` tree to produce the ground-truth Swift module list for validation. Cross-SDK aware via `activeSDKPath(sdk:)`.
  - `Manifest` schema v3; per-corpus metadata: generation timestamp, Swift version, ordered list of `(SDK, target)` pairs with versions, per-slug results, summary aggregates (`okCount`, `failedCount`, `skippedCount`, `bytesPerTarget`, `slugsPerTarget`).

- `cupertino-symbolgraphs-gen` executable (ArgumentParser CLI):
  - Default behaviour: extract every slug against macOS → iOS → watchOS → visionOS SDKs in that order, validate against each SDK's `.swiftmodule` ground truth, write `manifest.json`.
  - Per-target SDK paths + target triples overridable; any fallback disable-able via empty string.
  - Live per-25-slug progress (stdout unbuffered for piped use).
  - Honest unexplained-FAILs dump on completion (zero in this release).

- 19 unit tests covering the curated table (size floor, no duplicates, lowercase entries, drift fill-in), the `knownNonExtractable` invariants (non-empty reasons, disjoint from curated, covers all known residuals), Manifest schema (aggregation, per-target split, sorted-by-slug results, JSON round-trip), and extractor hygiene (multi-target ordering, partial-output cleanup).

### Corpus shape (this release)

To be filled in by the release script; see `manifest.json` in the published zip.

[Unreleased]: https://github.com/mihaelamj/cupertino-symbolgraphs/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/mihaelamj/cupertino-symbolgraphs/releases/tag/v0.1.1
[0.1.0]: https://github.com/mihaelamj/cupertino-symbolgraphs/releases/tag/v0.1.0
