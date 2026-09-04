import Foundation
import Security

struct GeminiCredentialStore {
  private var service: String {
    "\(Bundle.main.bundleIdentifier ?? "com.example.GeminiVoiceSample").credentials"
  }
  private let account = "gemini-api-key"

  func loadAPIKey() -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
      let data = item as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      if status != errSecItemNotFound {
        NSLog("IOS_VALIDATION_FAILURE keychain credential read status=%d", status)
      }
      return ""
    }
    return value
  }

  @discardableResult
  func saveAPIKey(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    guard !trimmed.isEmpty else {
      let status = SecItemDelete(query as CFDictionary)
      if status != errSecSuccess, status != errSecItemNotFound {
        NSLog("IOS_VALIDATION_FAILURE keychain credential delete status=%d", status)
        return false
      }
      return true
    }

    let attributes: [String: Any] = [
      kSecValueData as String: Data(trimmed.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return true }
    guard updateStatus == errSecItemNotFound else {
      NSLog("IOS_VALIDATION_FAILURE keychain credential update status=%d", updateStatus)
      return false
    }

    var newItem = query
    for (key, value) in attributes {
      newItem[key] = value
    }
    let addStatus = SecItemAdd(newItem as CFDictionary, nil)
    if addStatus != errSecSuccess {
      NSLog("IOS_VALIDATION_FAILURE keychain credential add status=%d", addStatus)
      return false
    }
    return true
  }
}
