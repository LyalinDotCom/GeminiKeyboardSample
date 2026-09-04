import Foundation

extension GeminiLiveSpeechSession {
  static func endpoint(credential: GeminiLiveCredential) throws -> GeminiLiveEndpoint {
    guard let transport = credential.transport else {
      throw GeminiLiveSpeechError.missingCredential
    }
    guard
      var components = URLComponents(
        string:
          "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.\(credential.websocketMethod)"
      )
    else {
      throw GeminiLiveSpeechError.invalidEndpoint
    }
    var headers: [String: String] = [:]
    switch transport {
    case .header(let field, let value):
      headers[field] = value
    case .query(let queryItem):
      components.queryItems = [queryItem]
    }
    guard let url = components.url else {
      throw GeminiLiveSpeechError.invalidEndpoint
    }
    return GeminiLiveEndpoint(url: url, headers: headers)
  }

  static func setupMessage(for mode: Mode) -> [String: Any] {
    switch mode {
    case .transcribe:
      return [
        "setup": [
          "model": "models/\(transcriptionModel)",
          "generationConfig": [
            "responseModalities": ["TEXT"]
          ],
          "realtimeInputConfig": [
            "automaticActivityDetection": ["disabled": true]
          ],
          "inputAudioTranscription": [
            "languageCodes": [],
            "mode": "SMART",
          ],
        ]
      ]
    case .translate(let targetLanguageCode):
      return [
        "setup": [
          "model": "models/\(translationModel)",
          "generationConfig": [
            "responseModalities": ["AUDIO"],
            "inputAudioTranscription": [:],
            "outputAudioTranscription": [:],
            "translationConfig": [
              "targetLanguageCode": targetLanguageCode,
              "echoTargetLanguage": true,
            ],
          ],
        ]
      ]
    }
  }

  static func events(from data: Data) throws -> [ServerEvent] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw GeminiLiveSpeechError.invalidMessage
    }
    if let serviceError = root["error"] as? [String: Any] {
      let message =
        serviceError["message"] as? String
        ?? "Gemini Live returned an unknown streaming error."
      return [.serviceError(message)]
    }
    if root["setupComplete"] != nil {
      return [.setupComplete]
    }
    if root["goAway"] != nil {
      return [.serviceError("Gemini Live asked the session to close.")]
    }
    guard let content = root["serverContent"] as? [String: Any] else { return [] }

    var events: [ServerEvent] = []
    if let transcription = content["interimInputTranscription"] as? [String: Any],
      let text = transcription["text"] as? String
    {
      events.append(.interimInput(text))
    }
    if let transcription = content["inputTranscription"] as? [String: Any],
      let text = transcription["text"] as? String
    {
      events.append(.finalInput(text))
    }
    if let transcription = content["outputTranscription"] as? [String: Any],
      let text = transcription["text"] as? String
    {
      events.append(.finalOutput(text))
    }
    if content["generationComplete"] as? Bool == true {
      events.append(.generationComplete)
    }
    if content["turnComplete"] as? Bool == true {
      events.append(.turnComplete)
    }
    return events
  }

  static func mergedTranscript(existing: String, update: String) -> String {
    let current = TranscriptFormatter.cleaned(existing)
    let next = TranscriptFormatter.cleaned(update)
    guard !next.isEmpty else { return current }
    guard !current.isEmpty else { return next }
    if next == current || current.hasSuffix(next) { return current }
    if next.hasPrefix(current) { return next }
    return TranscriptFormatter.cleaned(current + " " + next)
  }

  static func activityStartMessage() -> [String: Any] {
    ["realtimeInput": ["activityStart": [:]]]
  }

  static func activityEndMessage() -> [String: Any] {
    ["realtimeInput": ["activityEnd": [:]]]
  }

  static func audioStreamEndMessage() -> [String: Any] {
    ["realtimeInput": ["audioStreamEnd": true]]
  }

  static func audioMessage(_ data: Data) -> [String: Any] {
    [
      "realtimeInput": [
        "audio": [
          "data": data.base64EncodedString(),
          "mimeType": "audio/pcm;rate=16000",
        ]
      ]
    ]
  }

  /// Uses the same -52 dB floor as the app's waveform normalization. False
  /// positives only make Live wait for another final or use the complete WAV;
  /// they cannot cause speech to be discarded.
  static func containsLikelySpeech(_ data: Data) -> Bool {
    let sampleCount = data.count / MemoryLayout<Int16>.size
    guard sampleCount > 0 else { return false }

    var sumOfSquares = 0.0
    data.withUnsafeBytes { rawBuffer in
      for sampleIndex in 0..<sampleCount {
        let byteIndex = sampleIndex * 2
        let bits =
          UInt16(rawBuffer[byteIndex])
          | (UInt16(rawBuffer[byteIndex + 1]) << 8)
        let sample = Double(Int16(bitPattern: bits)) / Double(Int16.max)
        sumOfSquares += sample * sample
      }
    }
    let rootMeanSquare = sqrt(sumOfSquares / Double(sampleCount))
    let decibels = 20 * log10(max(rootMeanSquare, 0.000_001))
    return decibels > -52
  }
}
