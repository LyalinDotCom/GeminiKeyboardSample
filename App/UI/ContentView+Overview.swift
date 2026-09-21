import SwiftUI
import UIKit

extension ContentView {
  var apiKeyRequiredCard: some View {
    card {
      VStack(alignment: .leading, spacing: 10) {
        Label("Gemini API key required", systemImage: "key.fill")
          .font(.headline)
          .foregroundStyle(.orange)
        Text(
          "Add your Gemini API key below. Voice dictation, live translation, OCR, and saved-recording retries stay disabled until a key is configured."
        )
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.72))
        .fixedSize(horizontal: false, vertical: true)
        Button("Open API key settings") {
          settingsExpanded = true
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.cyan)
      }
    }
    .accessibilityIdentifier("api-key-required-card")
  }

  var header: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(
            LinearGradient(
              colors: [.cyan, .blue, .purple],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        Image(systemName: "waveform.badge.mic")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: 62, height: 62)

      VStack(alignment: .leading, spacing: 4) {
        Text("Gemini Voice")
          .font(.system(size: 28, weight: .bold, design: .rounded))
        Text("Dictation for every text field")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.64))
      }
      Spacer()
    }
    .accessibilityElement(children: .combine)
  }

  var relayCard: some View {
    card {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          statusPill
          Spacer()
          Text(configuration.liveTranscriptionModel)
          .font(.caption.monospaced())
          .foregroundStyle(.white.opacity(0.5))
          .lineLimit(1)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(
            !configuration.hasUsableAPIKey
              ? "Add an API key to continue"
              : relay.isRelayRunning
              ? "Background relay is active"
              : relay.isRelayStarting
                ? "Starting the relay automatically…"
                : "Relay is off — tap below to restart"
          )
          .font(.title3.weight(.semibold))
          Text(
            configuration.hasUsableAPIKey
              ? relay.statusMessage
              : GeminiCredentialAvailability.appMessage
          )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.68))
            .fixedSize(horizontal: false, vertical: true)
          if relay.isRelayRunning {
            Text(
              "The microphone session stays armed while the relay is on. During Dictate or Translate, audio streams to Gemini Live and is also saved temporarily for fallback. It turns off after 2 minutes without dictation."
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
          }
        }

        Button {
          if relay.isRelayRunning {
            relay.stopRelay()
          } else {
            Task { await relay.startRelay() }
          }
        } label: {
          HStack(spacing: 10) {
            Image(systemName: relay.isRelayRunning ? "stop.fill" : "mic.fill")
            Text(
              !configuration.hasUsableAPIKey
                ? "API Key Required"
                : relay.isRelayRunning
                ? "Stop Until Next Open"
                : relay.isRelayStarting
                  ? "Starting Relay…"
                  : "Start Relay Now"
            )
            .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 15)
          .background(
            !configuration.hasUsableAPIKey
              ? Color.gray.opacity(0.45)
              : relay.isRelayRunning
              ? Color.white.opacity(0.12)
              : Color.blue
          )
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(relay.isRelayStarting || !configuration.hasUsableAPIKey)
        .opacity(configuration.hasUsableAPIKey ? 1 : 0.64)
        .accessibilityIdentifier("relay-control-button")
      }
    }
  }

  var statusPill: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
      Text(statusTitle)
        .font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(statusColor.opacity(0.14))
    .clipShape(Capsule())
  }
}
