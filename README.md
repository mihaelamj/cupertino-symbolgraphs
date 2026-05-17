# cupertino-symbolgraphs

Apple SDK symbolgraph corpus for [cupertino](https://github.com/mihaelamj/cupertino)'s indexer + AppleConstraintsKit.

## What this is

`cupertino-symbolgraphs-gen` runs `xcrun swift symbolgraph-extract` for every Apple framework slug that appears in cupertino's apple-docs corpus, producing one `*.symbols.json` per module. The result is a per-Swift-version snapshot of Apple's public Swift API surface used by downstream tools (e.g. constraint extraction, conformance graph, availability matrix) that need authoritative SDK metadata rather than what's parseable from rendered HTML.

The corpus itself (~1.3 GB on disk) is **not committed to this repo's git tree**. It's regenerated from the active Xcode toolchain via this binary and distributed via [GitHub Releases](https://github.com/mihaelamj/cupertino-symbolgraphs/releases) — one zip per Swift version. The git tree holds only the slug→module mapper, the extractor source, the validation step, and the manifest of the last published corpus.

## When to regenerate

Run `cupertino-symbolgraphs-gen` when any of these change:

- **Xcode / CommandLineTools update** ships a new Swift compiler or new SDK headers
- **macOS SDK target** bumps (the `-target` flag value)
- **New Apple framework** appears in cupertino's apple-docs corpus that isn't in `FrameworkModuleMap.curated` yet — the validator's "SDK has Swift module(s) not in our extraction" warning surfaces this
- **CHANGELOG-tracked Apple deprecation** that drops a previously-extracted framework

After regenerating: publish the corpus as a new GitHub Release zip; update `cupertino`'s pinning to the new release.

## Quick start

```bash
# Build
swift build -c release

# Run
./.build/release/cupertino-symbolgraphs-gen --output /tmp/corpus

# Verify
cat /tmp/corpus/manifest.json | jq '.summary'
ls /tmp/corpus/swiftui/
```

The binary reports per-25-slug progress, validates the result against the SDK's authoritative `.swiftmodule` ground truth, and writes `manifest.json` carrying generation metadata (Swift version, SDK version, target triple, ISO8601 timestamp, per-slug outcomes).

## Architecture

| Source | Purpose |
|---|---|
| `Sources/AppleSymbolGraphsKit/FrameworkModuleMap.swift` | Hand-curated `slug → Swift module name` table. 165+ entries. The source of truth for the extraction input list. |
| `Sources/AppleSymbolGraphsKit/SymbolGraphExtractor.swift` | Wraps `xcrun swift symbolgraph-extract` for one slug at a time; tries curated → PascalCase → slug → uppercase variants in order; returns structured `ExtractionResult`. |
| `Sources/AppleSymbolGraphsKit/SDKModuleEnumerator.swift` | Walks `<sdk>/usr/lib/swift` + `<sdk>/System/Library/{Frameworks,SubFrameworks,PrivateFrameworks}/*.framework/Modules/*.swiftmodule` to enumerate the SDK's authoritative Swift module list — the validation ground truth. |
| `Sources/AppleSymbolGraphsKit/Manifest.swift` | Codable `manifest.json` schema with generation metadata + per-slug outcomes. |
| `Sources/cupertino-symbolgraphs-gen/main.swift` | CLI binary (ArgumentParser) — orchestrates extraction + validation + manifest write. |
| `Tests/AppleSymbolGraphsKitTests/` | Unit tests against the curated table, PascalCase fallback, variant ordering, de-duplication. |

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
| The 1.3 GB corpus itself | [GitHub Releases](https://github.com/mihaelamj/cupertino-symbolgraphs/releases) — zip per Swift version |

The git tree stays small (sources + per-release manifest only); fetching a corpus is one `gh release download` call.

## License

Same as the parent cupertino project.
