import FirebaseCore
import FirebaseAppCheck
import DeviceCheck
import UIKit

enum FirebaseConfigurationError: Error, Equatable {
    case invalidPropertyList
    case wrongProject
    case wrongBundle
    case invalidAppID
    case missingAPIKey
}

enum FirebaseSetup {
    static let projectID = "cortex-v1b"
    static let bundleID = "com.cortex.notes"

    static func googleCallbackScheme(bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let fields = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return fields["REVERSED_CLIENT_ID"] as? String
    }

    // Validate before invoking the SDK: an accidental Android or other-project
    // configuration must never initialize the consumer app against that backend.
    static func validate(_ data: Data) throws {
        guard let fields = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw FirebaseConfigurationError.invalidPropertyList
        }
        guard fields["PROJECT_ID"] as? String == projectID else { throw FirebaseConfigurationError.wrongProject }
        guard fields["BUNDLE_ID"] as? String == bundleID else { throw FirebaseConfigurationError.wrongBundle }
        guard let appID = fields["GOOGLE_APP_ID"] as? String,
              appID.hasPrefix("1:"), appID.contains(":ios:"),
              let sender = fields["GCM_SENDER_ID"] as? String,
              appID.hasPrefix("1:\(sender):ios:") else { throw FirebaseConfigurationError.invalidAppID }
        guard let key = fields["API_KEY"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FirebaseConfigurationError.missingAPIKey
        }
    }

    enum Status: Equatable {
        case missingConfiguration
        case configured
        case rejectedConfiguration
    }

    @MainActor
    static func configure(bundle: Bundle = .main) -> Status {
        #if DEBUG
        // Scheme-driven emulator tests create their own named demo app. Never
        // initialize the production app from a private CI config during tests.
        if ProcessInfo.processInfo.environment["CORTEX_TEST_EMULATORS"] == "1" { return .missingConfiguration }
        #endif
        if FirebaseApp.app() != nil { return .configured }
        guard let file = bundle.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            // The offline reader also runs in unsigned CI builds without live config.
            return .missingConfiguration
        }
        do {
            try validate(Data(contentsOf: file))
            guard let options = FirebaseOptions(contentsOfFile: file.path),
                  options.bundleID == Bundle.main.bundleIdentifier else { return .rejectedConfiguration }
            #if DEBUG && targetEnvironment(simulator)
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
            #else
            AppCheck.setAppCheckProviderFactory(CortexAttestationFactory())
            #endif
            FirebaseApp.configure(options: options)
            return .configured
        } catch { return .rejectedConfiguration }
    }
}

private final class CortexAttestationFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if DCAppAttestService.shared.isSupported { return AppAttestProvider(app: app) }
        return DeviceCheckProvider(app: app)
    }
}

final class CortexAppDelegate: NSObject, UIApplicationDelegate {
    private(set) var firebaseStatus: FirebaseSetup.Status = .missingConfiguration

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        firebaseStatus = FirebaseSetup.configure()
        return true
    }
}
