import SwiftUI
import UIKit

extension ContentView {
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
          Text(
            configuration.liveStreamingEnabled
              ? configuration.liveTranscriptionModel
              : configuration.transcriptionModel
          )
          .font(.caption.monospaced())
          .foregroundStyle(.white.opacity(0.5))
          .lineLimit(1)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(
            relay.isRelayRunning
              ? "Background relay is active"
              : relay.isRelayStarting
                ? "Starting the relay automatically…"
                : "Relay is off — tap below to restart"
          )
          .font(.title3.weight(.semibold))
          Text(relay.statusMessage)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.68))
            .fixedSize(horizontal: false, vertical: true)
          if relay.isRelayRunning {
            Text(
              configuration.liveStreamingEnabled
                ? "The microphone session stays armed while the relay is on. During Dictate, audio streams to Gemini and is also saved temporarily for fallback. It turns off after 2 minutes without dictation."
                : "The microphone session stays armed while the relay is on. Audio is saved only during Dictate and sent only after Finish. It turns off after 2 minutes without dictation."
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
              relay.isRelayRunning
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
            relay.isRelayRunning
              ? Color.white.opacity(0.12)
              : Color.blue
          )
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(relay.isRelayStarting)
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
