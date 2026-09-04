import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  func startPolling() {
    pollingTimer?.invalidate()
    let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refreshFromSharedState()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    pollingTimer = timer
  }

  func persistTrackedRequest() {
    guard let activeRequestID, let activeDictationAction else { return }
    let createdAt = trackedRequestCreatedAt ?? Date()
    trackedRequestCreatedAt = createdAt
    let defaults = UserDefaults.standard
    defaults.set(activeRequestID, forKey: LocalKey.activeRequestID)
    defaults.set(activeDictationAction.rawValue, forKey: LocalKey.activeRequestAction)
    defaults.set(createdAt.timeIntervalSince1970, forKey: LocalKey.activeRequestCreatedAt)
    defaults.set(mode == .cancelling, forKey: LocalKey.activeRequestIsCancelling)
    defaults.set(activeDocumentIdentifier?.uuidString, forKey: LocalKey.activeDocumentIdentifier)
    defaults.set(
      contextBeforeFingerprintAtRequest,
      forKey: LocalKey.contextBeforeFingerprint
    )
    defaults.set(
      contextAfterFingerprintAtRequest,
      forKey: LocalKey.contextAfterFingerprint
    )
    defaults.set(
      awaitsKeyboardReactivation,
      forKey: LocalKey.awaitsKeyboardReactivation
    )
    // Build 19 briefly stored these values verbatim. Remove that legacy
    // representation as soon as the extension next persists any request.
    defaults.removeObject(forKey: LocalKey.legacyContextBefore)
    defaults.removeObject(forKey: LocalKey.legacyContextAfter)
  }

  func restoreTrackedRequest() {
    let defaults = UserDefaults.standard
    let createdAt = defaults.double(forKey: LocalKey.activeRequestCreatedAt)
    let age = Date().timeIntervalSince1970 - createdAt
    guard createdAt > 0,
      age >= -5,
      age < 10 * 60,
      let requestID = defaults.string(forKey: LocalKey.activeRequestID),
      !requestID.isEmpty,
      let actionValue = defaults.string(forKey: LocalKey.activeRequestAction),
      let action = RelayDictationAction(rawValue: actionValue)
    else {
      clearTrackedRequest()
      return
    }

    activeRequestID = requestID
    activeDictationAction = action
    trackedRequestCreatedAt = Date(timeIntervalSince1970: createdAt)
    activeDocumentIdentifier = defaults.string(forKey: LocalKey.activeDocumentIdentifier)
      .flatMap(UUID.init(uuidString:))
    contextBeforeFingerprintAtRequest = defaults.string(
      forKey: LocalKey.contextBeforeFingerprint
    )
    contextAfterFingerprintAtRequest = defaults.string(
      forKey: LocalKey.contextAfterFingerprint
    )
    awaitsKeyboardReactivation = defaults.bool(
      forKey: LocalKey.awaitsKeyboardReactivation
    )
    keyboardReactivationIsReady = false
    defaults.removeObject(forKey: LocalKey.legacyContextBefore)
    defaults.removeObject(forKey: LocalKey.legacyContextAfter)
    mode =
      defaults.bool(forKey: LocalKey.activeRequestIsCancelling)
      ? .cancelling
      : .openingHost
  }

  func clearTrackedRequest() {
    if hostResolutionPendingForRequestID == activeRequestID {
      hostResolutionGeneration += 1
      hostResolutionPendingForRequestID = nil
    }
    if hostLaunchAttemptedForRequestID == activeRequestID {
      hostLaunchAttemptedForRequestID = nil
    }
    activeRequestID = nil
    activeDictationAction = nil
    trackedRequestCreatedAt = nil
    activeDocumentIdentifier = nil
    contextBeforeFingerprintAtRequest = nil
    contextAfterFingerprintAtRequest = nil
    awaitsKeyboardReactivation = false
    keyboardReactivationIsReady = false

    let defaults = UserDefaults.standard
    [
      LocalKey.activeRequestID,
      LocalKey.activeRequestAction,
      LocalKey.activeRequestCreatedAt,
      LocalKey.activeRequestIsCancelling,
      LocalKey.activeDocumentIdentifier,
      LocalKey.contextBeforeFingerprint,
      LocalKey.contextAfterFingerprint,
      LocalKey.awaitsKeyboardReactivation,
      LocalKey.legacyContextBefore,
      LocalKey.legacyContextAfter,
    ].forEach(defaults.removeObject(forKey:))
  }
}
