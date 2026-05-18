# Changelog

All notable changes to `cupertino-symbolgraphs` are documented here.

The corpus itself is distributed via GitHub Releases as `corpus-vX.Y.Z.zip`; see https://github.com/mihaelamj/cupertino-symbolgraphs/releases. This file tracks the regenerator (`cupertino-symbolgraphs-gen`) source + the corpus's shape per release.

## [Unreleased]

### Added

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

### Released artifacts (unchanged)

- v0.1.0 git tag still at `de62a95`.
- `corpus-v0.1.0.zip` (sha256 `f398c06d1566cfdd8629a51630d179d64e4697be8847aea438ebf54283363ee7`, 91 MB) and `manifest.json` (sha256 `6042f16678d1eb5b0933aefa66c503103c615cc2f9a67d6b3b88677eeedb6b3f`) on the GitHub release are byte-identical to what shipped.
- The expanded coverage + test surface ship in a future v0.1.1; no new artifact bundled in this Unreleased section.

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

[Unreleased]: https://github.com/mihaelamj/cupertino-symbolgraphs/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mihaelamj/cupertino-symbolgraphs/releases/tag/v0.1.0
