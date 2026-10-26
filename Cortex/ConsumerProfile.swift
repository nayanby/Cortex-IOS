import Foundation

struct ConsumerIdentity: Equatable, Sendable {
    let uid: String
    let email: String
    let name: String
}

struct ConsumerProfile: Codable, Equatable, Sendable {
    let uid: String
    let email: String
    let name: String
    let institute: String
    let plan: String
    let trialStartedAt: Int64

    static let trialDuration: Int64 = 60 * 24 * 60 * 60 * 1000
    static let deviceRestrictionsEnabled = false // Matches current Android source.

    var isBeta: Bool { email.lowercased() == "beta@cortex.notes" || plan.lowercased() == "beta" }
    var canReadLibrary: Bool { !uid.isEmpty && !email.isEmpty }
    func hasFullAccess(at now: Int64 = ConsumerProfile.millisecondsNow()) -> Bool {
        isBeta || plan.lowercased() == "full" ||
            (plan.lowercased() == "trial" && trialStartedAt > 0 && now - trialStartedAt < Self.trialDuration)
    }

    static func shouldStartTrial(plan: String, startedAt: Int64) -> Bool {
        startedAt <= 0 && ["", "free", "trial"].contains(plan.lowercased())
    }

    static func millisecondsNow() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
