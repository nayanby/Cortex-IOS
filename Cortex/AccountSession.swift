import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import UIKit

enum AccountFailurePolicy {
    static func requiresSignIn(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == "FIRAuthErrorDomain" && [17005, 17011, 17017, 17021].contains(e.code)
    }
    static func isOffline(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSURLErrorDomain { return [-1001, -1003, -1004, -1005, -1009].contains(e.code) }
        if e.domain == "FIRFirestoreErrorDomain" { return [4, 14].contains(e.code) }
        return e.domain == "FIRAuthErrorDomain" && e.code == 17020
    }
    static func message(_ error: Error) -> String {
        let e = error as NSError
        if isOffline(error) { return "Check the connection and try again." }
        if e.domain == "FIRAuthErrorDomain" {
            switch e.code {
            case 17005: return "This account has been disabled."
            case 17011, 17017, 17021: return "Sign in again to restore your session. Your saved notes are kept."
            case 17004, 17009: return "That email or password is not right."
            case 17010: return "Too many tries. Wait a moment and try again."
            default: break
            }
        }
        return error.localizedDescription
    }
}

@MainActor
final class AccountSession: ObservableObject {
    @Published private(set) var profile: ConsumerProfile?
    @Published private(set) var configurationAvailable = false
    @Published private(set) var configurationStatus: FirebaseSetup.Status = .missingConfiguration
    @Published private(set) var isRestoring = false
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?
    private var listener: AuthStateDidChangeListenerHandle?
    private var started = false
    private var revision = 0
    private let cache: ProfileCaching

    init(cache: ProfileCaching = KeychainProfileCache()) { self.cache = cache }

    func start() {
        guard !started else { return }
        started = true
        configurationStatus = FirebaseSetup.configure()
        configurationAvailable = configurationStatus == .configured
        guard configurationAvailable else { return }
        isRestoring = true
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isSigningIn else { return }
                if Auth.auth().currentUser == nil {
                    self.revision += 1
                    self.profile = nil
                    self.isRestoring = false
                } else { await self.refresh() }
            }
        }
    }

    func signInWithGoogle(presenting controller: UIViewController) async {
        guard configurationAvailable, !isSigningIn else { return }
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        guard let options = FirebaseApp.app()?.options, let clientID = options.clientID, !clientID.isEmpty,
              let callback = FirebaseSetup.googleCallbackScheme(), schemes.contains(callback) else {
            errorMessage = SessionFailure.googleNotConfigured.localizedDescription
            return
        }
        guard controller.viewIfLoaded?.window != nil else {
            errorMessage = SessionFailure.presentationUnavailable.localizedDescription
            return
        }
        revision += 1
        let operation = revision
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let google = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller)
            guard let idToken = google.user.idToken?.tokenString else { throw SessionFailure.signInRequired }
            try Task.checkCancellation()
            guard revision == operation else { return }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: google.user.accessToken.tokenString)
            let result = try await Auth.auth().signIn(with: credential)
            guard revision == operation else { return }
            try await loadProfile(user: result.user, operation: operation)
        } catch {
            guard revision == operation else { return }
            let e = error as NSError
            if !(e.domain == "com.google.GIDSignIn" && e.code == -5) {
                errorMessage = AccountFailurePolicy.message(error)
            }
        }
    }

    func refresh() async {
        guard configurationAvailable, !isSigningIn else { return }
        guard let user = Auth.auth().currentUser else { profile = nil; isRestoring = false; return }
        revision += 1
        let operation = revision
        isRestoring = true
        defer { if revision == operation { isRestoring = false } }
        do {
            do { try await user.reload() }
            catch { if !AccountFailurePolicy.isOffline(error) { throw error } }
            try await loadProfile(user: user, operation: operation)
        } catch {
            guard revision == operation else { return }
            if AccountFailurePolicy.requiresSignIn(error) {
                cache.remove(uid: user.uid)
                try? Auth.auth().signOut()
                GIDSignIn.sharedInstance.signOut()
                profile = nil
            } else if AccountFailurePolicy.isOffline(error), let saved = cache.read(uid: user.uid),
                      saved.email == user.email?.lowercased() {
                profile = saved
                errorMessage = nil
                return
            } else { profile = nil }
            errorMessage = AccountFailurePolicy.message(error)
        }
    }

    private func loadProfile(user: User, operation: Int) async throws {
        guard let email = user.email?.lowercased(), !email.isEmpty else { throw SessionFailure.signInRequired }
        let identity = ConsumerIdentity(uid: user.uid, email: email, name: user.displayName ?? "")
        let saved = try await FirebaseAccountBackend(database: Firestore.firestore()).profile(for: identity, startTrial: true)
        try Task.checkCancellation()
        guard revision == operation, Auth.auth().currentUser?.uid == identity.uid else { return }
        try cache.save(saved)
        profile = saved
        errorMessage = nil
    }

    func signOut() {
        guard configurationAvailable else { return }
        do {
            let uid = Auth.auth().currentUser?.uid
            try Auth.auth().signOut()
            revision += 1
            GIDSignIn.sharedInstance.signOut()
            if let uid { cache.remove(uid: uid) }
            profile = nil
            isRestoring = false
            errorMessage = nil
        } catch { errorMessage = AccountFailurePolicy.message(error) }
    }
}
