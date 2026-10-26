import Foundation
import Security

protocol ProfileCaching {
    func read(uid: String) -> ConsumerProfile?
    func save(_ profile: ConsumerProfile) throws
    func remove(uid: String)
}

struct KeychainProfileCache: ProfileCaching {
    private let service = "com.cortex.notes.consumer-profile"
    private func query(_ uid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: uid]
    }
    func read(uid: String) -> ConsumerProfile? {
        var request = query(uid)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let profile = try? JSONDecoder().decode(ConsumerProfile.self, from: data), profile.uid == uid else { return nil }
        return profile
    }
    func save(_ profile: ConsumerProfile) throws {
        let data = try JSONEncoder().encode(profile)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query(profile.uid) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var request = query(profile.uid)
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw CacheError.writeFailed }
        } else if status != errSecSuccess { throw CacheError.writeFailed }
    }
    func remove(uid: String) { SecItemDelete(query(uid) as CFDictionary) }
    enum CacheError: Error { case writeFailed }
}
