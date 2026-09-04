import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  @objc func characterTouchBegan(_ sender: KeyboardButton) {
    guard let title = sender.configuration?.title, title.count == 1 else { return }
    keyPreview.show(text: title, above: sender, in: view)
  }

  @objc func characterTouchEnded() {
    keyPreview.hide()
  }

  func playKeyFeedback() {
    UIDevice.current.playInputClick()
  }

  @objc func globeTouchDown() {
    playKeyFeedback()
  }

  @objc func microphoneTapped() {
    handleDictationTap(action: .transcribe)
  }

  @objc func translateTapped() {
    handleDictationTap(action: .translate)
  }

  func handleDictationTap(action: RelayDictationAction) {
    switch mode {
    case .recording:
      guard let activeRequestID,
        action == activeDictationAction
      else { return }
      store.issue(
        .stop,
        requestID: activeRequestID,
        dictationAction: action
      )
      mode = .transcribing
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .openingHost, .cancelling, .transcribing:
      break
    case .idle, .resultWaiting:
      guard action != .translate || keyboardTranslationEnabled else { return }
      let snapshot = store.snapshot()
      guard hasFullAccess else {
        refreshFromSharedState()
        return
      }

      let requestID = UUID().uuidString
      let requestCreatedAt = Date()
      if let pendingResultSequence {
        markResultConsumed(sequence: pendingResultSequence)
      }
      activeRequestID = requestID
      activeDictationAction = action
      trackedRequestCreatedAt = requestCreatedAt
      activeDocumentIdentifier = textDocumentProxy.documentIdentifier
      contextBeforeFingerprintAtRequest = Self.contextFingerprint(
        textDocumentProxy.documentContextBeforeInput
      )
      contextAfterFingerprintAtRequest = Self.contextFingerprint(
        textDocumentProxy.documentContextAfterInput
      )
      awaitsKeyboardReactivation = false
      keyboardReactivationIsReady = false
      pendingTranscript = nil
      pendingResultSequence = nil
      pendingResultKind = nil
      setInsertLatestVisible(false)
      persistTrackedRequest()

      if snapshot.hostIsOnline(),
        snapshot.status == .idle || snapshot.status == .error
      {
        mode = .openingHost
        store.issue(
          .start,
          requestID: requestID,
          dictationAction: action
        )
      } else {
        mode = .openingHost
        awaitsKeyboardReactivation = true
        persistTrackedRequest()
        hostLaunchFailureExpiresAt = nil
        resolveHostAndOpenContainingApp(
          requestID: requestID,
          dictationAction: action,
          createdAt: requestCreatedAt
        )
      }
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    refreshFromSharedState()
  }

  /// Capture the keyboard host before opening the containing app, then wait
  /// briefly for UIKit's keyboard arbiter to publish the source bundle for
  /// that exact PID. Unknown identity is deliberately carried as nil so the
  /// app shows the manual swipe-back guidance instead of inventing a target.
  func resolveHostAndOpenContainingApp(
    requestID: String,
    dictationAction: RelayDictationAction,
    createdAt: Date
  ) {
    guard hostLaunchAttemptedForRequestID != requestID,
      hostResolutionPendingForRequestID != requestID
    else {
      return
    }

    hostResolutionPendingForRequestID = requestID
    hostResolutionGeneration += 1
    let generation = hostResolutionGeneration

    resolveOriginatingApplicationBundleIdentifier(
      requestID: requestID,
      generation: generation
    ) { [weak self] bundleIdentifier in
      guard let self,
        self.hostResolutionGeneration == generation,
        self.hostResolutionPendingForRequestID == requestID,
        self.activeRequestID == requestID,
        self.mode == .openingHost,
        self.keyboardIsVisible,
        self.view.window != nil
      else {
        return
      }
      self.hostResolutionPendingForRequestID = nil
      self.openContainingApp(
        for: RelayLaunchRequest(
          requestID: requestID,
          dictationAction: dictationAction,
          createdAt: createdAt,
          originatingApplicationBundleIdentifier: bundleIdentifier
        )
      )
    }
  }
}
