import Combine
import Foundation

@MainActor
final class AppConfiguration: ObservableObject {
  private enum Key {
    static let apiKeyOverride = "configuration.gemini-api-key-override"
    static let transcriptionModelOverride = "configuration.gemini-transcription-model-override"
    static let liveStreamingEnabled = "configuration.gemini-live-streaming-enabled"
    static let translationEnabled = TranslationPreferenceKey.enabled
    static let translationTargetCode = TranslationPreferenceKey.targetCode
  }

  private let defaults: UserDefaults
  private let sharedDefaults: UserDefaults
  private let credentialStore: GeminiCredentialStore
  private let embeddedAPIKey: String
  private let embeddedTranscriptionModel: String
  private let embeddedOCRModel: String
  private let embeddedTranslationModel: String

  @Published var apiKeyOverride: String {
    didSet {
      if credentialStore.saveAPIKey(apiKeyOverride) {
        defaults.removeObject(forKey: Key.apiKeyOverride)
        credentialPersistenceWarning = nil
      } else {
        credentialPersistenceWarning =
          "The credential is usable for this session but could not be saved to Keychain."
      }
      // The keyboard and Live Activity never need the API key. Remove
      // any legacy App Group copy after migrating to Keychain.
      sharedDefaults.removeObject(forKey: Key.apiKeyOverride)
      sharedDefaults.synchronize()
    }
  }

  @Published private(set) var credentialPersistenceWarning: String?

  @Published var transcriptionModelOverride: String {
    didSet {
      defaults.set(transcriptionModelOverride, forKey: Key.transcriptionModelOverride)
    }
  }

  @Published var liveStreamingEnabled: Bool {
    didSet {
      defaults.set(liveStreamingEnabled, forKey: Key.liveStreamingEnabled)
    }
  }

  @Published var translationEnabled: Bool {
    didSet {
      defaults.set(translationEnabled, forKey: Key.translationEnabled)
      sharedDefaults.set(translationEnabled, forKey: Key.translationEnabled)
      sharedDefaults.synchronize()
    }
  }

  @Published var translationTargetCode: String {
    didSet {
      let resolved = TranslationLanguage.language(for: translationTargetCode)
      if resolved.code != translationTargetCode {
        translationTargetCode = resolved.code
      }
      defaults.set(resolved.code, forKey: Key.translationTargetCode)
      sharedDefaults.set(resolved.code, forKey: Key.translationTargetCode)
      sharedDefaults.synchronize()
    }
  }

  init(
    defaults: UserDefaults = .standard,
    bundle: Bundle = .main,
    credentialStore: GeminiCredentialStore = GeminiCredentialStore()
  ) {
    let sharedDefaults = UserDefaults(suiteName: VoiceAppGroup.identifier) ?? defaults
    self.defaults = defaults
    self.sharedDefaults = sharedDefaults
    self.credentialStore = credentialStore
    self.embeddedAPIKey =
      (bundle.object(forInfoDictionaryKey: "GeminiDefaultAPIKey") as? String) ?? ""
    self.embeddedTranscriptionModel = Self.nonEmptyBundleString(
      bundle,
      key: "GeminiDefaultTranscriptionModel",
      fallback: "gemini-3.5-transcribe"
    )
    self.embeddedOCRModel = Self.nonEmptyBundleString(
      bundle,
      key: "GeminiDefaultOCRModel",
      fallback: "gemini-3.7-flash"
    )
    self.embeddedTranslationModel = Self.nonEmptyBundleString(
      bundle,
      key: "GeminiDefaultTranslationModel",
      fallback: "gemini-3.7-flash"
    )
    let legacyOverride = defaults.string(forKey: Key.apiKeyOverride) ?? ""
    let securedOverride = credentialStore.loadAPIKey()
    self.apiKeyOverride = securedOverride.isEmpty ? legacyOverride : securedOverride
    self.credentialPersistenceWarning = nil
    self.transcriptionModelOverride = defaults.string(forKey: Key.transcriptionModelOverride) ?? ""
    self.liveStreamingEnabled = defaults.object(forKey: Key.liveStreamingEnabled) as? Bool ?? true
    // Translation is a first-class keyboard action. Older builds persisted
    // false here and accidentally hid the button entirely.
    self.translationEnabled = true
    let savedTargetCode =
      defaults.string(forKey: Key.translationTargetCode)
      ?? sharedDefaults.string(forKey: Key.translationTargetCode)
      ?? TranslationLanguage.defaultLanguage.code
    self.translationTargetCode = TranslationLanguage.language(for: savedTargetCode).code

    sharedDefaults.removeObject(forKey: Key.apiKeyOverride)
    if securedOverride.isEmpty, !legacyOverride.isEmpty {
      if credentialStore.saveAPIKey(legacyOverride) {
        defaults.removeObject(forKey: Key.apiKeyOverride)
      } else {
        credentialPersistenceWarning = "The existing credential could not be moved to Keychain yet."
      }
    } else {
      defaults.removeObject(forKey: Key.apiKeyOverride)
    }
    sharedDefaults.set(self.translationEnabled, forKey: Key.translationEnabled)
    sharedDefaults.set(self.translationTargetCode, forKey: Key.translationTargetCode)
    sharedDefaults.synchronize()
  }

  var apiKey: String {
    let override = apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    return override.isEmpty ? embeddedAPIKey : override
  }

  var transcriptionModel: String {
    let override = transcriptionModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    return override.isEmpty ? embeddedTranscriptionModel : override
  }

  var liveTranscriptionModel: String {
    GeminiLiveSpeechSession.transcriptionModel
  }

  var liveTranslationModel: String {
    GeminiLiveSpeechSession.translationModel
  }

  var ocrModel: String {
    embeddedOCRModel
  }

  var translationModel: String {
    embeddedTranslationModel
  }

  var translationTarget: TranslationLanguage {
    TranslationLanguage.language(for: translationTargetCode)
  }

  var hasUsableAPIKey: Bool {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return !key.isEmpty
      && key != "YOUR_GEMINI_API_KEY"
      && key != "__GEMINI_API_KEY__"
  }

  var embeddedKeyDescription: String {
    let key = embeddedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty,
      key != "YOUR_GEMINI_API_KEY",
      key != "__GEMINI_API_KEY__"
    else {
      return "No embedded key"
    }
    return "Extractable Debug credential configured — personal-device use only"
  }

  func clearOverrides() {
    apiKeyOverride = ""
    transcriptionModelOverride = ""
  }

  private static func nonEmptyBundleString(
    _ bundle: Bundle,
    key: String,
    fallback: String
  ) -> String {
    let configured =
      (bundle.object(forInfoDictionaryKey: key) as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return configured.isEmpty ? fallback : configured
  }
}
