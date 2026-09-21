import SwiftUI
import UIKit

struct NoteCaptureSheet: View {
  @ObservedObject var relay: RelayController
  let retentionDays: Int
  let showHistory: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var confirmDiscard = false
  @State private var copied = false

  private var isRecording: Bool { relay.noteCapturePhase == .recording }
  private var canDiscard: Bool { isRecording || relay.noteCapturePhase == .preparing }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          switch relay.noteCapturePhase {
          case .saved(let item):
            Label("Saved to History", systemImage: "checkmark.circle.fill")
              .font(.subheadline.weight(.medium)).foregroundStyle(.blue)
            Text(item.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
              .font(.caption).foregroundStyle(.secondary)
            Text(item.text)
              .font(.title3).lineSpacing(7).textSelection(.enabled)
              .accessibilityIdentifier("saved-note-text")
          case .failed(let message):
            Image(systemName: "waveform.badge.exclamationmark")
              .font(.largeTitle).foregroundStyle(.orange)
            Text("Your note needs attention").font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary)
          case .preparing, .recording, .processing:
            recordingHeader
            Text(relay.notePreviewText.isEmpty ? "A thought, a plan, something to remember…" : relay.notePreviewText)
              .font(.title3).lineSpacing(7)
              .foregroundStyle(relay.notePreviewText.isEmpty ? .secondary : .primary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentTransition(.opacity)
              .accessibilityIdentifier("note-live-preview")
          }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(28)
        .frame(maxWidth: .infinity)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .safeAreaInset(edge: .bottom) { bottomControls }
      .navigationTitle(relay.noteCapturePhase.isBusy ? "New Note" : "Voice Note")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if canDiscard {
            Button("Cancel", systemImage: "xmark") { confirmDiscard = true }
              .accessibilityIdentifier("cancel-note-button")
          } else {
            Button("Done", systemImage: "checkmark") { relay.dismissNoteCapture() }
              .accessibilityIdentifier("done-note-button")
          }
        }
      }
      .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
        Button("Discard Recording", role: .destructive) { relay.discardNoteCapture() }
        Button("Keep Recording", role: .cancel) {}
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(32)
    .interactiveDismissDisabled(canDiscard)
    .sensoryFeedback(.success, trigger: copied)
    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: relay.noteCapturePhase)
    .task(id: copied) {
      guard copied else { return }
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      copied = false
    }
  }

  private var recordingHeader: some View {
    VStack(spacing: 18) {
      HStack(alignment: .center, spacing: 6) {
        ForEach(0..<15, id: \.self) { index in
          let shape = 0.3 + abs(sin(Double(index) * 1.7)) * 0.7
          Capsule()
            .fill(Color.blue.opacity(isRecording ? 1 : 0.3))
            .frame(width: 5, height: 10 + (isRecording ? 72 * max(0.04, relay.audioLevel) * shape : 0))
        }
      }
      .frame(height: 96)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: relay.audioLevel)
      .accessibilityHidden(true)
      Text(isRecording ? "Go ahead, I’m listening." : relay.noteCapturePhase == .preparing ? "Getting ready…" : "Saving your words…")
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)
      if isRecording, let started = relay.activeStartedAt {
        Text(timerInterval: started...max(started, started.addingTimeInterval(RelayController.maximumDictationDuration)), countsDown: false)
          .font(.body.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
          .accessibilityLabel("Recording duration")
      } else {
        ProgressView().controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
  }

  private var bottomControls: some View {
    VStack(spacing: 14) {
      switch relay.noteCapturePhase {
      case .recording:
        Button("Finish & save", systemImage: "stop.fill") { relay.finishNoteCapture() }
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("finish-note-button")
        Text("Up to 5 minutes · Kept for \(retentionDays) days")
          .font(.caption).foregroundStyle(.secondary)
      case .saved(let item):
        Button(copied ? "Copied" : "Copy note", systemImage: copied ? "checkmark" : "doc.on.doc") {
          UIPasteboard.general.string = item.text
          copied = true
        }
        .buttonStyle(.glassProminent)
        .accessibilityIdentifier("copy-note-button")
        HStack(spacing: 28) {
          Button("View in History", action: showHistory)
          ShareLink(item: item.text) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        .font(.subheadline)
      case .failed:
        Button("Open History", systemImage: "clock", action: showHistory)
          .buttonStyle(.glassProminent)
      case .processing:
        Text("You can close this. Your note will appear in History.")
          .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
      case .preparing:
        Text("Preparing your microphone")
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .controlSize(.large)
    .buttonSizing(.flexible)
    .frame(maxWidth: 540)
    .padding(.horizontal, 28)
    .padding(.vertical, 20)
    .frame(maxWidth: .infinity)
    .background(.bar)
  }
}
