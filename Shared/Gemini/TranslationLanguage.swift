import Foundation

enum TranslationPreferenceKey {
  static let enabled = "configuration.translation-enabled"
  static let targetCode = "configuration.translation-target-code"
}

struct TranslationLanguage: Identifiable, Hashable {
  let code: String
  let name: String

  var id: String { code }

  static let defaultLanguage = language(for: "en")

  static func language(for code: String) -> TranslationLanguage {
    supported.first(where: { $0.code == code })
      ?? TranslationLanguage(code: "en", name: "English")
  }

  // Exact output-language choices documented for Gemini 3.5 Live Translate.
  static let supported: [TranslationLanguage] = [
    .init(code: "en", name: "English"),
    .init(code: "es", name: "Spanish"),
    .init(code: "fr", name: "French"),
    .init(code: "de", name: "German"),
    .init(code: "it", name: "Italian"),
    .init(code: "pt-BR", name: "Portuguese (Brazil)"),
    .init(code: "pt-PT", name: "Portuguese (Portugal)"),
    .init(code: "ru", name: "Russian"),
    .init(code: "uk", name: "Ukrainian"),
    .init(code: "pl", name: "Polish"),
    .init(code: "zh-Hans", name: "Chinese (Simplified)"),
    .init(code: "zh-Hant", name: "Chinese (Traditional)"),
    .init(code: "ja", name: "Japanese"),
    .init(code: "ko", name: "Korean"),
    .init(code: "hi", name: "Hindi"),
    .init(code: "ar", name: "Arabic"),
    .init(code: "he", name: "Hebrew"),
    .init(code: "tr", name: "Turkish"),
    .init(code: "nl", name: "Dutch"),
    .init(code: "sv", name: "Swedish"),
    .init(code: "nb", name: "Norwegian"),
    .init(code: "da", name: "Danish"),
    .init(code: "fi", name: "Finnish"),
    .init(code: "cs", name: "Czech"),
    .init(code: "ro", name: "Romanian"),
    .init(code: "bg", name: "Bulgarian"),
    .init(code: "el", name: "Greek"),
    .init(code: "hu", name: "Hungarian"),
    .init(code: "sk", name: "Slovak"),
    .init(code: "sl", name: "Slovenian"),
    .init(code: "hr", name: "Croatian"),
    .init(code: "sr", name: "Serbian"),
    .init(code: "mk", name: "Macedonian"),
    .init(code: "sq", name: "Albanian"),
    .init(code: "et", name: "Estonian"),
    .init(code: "lv", name: "Latvian"),
    .init(code: "lt", name: "Lithuanian"),
    .init(code: "is", name: "Icelandic"),
    .init(code: "ca", name: "Catalan"),
    .init(code: "gl", name: "Galician"),
    .init(code: "eu", name: "Basque"),
    .init(code: "af", name: "Afrikaans"),
    .init(code: "ak", name: "Akan"),
    .init(code: "sw", name: "Swahili"),
    .init(code: "zu", name: "Zulu"),
    .init(code: "rw", name: "Kinyarwanda"),
    .init(code: "id", name: "Indonesian"),
    .init(code: "ms", name: "Malay"),
    .init(code: "fil", name: "Filipino"),
    .init(code: "vi", name: "Vietnamese"),
    .init(code: "th", name: "Thai"),
    .init(code: "bn", name: "Bengali"),
    .init(code: "pa", name: "Punjabi"),
    .init(code: "gu", name: "Gujarati"),
    .init(code: "mr", name: "Marathi"),
    .init(code: "ta", name: "Tamil"),
    .init(code: "te", name: "Telugu"),
    .init(code: "kn", name: "Kannada"),
    .init(code: "ml", name: "Malayalam"),
    .init(code: "sd", name: "Sindhi"),
    .init(code: "si", name: "Sinhala"),
    .init(code: "ne", name: "Nepali"),
    .init(code: "fa", name: "Persian"),
    .init(code: "ur", name: "Urdu"),
    .init(code: "hy", name: "Armenian"),
    .init(code: "ka", name: "Georgian"),
    .init(code: "az", name: "Azerbaijani"),
    .init(code: "kk", name: "Kazakh"),
    .init(code: "uz", name: "Uzbek"),
    .init(code: "mn", name: "Mongolian"),
    .init(code: "my", name: "Burmese (Myanmar)"),
    .init(code: "km", name: "Khmer"),
    .init(code: "lo", name: "Lao"),
    .init(code: "jv", name: "Javanese"),
    .init(code: "su", name: "Sundanese"),
    .init(code: "am", name: "Amharic"),
    .init(code: "ha", name: "Hausa"),
  ]
}
