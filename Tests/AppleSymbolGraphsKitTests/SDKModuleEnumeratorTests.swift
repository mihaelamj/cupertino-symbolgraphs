@testable import AppleSymbolGraphsKit
import Foundation
import Testing

@Suite("SDKModuleEnumerator; SDK resolution + module discovery")
struct SDKModuleEnumeratorTests {
    /// Skip integration cases when xcrun isn't available (e.g. CI without
    /// Xcode). All these tests need a working `xcrun` + at least the
    /// macOS SDK; without it they have nothing to assert against.
    private static let xcrunAvailable: Bool = FileManager.default.fileExists(atPath: "/usr/bin/xcrun")

    @Test("activeSDKPath() returns a path that exists on disk", .enabled(if: xcrunAvailable))
    func activeSDKPathExists() async throws {
        let path = try await SDKModuleEnumerator.activeSDKPath()
        #expect(!path.isEmpty)
        #expect(FileManager.default.fileExists(atPath: path), "resolved SDK path doesn't exist: \(path)")
    }

    @Test("activeSDKPath() resolves explicitly to macosx (Xcode SDK, not CommandLineTools)",
          .enabled(if: xcrunAvailable))
    func activeSDKPathPrefersXcodeMacOSX() async throws {
        // The bug we shipped a fix for: bare `xcrun --show-sdk-path` returns
        // CommandLineTools (0 swiftmodules) when xcode-select points there.
        // activeSDKPath() must use `--sdk macosx` so we get Xcode's full SDK.
        let path = try await SDKModuleEnumerator.activeSDKPath()
        // Path should mention "MacOSX" (Xcode platform) or be under Xcode.app.
        // CommandLineTools paths are under /Library/Developer/CommandLineTools/
        // and lack the iOSSupport cryptex.
        let hasModules = (try? SDKModuleEnumerator.swiftModules(at: path).count) ?? 0
        #expect(hasModules > 100, "activeSDKPath() resolved an SDK with only \(hasModules) Swift modules; likely CommandLineTools instead of Xcode's MacOSX SDK")
    }

    @Test("activeSDKPath(sdk:) resolves named SDKs", .enabled(if: xcrunAvailable))
    func activeSDKPathByName() async throws {
        let macosx = try await SDKModuleEnumerator.activeSDKPath(sdk: "macosx")
        #expect(macosx.contains("MacOSX"), "macosx SDK path should contain 'MacOSX': \(macosx)")

        // iphoneos is usually present on dev Macs; tolerate absence.
        if let iphoneos = try? await SDKModuleEnumerator.activeSDKPath(sdk: "iphoneos") {
            #expect(iphoneos.contains("iPhoneOS"), "iphoneos SDK path should contain 'iPhoneOS': \(iphoneos)")
        }
    }

    @Test("activeSDKPath(sdk:) throws on a nonexistent SDK name", .enabled(if: xcrunAvailable))
    func activeSDKPathNonexistent() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await SDKModuleEnumerator.activeSDKPath(sdk: "totally-fake-sdk-name-xyz")
        }
    }

    @Test("swiftModules(at:) finds canonical Apple modules in the macOS SDK",
          .enabled(if: xcrunAvailable))
    func swiftModulesCanonical() async throws {
        let sdkPath = try await SDKModuleEnumerator.activeSDKPath()
        let modules = try SDKModuleEnumerator.swiftModules(at: sdkPath)
        // Foundation + Swift stdlib are non-negotiable on any macOS SDK.
        #expect(modules.contains("Foundation"), "macOS SDK is missing Foundation? found \(modules.count) modules")
        #expect(modules.contains("Swift"))
        // SwiftUI is in the iOSSupport cryptex on macOS; proves the
        // cryptex paths are being walked (the bug the v0.1.0 fix closed).
        #expect(modules.contains("SwiftUI"), "SwiftUI not found; cryptex path likely not walked")
    }

    @Test("swiftModules(at:) returns sorted unique values", .enabled(if: xcrunAvailable))
    func swiftModulesSortedUnique() async throws {
        let sdkPath = try await SDKModuleEnumerator.activeSDKPath()
        let modules = try SDKModuleEnumerator.swiftModules(at: sdkPath)
        let sorted = modules.sorted()
        let unique = Set(modules)
        #expect(modules == sorted, "swiftModules(at:) result must be sorted")
        #expect(modules.count == unique.count, "swiftModules(at:) returned duplicates")
    }

    @Test("swiftModules(at:) tolerates a nonexistent SDK path (returns empty)",
          .enabled(if: xcrunAvailable))
    func swiftModulesNonexistentPath() throws {
        // Per the implementation, missing dirs are silently skipped.
        // Passing a fully fake path returns an empty list, not a throw.
        let modules = try SDKModuleEnumerator.swiftModules(at: "/var/empty/totally-fake-sdk-path")
        #expect(modules.isEmpty)
    }
}
