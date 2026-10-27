import XCTest
@testable import Cortex

final class FirebaseSetupTests: XCTestCase {
    private func config(changing key: String? = nil, to value: String = "") throws -> Data {
        var fields = ["PROJECT_ID": "cortex-v1b", "BUNDLE_ID": "com.cortex.notes",
                      "GOOGLE_APP_ID": "1:123:ios:test-only", "GCM_SENDER_ID": "123", "API_KEY": "test-only-not-a-key"]
        if let key { fields[key] = value }
        return try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0)
    }

    func testAcceptsMatchingAppleConfiguration() throws {
        XCTAssertNoThrow(try FirebaseSetup.validate(config()))
    }

    func testSideloadConfigurationMustMatchItsRegisteredBuildIdentifier() throws {
        let signedID = "com.cortex.notes.TESTTEAM01"
        let data = try config(changing: "BUNDLE_ID", to: signedID)
        XCTAssertNoThrow(try FirebaseSetup.validate(data, expectedBundleID: signedID))
        XCTAssertThrowsError(try FirebaseSetup.validate(data)) {
            XCTAssertEqual($0 as? FirebaseConfigurationError, .wrongBundle)
        }
    }

    func testRejectsWrongProjectAndBundle() throws {
        XCTAssertThrowsError(try FirebaseSetup.validate(config(changing: "PROJECT_ID", to: "other-project"))) {
            XCTAssertEqual($0 as? FirebaseConfigurationError, .wrongProject)
        }
        XCTAssertThrowsError(try FirebaseSetup.validate(config(changing: "BUNDLE_ID", to: "com.cortex.monitor"))) {
            XCTAssertEqual($0 as? FirebaseConfigurationError, .wrongBundle)
        }
    }

    func testRejectsAndroidAppAndEmptyKey() throws {
        XCTAssertThrowsError(try FirebaseSetup.validate(config(changing: "GOOGLE_APP_ID", to: "1:123:android:test"))) {
            XCTAssertEqual($0 as? FirebaseConfigurationError, .invalidAppID)
        }
        XCTAssertThrowsError(try FirebaseSetup.validate(config(changing: "API_KEY", to: " "))) {
            XCTAssertEqual($0 as? FirebaseConfigurationError, .missingAPIKey)
        }
    }
}
