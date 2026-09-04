import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  func refreshFromSharedState() {
    if mode == .openingHost {
      let trackedAge =
        trackedRequestCreatedAt.map {
          Date().timeIntervalSince($0)
        } ?? .infinity
      if trackedAge > RelayLaunchRequest.defaultMaximumAge {
        if let activeRequestID {
          store.clearLaunchAuthorization(for: activeRequestID)
        }
        clearTrackedRequest()
        mode = .idle
        hostLaunchFailureExpiresAt = Date().addingTimeInterval(8)
      }
    }

    let snapshot = store.snapshot()
    observeResult(in: snapshot)
    reconcileDictationState(with: snapshot)
    issueDeferredStartIfReady(with: snapshot)
    updateActionVisibility()
    updateCancelAccessibility()
    updateRecordingPresentation(with: snapshot)
    updateProcessingPresentation(with: snapshot)

    if mode == .recording, let startedAt = snapshot.recordingStartedAt {
      let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
      timerLabel.text = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
      timerLabel.isHidden = false
    } else {
      timerLabel.isHidden = true
    }

    guard hasFullAccess else {
      setStatus("Enable Allow Full Access in Settings", color: .systemOrange)
      microphoneButton.isEnabled = false
      translateButton.isEnabled = false
      cancelButton.isEnabled = false
      return
    }

    guard snapshot.hostIsOnline(), snapshot.status != .offline else {
      if mode == .openingHost {
        if let activeRequestID,
          let activeDictationAction,
          let trackedRequestCreatedAt,
          hostLaunchAttemptedForRequestID != activeRequestID
        {
          resolveHostAndOpenContainingApp(
            requestID: activeRequestID,
            dictationAction: activeDictationAction,
            createdAt: trackedRequestCreatedAt
          )
        }
        let launchFailed = hostLaunchFailureExpiresAt.map { $0 > Date() } ?? false
        let unavailableMessage =
          snapshot.offlineReason == .unavailable
          ? snapshot.message
          : nil
        setStatus(
          unavailableMessage.map { "\($0) — × cancels" }
            ?? (launchFailed
              ? "Open Gemini Voice manually — × cancels"
              : "Opening Gemini Voice — × cancels"),
          color: unavailableMessage != nil || launchFailed ? .systemOrange : .systemCyan
        )
        configureMicrophone(
          title: "Opening…",
          image: "arrow.up.forward.app",
          color: .systemGray
        )
        configureTranslationButton(color: .systemGray)
        microphoneButton.isEnabled = false
        translateButton.isEnabled = false
        cancelButton.isEnabled = true
      } else {
        let launchFailed = hostLaunchFailureExpiresAt.map { $0 > Date() } ?? false
        let unavailableMessage: String?
        if snapshot.offlineReason == .unavailable
          || snapshot.offlineReason == .idleTimeout
        {
          unavailableMessage = snapshot.message
        } else {
          unavailableMessage = nil
        }
        setStatus(
          unavailableMessage
            ?? (launchFailed
              ? "iOS blocked the handoff — open Gemini Voice manually"
              : "Relay offline — tap Dictate to open Gemini Voice"),
          color: .systemOrange
        )
        configureMicrophone(
          title: "Open & dictate",
          image: "arrow.up.forward.app.fill",
          color: .systemBlue
        )
        configureTranslationButton()
        microphoneButton.isEnabled = true
        translateButton.isEnabled = keyboardTranslationEnabled
        cancelButton.isEnabled = false
      }
      return
    }

    switch mode {
    case .openingHost:
      setStatus("Starting dictation — × cancels", color: .systemCyan)
      configureMicrophone(title: "Starting…", image: "waveform", color: .systemGray)
      configureTranslationButton(color: .systemGray)
      microphoneButton.isEnabled = false
      translateButton.isEnabled = false
      cancelButton.isEnabled = true
    case .recording:
      let livePreview =
        snapshot.activeRequestID == activeRequestID
          && snapshot.message.hasPrefix("Live ")
        ? snapshot.message
        : nil
      if activeDictationAction == .translate {
        setStatus(livePreview ?? "Listening — Translate finishes; × discards", color: .systemRed)
        configureMicrophone(title: "Dictate", image: "mic.fill", color: .systemBlue)
        configureTranslationButton(title: "Finish", image: "arrow.up", color: .systemIndigo)
        microphoneButton.isEnabled = false
        translateButton.isEnabled = true
      } else {
        setStatus(livePreview ?? "Listening — Finish inserts; × discards", color: .systemRed)
        configureMicrophone(title: "Finish", image: "arrow.up", color: .systemBlue)
        configureTranslationButton()
        microphoneButton.isEnabled = true
        translateButton.isEnabled = false
      }
      cancelButton.isEnabled = true
    case .cancelling:
      setStatus("Stopping and discarding the result", color: .systemOrange)
      configureMicrophone(title: "Dictate", image: "mic.fill", color: .systemGray)
      configureTranslationButton(color: .systemGray)
      microphoneButton.isEnabled = false
      translateButton.isEnabled = false
      cancelButton.isEnabled = false
    case .transcribing:
      cancelButton.isEnabled = false
      if snapshot.status == .error {
        mode = .idle
        clearTrackedRequest()
        setStatus(snapshot.message, color: .systemOrange)
        configureMicrophone(title: "Try again", image: "mic.fill", color: .systemBlue)
        configureTranslationButton()
        microphoneButton.isEnabled = true
        translateButton.isEnabled = keyboardTranslationEnabled
      } else {
        setStatus(snapshot.message, color: .systemCyan)
        if activeDictationAction == .translate {
          configureMicrophone(title: "Dictate", image: "mic.fill", color: .systemBlue)
          configureTranslationButton(title: "…", image: "ellipsis", color: .systemGray)
        } else {
          configureMicrophone(title: "Transcribing", image: "ellipsis", color: .systemGray)
          configureTranslationButton()
        }
        microphoneButton.isEnabled = false
        translateButton.isEnabled = false
      }
    case .resultWaiting:
      setStatus(
        pendingResultKind == .ocr
          ? "OCR ready — tap Insert OCR"
          : "Text field changed — tap Insert latest",
        color: .systemCyan
      )
      configureMicrophone(title: "Dictate", image: "mic.fill", color: .systemBlue)
      configureTranslationButton()
      microphoneButton.isEnabled = true
      translateButton.isEnabled = keyboardTranslationEnabled
      cancelButton.isEnabled = false
    case .idle:
      setStatus(
        snapshot.status == .error ? snapshot.message : "Ready for Gemini dictation",
        color: snapshot.status == .error ? .systemOrange : .systemGreen)
      configureMicrophone(title: "Dictate", image: "mic.fill", color: .systemBlue)
      configureTranslationButton()
      microphoneButton.isEnabled = true
      translateButton.isEnabled = keyboardTranslationEnabled
      cancelButton.isEnabled = false
    }
  }

  func issueDeferredStartIfReady(with snapshot: RelaySnapshot) {
    guard keyboardReactivationIsReady,
      let activeRequestID,
      let activeDictationAction,
      let trackedRequestCreatedAt
    else {
      return
    }

    let pendingLaunchRequest = store.pendingLaunchRequest()
    guard
      RelayKeyboardStartGate.canIssueStart(
        requestID: activeRequestID,
        action: activeDictationAction,
        createdAt: trackedRequestCreatedAt,
        pendingLaunchRequest: pendingLaunchRequest,
        snapshot: snapshot,
        keyboardIsVisible: keyboardIsVisible,
        keyboardIsAttached: view.window != nil,
        startAlreadyIssued: !awaitsKeyboardReactivation
      )
    else {
      return
    }

    // The controller or UITextDocumentProxy can be recreated while the
    // containing app is foreground. Capture the insertion anchor only after
    // this returned keyboard is attached to the active text field.
    activeDocumentIdentifier = textDocumentProxy.documentIdentifier
    contextBeforeFingerprintAtRequest = Self.contextFingerprint(
      textDocumentProxy.documentContextBeforeInput
    )
    contextAfterFingerprintAtRequest = Self.contextFingerprint(
      textDocumentProxy.documentContextAfterInput
    )
    persistTrackedRequest()

    store.issue(
      .start,
      requestID: activeRequestID,
      dictationAction: activeDictationAction
    )
    awaitsKeyboardReactivation = false
    keyboardReactivationIsReady = false
    persistTrackedRequest()
  }

  func reconcileDictationState(with snapshot: RelaySnapshot) {
    guard snapshot.hostIsOnline(), snapshot.status != .offline else {
      let failureIsForTrackedRequest =
        mode == .openingHost
        && snapshot.status == .offline
        && snapshot.offlineReason == .unavailable
        && snapshot.heartbeat.map { heartbeat in
          trackedRequestCreatedAt.map { heartbeat >= $0 } ?? false
        } == true
      if failureIsForTrackedRequest {
        if let activeRequestID {
          store.clearLaunchAuthorization(for: activeRequestID)
        }
        clearTrackedRequest()
        mode = .idle
      }
      if mode == .recording || mode == .cancelling || mode == .transcribing {
        mode = .idle
        clearTrackedRequest()
      }
      return
    }

    switch snapshot.status {
    case .recording:
      guard let relayRequestID = snapshot.activeRequestID else { return }
      if mode == .openingHost,
        let activeRequestID,
        activeRequestID != relayRequestID
      {
        return
      }
      if mode == .cancelling, activeRequestID == relayRequestID {
        return
      }
      if mode == .transcribing, activeRequestID == relayRequestID {
        // A stop command is in flight; wait for the host to acknowledge
        // `.transcribing` instead of re-enabling Finish.
        return
      }
      if activeRequestID != relayRequestID {
        activeRequestID = relayRequestID
        activeDocumentIdentifier = textDocumentProxy.documentIdentifier
        contextBeforeFingerprintAtRequest = Self.contextFingerprint(
          textDocumentProxy.documentContextBeforeInput
        )
        contextAfterFingerprintAtRequest = Self.contextFingerprint(
          textDocumentProxy.documentContextAfterInput
        )
      }
      activeDictationAction = snapshot.activeDictationAction ?? .transcribe
      store.clearLaunchAuthorization(for: relayRequestID)
      persistTrackedRequest()
      mode = .recording
    case .transcribing:
      guard let relayRequestID = snapshot.activeRequestID else { return }
      if mode == .openingHost,
        let activeRequestID,
        activeRequestID != relayRequestID
      {
        return
      }
      if mode == .cancelling, activeRequestID == relayRequestID {
        return
      }
      activeRequestID = relayRequestID
      activeDictationAction = snapshot.activeDictationAction ?? activeDictationAction
      persistTrackedRequest()
      mode = .transcribing
    case .idle:
      if mode == .openingHost {
        // `.idle` can be a transient snapshot while the containing app
        // starts. Wait for a matching `.recording` acknowledgement or
        // the launch timeout instead of enabling a second request.
        return
      }
      if mode == .recording || mode == .cancelling || mode == .transcribing {
        clearTrackedRequest()
        mode = .idle
      }
    case .error:
      if mode == .openingHost,
        snapshot.activeRequestID != activeRequestID
      {
        // This is the previous request's error snapshot. The relay has
        // not acknowledged the new start command yet.
        return
      }
      if mode == .openingHost || mode == .recording || mode == .cancelling || mode == .transcribing
      {
        clearTrackedRequest()
        mode = .idle
      }
    case .offline:
      break
    }
  }

  func observeResult(in snapshot: RelaySnapshot) {
    guard snapshot.resultSequence > lastObservedResultSequence else { return }

    // A refresh task can already be queued when the keyboard disappears.
    // Leave a matching dictation result unconsumed until viewDidAppear so
    // the returned text proxy gets a fair automatic-insertion check.
    if snapshot.resultKind == .dictation,
      snapshot.resultRequestID == activeRequestID,
      !keyboardIsVisible
    {
      return
    }
    lastObservedResultSequence = snapshot.resultSequence

    guard let transcript = snapshot.transcript,
      !TranscriptFormatter.cleaned(transcript).isEmpty
    else {
      markResultConsumed(sequence: snapshot.resultSequence)
      return
    }

    let resultIsRecent =
      snapshot.resultCreatedAt.map {
        abs(Date().timeIntervalSince($0)) < 10 * 60
      } ?? false

    if snapshot.resultKind == .ocr {
      guard resultIsRecent else {
        markResultConsumed(sequence: snapshot.resultSequence)
        return
      }

      pendingTranscript = transcript
      pendingResultSequence = snapshot.resultSequence
      pendingResultKind = .ocr
      insertLatestButton.configuration?.title = "Insert OCR"
      insertLatestButton.accessibilityLabel = "Insert OCR text"
      setInsertLatestVisible(true)
      mode = .resultWaiting
      return
    }

    if mode == .cancelling,
      snapshot.resultRequestID == activeRequestID
    {
      markResultConsumed(sequence: snapshot.resultSequence)
      clearTrackedRequest()
      mode = .idle
      return
    }

    guard let activeRequestID,
      snapshot.resultRequestID == activeRequestID
    else {
      if resultIsRecent, snapshot.resultKind != .ocr {
        pendingTranscript = transcript
        pendingResultSequence = snapshot.resultSequence
        pendingResultKind = .dictation
        insertLatestButton.configuration?.title = "Insert latest"
        insertLatestButton.accessibilityLabel = "Insert the latest dictation"
        setInsertLatestVisible(true)
        mode = .resultWaiting
        return
      }
      markResultConsumed(sequence: snapshot.resultSequence)
      return
    }

    let sameDocument = textDocumentProxy.documentIdentifier == activeDocumentIdentifier
    let sameContext =
      Self.contextFingerprint(
        textDocumentProxy.documentContextBeforeInput
      ) == contextBeforeFingerprintAtRequest
      && Self.contextFingerprint(
        textDocumentProxy.documentContextAfterInput
      ) == contextAfterFingerprintAtRequest
    clearTrackedRequest()

    if keyboardIsVisible && sameDocument && sameContext {
      insertTranscript(transcript)
      markResultConsumed(sequence: snapshot.resultSequence)
      mode = .idle
    } else {
      pendingTranscript = transcript
      pendingResultSequence = snapshot.resultSequence
      pendingResultKind = .dictation
      insertLatestButton.configuration?.title = "Insert latest"
      insertLatestButton.accessibilityLabel = "Insert the latest dictation"
      setInsertLatestVisible(true)
      mode = .resultWaiting
    }
  }

  func insertTranscript(_ transcript: String) {
    let insertion = TranscriptFormatter.textForInsertion(
      transcript,
      contextBefore: textDocumentProxy.documentContextBeforeInput
    )
    guard !insertion.isEmpty else { return }
    textDocumentProxy.insertText(insertion)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  static func contextFingerprint(_ context: String?) -> String {
    var data = Data()
    data.append(context == nil ? 0 : 1)
    if let context {
      data.append(contentsOf: context.utf8)
    }
    return SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
