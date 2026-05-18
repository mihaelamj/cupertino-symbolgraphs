@testable import AppleSymbolGraphsKit
import Foundation
import Testing

/// Edge-case + invariant suite. The headline tests in
/// `FrameworkModuleMapTests` cover the happy paths; this file pins
/// the boundary behaviour future contributors might quietly break.
@Suite("FrameworkModuleMap — edge cases + invariants")
struct FrameworkModuleMapEdgeTests {
    @Test("moduleName(for:) returns the curated value when present (not PascalCase)")
    func curatedWinsOverPascalCase() {
        // Without the curated entry, `swiftui` → PascalCase = "Swiftui".
        // The curated entry must win.
        #expect(FrameworkModuleMap.moduleName(for: "swiftui") == "SwiftUI")
        #expect(FrameworkModuleMap.moduleName(for: "swiftui") != "Swiftui")
    }

    @Test("moduleName(for:) returns nil for empty slug")
    func emptySlugReturnsNil() {
        // PascalCase of empty string returns empty; moduleName(for:)
        // falls through to that (no curated entry for "")
        let result = FrameworkModuleMap.moduleName(for: "")
        #expect(result == "" || result == nil, "expected empty or nil for empty slug, got '\(String(describing: result))'")
    }

    @Test("Every curated value is non-empty + has no leading/trailing whitespace")
    func curatedValuesWellFormed() {
        for (slug, module) in FrameworkModuleMap.curated {
            #expect(!module.isEmpty, "curated[\(slug)] is empty")
            let trimmed = module.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(module == trimmed, "curated[\(slug)] = '\(module)' has surrounding whitespace")
        }
    }

    @Test("Every curated key is lowercase + has no whitespace")
    func curatedKeysWellFormed() {
        for slug in FrameworkModuleMap.curated.keys {
            #expect(slug == slug.lowercased(), "curated slug '\(slug)' must be lowercase")
            #expect(!slug.contains(" "), "curated slug '\(slug)' must not contain whitespace")
            #expect(!slug.isEmpty, "empty slug in curated map")
        }
    }

    @Test("knownNonExtractable keys + reasons share the same hygiene rules")
    func nonExtractableWellFormed() {
        for (slug, reason) in FrameworkModuleMap.knownNonExtractable {
            #expect(slug == slug.lowercased(), "non-extractable slug '\(slug)' must be lowercase")
            #expect(!slug.contains(" "), "non-extractable slug '\(slug)' must not contain whitespace")
            let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(reason == trimmedReason, "knownNonExtractable['\(slug)'] reason has surrounding whitespace")
            #expect(!reason.contains("TODO") && !reason.contains("FIXME"),
                    "knownNonExtractable['\(slug)'] reason contains a placeholder marker")
        }
    }

    @Test("allCuratedSlugs is sorted ascending")
    func allCuratedSlugsSorted() {
        let slugs = FrameworkModuleMap.allCuratedSlugs
        #expect(slugs == slugs.sorted(), "allCuratedSlugs must return sorted output for stable diffs")
    }

    @Test("Apple's prominent first-party modules are all curated (regression floor)")
    func canonicalAppleSurfaceCovered() {
        // The headline modules every Apple-docs consumer expects.
        // If any of these drops out of curated, that's an audit failure.
        let mustHave = [
            "swiftui", "uikit", "appkit", "foundation", "combine",
            "swiftdata", "storekit", "mapkit", "coredata", "coregraphics",
            "avfoundation", "metal", "realitykit", "arkit", "healthkit",
            "homekit", "watchkit", "cloudkit", "cryptokit", "security",
            "network", "networkextension", "weatherkit", "musickit",
        ]
        for slug in mustHave {
            #expect(FrameworkModuleMap.curated[slug] != nil,
                    "canonical Apple slug '\(slug)' missing from curated map")
        }
    }

    @Test("PascalCase fallback preserves multi-char tokens unchanged after first cap")
    func pascalCaseFallbackPreservesTail() {
        // The fallback only capitalizes the first character — the tail
        // is preserved verbatim. Documents the limitation that
        // multi-word slugs like 'foobarkit' become 'Foobarkit' not 'FooBarKit'.
        #expect(FrameworkModuleMap.pascalCaseFallback("foobarkit") == "Foobarkit")
        #expect(FrameworkModuleMap.pascalCaseFallback("a") == "A")
    }
}
