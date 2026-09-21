import SwiftUI
import UIKit

extension ContentView {
  var keyboardHandoffOverlay: some View {
    ZStack {
      Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

      VStack(spacing: 28) {
        Spacer()

        Image(systemName: "waveform")
          .font(.system(size: 42, weight: .medium))
          .foregroundStyle(.blue)
          .frame(width: 92, height: 92)
          .glassEffect(.regular, in: .circle)

        if relay.status == .recording { handoffWaveform }

        VStack(spacing: 10) {
          Text(handoffTitle)
            .font(.largeTitle.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
          Text(handoffMessage)
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 26)
        }

        if relay.status == .idle && !relay.requiresManualKeyboardReturn {
          Text("Recording begins only after the keyboard is attached to your text field.")
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
        }

        Button {
          relay.cancelKeyboardHandoff()
        } label: {
          Label(
            relay.status == .recording ? "Cancel recording" : "Cancel handoff",
            systemImage: "xmark"
          )
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 15)
          .background(Color(uiColor: .secondarySystemGroupedBackground))
          .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28)

        Spacer()
      }
    }
    .transition(.opacity)
    .accessibilityIdentifier("keyboard-handoff-overlay")
  }

  var handoffTitle: String {
    switch relay.status {
    case .idle:
      #if GEMINI_PERSONAL_DEVICE
        return relay.requiresManualKeyboardReturn
          ? "Couldn’t return automatically"
          : "Returning to your keyboard"
      #else
        return "Relay ready"
      #endif
    case .recording:
      return "Listening"
    case .transcribing:
      return "Finishing"
    case .error:
      return "Setup needs attention"
    case .offline:
      return "Preparing microphone…"
    }
  }

  var handoffMessage: String {
    switch relay.status {
    case .idle:
      #if GEMINI_PERSONAL_DEVICE
        if relay.requiresManualKeyboardReturn {
          return "Swipe back to the app where you were typing. Recording hasn’t started."
        }
        return
          "Gemini Voice is ready. Recording will start as soon as your original text field and keyboard are active again."
      #else
        return
          "Gemini Voice is ready. Return to your original text field; recording starts when the keyboard reappears."
      #endif
    case .recording:
      return "Gemini Voice will keep listening while you use the keyboard."
    case .transcribing, .error, .offline:
      return relay.statusMessage
    }
  }

  var handoffWaveform: some View {
    HStack(alignment: .center, spacing: 7) {
      ForEach(0..<9, id: \.self) { index in
        let shape = [0.42, 0.68, 0.9, 0.62, 1.0, 0.72, 0.86, 0.58, 0.38][index]
        Capsule()
          .fill(relay.status == .recording ? Color.blue : Color.secondary.opacity(0.35))
          .frame(
            width: 7,
            height: 14 + (58 * max(0.08, relay.audioLevel) * shape)
          )
      }
    }
    .frame(height: 78)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: relay.audioLevel)
  }
}
