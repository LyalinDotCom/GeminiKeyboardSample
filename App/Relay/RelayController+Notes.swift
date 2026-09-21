import Foundation

enum NoteCapturePhase: Equatable {
  case preparing
  case recording
  case processing
  case saved(TranscriptHistoryItem)
  case failed(String)

  var isBusy: Bool {
    switch self {
    case .preparing, .recording, .processing: true
    case .saved, .failed: false
    }
  }
}

extension RelayController {
  var canStartNoteCapture: Bool {
    configuration.hasUsableAPIKey && !status.isBusy && !isRelayStarting
      && !isProcessingImage && !isImagePickerPresented && retryingRecordingID == nil
      && !isKeyboardHandoffActive && !isNoteCapturePresented
  }

  func startNoteCapture() async {
    guard canStartNoteCapture else { return }
    let startupID = UUID()
    noteStartupID = startupID
    notePreviewText = ""
    noteCapturePhase = .preparing
    isNoteCapturePresented = true
    pendingLaunchRequest = pendingLaunchRequest ?? store.pendingLaunchRequest()
    discardPendingLaunchRequest()
    if !isRelayRunning { await startRelay() }
    guard noteStartupID == startupID, isNoteCapturePresented else { return }
    noteStartupID = nil
    guard isRelayRunning else {
      noteCapturePhase = .failed(statusMessage)
      return
    }
    beginDictation(requestID: UUID().uuidString, action: .note)
    noteCapturePhase = status == .recording ? .recording : .failed(statusMessage)
  }

  func finishNoteCapture() {
    guard activeDictationAction == .note, let activeRequestID else { return }
    finishDictationAndTranscribe(requestID: activeRequestID)
  }

  func dismissNoteCapture() {
    guard noteCapturePhase != .preparing, noteCapturePhase != .recording else { return }
    isNoteCapturePresented = false
  }

  func discardNoteCapture() {
    let wasStarting = noteStartupID != nil && isRelayStarting
    noteStartupID = nil
    isNoteCapturePresented = false
    if activeDictationAction == .note {
      cancelDictation()
    } else if wasStarting {
      stopRelay()
    }
  }

  func failNoteCapture(_ message: String) {
    guard isNoteCapturePresented, noteCapturePhase.isBusy else { return }
    noteCapturePhase = .failed(message)
  }

  /// Save first. App notes never become pending insertions in another app's keyboard.
  @discardableResult
  func completeTranscription(
    _ text: String,
    requestID: String,
    action: RelayDictationAction
  ) throws -> TranscriptHistoryItem {
    let item = try addToHistory(text)
    if action == .note {
      noteCapturePhase = .saved(item)
    } else {
      store.publishTranscript(text, requestID: requestID, kind: .dictation)
    }
    return item
  }
}
