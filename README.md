# cupertino-symbolgraphs

Apple SDK symbolgraph corpus for [cupertino](https://github.com/mihaelamj/cupertino)'s indexer + AppleConstraintsKit.

## What this is

`cupertino-symbolgraphs-gen` runs `xcrun swift symbolgraph-extract` for every Apple framework slug that appears in cupertino's apple-docs corpus, producing one `*.symbols.json` per module. The result is a per-Swift-version snapshot of Apple's public Swift API surface used by downstream tools (e.g. constraint extraction, conformance graph, availability matrix) that need authoritative SDK metadata rather than what's parseable from rendered HTML.

The corpus is **not committed to this repo's git tree**. It's regenerated from the active Xcode toolchain via this binary and distributed via [GitHub Releases](https://github.com/mihaelamj/cupertino-symbolgraphs/releases); one zip per Swift version. The git tree holds only the slug→module mapper, the extractor source, the validation step, and the manifest of the last published corpus.

## Coverage

Each framework is extracted under macOS first (`arm64-apple-macos15` against the active macOS SDK). Frameworks that don't exist on macOS (UIKit, WatchKit, MessageUI, CarPlay, HealthKitUI, etc.) automatically fall back to iOS (`arm64-apple-ios18` against the active iPhoneOS SDK) so the published corpus is the union of both platforms. Per-slug results record which target produced them; the manifest's `summary.slugsPerTarget` aggregates the split.

## When to regenerate

Run `cupertino-symbolgraphs-gen` when any of these change:

- **Xcode / CommandLineTools update** ships a new Swift compiler or new SDK headers
- **macOS or iOS SDK target** bumps (the `--macos-target` / `--ios-target` flags)
- **New Apple framework** appears in cupertino's apple-docs corpus that isn't in `FrameworkModuleMap.curated` yet; the validator's "module(s) present in SDK but not extracted" warning surfaces this
- **CHANGELOG-tracked Apple deprecation** that drops a previously-extracted framework

After regenerating: publish the corpus as a new GitHub Release zip; update `cupertino`'s pinning to the new release.

## Quick start

```bash
# Build
swift build -c release

# Run (dual-target by default: macOS primary, iOS fallback)
./.build/release/cupertino-symbolgraphs-gen --output /tmp/corpus

# Single-target (e.g. macOS only)
./.build/release/cupertino-symbolgraphs-gen --output /tmp/corpus --ios-sdk-path ""

# Verify
cat /tmp/corpus/manifest.json | jq '.summary'
ls /tmp/corpus/swiftui/
ls /tmp/corpus/uikit/    # iOS-only framework, captured via fallback
```

The binary reports per-25-slug progress, validates the result against each SDK's authoritative `.swiftmodule` ground truth, and writes `manifest.json` carrying generation metadata (Swift version, per-target SDK paths + versions, ISO8601 timestamp, per-slug outcomes, per-target bytes / slug counts).

## Architecture

| Source | Purpose |
|---|---|
| `Sources/AppleSymbolGraphsKit/FrameworkModuleMap.swift` | Hand-curated `slug → Swift module name` table (225+ entries) + `knownNonExtractable` table mapping the 8 slugs that aren't Swift modules in any SDK (server-side REST, separate SPM packages, Xcode-bundled tools, deprecated frameworks) to human-readable reasons. The disjoint invariant is test-enforced. |
| `Sources/AppleSymbolGraphsKit/SymbolGraphExtractor.swift` | Multi-target wrapper around `xcrun swift symbolgraph-extract`. For each `(sdk, target)` pair, tries `curated → PascalCase → slug → UPPERCASE` variants until first non-empty output. Short-circuits to `Status.skipped` when the slug is in `knownNonExtractable`. |
| `Sources/AppleSymbolGraphsKit/SDKModuleEnumerator.swift` | Walks `<sdk>/usr/lib/swift` + `<sdk>/System/Library/{Frameworks,SubFrameworks,PrivateFrameworks}/*.framework/Modules/*.swiftmodule` to enumerate the SDK's authoritative Swift module list. Cross-SDK aware via `activeSDKPath(sdk:)`. |
| `Sources/AppleSymbolGraphsKit/Manifest.swift` | Codable `manifest.json` schema (v3): per-corpus metadata, ordered `[TargetEntry]` list with versions, per-slug results, aggregate `(ok / skipped / failed)` counts + `bytesPerTarget` + `slugsPerTarget` splits. |
| `Sources/cupertino-symbolgraphs-gen/main.swift` | CLI binary (ArgumentParser); orchestrates extraction across all four SDKs + validation + manifest write. |
| `Tests/AppleSymbolGraphsKitTests/` | 81 tests in 12 suites covering: curated lookups + PascalCase fallback + lowercase modules + drift fill-in; `knownNonExtractable` invariants (disjoint, non-empty reasons, no shadow of canonical slugs); Manifest schema + aggregation + JSON round-trip; ExtractionResult Codable round-trip (all 3 statuses); SDKModuleEnumerator (cryptex paths, named SDKs); SymbolGraphExtractor variant ordering + multi-target chain + playgrounds rescue + end-to-end against real SDKs (Foundation/WatchKit/bogus); CLI binary smoke (spawns the built binary, asserts --help/missing-arg/unknown-flag); golden-file regression against shipped v0.1.0; brew-DB completeness regression (every cupertino apple-docs slug routed). |

## Validation

After extracting, the binary cross-references its OK set against the SDK's `.swiftmodule` ground truth and reports any user-facing Swift module the SDK has but our extraction missed. Private modules (`_Concurrency`, `_StringProcessing`, etc.) and slugs not in cupertino's apple-docs corpus are filtered out of the drift report.

A clean run reports `✅ All user-facing SDK Swift modules extracted`. A drift report names missing modules so the next maintainer can add them to `FrameworkModuleMap.curated`.

## Why this exists as its own package

Two consumers:

1. **cupertino's AppleConstraintsKit** (in flight) parses these `.symbols.json` files to populate the `doc_symbols.generic_constraints` column (cupertino #755 / #759).
2. **Future Apple-SDK introspection work** (conformance graph, availability matrix, anything that wants the canonical Swift API surface) reads the same corpus instead of re-extracting.

Splitting the extractor from any one consumer keeps the dependency direction clean: consumers depend on `AppleSymbolGraphsKit`, never the other way. The package lifts out with only Foundation + ArgumentParser as deps.

## Distribution

| Artifact | Where |
|---|---|
| Slug→module mapper | This git tree (`Sources/AppleSymbolGraphsKit/FrameworkModuleMap.swift`) |
| Extractor source | This git tree |
| Validator source | This git tree |
| Most-recent corpus manifest | This git tree (`manifest.json` in each release tag) |
| The 1.3 GB corpus itself | [GitHub Releases](https://github.com/mihaelamj/cupertino-symbolgraphs/releases); zip per Swift version |

The git tree stays small (sources + per-release manifest only); fetching a corpus is one `gh release download` call.

## License

Same as the parent cupertino project.
