import XCTest
@testable import DietCloud

final class CredentialStoreTests: XCTestCase {
    func testInMemoryStoreDoesNotUseUserDefaults() throws {
        let store = InMemoryCredentialStore()
        let key = "supabase.auth.session"
        let payload = Data("not-a-real-token-payload".utf8)

        // Poison UserDefaults and ensure our store never writes there.
        let defaultsKey = "dietcloud.test.leak"
        UserDefaults.standard.set("sentinel", forKey: defaultsKey)

        try store.setData(payload, forKey: key)
        XCTAssertEqual(try store.data(forKey: key), payload)
        XCTAssertEqual(UserDefaults.standard.string(forKey: defaultsKey), "sentinel")
        XCTAssertNil(UserDefaults.standard.data(forKey: key))
        XCTAssertNil(UserDefaults.standard.object(forKey: key))

        try store.removeData(forKey: key)
        XCTAssertNil(try store.data(forKey: key))
        XCTAssertEqual(UserDefaults.standard.string(forKey: defaultsKey), "sentinel")

        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func testKeychainRoundTripAndDelete() throws {
        let store = KeychainCredentialStore(service: "app.dietcloud.DietCloud.tests.\(UUID().uuidString)")
        let key = "session-blob"
        let payload = Data("opaque-session-bytes".utf8)

        try store.setData(payload, forKey: key)
        XCTAssertEqual(try store.data(forKey: key), payload)
        XCTAssertNil(UserDefaults.standard.data(forKey: key))

        try store.removeData(forKey: key)
        XCTAssertNil(try store.data(forKey: key))
    }

    func testSupabaseAuthLocalStoragePrefixesKeys() throws {
        let memory = InMemoryCredentialStore()
        let storage = SupabaseAuthLocalStorage(store: memory, keyPrefix: "supabase.auth.")
        let value = Data([1, 2, 3, 4])
        try storage.store(key: "session", value: value)
        XCTAssertEqual(try memory.data(forKey: "supabase.auth.session"), value)
        XCTAssertEqual(try storage.retrieve(key: "session"), value)
        try storage.remove(key: "session")
        XCTAssertNil(try storage.retrieve(key: "session"))
        XCTAssertTrue(memory.storedKeys.isEmpty)
    }
}
