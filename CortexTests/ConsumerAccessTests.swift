import XCTest
@testable import Cortex

final class ConsumerAccessTests: XCTestCase {
    private func profile(plan: String, started: Int64 = 0) -> ConsumerProfile {
        ConsumerProfile(uid: "test-user", email: "reader@example.test", name: "Reader", institute: "", plan: plan, trialStartedAt: started)
    }
    func testTrialExpiresExactlyAtSixtyDaysButNotesRemainReadable() {
        let start: Int64 = 1_700_000_000_000
        let trial = profile(plan: "trial", started: start)
        XCTAssertTrue(trial.hasFullAccess(at: start + ConsumerProfile.trialDuration - 1))
        XCTAssertFalse(trial.hasFullAccess(at: start + ConsumerProfile.trialDuration))
        XCTAssertTrue(trial.canReadLibrary)
        XCTAssertFalse(ConsumerProfile.deviceRestrictionsEnabled)
    }
    func testTrialIsNotRestartedOrAppliedToFullAndBetaAccounts() {
        XCTAssertTrue(ConsumerProfile.shouldStartTrial(plan: "free", startedAt: 0))
        XCTAssertTrue(ConsumerProfile.shouldStartTrial(plan: "", startedAt: 0))
        XCTAssertFalse(ConsumerProfile.shouldStartTrial(plan: "trial", startedAt: 1))
        XCTAssertFalse(ConsumerProfile.shouldStartTrial(plan: "full", startedAt: 0))
        XCTAssertFalse(ConsumerProfile.shouldStartTrial(plan: "beta", startedAt: 0))
        XCTAssertFalse(ConsumerProfile.shouldStartTrial(plan: "blocked", startedAt: 0))
        XCTAssertTrue(profile(plan: "full").hasFullAccess())
        XCTAssertTrue(profile(plan: "beta").hasFullAccess())
    }
    func testOnlyNetworkFailuresPermitOfflineProfileFallback() {
        XCTAssertTrue(AccountFailurePolicy.isOffline(NSError(domain: NSURLErrorDomain, code: -1009)))
        XCTAssertTrue(AccountFailurePolicy.isOffline(NSError(domain: "FIRFirestoreErrorDomain", code: 14)))
        XCTAssertFalse(AccountFailurePolicy.isOffline(NSError(domain: "FIRFirestoreErrorDomain", code: 7)))
        XCTAssertFalse(AccountFailurePolicy.isOffline(NSError(domain: "FIRAuthErrorDomain", code: 17005)))
        XCTAssertTrue(AccountFailurePolicy.requiresSignIn(NSError(domain: "FIRAuthErrorDomain", code: 17005)))
        XCTAssertTrue(AccountFailurePolicy.requiresSignIn(NSError(domain: "FIRAuthErrorDomain", code: 17021)))
    }
    func testStoragePathsAreLimitedToLibraryWordFiles() {
        XCTAssertTrue(FirebaseLibraryBackend.validStoragePath("files/Tests/Reader.docx"))
        XCTAssertTrue(FirebaseLibraryBackend.validStoragePath("notes/Reader.docx"))
        XCTAssertFalse(FirebaseLibraryBackend.validStoragePath("user-data/other-user/Reader.docx"))
        XCTAssertFalse(FirebaseLibraryBackend.validStoragePath("files/../private.docx"))
        XCTAssertFalse(FirebaseLibraryBackend.validStoragePath("https://example.com/Reader.docx"))
    }
}
