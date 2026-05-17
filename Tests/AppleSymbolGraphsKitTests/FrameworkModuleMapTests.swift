@testable import AppleSymbolGraphsKit
import Testing

@Suite("FrameworkModuleMap — curated mapper")
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
        // PascalCase fallback of "foundation" is also "Foundation" — should de-dupe.
        #expect(variants.filter { $0 == "Foundation" }.count == 1)
    }
}
