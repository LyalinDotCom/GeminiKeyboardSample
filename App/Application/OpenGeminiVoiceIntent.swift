import AppIntents

struct OpenGeminiVoiceIntent: AppIntent {
  static let title: LocalizedStringResource = "Start Gemini Voice"
  static let description = IntentDescription(
    "Opens Gemini Voice and automatically arms the dictation relay."
  )
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    .result()
  }
}

struct GeminiVoiceShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenGeminiVoiceIntent(),
      phrases: [
        "Start \(.applicationName)",
        "Open \(.applicationName)",
        "Show \(.applicationName)",
      ],
      shortTitle: "Start Gemini Voice",
      systemImageName: "waveform.badge.mic"
    )
  }
}
