import SwiftUI
import UIKit

extension ContentView {
  var privacyFooter: some View {
    Label(
      "While the relay is on, iOS shows microphone access because the audio session stays armed. After Dictate or Translate, microphone audio streams to Google Gemini Live; Finish inserts the result, while Cancel stops streaming and discards it. A local fallback recording is deleted after success, or kept on this iPhone for Retry after a failure.",
      systemImage: "lock.shield"
    )
    .font(.caption)
    .foregroundStyle(.white.opacity(0.48))
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 6)
  }

  func instruction(_ number: Int, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 11) {
      Text("\(number)")
        .font(.caption.bold())
        .frame(width: 24, height: 24)
        .background(Color.white.opacity(0.1))
        .clipShape(Circle())
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.74))
        .padding(.top, 2)
      Spacer(minLength: 0)
    }
  }

  func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.ultraThinMaterial.opacity(0.78))
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      }
  }

  var statusTitle: String {
    if !configuration.hasUsableAPIKey { return "KEY REQUIRED" }
    switch relay.status {
    case .offline: return "OFFLINE"
    case .idle: return "READY"
    case .recording: return "LISTENING"
    case .transcribing: return "TRANSCRIBING"
    case .error: return "CHECK SETUP"
    }
  }

  var statusColor: Color {
    if !configuration.hasUsableAPIKey { return .orange }
    switch relay.status {
    case .offline: return .gray
    case .idle: return .green
    case .recording: return .red
    case .transcribing: return .cyan
    case .error: return .orange
    }
  }
}
