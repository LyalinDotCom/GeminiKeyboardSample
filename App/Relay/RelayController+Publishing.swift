import AVFoundation
import Combine
import Foundation
import UIKit

extension RelayController {
  func publish(
    _ status: RelayStatus,
    message: String,
    offlineReason: RelayOfflineReason? = nil,
    activeRequestID: String? = nil,
    activeDictationAction: RelayDictationAction? = nil,
    recordingStartedAt: Date? = nil
  ) {
    setLocalStatus(status, message: message)
    if status != .recording {
      audioLevel = 0
    }
    store.publishStatus(
      status,
      message: message,
      offlineReason: offlineReason,
      activeRequestID: activeRequestID,
      activeDictationAction: activeDictationAction,
      recordingStartedAt: recordingStartedAt
    )
    if isRelayRunning, let relaySessionID {
      let controlToken =
        status == .recording
        ? (activeRequestID ?? relaySessionID)
        : relaySessionID
      liveActivity.startOrUpdate(
        status: status,
        message: message,
        action: activeDictationAction,
        recordingStartedAt: recordingStartedAt,
        controlToken: controlToken,
        relaySessionID: relaySessionID
      )
    }
    if status == .idle, pendingLaunchRequest != nil {
      preparePendingLaunchHandoffIfNeeded()
    }
  }

  func publishUnavailable(message: String) {
    idleShutdownWorkItem?.cancel()
    idleShutdownWorkItem = nil
    setLocalStatus(.error, message: message)
    store.publishStatus(.offline, message: message, offlineReason: .unavailable)
    relaySessionID = nil
    liveActivity.end(message: message)
  }

  func discardPendingLaunchRequest() {
    cancelAutomaticReturnToKeyboard()
    if let pendingLaunchRequest {
      store.clearLaunchAuthorization(for: pendingLaunchRequest.requestID)
    }
    pendingLaunchRequest = nil
    isKeyboardHandoffActive = false
    requiresManualKeyboardReturn = false
    scheduleIdleShutdownIfEligible()
  }

  func setLocalStatus(_ status: RelayStatus, message: String) {
    self.status = status
    self.statusMessage = message
  }
}
