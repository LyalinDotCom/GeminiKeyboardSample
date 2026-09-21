import SwiftUI
import UIKit

extension ContentView {
  var languagePicker: some View {
    Picker("Output language", selection: $configuration.translationTargetCode) {
      ForEach(TranslationLanguage.supported) { language in
        Text(language.name).tag(language.code)
      }
    }
    .pickerStyle(.menu)
    .accessibilityIdentifier("translation-language-picker")
  }

  func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  var statusTitle: String {
    if !configuration.hasUsableAPIKey { return "Setup needed" }
    if relay.isRelayStarting { return "Connecting" }
    switch relay.status {
    case .offline: return "Relay is paused"
    case .idle: return relay.isRelayRunning ? "Relay is on" : "Relay is paused"
    case .recording: return "Listening"
    case .transcribing: return "Finishing up"
    case .error: return "Needs attention"
    }
  }

  var statusSymbol: String {
    if !configuration.hasUsableAPIKey { return "key" }
    if relay.isRelayStarting { return "circle.dotted" }
    switch relay.status {
    case .idle where relay.isRelayRunning: return "checkmark.circle.fill"
    case .recording: return "mic.fill"
    case .transcribing: return "ellipsis.circle"
    case .error: return "exclamationmark.circle"
    default: return "pause.circle"
    }
  }

  var statusColor: Color {
    if !configuration.hasUsableAPIKey { return .secondary }
    switch relay.status {
    case .idle where relay.isRelayRunning: return .blue
    case .recording, .transcribing: return .blue
    case .error: return .orange
    default: return .secondary
    }
  }
}
