import SwiftUI
import UIKit

extension ContentView {
  var historyScreen: some View {
    List {
      if let error = relay.historyError {
        Label(error, systemImage: "exclamationmark.circle")
          .foregroundStyle(.orange)
      }
      if !relay.recoverableRecordings.isEmpty {
        Section {
          ForEach(relay.recoverableRecordings) { recording in
            recordingRow(recording)
          }
        } header: {
          Text("Saved recordings")
        } footer: {
          Text("These clips are still on this iPhone. Retry to recover the text, or delete them.")
        }
      }
      if !relay.history.isEmpty {
        Section {
          ForEach(relay.history) { item in
            NavigationLink {
              transcriptScreen(item)
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                Text(item.text).font(.body).lineLimit(3)
                Text(item.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                  .font(.caption).foregroundStyle(.secondary)
              }
              .padding(.vertical, 8)
            }
            .contextMenu {
              Button("Copy text", systemImage: "doc.on.doc") { copyTranscript(item) }
              ShareLink(item: item.text)
            }
            .swipeActions {
              Button("Delete", role: .destructive) { relay.deleteHistoryItem(item) }
            }
          }
        } header: {
          Text("Saved text")
        } footer: {
          Text("Kept for \(configuration.historyRetentionDays) days. Change this in Settings.")
        }
      }
    }
    .overlay {
      if relay.history.isEmpty && relay.recoverableRecordings.isEmpty {
        ContentUnavailableView {
          Label("Words worth keeping", systemImage: "text.quote")
        } description: {
          Text("Record a note, then copy or share it. Your keyboard dictations and photo text appear here too.")
        } actions: {
          Button("Record a note", systemImage: "mic.badge.plus") {
            Task { await relay.startNoteCapture() }
          }
          .buttonStyle(.glassProminent)
          .disabled(!relay.canStartNoteCapture)
        }
      }
    }
    .navigationTitle("History")
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button("Record a note", systemImage: "mic.badge.plus") {
          Task { await relay.startNoteCapture() }
        }
        .disabled(!relay.canStartNoteCapture)
        .accessibilityIdentifier("history-record-note-button")
      }
      if !relay.history.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Clear history", systemImage: "trash") { isClearHistoryPresented = true }
        }
      }
    }
  }

  func transcriptScreen(_ item: TranscriptHistoryItem) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text(item.createdAt, format: .dateTime.month(.wide).day().hour().minute())
          .font(.subheadline).foregroundStyle(.secondary)
        Text(item.text)
          .font(.body).lineSpacing(6).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: 640)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationTitle("Saved Text")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button(copiedItemID == item.id ? "Copied" : "Copy text", systemImage: copiedItemID == item.id ? "checkmark" : "doc.on.doc") {
          copyTranscript(item)
        }
        .accessibilityIdentifier("copy-transcript-button")
        ShareLink(item: item.text)
      }
    }
    .sensoryFeedback(.success, trigger: copiedItemID)
    .task(id: copiedItemID) {
      guard copiedItemID != nil else { return }
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      copiedItemID = nil
    }
  }

  func copyTranscript(_ item: TranscriptHistoryItem) {
    UIPasteboard.general.string = item.text
    copiedItemID = item.id
  }

  func recordingRow(_ recording: RecoverableRecording) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(recording.actionTitle, systemImage: "waveform")
          .font(.headline)
        Spacer()
        Text(recording.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
      }
      Text(recording.lastError).font(.subheadline).foregroundStyle(.secondary)
      HStack {
        Button {
          relay.retryRecording(recording)
        } label: {
          HStack(spacing: 6) {
            if relay.retryingRecordingID == recording.id { ProgressView().controlSize(.small) }
            Label(recording.transcriptSaved == true ? "Transcript saved" : "Retry", systemImage: "arrow.clockwise")
          }
        }
        .buttonStyle(.bordered)
        .disabled(recording.transcriptSaved == true || relay.retryingRecordingID != nil || relay.status.isBusy || !configuration.hasUsableAPIKey)
        Spacer()
        Button("Delete recording", systemImage: "trash", role: .destructive) {
          recordingPendingDeletion = recording
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(relay.retryingRecordingID == recording.id)
      }
    }
    .padding(.vertical, 8)
  }
}
