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

    @MainActor
    func testSharedDataStorageRoundTripsOAuthShapedPayload() throws {
        let service = "com.augenda.AuGenda.tests.oauth"
        let account = "oauth-test-provider"
        try? KeychainStore.remove(service: service, account: account)
        defer { try? KeychainStore.remove(service: service, account: account) }

        let tokens = OAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let data = try JSONEncoder().encode(tokens)

        try KeychainStore.setData(data, service: service, account: account)

        let stored = try KeychainStore.getData(service: service, account: account)
        XCTAssertNotNil(stored)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: stored ?? Data())
        XCTAssertEqual(decoded.accessToken, tokens.accessToken)
        XCTAssertEqual(decoded.refreshToken, tokens.refreshToken)
        XCTAssertEqual(decoded.expiresAt, tokens.expiresAt)
    }
}
