import SwiftUI
import UIKit

extension ContentView {
  var keyboardHandoffOverlay: some View {
    ZStack {
      LinearGradient(
        colors: [Color.black, Color(red: 0.035, green: 0.08, blue: 0.16)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 28) {
        Spacer()

        ZStack {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
              LinearGradient(
                colors: [.cyan, .blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
          Image(systemName: "waveform.badge.mic")
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(width: 92, height: 92)

        handoffWaveform

        VStack(spacing: 10) {
          Text(handoffTitle)
            .font(.system(size: 30, weight: .bold, design: .rounded))
          Text(handoffMessage)
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.68))
            .padding(.horizontal, 26)
        }

        if relay.status == .idle && !relay.requiresManualKeyboardReturn {
          Text("Recording begins only after the keyboard is attached to your text field.")
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.cyan.opacity(0.8))
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
          .background(Color.white.opacity(0.12))
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
          .fill(relay.status == .recording ? Color.cyan : Color.white.opacity(0.35))
          .frame(
            width: 7,
            height: 14 + (58 * max(0.08, relay.audioLevel) * shape)
          )
      }
    }
    .frame(height: 78)
    .animation(.easeOut(duration: 0.1), value: relay.audioLevel)
  }
}
