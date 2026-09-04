import AVFoundation
import Combine
import Foundation
import UIKit

extension RelayController {
  func beginDictationFromKeyboardCommand(_ envelope: RelayCommandEnvelope) {
    let storedPendingLaunch = store.pendingLaunchRequest()
    switch RelayStartAuthorizationPolicy.resolve(
      command: envelope,
      loadedPendingLaunch: pendingLaunchRequest,
      storedPendingLaunch: storedPendingLaunch
    ) {
    case .pendingLaunch(let launchRequest):
      pendingLaunchRequest = launchRequest
      guard store.claimPendingLaunchRequest(matching: launchRequest) == launchRequest else {
        markRelayActivityAndScheduleIdleShutdown()
        return
      }
      pendingLaunchRequest = nil
      isKeyboardHandoffActive = false
      requiresManualKeyboardReturn = false
      cancelAutomaticReturnToKeyboard()
    case .reject:
      pendingLaunchRequest = nil
      isKeyboardHandoffActive = false
      requiresManualKeyboardReturn = false
      cancelAutomaticReturnToKeyboard()
      markRelayActivityAndScheduleIdleShutdown()
      return
    case .warm:
      if pendingLaunchRequest != nil {
        discardPendingLaunchRequest()
      }
    }

    beginDictation(
      requestID: envelope.requestID,
      action: envelope.dictationAction
    )
  }

  func beginDictation(
    requestID: String,
    action: RelayDictationAction
  ) {
    guard status != .transcribing, activeRequestID == nil else { return }
    markRelayActivityAndSuspendIdleShutdown()

    let liveSession: GeminiLiveSpeechSession?
    if configuration.liveStreamingEnabled {
      let translationTarget = configuration.translationTarget
      let mode: GeminiLiveSpeechSession.Mode =
        action == .translate
        ? .translate(targetLanguageCode: translationTarget.code)
        : .transcribe
      let session = GeminiLiveSpeechSession(
        mode: mode,
        progressHandler: { [weak self] text in
          Task { @MainActor [weak self] in
            self?.publishLivePreview(
              text,
              requestID: requestID,
              action: action
            )
          }
        }
      )
      liveSession = session
      liveRequestID = requestID
      activeLiveSession = session
      lastLivePreviewAt = .distantPast
      let apiKey = configuration.apiKey
      liveConnectionTask = Task {
        try await session.connect(credential: .apiKey(apiKey))
      }
    } else {
      liveSession = nil
    }

    let chunkHandler: (@Sendable (Data) -> Void)?
    let streamingFailureHandler: (@Sendable (String) -> Void)?
    if let liveSession {
      chunkHandler = { data in
        liveSession.enqueueAudio(data)
      }
      streamingFailureHandler = { reason in
        Task { await liveSession.invalidateAudioStream(reason) }
      }
    } else {
      chunkHandler = nil
      streamingFailureHandler = nil
    }

    do {
      let startedAt = Date()
      try capture.beginSegment(
        requestID: requestID,
        action: action,
        translationTargetCode: configuration.translationTarget.code,
        at: startedAt,
        audioChunkHandler: chunkHandler,
        audioStreamingFailureHandler: streamingFailureHandler
      )
      activeRequestID = requestID
      activeDictationAction = action
      activeStartedAt = startedAt
      let listeningMessage: String
      if liveSession != nil {
        listeningMessage =
          action == .translate
          ? "Streaming live translation… tap again when finished"
          : "Streaming live transcription… tap the microphone again when finished"
      } else {
        listeningMessage =
          action == .translate
          ? "Listening for translation… tap again when finished"
          : "Listening… tap the microphone again when finished"
      }
      publish(
        .recording,
        message: listeningMessage,
        activeRequestID: requestID,
        activeDictationAction: action,
        recordingStartedAt: startedAt
      )

      let workItem = DispatchWorkItem { [weak self] in
        Task { @MainActor [weak self] in
          guard let self, self.activeRequestID == requestID else { return }
          self.finishDictationAndTranscribe(requestID: requestID)
        }
      }
      maximumDurationWorkItem = workItem
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Self.maximumDictationDuration,
        execute: workItem
      )
    } catch {
      cancelAutomaticReturnToKeyboard()
      cancelLiveStream(matching: requestID)
      publish(
        .error,
        message: error.localizedDescription,
        activeRequestID: requestID,
        activeDictationAction: action
      )
      markRelayActivityAndScheduleIdleShutdown()
    }
  }
}
