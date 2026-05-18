import Foundation

/// Maps cupertino's apple-docs framework slugs to the Apple Swift module
/// names accepted by `xcrun swift symbolgraph-extract -module-name`.
///
/// The mapping is hand-curated because Apple's docs URL slugs are
/// lowercased (`swiftui`, `coreaudio`) while module names use
/// PascalCase with project-specific casing (`SwiftUI`, `CoreAudio`,
/// `AVFoundation`, `UIKit`, `OpenCL`). Simple uppercase-first
/// PascalCasing produces the right answer for ~half the corpus;
/// the rest need explicit entries.
///
/// The map is a single source of truth for `cupertino-symbolgraphs-gen`
/// (which uses it as the extraction input) and any downstream consumer
/// that needs to reverse-look-up "what Swift module does this docs page
/// belong to?". Both surfaces import `AppleSymbolGraphsKit` and read
/// the same table.
///
/// Regeneration trigger: when a new Apple framework appears in
/// cupertino's apple-docs corpus that this table doesn't already
/// cover. The cross-validation step in `SDKModuleEnumerator` surfaces
/// missing entries against the SDK's authoritative `.swiftmodule`
/// list, so the regeneration script self-reports drift.
public enum FrameworkModuleMap {
    /// Resolve a docs-corpus framework slug to its Swift module name.
    /// Returns `nil` when the slug isn't a Swift module at all (e.g.
    /// JS-only APIs like `cloudkitjs`, web REST endpoints, docs-only
    /// slugs like `xcode-release-notes`).
    ///
    /// When the slug is a Swift module but not in the hand-curated
    /// table, returns the PascalCase fallback. Callers that need
    /// confidence should validate against `SDKModuleEnumerator`.
    public static func moduleName(for slug: String) -> String? {
        if let curated = curated[slug] {
            return curated
        }
        return pascalCaseFallback(slug)
    }

    /// All slugs the curated map knows about (input list for the
    /// extractor; doesn't include the PascalCase-fallback frameworks
    /// since those are derived on demand).
    public static var allCuratedSlugs: [String] {
        Array(curated.keys).sorted()
    }

    /// Slugs that appear in cupertino's apple-docs corpus but cannot be
    /// extracted as Swift modules from any Xcode SDK, mapped to a short
    /// human-readable reason. The extractor short-circuits these with
    /// `Status.skipped` so they don't show up as FAILs in the manifest.
    ///
    /// Update only with evidence; a slug here means we've verified the
    /// framework is genuinely not a Swift module in the SDK family.
    public static let knownNonExtractable: [String: String] = [
        "appstoreserverapi":   "server-side REST API, no client Swift module in any SDK",
        "carekit":             "separate open-source SPM package (carekit-apple/CareKit), not bundled with Xcode SDKs",
        "docc":                "documentation compiler tool, not a Swift module",
        // over-coverage rationale (#5): mapkitswiftbridge is NOT in cupertino's apple-docs
        // corpus (no dedicated docs page; the framework is nested inside MapKit.framework
        // as MapKit.framework/MapKitSwiftBridge.framework/Modules/MapKitSwiftBridge.swiftmodule).
        // We keep it in knownNonExtractable solely to silence the iOS + xros SDK validator
        // drift report; without this entry the validator would emit
        // "⚠️  1 module(s) present in SDK but not extracted: MapKitSwiftBridge" on every run.
        // Surface lives under slug 'mapkit' (extracted normally as MapKit's .symbols.json).
        "mapkitswiftbridge":   "nested inside MapKit.framework (MapKit.framework/MapKitSwiftBridge.framework/Modules/), not standalone-extractable; surface lives under slug 'mapkit'",
        "photokit":            "marketing alias for the Photos framework; use slug 'photos' (module 'Photos') instead",
        "realitycomposerpro":  "Xcode-bundled tool, not a Swift module",
        "sirikit":             "deprecated; functionality moved to Intents + IntentsUI",
        "testing":             "swift-testing package distributed via swift-package-manager, not the platform SDK",
        "xctest":              "lives at Xcode platform Developer/Library/Frameworks, outside the SDK module search path",

        // MARK: - Brew-DB completeness audit additions (129 slugs cupertino indexes that aren't Swift modules in any Xcode SDK; classified mechanically by slug shape + verified against the union of macOS / iOS / watchOS / visionOS / DriverKit `.swiftmodule` directories)
        "accountdatatransfer":                       "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "accountorganizationaldatasharing":          "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "addressbook":                               "deprecated; functionality moved to Contacts (slug: contacts)",
        "addressbookui":                             "deprecated; functionality moved to ContactsUI (slug: contactsui)",
        "adservices":                                "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "adsupport":                                 "Obj-C ASIdentifierManager; no Swift module ships in SDK",
        "advancedcommerceapi":                       "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "analytics-reports":                         "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "appclip":                                   "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "appdatatransfer":                           "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "appdistribution":                           "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "apple-silicon":                             "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "apple_ads":                                 "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "apple_pay_on_the_web":                      "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "applemapsserverapi":                        "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "applemusicapi":                             "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "applemusicfeed":                            "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "applenews":                                 "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "applenewsapi":                              "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "applenewsformat":                           "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "applepaymerchanttokenmanagementapi":        "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "applepaymerchanttokenusageinformation":     "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "applepayontheweb":                          "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "applepaywebmerchantregistrationapi":        "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "applepencil":                               "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "applicationservices":                       "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "applicensedeliverysdk":                     "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "appstoreconnectapi":                        "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "appstorereceipts":                          "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "appstoreservernotifications":               "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "apptrackingtransparency":                   "Obj-C only framework with C-API; no Swift module ships in SDK",
        "audiodriverkit":                            "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "automaticsigninapi":                        "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "availability":                              "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "blockstoragedevicedriverkit":               "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "bundleresources":                           "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "cktooljs":                                  "web JavaScript SDK, not a Swift module",
        "classkitcatalogapi":                        "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "cloudkitjs":                                "web JavaScript SDK, not a Swift module",
        "colorsync":                                 "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "darwinnotify":                              "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "developertoolssupport":                     "no primary Swift module ships under this slug; surfaces only as cross-module extension target (e.g. SwiftUI@DeveloperToolsSupport)",
        "devicemanagement":                          "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "diskarbitration":                           "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "driverkit":                                 "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "endpointsecurity":                          "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "enterpriseprogramapi":                      "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "exceptionhandling":                         "legacy Foundation exception bridge; deprecated, NSError pattern preferred",
        "executionpolicy":                           "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "exposurenotification":                      "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "externalpurchaseserverapi":                 "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "forcefeedback":                             "legacy macOS-only haptics framework, superseded by Core Haptics (slug: corehaptics)",
        "hiddriverkit":                              "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "http-live-streaming":                       "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "iad":                                       "discontinued by Apple; iAd network shut down in 2016",
        "inputmethodkit":                            "macOS framework with C-only API surface; no Swift module ships in the SDK",
        "installer_js":                              "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "ios-ipados-release-notes":                  "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "iworkdocumentexportingapi":                 "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "kernel":                                    "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "latentsemanticmapping":                     "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "livephotoskitjs":                           "web JavaScript SDK, not a Swift module",
        "macos-release-notes":                       "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "mapkitjs":                                  "web JavaScript SDK, not a Swift module",
        "medialibrary":                              "deprecated; replaced by Photos (slug: photos)",
        "mediasetup":                                "deprecated 2024; functionality folded into Network framework",
        "merchanttokennotificationservices":         "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "mididriverkit":                             "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "networkingdriverkit":                       "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "notaryapi":                                 "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "packagedescription":                        "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "paravirtualizedgraphics":                   "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "passkit_apple_pay_and_wallet":              "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "pcidriverkit":                              "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "playgroundbluetooth":                       "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "playgroundsupport":                         "Swift Playgrounds-only framework; not bundled in standard Xcode SDKs",
        "preferencepanes":                           "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "professional-video-applications":           "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "professional_video_applications":           "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "quicktime-file-format":                     "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "retentionmessaging":                        "Apple-internal service surface, no client Swift module",
        "root":                                      "documentation root page, not a framework",
        "rosterapi":                                 "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "safari-developer-tools":                    "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "safari-release-notes":                      "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "safariextensions":                          "Safari extension surface (Obj-C / WebExtensions JSON); no extractable Swift module",
        "samplecode":                                "documentation umbrella for sample-code pages, not a framework",
        "screentimeapidocumentation":                "documentation umbrella under ScreenTime, not a framework",
        "scriptingbridge":                           "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "scsicontrollerdriverkit":                   "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "scsiperipheralsdriverkit":                  "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "serialdriverkit":                           "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "shadergraph":                               "Reality Composer Pro shader-graph editor surface; not an extractable Swift module",
        "sign_in_with_apple":                        "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "signinwithapple":                           "no top-level Swift module under this slug; functionality is in AuthenticationServices (slug: authenticationservices)",
        "signinwithapplejs":                         "web JavaScript SDK, not a Swift module",
        "signinwithapplerestapi":                    "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "sirieventsuggestionsmarkup":                "schema.org-style markup for Siri Suggestions, not a Swift framework",
        "sirikitcloudmedia":                         "sub-framework / private surface; no extractable Swift module",
        "skadnetworkforwebads":                      "web/server-side ad attribution surface, not a Swift module",
        "snapshots":                                 "documentation umbrella, not a framework",
        "storekittest":                              "Apple-internal StoreKit test support; not shipped as an extractable Swift module in any standard SDK module search path",
        "swift-playgrounds":                         "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "technologies":                              "documentation umbrella for technology landing pages, not a framework",
        "technologyoverviews":                       "documentation umbrella, not a framework",
        "technotes":                                 "documentation umbrella for Apple Tech Notes, not a framework",
        "touchcontrols":                             "visionOS Touch Controls surface; no extractable Swift module under this slug",
        "tvml":                                      "TVML is a web markup language for Apple TV, not a Swift framework",
        "tvmljs":                                    "web JavaScript SDK, not a Swift module",
        "tvmlkit":                                   "TVMLKit is Obj-C only; no Swift module in SDK",
        "tvos-release-notes":                        "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "tvservices":                                "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "tvuikit":                                   "tvOS-only Swift module; would extract under an appletvos SDK target which is not currently configured in cupertino-symbolgraphs-gen",
        "updates":                                   "documentation umbrella for what-new-in pages, not a framework",
        "usbdriverkit":                              "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "usbserialdriverkit":                        "DriverKit family framework; Obj-C/C++ only; DriverKit SDK ships zero .swiftmodule files",
        "usd":                                       "Universal Scene Description (Pixar); Obj-C/C++ only, no Swift module in SDK",
        "visionos":                                  "platform documentation umbrella, not a framework",
        "visionos-release-notes":                    "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "walletorders":                              "PassKit Orders / Apple Wallet orders surface; no standalone Swift module under this slug",
        "walletpasses":                              "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "watchos-apps":                              "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "watchos-release-notes":                     "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "weatherkitrestapi":                         "server-side REST API / service surface, no client Swift module in any Xcode SDK",
        "webkitjs":                                  "web JavaScript SDK, not a Swift module",
        "xcode":                                     "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "xcode-release-notes":                       "documentation-only page (slug contains hyphen/underscore; not a framework module name)",
        "xcodekit":                                  "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",
        "xcuiautomation":                            "no Swift module in any Xcode SDK (macOS / iOS / watchOS / visionOS / DriverKit); likely an Obj-C/C++ framework, documentation umbrella, or legacy/private surface",

    ]

    /// Default uppercase-first transformation. Used as the fallback
    /// when no curated entry exists. Handles single-word slugs
    /// correctly (`foundation` → `Foundation`); fails on multi-word
    /// camelcase Apple frameworks (`avfoundation` → `Avfoundation`,
    /// should be `AVFoundation`); those need curated entries.
    public static func pascalCaseFallback(_ slug: String) -> String {
        guard let first = slug.first else { return slug }
        return first.uppercased() + slug.dropFirst()
    }

    /// Hand-curated map of slug → exact Swift module name. The keys are
    /// the lowercased framework slugs cupertino's apple-docs corpus
    /// uses; the values are the case-sensitive `module-name` arg
    /// `swift symbolgraph-extract` accepts.
    ///
    /// Order in the source file follows logical groupings: Apple-Core
    /// frameworks first, then AV/Media, then UI/AppKit, then
    /// CloudKit/Network/Auth, then ML/Vision, then everything else.
    /// Sort discipline isn't load-bearing; readability is.
    public static let curated: [String: String] = [
        // MARK: - Foundation + Core
        "foundation": "Foundation",
        "swift": "Swift",
        "dispatch": "Dispatch",
        // over-coverage rationale (cupertino-symbolgraphs#5): Darwin is the Swift overlay
        // over libc / POSIX C surface; ships in every Apple SDK. cupertino's apple-docs
        // corpus doesn't index it (no dedicated /documentation/darwin page), but downstream
        // consumers of the corpus (constraint generators, conformance walkers) often need
        // to resolve type references that bottom out in Darwin types (CInt, time_t, …).
        // Keeping extracted. Removing would also fire SDK validator drift.
        "darwin": "Darwin",
        "os": "os",
        "oslog": "OSLog",
        "observation": "Observation",
        "combine": "Combine",
        "distributed": "Distributed",
        "synchronization": "Synchronization",
        "regexbuilder": "RegexBuilder",
        "objectivec": "ObjectiveC",

        // MARK: - Core* family
        "coreaudio": "CoreAudio",
        "coreaudiokit": "CoreAudioKit",
        "coreaudiotypes": "CoreAudioTypes",
        "corebluetooth": "CoreBluetooth",
        "coredata": "CoreData",
        "corefoundation": "CoreFoundation",
        "coregraphics": "CoreGraphics",
        "corehaptics": "CoreHaptics",
        "corehid": "CoreHID",
        "coreimage": "CoreImage",
        "corelocation": "CoreLocation",
        "corelocationui": "CoreLocationUI",
        "coremedia": "CoreMedia",
        "coremediaio": "CoreMediaIO",
        "coremidi": "CoreMIDI",
        "coreml": "CoreML",
        "coremotion": "CoreMotion",
        "corenfc": "CoreNFC",
        "coreservices": "CoreServices",
        "corespotlight": "CoreSpotlight",
        "coretelephony": "CoreTelephony",
        "coretext": "CoreText",
        "coretransferable": "CoreTransferable",
        "corevideo": "CoreVideo",
        "corewlan": "CoreWLAN",

        // MARK: - AV / Media
        "avfoundation": "AVFoundation",
        "avfaudio": "AVFAudio",
        "avkit": "AVKit",
        "avrouting": "AVRouting",
        "audiotoolbox": "AudioToolbox",
        "audiounit": "AudioUnit",
        "soundanalysis": "SoundAnalysis",
        "speech": "Speech",
        "shazamkit": "ShazamKit",
        "musickit": "MusicKit",
        "mediaplayer": "MediaPlayer",
        "mediaaccessibility": "MediaAccessibility",
        "mediatoolbox": "MediaToolbox",
        "videotoolbox": "VideoToolbox",
        "cinematic": "Cinematic",

        // MARK: - UI (AppKit / UIKit / SwiftUI)
        "swiftui": "SwiftUI",
        "uikit": "UIKit",
        "appkit": "AppKit",
        "watchkit": "WatchKit",
        "spritekit": "SpriteKit",
        "scenekit": "SceneKit",
        "quartzcore": "QuartzCore",
        "metal": "Metal",
        "metalkit": "MetalKit",
        "metalfx": "MetalFX",
        "metalperformanceshaders": "MetalPerformanceShaders",
        "metalperformanceshadersgraph": "MetalPerformanceShadersGraph",
        "modelio": "ModelIO",
        "realitykit": "RealityKit",
        // "realitycomposerpro": Xcode-bundled tool, see knownNonExtractable.
        "carplay": "CarPlay",
        "callkit": "CallKit",
        "messages": "Messages",
        "messageui": "MessageUI",
        "mailkit": "MailKit",
        "paperkit": "PaperKit",
        "pencilkit": "PencilKit",
        "tipkit": "TipKit",
        "widgetkit": "WidgetKit",
        "tabletopkit": "TabletopKit",
        "tabulardata": "TabularData",
        "charts": "Charts",
        "pdfkit": "PDFKit",
        "quicklook": "QuickLook",
        "quicklookthumbnailing": "QuickLookThumbnailing",
        "quicklookui": "QuickLookUI",
        "passkit": "PassKit",
        "linkpresentation": "LinkPresentation",

        // MARK: - Network / Cloud / Auth
        "network": "Network",
        "networkextension": "NetworkExtension",
        "cfnetwork": "CFNetwork",
        "cloudkit": "CloudKit",
        "authenticationservices": "AuthenticationServices",
        "localauthentication": "LocalAuthentication",
        "cryptokit": "CryptoKit",
        "security": "Security",
        "securityfoundation": "SecurityFoundation",
        "securityinterface": "SecurityInterface",
        // "appstoreserverapi": server-side REST, see knownNonExtractable.

        // MARK: - Sensors / Hardware / IO
        "sensorkit": "SensorKit",
        "iokit": "IOKit",
        "iobluetooth": "IOBluetooth",
        "iobluetoothui": "IOBluetoothUI",
        "iousbhost": "IOUSBHost",
        "iosurface": "IOSurface",
        "externalaccessory": "ExternalAccessory",
        "homekit": "HomeKit",
        "nearbyinteraction": "NearbyInteraction",
        "proximityreader": "ProximityReader",
        "threadnetwork": "ThreadNetwork",
        "watchconnectivity": "WatchConnectivity",
        "weatherkit": "WeatherKit",
        "spatial": "Spatial",
        "phase": "PHASE",
        "hvf": "hvf",

        // MARK: - ML / Vision / NLP
        "createml": "CreateML",
        "createmlcomponents": "CreateMLComponents",
        "mlcompute": "MLCompute",
        "naturallanguage": "NaturalLanguage",
        "vision": "Vision",
        "visionkit": "VisionKit",
        "visualintelligence": "VisualIntelligence",
        "imagecapturecore": "ImageCaptureCore",
        "imageio": "ImageIO",
        "datadetection": "DataDetection",

        // MARK: - Game / AR
        "arkit": "ARKit",
        "gamecontroller": "GameController",
        "gamekit": "GameKit",
        "gameplaykit": "GameplayKit",
        "glkit": "GLKit",
        "groupactivities": "GroupActivities",
        "replaykit": "ReplayKit",

        // MARK: - Health / Care
        "healthkit": "HealthKit",
        "healthkitui": "HealthKitUI",
        // "carekit": separate SPM package, see knownNonExtractable.

        // MARK: - System / Configuration
        "systemconfiguration": "SystemConfiguration",
        "systemextensions": "SystemExtensions",
        "extensionfoundation": "ExtensionFoundation",
        "extensionkit": "ExtensionKit",
        "servicemanagement": "ServiceManagement",
        "managedsettings": "ManagedSettings",
        "managedsettingsui": "ManagedSettingsUI",
        "screentime": "ScreenTime",
        "familycontrols": "FamilyControls",
        "devicecheck": "DeviceCheck",
        "appintents": "AppIntents",
        "intents": "Intents",
        "intentsui": "IntentsUI",
        // "sirikit": deprecated, functionality in Intents, see knownNonExtractable.
        "activitykit": "ActivityKit",
        "backgroundtasks": "BackgroundTasks",
        "lockedcameracapture": "LockedCameraCapture",
        "screencapturekit": "ScreenCaptureKit",
        "storekit": "StoreKit",
        "applearchive": "AppleArchive",

        // MARK: - Identity / Notification / Contacts
        "contacts": "Contacts",
        "contactsui": "ContactsUI",
        "eventkit": "EventKit",
        "eventkitui": "EventKitUI",
        "identitylookup": "IdentityLookup",
        "identitylookupui": "IdentityLookupUI",
        "usernotifications": "UserNotifications",
        "usernotificationsui": "UserNotificationsUI",
        "notificationcenter": "NotificationCenter",
        "pushkit": "PushKit",
        "fileprovider": "FileProvider",
        "fileproviderui": "FileProviderUI",
        "findersync": "FinderSync",
        "social": "Social",
        "multipeerconnectivity": "MultipeerConnectivity",
        "photos": "Photos",
        "photosui": "PhotosUI",
        // "photokit" is Apple's marketing alias for the Photos framework;
        // there is no PhotoKit Swift module. The docs page exists; the
        // slug is intentionally absent so it falls into knownNonExtractable
        // routing (or you point your consumer at the `photos` corpus entry).
        "sharedwithyou": "SharedWithYou",
        "sharedwithyoucore": "SharedWithYouCore",

        // MARK: - Web / Browser
        "webkit": "WebKit",
        "browserkit": "BrowserKit",
        "browserenginecore": "BrowserEngineCore",
        "browserenginekit": "BrowserEngineKit",
        "safariservices": "SafariServices",
        "safetykit": "SafetyKit",

        // MARK: - Maps / Translation / Symbols
        "mapkit": "MapKit",
        "translation": "Translation",
        "translationuiprovider": "TranslationUIProvider",
        "symbols": "Symbols",
        "uniformtypeidentifiers": "UniformTypeIdentifiers",
        "roomplan": "RoomPlan",
        "metrickit": "MetricKit",

        // MARK: - JavaScript / Doc / Misc
        "javascriptcore": "JavaScriptCore",
        // "docc": tool not module, see knownNonExtractable.
        "accelerate": "Accelerate",
        "accessibility": "Accessibility",
        "compression": "Compression",
        "virtualization": "Virtualization",
        "workoutkit": "WorkoutKit",
        "swiftdata": "SwiftData",
        // "testing": swift-testing package, see knownNonExtractable.
        // over-coverage rationale (cupertino-symbolgraphs#5): OpenCL is the deprecated
        // Apple OpenCL framework; ships as a Swift overlay in macOS SDK still (Apple
        // hasn't removed it). cupertino's apple-docs corpus dropped the slug because
        // the docs page is gone. We keep extracting because the .swiftmodule is still
        // in the SDK; consumers reading the corpus shouldn't see a gap where the
        // overlay still exists. Will become a brew-DB entry if cupertino re-adds the
        // docs page (unlikely; Metal replaces it).
        "opencl": "OpenCL",
        "opengles": "OpenGLES",
        "opendirectory": "OpenDirectory",
        "classkit": "ClassKit",
        "classkitui": "ClassKitUI",
        // "xctest": Xcode-platform-only, see knownNonExtractable.
        "xpc": "XPC",

        // MARK: - System-level + utilities (bash-discovered, Swift-missing fill-in)
        "accounts": "Accounts",
        "automator": "Automator",
        "collaboration": "Collaboration",
        "gss": "GSS",
        "hypervisor": "Hypervisor",
        "matter": "Matter",
        "quartz": "Quartz",
        "system": "System",
        // Apple ships these modules in all-lowercase (not PascalCase):
        "dnssd": "dnssd",
        "simd": "simd",
        "vmnet": "vmnet",
        "xcselect": "xcselect",

        // MARK: - SDK drift fill-in (modules present in *.swiftmodule but
        // previously missing from this table; surfaced by the validator
        // step in cupertino-symbolgraphs-gen)
        "mediaextension": "MediaExtension",
        "permissionkit": "PermissionKit",
        // over-coverage rationale (#5): RealityFoundation is the underlying type system
        // for RealityKit; ships its own .swiftmodule in macOS+iOS+visionOS SDKs.
        // cupertino's apple-docs corpus indexes only realitykit (the higher-level API)
        // not realityfoundation (the foundation types). We extract because consumers
        // doing constraint propagation across RealityKit's generic Component types
        // bottom out in RealityFoundation; without its symbols we'd see unresolved refs.
        "realityfoundation": "RealityFoundation",
        "relevancekit": "RelevanceKit",
        // over-coverage rationale (#5): SecurityUI is the SwiftUI surface for Security
        // (e.g. SecurityUI.LocalAuthenticationButton). Ships in macOS+iOS SDKs.
        // cupertino's apple-docs corpus folds it under securityinterface / authenticationservices
        // pages without a dedicated slug. Keeping extracted; the surface is small (~30 KB)
        // but referenced by AuthenticationServices consumers.
        "securityui": "SecurityUI",
        "sensitivecontentanalysis": "SensitiveContentAnalysis",
        // over-coverage rationale (#5): StickerKit is the iMessage stickers framework
        // (iOS-only); ships its .swiftmodule. cupertino's apple-docs corpus dropped
        // the dedicated slug when Apple consolidated stickers docs under Messages.
        // We extract because the Codable surface is still public + non-trivial.
        "stickerkit": "StickerKit",
        "telephonymessagingkit": "TelephonyMessagingKit",
        "videosubscriberaccount": "VideoSubscriberAccount",
        "wifiaware": "WiFiAware",
        "ituneslibrary": "iTunesLibrary",

        // MARK: - SDK drift round 2 (macOS-side, surfaced after the
        // dual-target run on Xcode 26.5 / Swift 6.3.2 / SDK 26.4)
        "audioaccessorykit": "AudioAccessoryKit",
        "automaticassessmentconfiguration": "AutomaticAssessmentConfiguration",
        "backgroundassets": "BackgroundAssets",
        "carkey": "CarKey",
        "compositorservices": "CompositorServices",
        "cryptotokenkit": "CryptoTokenKit",
        "declaredagerange": "DeclaredAgeRange",
        "deviceactivity": "DeviceActivity",
        "devicediscoveryextension": "DeviceDiscoveryExtension",
        "dockkit": "DockKit",
        "fskit": "FSKit",
        "financekit": "FinanceKit",
        "financekitui": "FinanceKitUI",
        "foundationmodels": "FoundationModels",
        "gamesave": "GameSave",
        "geotoolbox": "GeoToolbox",
        "identitydocumentservices": "IdentityDocumentServices",
        "identitydocumentservicesui": "IdentityDocumentServicesUI",
        "imageplayground": "ImagePlayground",
        "immersivemediasupport": "ImmersiveMediaSupport",
        "lightweightcoderequirements": "LightweightCodeRequirements",
        "livecommunicationkit": "LiveCommunicationKit",
        // over-coverage rationale (#5): LiveExecutionResultsRuntime lives under
        // <sdk>/usr/lib/swift/playgrounds/ (NOT the standard module search path);
        // rescued via the `playgroundsPath(for:)` -F injection in
        // cupertino-symbolgraphs-gen/main.swift. cupertino's apple-docs corpus
        // doesn't index it (Swift Playgrounds-specific). We extract because the
        // .swiftmodule is reachable + Apple's symbolgraph-extract treats it as
        // a public framework. Removing would fire SDK validator drift on macOS.
        "liveexecutionresultsruntime": "LiveExecutionResultsRuntime",
        "localauthenticationembeddedui": "LocalAuthenticationEmbeddedUI",
        "managedappdistribution": "ManagedAppDistribution",
        "mattersupport": "MatterSupport",

        // MARK: - SDK drift round 2 (iOS-only additions)
        "accessoryliveactivities": "AccessoryLiveActivities",
        "accessorynotifications": "AccessoryNotifications",
        "accessorysetupkit": "AccessorySetupKit",
        "accessorytransportextension": "AccessoryTransportExtension",
        "adattributionkit": "AdAttributionKit",
        "alarmkit": "AlarmKit",
        "appmigrationkit": "AppMigrationKit",
        "assetslibrary": "AssetsLibrary",
        "assignables": "Assignables",
        "automateddeviceenrollment": "AutomatedDeviceEnrollment",
        "clockkit": "ClockKit",
        "contactprovider": "ContactProvider",
        "devicediscoveryui": "DeviceDiscoveryUI",
        "energykit": "EnergyKit",
        "journalingsuggestions": "JournalingSuggestions",
        "managedapp": "ManagedApp",
        // "mapkitswiftbridge": nested inside MapKit.framework, see knownNonExtractable.
        "marketplacekit": "MarketplaceKit",
        "secureelementcredential": "SecureElementCredential",
        "servicesaccountlinking": "ServicesAccountLinking",
        "wifiinfrastructure": "WiFiInfrastructure",
        "wirelessinsights": "WirelessInsights",

        // MARK: - visionOS-only (require xros SDK fallback)
        "foveatedstreaming": "FoveatedStreaming",
        // over-coverage rationale (#5): VisionEntitlementServices is a visionOS-only
        // private-ish framework for entitlement checks (passes through cupertino's
        // apple-docs corpus filter as "no dedicated docs page"). The .swiftmodule
        // ships in xros SDK; we extract because the API surface is small but referenced
        // by entitlement-aware visionOS Swift code. Removing fires xros SDK validator drift.
        "visionentitlementservices": "VisionEntitlementServices",
        "touchcontroller": "TouchController",

        // MARK: - Brew-DB completeness audit additions (real Swift modules, probed-and-verified)
        "pushtotalk": "PushToTalk",     // iOS, ~290 KB symbol graph
        "screensaver": "ScreenSaver",   // macOS-only, ~28 KB symbol graph
    ]
}
