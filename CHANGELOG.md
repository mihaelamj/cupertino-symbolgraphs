# Changelog

All notable changes to `cupertino-symbolgraphs` are documented here.

The corpus itself is distributed via GitHub Releases as `corpus-vX.Y.Z.zip` — see https://github.com/mihaelamj/cupertino-symbolgraphs/releases. This file tracks the regenerator (`cupertino-symbolgraphs-gen`) source + the corpus's shape per release.

## [Unreleased]

## [0.1.0] - 2026-05-18

First release. Cupertino's apple-docs framework slugs extracted across four Apple SDKs (macOS / iOS / watchOS / visionOS) under Xcode 26.5 / Swift 6.3.2 / SDK 26.4.

### Added

- `AppleSymbolGraphsKit` library (Foundation-only):
  - `FrameworkModuleMap` — 225+ entry hand-curated slug → Swift module name table, plus `knownNonExtractable` table mapping 8 slugs that aren't Swift modules in any SDK (server-side REST, separate SPM packages, Xcode-bundled tools, deprecated frameworks) to human-readable reasons.
  - `SymbolGraphExtractor` — multi-target wrapper around `xcrun swift symbolgraph-extract`. Walks (module-name-variant × SDK-target) tuples until first non-empty output, returns structured `ExtractionResult`.
  - `SDKModuleEnumerator` — walks the SDK's `.swiftmodule` tree to produce the ground-truth Swift module list for validation. Cross-SDK aware via `activeSDKPath(sdk:)`.
  - `Manifest` schema v3 — per-corpus metadata: generation timestamp, Swift version, ordered list of `(SDK, target)` pairs with versions, per-slug results, summary aggregates (`okCount`, `failedCount`, `skippedCount`, `bytesPerTarget`, `slugsPerTarget`).

- `cupertino-symbolgraphs-gen` executable (ArgumentParser CLI):
  - Default behaviour: extract every slug against macOS → iOS → watchOS → visionOS SDKs in that order, validate against each SDK's `.swiftmodule` ground truth, write `manifest.json`.
  - Per-target SDK paths + target triples overridable; any fallback disable-able via empty string.
  - Live per-25-slug progress (stdout unbuffered for piped use).
  - Honest unexplained-FAILs dump on completion (zero in this release).

- 19 unit tests covering the curated table (size floor, no duplicates, lowercase entries, drift fill-in), the `knownNonExtractable` invariants (non-empty reasons, disjoint from curated, covers all known residuals), Manifest schema (aggregation, per-target split, sorted-by-slug results, JSON round-trip), and extractor hygiene (multi-target ordering, partial-output cleanup).

### Corpus shape (this release)

To be filled in by the release script — see `manifest.json` in the published zip.

[Unreleased]: https://github.com/mihaelamj/cupertino-symbolgraphs/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mihaelamj/cupertino-symbolgraphs/releases/tag/v0.1.0
