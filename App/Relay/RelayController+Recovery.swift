import AVFoundation
import Combine
import Foundation
import UIKit

extension RelayController {
  func clearHistory() {
    do {
      try historyStore.clear()
      history = historyStore.items
      historyError = nil
    } catch {
      historyError = error.localizedDescription
    }
  }

  func deleteHistoryItem(_ item: TranscriptHistoryItem) {
    do {
      try historyStore.remove(id: item.id)
      history = historyStore.items
      historyError = nil
    } catch {
      historyError = error.localizedDescription
    }
  }

  func applyHistoryRetention() {
    do {
      try historyStore.removeExpired(retentionDays: configuration.historyRetentionDays)
      history = historyStore.items
      historyError = nil
    } catch {
      historyError = "Couldn’t update history: \(error.localizedDescription)"
    }
  }

  func retryRecording(_ recording: RecoverableRecording) {
    guard retryingRecordingID == nil,
      status != .recording,
      status != .transcribing,
      recording.transcriptSaved != true,
      configuration.hasUsableAPIKey,
      let audioURL = recoveryStore.fileURL(for: recording)
    else { return }

    let retryRequestID = UUID().uuidString
    markRelayActivityAndSuspendIdleShutdown()
    retryingRecordingID = recording.id
    recoveryStore.markFailed(
      id: recording.id,
      message: "Retrying with Gemini…",
      incrementRetryCount: true
    )
    refreshRecoverableRecordings()
    if isRelayRunning {
      publish(
        .transcribing,
        message: "Retrying saved recording…",
        activeRequestID: retryRequestID,
        activeDictationAction: recording.action
      )
    } else {
      statusMessage = "Retrying saved recording…"
    }
    beginTranscriptionBackgroundTaskIfNeeded()

    let apiKey = configuration.apiKey
    let translationTarget = TranslationLanguage.language(
      for: recording.translationTargetCode
    )
    recoveryRetryTask = Task { [weak self] in
      guard let self else { return }
      defer {
        retryingRecordingID = nil
        recoveryRetryTask = nil
        endTranscriptionBackgroundTaskIfNeeded()
      }

      do {
        let outputText = try await fallbackResult(
          from: audioURL,
          action: recording.action,
          translationTarget: translationTarget,
          apiKey: apiKey
        )
        try Task.checkCancellation()
        try completeTranscription(outputText, requestID: retryRequestID, action: recording.action)
        do {
          try recoveryStore.remove(id: recording.id)
        } catch {
          recoveryStore.markTranscriptSaved(
            id: recording.id,
            cleanupError: "Transcript saved. Audio cleanup failed: \(error.localizedDescription)"
          )
          refreshRecoverableRecordings()
          statusMessage = error.localizedDescription
          if isRelayRunning {
            publish(.error, message: error.localizedDescription)
            markRelayActivityAndScheduleIdleShutdown()
          }
          return
        }
        refreshRecoverableRecordings()
        if isRelayRunning {
          publish(.idle, message: recording.action == .note ? "Note saved in History" : "Saved recording transcribed — ready to insert")
          markRelayActivityAndScheduleIdleShutdown()
        } else {
          statusMessage = "Saved recording transcribed"
        }
      } catch is CancellationError {
        recoveryStore.markFailed(
          id: recording.id,
          message: "Retry paused; the recording is still saved"
        )
        refreshRecoverableRecordings()
      } catch {
        recoveryStore.markFailed(
          id: recording.id,
          message: error.localizedDescription
        )
        refreshRecoverableRecordings()
        if isRelayRunning {
          publish(
            .error,
            message: RecoverableRecordingStatus.keyboardMessage(for: error),
            activeRequestID: retryRequestID,
            activeDictationAction: recording.action
          )
          markRelayActivityAndScheduleIdleShutdown()
        } else {
          statusMessage = RecoverableRecordingStatus.keyboardMessage(for: error)
        }
      }
    }
  }

  func deleteRecording(_ recording: RecoverableRecording) {
    guard retryingRecordingID != recording.id else { return }
    do {
      try recoveryStore.remove(id: recording.id)
      refreshRecoverableRecordings()
      if isRelayRunning, status == .error {
        publish(.idle, message: "Saved recording deleted — ready")
        markRelayActivityAndScheduleIdleShutdown()
      }
    } catch {
      recoveryStore.markFailed(id: recording.id, message: error.localizedDescription)
      refreshRecoverableRecordings()
      statusMessage = error.localizedDescription
      if isRelayRunning {
        publish(.error, message: error.localizedDescription)
        markRelayActivityAndScheduleIdleShutdown()
      }
    }
  }

  func refreshRecoverableRecordings() {
    recoverableRecordings = recoveryStore.recordings
  }

  @discardableResult
  func addToHistory(_ text: String) throws -> TranscriptHistoryItem {
    try historyStore.removeExpired(retentionDays: configuration.historyRetentionDays)
    let item = try historyStore.add(text: text)
    history = historyStore.items
    return item
  }
}
