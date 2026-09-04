import AVFoundation
import Combine
import Foundation
import UIKit

extension RelayController {
  func cancelAutomaticReturnToKeyboard() {
    returnToKeyboardWorkItem?.cancel()
    returnToKeyboardWorkItem = nil
    returnToKeyboardGeneration += 1
    pendingHostReturn = nil
    hostReturnAttemptCount = 0
    systemNavigationReturnDeadline = nil
    systemNavigationReturnAccepted = false
  }

  func cancelDictation(message: String? = nil) {
    cancelAutomaticReturnToKeyboard()
    pendingAudioRecoveryError = nil
    maximumDurationWorkItem?.cancel()
    maximumDurationWorkItem = nil
    pendingFinishWorkItem?.cancel()
    pendingFinishWorkItem = nil
    let hadLiveStream = liveRequestID == activeRequestID
    if let activeRequestID {
      cancelLiveStream(matching: activeRequestID)
    }
    capture.cancelSegment()
    audioLevel = 0
    activeRequestID = nil
    activeDictationAction = nil
    activeStartedAt = nil
    isKeyboardHandoffActive = false
    publish(
      .idle,
      message: message
        ?? (hadLiveStream
          ? "Live stream stopped and result discarded — ready"
          : "Dictation cancelled — ready")
    )
    markRelayActivityAndScheduleIdleShutdown()
  }

  func finishDictationAndTranscribe(requestID: String) {
    markRelayActivityAndSuspendIdleShutdown()
    pendingFinishWorkItem?.cancel()
    pendingFinishWorkItem = nil
    maximumDurationWorkItem?.cancel()
    maximumDurationWorkItem = nil

    let segment: CapturedAudioSegment
    let action = activeDictationAction ?? .transcribe
    let liveSession = liveRequestID == requestID ? activeLiveSession : nil
    let connectionTask = liveRequestID == requestID ? liveConnectionTask : nil
    do {
      segment = try capture.endSegment()
      audioLevel = 0
    } catch {
      cancelLiveStream(matching: requestID)
      activeRequestID = nil
      activeDictationAction = nil
      activeStartedAt = nil
      publish(
        .error,
        message: error.localizedDescription,
        activeRequestID: requestID,
        activeDictationAction: action
      )
      markRelayActivityAndScheduleIdleShutdown()
      return
    }

    activeRequestID = nil
    activeDictationAction = nil
    activeStartedAt = nil
    isKeyboardHandoffActive = false
    let processingMessage: String
    if liveSession != nil {
      processingMessage =
        action == .translate
        ? "Finalizing live translation…"
        : "Finalizing live transcript…"
    } else {
      processingMessage =
        action == .translate
        ? "Gemini is transcribing, then translating…"
        : "Gemini is transcribing…"
    }
    publish(
      .transcribing,
      message: processingMessage,
      activeRequestID: requestID,
      activeDictationAction: action
    )
    beginTranscriptionBackgroundTaskIfNeeded()

    let apiKey = configuration.apiKey
    let translationTarget = configuration.translationTarget
    let recoverableRecording: RecoverableRecording
    do {
      recoverableRecording = try recoveryStore.stage(
        segment,
        action: action,
        translationTargetCode: translationTarget.code
      )
    } catch {
      cancelLiveStream(matching: requestID)
      publish(
        .error,
        message: "Recording saved, but retry metadata failed: \(error.localizedDescription)",
        activeRequestID: requestID,
        activeDictationAction: action
      )
      markRelayActivityAndScheduleIdleShutdown()
      endTranscriptionBackgroundTaskIfNeeded()
      return
    }
    refreshRecoverableRecordings()
    transcriptionGeneration += 1
    let generation = transcriptionGeneration
    transcriptionTask?.cancel()
    transcriptionTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if generation == transcriptionGeneration {
          cancelLiveStream(matching: requestID)
          transcriptionTask = nil
          endTranscriptionBackgroundTaskIfNeeded()
        }
      }

      do {
        try Task.checkCancellation()
        let outputText: String
        let usedLiveStream: Bool
        if let liveSession, let connectionTask {
          do {
            try await connectionTask.value
            try Task.checkCancellation()
            outputText = try await liveSession.finish()
            usedLiveStream = true
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            NSLog(
              "LIVE_STREAM_FALLBACK request=%@ reason=%@",
              requestID,
              Self.safeErrorSummary(error)
            )
            outputText = try await fallbackResult(
              from: segment,
              action: action,
              translationTarget: translationTarget,
              apiKey: apiKey
            )
            usedLiveStream = false
          }
        } else {
          outputText = try await fallbackResult(
            from: segment,
            action: action,
            translationTarget: translationTarget,
            apiKey: apiKey
          )
          usedLiveStream = false
        }
        try Task.checkCancellation()
        guard generation == transcriptionGeneration, isRelayRunning else {
          recoveryStore.markFailed(
            id: recoverableRecording.id,
            message: "Processing was interrupted; the recording is still saved"
          )
          refreshRecoverableRecordings()
          return
        }

        try addToHistory(outputText)
        store.publishTranscript(
          outputText,
          requestID: requestID,
          kind: .dictation
        )
        do {
          try recoveryStore.remove(id: recoverableRecording.id)
        } catch {
          recoveryStore.markTranscriptSaved(
            id: recoverableRecording.id,
            cleanupError: "Transcript saved. Audio cleanup failed: \(error.localizedDescription)"
          )
          refreshRecoverableRecordings()
          publish(.error, message: error.localizedDescription)
          markRelayActivityAndScheduleIdleShutdown()
          return
        }
        refreshRecoverableRecordings()
        if applyPendingAudioRecoveryFailureIfNeeded() {
          return
        }
        let completionMessage: String
        if usedLiveStream {
          completionMessage =
            action == .translate
            ? "Live translation inserted — ready"
            : "Live transcript inserted — ready"
        } else {
          completionMessage =
            action == .translate
            ? "Translated to \(translationTarget.name) and inserted — ready"
            : "Inserted — ready for the next dictation"
        }
        publish(.idle, message: completionMessage)
        markRelayActivityAndScheduleIdleShutdown()
      } catch is CancellationError {
        recoveryStore.markFailed(
          id: recoverableRecording.id,
          message: "Processing paused; the recording is still saved"
        )
        refreshRecoverableRecordings()
        return
      } catch {
        recoveryStore.markFailed(
          id: recoverableRecording.id,
          message: error.localizedDescription
        )
        refreshRecoverableRecordings()
        guard generation == transcriptionGeneration, isRelayRunning else { return }
        if applyPendingAudioRecoveryFailureIfNeeded() {
          return
        }
        publish(
          .error,
          message: RecoverableRecordingStatus.keyboardMessage(for: error),
          activeRequestID: requestID,
          activeDictationAction: action
        )
        markRelayActivityAndScheduleIdleShutdown()
      }
    }
  }

  func fallbackResult(
    from segment: CapturedAudioSegment,
    action: RelayDictationAction,
    translationTarget: TranslationLanguage,
    apiKey: String
  ) async throws -> String {
    try Task.checkCancellation()
    return try await fallbackResult(
      from: segment.url,
      action: action,
      translationTarget: translationTarget,
      apiKey: apiKey
    )
  }

  func fallbackResult(
    from segmentURL: URL,
    action: RelayDictationAction,
    translationTarget: TranslationLanguage,
    apiKey: String
  ) async throws -> String {
    try Task.checkCancellation()
    let audioData = try await Task.detached(priority: .userInitiated) {
      try Data(contentsOf: segmentURL)
    }.value
    try Task.checkCancellation()
    let sourceText = try await client.transcribe(
      audioData: audioData,
      apiKey: apiKey,
      model: configuration.transcriptionModel
    )
    guard action == .translate else { return sourceText }
    return try await client.translate(
      text: sourceText,
      targetLanguage: translationTarget,
      apiKey: apiKey,
      model: configuration.translationModel
    )
  }

  func publishLivePreview(
    _ text: String,
    requestID: String,
    action: RelayDictationAction
  ) {
    guard status == .recording, activeRequestID == requestID else { return }
    let now = Date()
    guard now.timeIntervalSince(lastLivePreviewAt) >= 0.35 else { return }
    let cleaned = TranscriptFormatter.cleaned(text)
    guard !cleaned.isEmpty else { return }
    lastLivePreviewAt = now

    let preview = String(cleaned.prefix(100))
    let label = action == .translate ? "Live translation" : "Live transcript"
    let message = "\(label): \(preview)"
    setLocalStatus(.recording, message: message)
    store.publishStatus(
      .recording,
      message: message,
      activeRequestID: requestID,
      activeDictationAction: action,
      recordingStartedAt: activeStartedAt
    )
  }

  func cancelLiveStream(matching requestID: String? = nil) {
    if let requestID, liveRequestID != requestID { return }
    liveConnectionTask?.cancel()
    liveConnectionTask = nil
    if let activeLiveSession {
      Task { await activeLiveSession.cancel() }
    }
    activeLiveSession = nil
    liveRequestID = nil
  }

  static func safeErrorSummary(_ error: Error) -> String {
    switch error {
    case let liveError as GeminiLiveSpeechError:
      return liveError.localizedDescription
    default:
      return "stream connection failed"
    }
  }
}
