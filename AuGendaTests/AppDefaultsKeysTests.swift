import XCTest
@testable import AuGenda

final class AppDefaultsKeysTests: XCTestCase {

    func testRemoveResettableValuesClearsEveryRegisteredKey() {
        let suiteName = "com.augenda.AuGenda.tests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for key in AppDefaultsKeys.resettable {
            defaults.set("sentinel", forKey: key)
        }

        AppDefaultsKeys.removeResettableValues(from: defaults)

        for key in AppDefaultsKeys.resettable {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should be cleared")
        }
    }
}
