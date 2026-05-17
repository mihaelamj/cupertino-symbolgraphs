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

    /// Default uppercase-first transformation. Used as the fallback
    /// when no curated entry exists. Handles single-word slugs
    /// correctly (`foundation` → `Foundation`); fails on multi-word
    /// camelcase Apple frameworks (`avfoundation` → `Avfoundation`,
    /// should be `AVFoundation`) — those need curated entries.
    static func pascalCaseFallback(_ slug: String) -> String {
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
    static let curated: [String: String] = [
        // MARK: - Foundation + Core
        "foundation": "Foundation",
        "swift": "Swift",
        "dispatch": "Dispatch",
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
        "realitycomposerpro": "RealityComposerPro",
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
        "appstoreserverapi": "AppStoreServerAPI",

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
        "carekit": "CareKit",

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
        "sirikit": "SiriKit",
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
        "photokit": "PhotoKit",
        "sharedwithyou": "SharedWithYou",
        "sharedwithyoucore": "SharedWithYouCore",

        // MARK: - Web / Browser
        "webkit": "WebKit",
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
        "docc": "DocC",
        "accelerate": "Accelerate",
        "accessibility": "Accessibility",
        "compression": "Compression",
        "virtualization": "Virtualization",
        "workoutkit": "WorkoutKit",
        "swiftdata": "SwiftData",
        "testing": "Testing",
        "opencl": "OpenCL",
        "opengles": "OpenGLES",
        "opendirectory": "OpenDirectory",
        "classkit": "ClassKit",
        "classkitui": "ClassKitUI",
        "xctest": "XCTest",
        "xpc": "XPC",
    ]
}
