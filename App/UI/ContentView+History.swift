import SwiftUI
import UIKit

extension ContentView {
  @ViewBuilder
  var savedRecordingsCard: some View {
    if !relay.recoverableRecordings.isEmpty {
      card {
        VStack(alignment: .leading, spacing: 12) {
          Label("Saved recordings", systemImage: "waveform.badge.exclamationmark")
            .font(.headline)

          Text(
            "These clips did not finish transcribing. They stay on this iPhone until Retry succeeds or you delete them."
          )
          .font(.caption)
          .foregroundStyle(.white.opacity(0.58))
          .fixedSize(horizontal: false, vertical: true)

          ForEach(relay.recoverableRecordings) { recording in
            VStack(alignment: .leading, spacing: 9) {
              HStack {
                Text(recording.actionTitle)
                  .font(.subheadline.weight(.semibold))
                Spacer()
                Text(recording.createdAt, style: .relative)
                  .font(.caption)
                  .foregroundStyle(.white.opacity(0.48))
              }

              Text(recording.lastError)
                .font(.caption)
                .foregroundStyle(.orange.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

              HStack(spacing: 10) {
                Button {
                  relay.retryRecording(recording)
                } label: {
                  HStack(spacing: 7) {
                    if relay.retryingRecordingID == recording.id {
                      ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    } else {
                      Image(systemName: "arrow.clockwise")
                    }
                    Text(
                      recording.transcriptSaved == true
                        ? "Transcript saved"
                        : relay.retryingRecordingID == recording.id ? "Retrying…" : "Retry")
                  }
                  .frame(maxWidth: .infinity)
                }
                .buttonStyle(OCRButtonStyle(color: .blue))
                .disabled(
                  recording.transcriptSaved == true
                    || relay.retryingRecordingID != nil
                    || relay.status.isBusy)

                Button(role: .destructive) {
                  recordingPendingDeletion = recording
                } label: {
                  Image(systemName: "trash")
                    .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .disabled(relay.retryingRecordingID == recording.id)
                .accessibilityLabel("Delete saved recording")
              }
            }
            .padding(12)
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
        }
      }
    }
  }

  @ViewBuilder
  var recentCard: some View {
    if !relay.history.isEmpty {
      card {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Label("Recent results", systemImage: "text.quote")
              .font(.headline)
            Spacer()
            Button("Clear") { relay.clearHistory() }
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white.opacity(0.58))
          }

          ForEach(relay.history.prefix(3)) { item in
            Text(item.text)
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.8))
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(12)
              .background(Color.black.opacity(0.18))
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .textSelection(.enabled)
          }
        }
      }
    }
  }
}
