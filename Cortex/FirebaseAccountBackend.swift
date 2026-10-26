import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

protocol AccountBackend {
    func profile(for identity: ConsumerIdentity, startTrial: Bool) async throws -> ConsumerProfile
}

// Deliberately non-actor-isolated: Firestore can retry this transaction on its
// own worker queue. It captures immutable identity/time, never UI state.
final class FirebaseAccountBackend: AccountBackend {
    let database: Firestore
    init(database: Firestore) { self.database = database }

    func profile(for identity: ConsumerIdentity, startTrial: Bool) async throws -> ConsumerProfile {
        let email = identity.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !identity.uid.isEmpty, !email.isEmpty else { throw SessionFailure.signInRequired }
        let reference = database.collection("users").document(email)
        let now = ConsumerProfile.millisecondsNow()
        let result = try await database.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(reference)
                var fields = snapshot.data() ?? [:]
                var updates: [String: Any] = [:]
                if !snapshot.exists {
                    updates = ["name": identity.name, "email": email, "institute": "", "plan": "free", "trialStartedAt": Int64(0)]
                    fields.merge(updates) { _, new in new }
                }
                let plan = fields["plan"] as? String ?? ""
                let started = Self.milliseconds(fields["trialStartedAt"])
                if startTrial && ConsumerProfile.shouldStartTrial(plan: plan, startedAt: started) {
                    updates["plan"] = "trial"
                    updates["trialStartedAt"] = now
                    fields["plan"] = "trial"
                    fields["trialStartedAt"] = now
                }
                if !updates.isEmpty { transaction.setData(updates, forDocument: reference, merge: true) }
                return fields
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }
        guard let fields = result as? [String: Any] else { throw SessionFailure.profileUnavailable }
        return ConsumerProfile(uid: identity.uid, email: email,
            name: (fields["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? identity.name,
            institute: fields["institute"] as? String ?? "", plan: fields["plan"] as? String ?? "free",
            trialStartedAt: Self.milliseconds(fields["trialStartedAt"]))
    }

    static func milliseconds(_ raw: Any?) -> Int64 {
        if let timestamp = raw as? Timestamp { return Int64(timestamp.dateValue().timeIntervalSince1970 * 1000) }
        return (raw as? NSNumber)?.int64Value ?? 0
    }
}

enum SessionFailure: LocalizedError {
    case signInRequired, profileUnavailable, googleNotConfigured, presentationUnavailable
    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in to continue. Your saved notes are kept."
        case .profileUnavailable: return "Could not read your account. Check the connection and try again."
        case .googleNotConfigured: return "Google sign-in is not set up on this build."
        case .presentationUnavailable: return "Sign-in could not open. Please try again."
        }
    }
}
