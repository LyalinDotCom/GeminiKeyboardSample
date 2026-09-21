import Foundation

/// Cross-process credential state. Only this boolean is shared with the
/// keyboard extension; the API key remains in the app's Keychain or bundle.
enum GeminiCredentialAvailability {
  static let sharedDefaultsKey = "configuration.gemini-api-key-available"
  static let keyboardMessage = "Open Gemini Voice and add an API key"
  static let appMessage = "Add a Gemini API key in Settings to enable voice and OCR"

  static func isUsable(_ rawValue: String) -> Bool {
    let key = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return !key.isEmpty
      && key != "YOUR_GEMINI_API_KEY"
      && key != "__GEMINI_API_KEY__"
  }
}
