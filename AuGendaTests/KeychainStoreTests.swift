import XCTest
@testable import AuGenda

final class KeychainStoreTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clean up any test keys
        KeychainStore.removeAll(for: "test-provider")
    }
    
    override func tearDown() {
        KeychainStore.removeAll(for: "test-provider")
        super.tearDown()
    }
    
    func testSetAndGet() {
        KeychainStore.set("secret-api-key", for: "test-provider")
        let retrieved = KeychainStore.get(for: "test-provider")
        XCTAssertEqual(retrieved, "secret-api-key")
    }
    
    func testRemove() {
        KeychainStore.set("temp-key", for: "test-provider")
        KeychainStore.remove(for: "test-provider")
        let retrieved = KeychainStore.get(for: "test-provider")
        XCTAssertNil(retrieved)
    }
    
    func testNonExistentKey() {
        let retrieved = KeychainStore.get(for: "non-existent-provider")
        XCTAssertNil(retrieved)
    }
    
    func testUpdateExistingKey() {
        KeychainStore.set("old-key", for: "test-provider")
        KeychainStore.set("new-key", for: "test-provider")
        let retrieved = KeychainStore.get(for: "test-provider")
        XCTAssertEqual(retrieved, "new-key")
    }
}
