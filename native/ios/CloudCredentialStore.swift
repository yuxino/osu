import Foundation
import Security

enum CloudCredentialStore {
  enum Failure: Error { case unavailable, invalid }
  private static func query(_ service: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "beijing-api-key", kSecAttrSynchronizable as String: false] }
  static func isPresent(service: String = "com.yuxino.osu.alibaba") throws -> Bool {
    let query = query(service)
    var q = query; q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    var attributes: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &attributes)
    if status == errSecItemNotFound { return false }
    guard status == errSecSuccess else { DiagnosticStore.shared.record("credential", "lookup_failed", metrics: ["code": Double(status)]); throw Failure.unavailable }; return true
  }
  static func read(service: String = "com.yuxino.osu.alibaba") throws -> String? {
    let query = query(service)
    var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw Failure.unavailable }
    return value
  }
  static func isValid(_ raw: String) -> Bool {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return (8...512).contains(value.utf8.count) && value.unicodeScalars.allSatisfy { $0.value >= 33 && $0.value <= 126 }
  }
  static func save(_ raw: String, service: String = "com.yuxino.osu.alibaba") throws {
    let query = query(service)
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValid(value) else { throw Failure.invalid }
    let updates: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
    if status == errSecItemNotFound {
      let add = query.merging(updates) { _, new in new }
      guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw Failure.unavailable }
    } else if status != errSecSuccess { throw Failure.unavailable }
  }
  static func remove(service: String = "com.yuxino.osu.alibaba") throws {
    let query = query(service)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.unavailable }
  }
}
