import Foundation

enum TranscriptFormatter {
  static func cleaned(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    if value.hasPrefix("```") && value.hasSuffix("```") {
      value = String(value.dropFirst(3).dropLast(3))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    for prefix in ["Transcript:", "Transcription:"] where value.hasPrefix(prefix) {
      value = String(value.dropFirst(prefix.count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if value.count >= 2,
      value.first == "\"",
      value.last == "\""
    {
      value = String(value.dropFirst().dropLast())
    }

    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func cleanedTranslation(_ raw: String) -> String {
    let value = cleaned(raw)
    guard let data = value.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      dictionary.count == 1,
      let entry = dictionary.first,
      let wrappedText = entry.value as? String
    else {
      return value
    }

    let normalizedKey = entry.key
      .lowercased()
      .filter(\.isLetter)
    guard ["sourcetext", "translatedtext", "translation"].contains(normalizedKey) else {
      return value
    }
    return cleaned(wrappedText)
  }

  static func textForInsertion(_ transcript: String, contextBefore: String?) -> String {
    let cleanedTranscript = cleaned(transcript)
    guard !cleanedTranscript.isEmpty,
      let last = contextBefore?.last,
      !last.isWhitespace,
      !last.isNewline,
      !"([{—–-/".contains(last),
      let first = cleanedTranscript.first,
      !".,!?;:)]}".contains(first)
    else {
      return cleanedTranscript
    }
    return " " + cleanedTranscript
  }
}
