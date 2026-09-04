import SwiftUI
import UIKit

extension ContentView {
  var privacyFooter: some View {
    Label(
      configuration.liveStreamingEnabled
        ? "While the relay is on, iOS shows microphone access because the audio session stays armed. After Dictate, microphone audio streams to Google Gemini; Finish inserts the result, while Cancel stops streaming and discards it. A local fallback recording is deleted after success, or kept on this iPhone for Retry after a failure."
        : "While the relay is on, iOS shows microphone access because the audio session stays armed. Only audio captured after Dictate and completed with Finish—and images you explicitly choose—are sent to Google Gemini. Failed recordings stay on this iPhone for Retry; successful recordings are deleted.",
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
    switch relay.status {
    case .offline: return "OFFLINE"
    case .idle: return "READY"
    case .recording: return "LISTENING"
    case .transcribing: return "TRANSCRIBING"
    case .error: return "CHECK SETUP"
    }
  }

  var statusColor: Color {
    switch relay.status {
    case .offline: return .gray
    case .idle: return .green
    case .recording: return .red
    case .transcribing: return .cyan
    case .error: return .orange
    }
  }
}
