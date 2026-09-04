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

  @objc func letterTapped(_ sender: UIButton) {
    guard let title = sender.configuration?.title else { return }
    playKeyFeedback()
    textDocumentProxy.insertText(title)
    let capitalizationBeforeInsertion = keyboardState.capitalization
    keyboardState.consumeCharacter()
    if keyboardState.capitalization != capitalizationBeforeInsertion {
      updateShiftAppearance()
    }
  }

  @objc func symbolTapped(_ sender: UIButton) {
    guard let text = sender.configuration?.title else { return }
    playKeyFeedback()
    textDocumentProxy.insertText(text)
  }

  @objc func spaceTapped() {
    playKeyFeedback()
    textDocumentProxy.insertText(" ")
  }

  @objc func returnTapped() {
    playKeyFeedback()
    textDocumentProxy.insertText("\n")
  }

  @objc func deleteTouchDown() {
    deleteBackwardWithFeedback()
    stopDeleteRepeat()

    let timer = Timer(timeInterval: 0.42, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.deleteButton.isHighlighted else { return }
        let repeatTimer = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in
          Task { @MainActor [weak self] in
            guard let self, self.deleteButton.isHighlighted else {
              self?.stopDeleteRepeat()
              return
            }
            self.deleteBackwardWithFeedback()
          }
        }
        RunLoop.main.add(repeatTimer, forMode: .common)
        self.deleteRepeatTimer = repeatTimer
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    deleteRepeatTimer = timer
  }

  @objc func deleteTouchEnded() {
    stopDeleteRepeat()
  }

  func deleteBackwardWithFeedback() {
    playKeyFeedback()
    textDocumentProxy.deleteBackward()
  }

  func stopDeleteRepeat() {
    deleteRepeatTimer?.invalidate()
    deleteRepeatTimer = nil
  }

  @objc func shiftTapped() {
    playKeyFeedback()
    keyboardState.tapShift(at: ProcessInfo.processInfo.systemUptime)
    updateKeyboardPage()
  }

  @objc func pageTapped() {
    playKeyFeedback()
    keyboardState.tapPage()
    updateKeyboardPage()
  }

  func updateKeyboardPage() {
    keyPreview.hide()
    let titles = keyboardState.titles
    switch keyboardState.page {
    case .letters:
      shiftButton.configuration?.title = nil
      shiftButton.configuration?.image = UIImage(systemName: "shift")
      shiftButton.accessibilityLabel = "Shift"
      pageButton.configuration?.title = "123"
      pageButton.accessibilityLabel = "Numbers and symbols"
    case .numbers:
      shiftButton.configuration?.image = nil
      shiftButton.configuration?.title = "#+="
      shiftButton.accessibilityLabel = "More symbols"
      pageButton.configuration?.title = "ABC"
      pageButton.accessibilityLabel = "Letters"
    case .symbols:
      shiftButton.configuration?.image = nil
      shiftButton.configuration?.title = "123"
      shiftButton.accessibilityLabel = "Numbers"
      pageButton.configuration?.title = "ABC"
      pageButton.accessibilityLabel = "Letters"
    }

    guard titles.count == letterButtons.count else {
      NSLog(
        "IOS_VALIDATION_FAILURE keyboard title count=%ld button count=%ld",
        titles.count,
        letterButtons.count
      )
      return
    }
    for (button, title) in zip(letterButtons, titles) {
      button.configuration?.title = title
      button.accessibilityLabel = title
    }
    updateShiftAppearance()
  }

  func updateShiftAppearance() {
    if keyboardState.page == .letters {
      for button in letterButtons {
        guard let title = button.configuration?.title else { continue }
        button.configuration?.title =
          keyboardState.usesUppercaseLetters
          ? title.uppercased()
          : title.lowercased()
      }
      let shiftSymbol =
        keyboardState.isCapsLocked
        ? "capslock.fill"
        : (keyboardState.usesUppercaseLetters ? "shift.fill" : "shift")
      shiftButton.configuration?.image = UIImage(systemName: shiftSymbol)
      shiftButton.configuration?.baseBackgroundColor =
        keyboardState.usesUppercaseLetters
        ? .systemBlue
        : Self.systemKeyBackgroundColor
      shiftButton.accessibilityValue =
        keyboardState.isCapsLocked
        ? "Caps Lock"
        : (keyboardState.usesUppercaseLetters ? "On" : "Off")
    } else {
      shiftButton.configuration?.baseBackgroundColor = Self.systemKeyBackgroundColor
      shiftButton.accessibilityValue = nil
    }
  }

  func markResultConsumed(sequence: Int) {
    store.acknowledgeResult(sequence: sequence)
    UserDefaults.standard.set(sequence, forKey: LocalKey.consumedResultSequence)
    lastObservedResultSequence = max(lastObservedResultSequence, sequence)
  }
}
