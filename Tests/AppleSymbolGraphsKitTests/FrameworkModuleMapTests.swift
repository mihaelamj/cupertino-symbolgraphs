@testable import AppleSymbolGraphsKit
import Foundation
import Testing

@Suite("FrameworkModuleMap; curated mapper")
struct FrameworkModuleMapTests {
    @Test("Resolves canonical Apple slugs via curated table")
    func curatedKnown() {
        #expect(FrameworkModuleMap.moduleName(for: "swiftui") == "SwiftUI")
        #expect(FrameworkModuleMap.moduleName(for: "uikit") == "UIKit")
        #expect(FrameworkModuleMap.moduleName(for: "avfoundation") == "AVFoundation")
        #expect(FrameworkModuleMap.moduleName(for: "coredata") == "CoreData")
        #expect(FrameworkModuleMap.moduleName(for: "applearchive") == "AppleArchive")
        #expect(FrameworkModuleMap.moduleName(for: "mlcompute") == "MLCompute")
        #expect(FrameworkModuleMap.moduleName(for: "opencl") == "OpenCL")
    }

    @Test("Resolves all-lowercase Apple modules verbatim (no PascalCase)")
    func lowercaseModules() {
        // Apple ships these as lowercase Swift module names.
        #expect(FrameworkModuleMap.moduleName(for: "simd") == "simd")
        #expect(FrameworkModuleMap.moduleName(for: "dnssd") == "dnssd")
        #expect(FrameworkModuleMap.moduleName(for: "vmnet") == "vmnet")
        #expect(FrameworkModuleMap.moduleName(for: "xcselect") == "xcselect")
        #expect(FrameworkModuleMap.moduleName(for: "os") == "os")
    }

    @Test("Resolves SDK-drift fill-in slugs")
    func driftFillIn() {
        #expect(FrameworkModuleMap.moduleName(for: "permissionkit") == "PermissionKit")
        #expect(FrameworkModuleMap.moduleName(for: "realityfoundation") == "RealityFoundation")
        #expect(FrameworkModuleMap.moduleName(for: "wifiaware") == "WiFiAware")
        #expect(FrameworkModuleMap.moduleName(for: "ituneslibrary") == "iTunesLibrary")
        #expect(FrameworkModuleMap.moduleName(for: "sensitivecontentanalysis") == "SensitiveContentAnalysis")
    }

    @Test("Curated map covers cupertino's core surface (≥225 entries)")
    func curatedSizeFloor() {
        // Floor catches accidental shrinkage. Bump as we extend.
        #expect(FrameworkModuleMap.curated.count >= 225, "curated entries dropped; found \(FrameworkModuleMap.curated.count)")
    }

    @Test("knownNonExtractable carries human-readable reasons")
    func nonExtractableHasReasons() {
        for (slug, reason) in FrameworkModuleMap.knownNonExtractable {
            #expect(!slug.isEmpty, "empty slug in knownNonExtractable")
            #expect(reason.count >= 20, "knownNonExtractable[\(slug)] reason too terse: '\(reason)'")
        }
    }

    @Test("knownNonExtractable covers the residual FAILs we verified")
    func nonExtractableCoversKnownResiduals() {
        let residuals = ["appstoreserverapi", "carekit", "docc", "mapkitswiftbridge",
                         "photokit", "realitycomposerpro", "sirikit", "testing", "xctest"]
        for slug in residuals {
            #expect(FrameworkModuleMap.knownNonExtractable[slug] != nil, "\(slug) missing from knownNonExtractable")
        }
    }

    @Test("knownNonExtractable is disjoint from curated (no double-routing)")
    func nonExtractableDisjointFromCurated() {
        // A slug should be either extractable (curated/PascalCase) OR
        // known-non-extractable, never both.
        let overlap = Set(FrameworkModuleMap.knownNonExtractable.keys)
            .intersection(Set(FrameworkModuleMap.curated.keys))
        #expect(overlap.isEmpty, "slugs in both curated and knownNonExtractable: \(overlap.sorted())")
    }

    @Test("pascalCaseFallback handles empty input + idempotent for already-PascalCase")
    func pascalCaseFallbackEdge() {
        #expect(FrameworkModuleMap.pascalCaseFallback("") == "")
        #expect(FrameworkModuleMap.pascalCaseFallback("foo") == "Foo")
        #expect(FrameworkModuleMap.pascalCaseFallback("F") == "F", "single uppercase char stays put")
    }

    @Test("Public API surface is stable for downstream consumers")
    func publicAPI() {
        // These calls compile + return; proves the access levels needed
        // by cupertino-symbolgraphs-gen (a sibling target) are exported.
        _ = FrameworkModuleMap.curated["foundation"]
        _ = FrameworkModuleMap.knownNonExtractable["sirikit"]
        _ = FrameworkModuleMap.allCuratedSlugs
        _ = FrameworkModuleMap.pascalCaseFallback("test")
        _ = FrameworkModuleMap.moduleName(for: "foundation")
    }

    @Test("knownNonExtractable.count matches the documented 9-slug ship state")
    func nonExtractableCountStable() {
        // v0.1.0 shipped with exactly 9 known-non-extractable slugs.
        // Bump this floor as future slugs are added.
        #expect(FrameworkModuleMap.knownNonExtractable.count >= 9,
                "knownNonExtractable shrunk; \(FrameworkModuleMap.knownNonExtractable.count) entries")
    }

    @Test("Every knownNonExtractable slug is reachable via moduleName(for:) too")
    func nonExtractableModuleNameReachable() {
        // Even though the slug is short-circuited at extraction time,
        // moduleName(for:) should still return the canonical PascalCase
        // form so downstream tools can render a display name.
        for slug in FrameworkModuleMap.knownNonExtractable.keys {
            #expect(FrameworkModuleMap.moduleName(for: slug) != nil,
                    "moduleName(for: '\(slug)') returned nil")
        }
    }

    @Test("Falls back to PascalCase for slugs not in the curated table")
    func pascalCaseFallback() {
        // Single-word slugs with no special casing → PascalCase fallback works.
        #expect(FrameworkModuleMap.moduleName(for: "somenewframework") == "Somenewframework")
    }

    @Test("Curated table has no empty values")
    func curatedNonEmpty() {
        for (slug, module) in FrameworkModuleMap.curated {
            #expect(!slug.isEmpty, "empty slug key in curated table")
            #expect(!module.isEmpty, "curated[\(slug)] is empty")
        }
    }

    @Test("Curated table has no duplicate Swift module names mapped from different slugs")
    func noDuplicateModules() {
        let modules = FrameworkModuleMap.curated.values
        let unique = Set(modules)
        #expect(modules.count == unique.count, "curated map has duplicate module names")
    }

    @Test("Variants ordering: curated wins, then PascalCase, then slug, then upper")
    func variantOrdering() {
        let variants = SymbolGraphExtractor.variantsToTry(for: "swiftui")
        // Curated is "SwiftUI"; PascalCase fallback is "Swiftui"; slug is "swiftui"; upper is "SWIFTUI"
        #expect(variants.first == "SwiftUI", "curated must lead, got \(variants)")
        #expect(variants.contains("Swiftui"))
        #expect(variants.contains("swiftui"))
        #expect(variants.contains("SWIFTUI"))
    }

    @Test("Variant list de-dupes")
    func variantDedupes() {
        // For a single-character slug all variants might collapse.
        let variants = SymbolGraphExtractor.variantsToTry(for: "foundation")
        #expect(variants.first == "Foundation")
        // PascalCase fallback of "foundation" is also "Foundation"; should de-dupe.
        #expect(variants.filter { $0 == "Foundation" }.count == 1)
    }
}
