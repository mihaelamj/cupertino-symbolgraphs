@testable import AppleSymbolGraphsKit
import Foundation
import Testing

/// Parity check between cupertino's brew-installed DB framework list
/// (`cupertino-brew-framework-slugs-v1.0.2.txt`) and the dev DB
/// captured after develop's iter-1+2+3 reindex
/// (`cupertino-dev-framework-slugs-v1.0.x.txt`).
///
/// **Why both fixtures?**
/// At capture time (2026-05-18) the two DBs had identical 398-slug
/// framework lists. This test pins that parity: if a future cupertino
/// release adds new framework slugs only on the dev side (because
/// develop's branch indexed an extra source) or vice versa, the
/// drift is caught here with a concrete added/removed list.
///
/// When the two fixtures genuinely should diverge (e.g. dev-only
/// experimental framework added by an in-flight branch), update both
/// fixtures + adjust the expected delta below.
@Suite("Brew DB ↔ dev DB framework list parity")
struct DevDBParityTests {
    private static let brewFixture = "cupertino-brew-framework-slugs-v1.0.2.txt"
    private static let devFixture  = "cupertino-dev-framework-slugs-v1.0.x.txt"

    private static func loadFixture(_ name: String) throws -> Set<String> {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext) else {
            throw NSError(domain: "DevDBParityTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundle.module missing fixture '\(name)'",
            ])
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        var slugs: Set<String> = []
        for line in raw.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            slugs.insert(t)
        }
        return slugs
    }

    @Test("Both fixtures load and have the expected v1.0.2-era 398-slug count")
    func bothLoadAndHaveExpectedCount() throws {
        let brew = try Self.loadFixture(Self.brewFixture)
        let dev  = try Self.loadFixture(Self.devFixture)
        #expect(brew.count == 398, "brew fixture should have 398 slugs, got \(brew.count)")
        #expect(dev.count == 398, "dev fixture should have 398 slugs, got \(dev.count)")
    }

    @Test("Brew DB ↔ dev DB framework lists are byte-identical at capture time")
    func parityHolds() throws {
        let brew = try Self.loadFixture(Self.brewFixture)
        let dev  = try Self.loadFixture(Self.devFixture)
        let onlyInBrew = brew.subtracting(dev)
        let onlyInDev  = dev.subtracting(brew)
        #expect(onlyInBrew.isEmpty,
                "slugs in brew DB but missing from dev DB: \(onlyInBrew.sorted())")
        #expect(onlyInDev.isEmpty,
                "slugs in dev DB but missing from brew DB (likely dev added new sources): \(onlyInDev.sorted())")
    }

    @Test("Dev DB coverage is also 100% routed via FrameworkModuleMap")
    func devDBFullyRouted() throws {
        // Independent of the brew DB check; if the two fixtures ever
        // diverge, this still proves the dev DB side is fully routed.
        let dev = try Self.loadFixture(Self.devFixture)
        let curated = Set(FrameworkModuleMap.curated.keys)
        let nonExtractable = Set(FrameworkModuleMap.knownNonExtractable.keys)
        let covered = curated.union(nonExtractable)
        let uncovered = dev.subtracting(covered)
        #expect(uncovered.isEmpty,
                "dev DB has \(uncovered.count) slug(s) not routed by FrameworkModuleMap: \(uncovered.sorted())")
    }
}
