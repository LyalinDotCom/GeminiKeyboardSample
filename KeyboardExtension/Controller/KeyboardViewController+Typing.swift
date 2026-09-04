import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  @objc func cancelTapped() {
    guard let activeRequestID,
      let activeDictationAction
    else { return }

    switch mode {
    case .openingHost:
      // Supersede any unhandled start command and remove a cold-launch
      // request before the containing app can send audio to Gemini.
      store.clearLaunchAuthorization(for: activeRequestID)
      store.issue(
        .cancel,
        requestID: activeRequestID,
        dictationAction: activeDictationAction
      )
      clearTrackedRequest()
      hostLaunchFailureExpiresAt = nil
      mode = .idle
    case .recording:
      store.issue(
        .cancel,
        requestID: activeRequestID,
        dictationAction: activeDictationAction
      )
      mode = .cancelling
      persistTrackedRequest()
    case .idle, .cancelling, .transcribing, .resultWaiting:
      return
    }
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    refreshFromSharedState()
  }

  @objc func insertLatestTapped() {
    guard let pendingTranscript else { return }
    insertTranscript(pendingTranscript)
    self.pendingTranscript = nil
    if let pendingResultSequence {
      markResultConsumed(sequence: pendingResultSequence)
    }
    self.pendingResultSequence = nil
    self.pendingResultKind = nil
    setInsertLatestVisible(false)
    mode = .idle
    refreshFromSharedState()
  }

  func setInsertLatestVisible(_ isVisible: Bool) {
    insertLatestButton.isHidden = !isVisible
    updateActionVisibility()
    updateKeyboardHeight()
  }

  func markResultConsumed(sequence: Int) {
    store.acknowledgeResult(sequence: sequence)
    UserDefaults.standard.set(sequence, forKey: LocalKey.consumedResultSequence)
    lastObservedResultSequence = max(lastObservedResultSequence, sequence)
  }
}
