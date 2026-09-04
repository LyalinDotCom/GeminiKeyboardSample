import AVFoundation
import Combine
import Foundation
import UIKit

extension RelayController {
  func beginPolling() {
    let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(40))
    timer.setEventHandler { [weak self] in
      Task { @MainActor [weak self] in
        self?.pollRelayStore()
      }
    }
    pollTimer = timer
    timer.resume()
  }

  func markRelayActivityAndSuspendIdleShutdown() {
    idleShutdownWorkItem?.cancel()
    idleShutdownWorkItem = nil
  }

  func markRelayActivityAndScheduleIdleShutdown() {
    markRelayActivityAndSuspendIdleShutdown()
    scheduleIdleShutdownIfEligible()
  }

  func scheduleIdleShutdownIfEligible() {
    idleShutdownWorkItem?.cancel()
    idleShutdownWorkItem = nil
    let operationIsBusy =
      status.isBusy
      || activeRequestID != nil
      || retryingRecordingID != nil
    guard
      RelayIdleShutdownPolicy.canStop(
        relayIsRunning: isRelayRunning,
        operationIsBusy: operationIsBusy,
        hasPendingHandoff: pendingLaunchRequest != nil
          || store.pendingLaunchRequest() != nil,
        hasPendingCommand: false
      )
    else { return }

    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor [weak self] in
        self?.idleShutdownDeadlineReached()
      }
    }
    idleShutdownWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + RelayIdleShutdownPolicy.timeout,
      execute: workItem
    )
  }

  func idleShutdownDeadlineReached() {
    idleShutdownWorkItem = nil
    let operationIsBusy =
      status.isBusy
      || activeRequestID != nil
      || retryingRecordingID != nil
    let hasPendingCommand = store.pendingCommand(after: lastHandledSequence) != nil
    if hasPendingCommand {
      let recheck = DispatchWorkItem { [weak self] in
        Task { @MainActor [weak self] in
          self?.idleShutdownDeadlineReached()
        }
      }
      idleShutdownWorkItem = recheck
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: recheck)
      return
    }
    guard
      RelayIdleShutdownPolicy.canStop(
        relayIsRunning: isRelayRunning,
        operationIsBusy: operationIsBusy,
        hasPendingHandoff: pendingLaunchRequest != nil
          || store.pendingLaunchRequest() != nil,
        hasPendingCommand: false
      )
    else { return }
    stopRelay(
      message: "Relay paused after 2 minutes — tap Dictate to restart",
      offlineReason: .idleTimeout
    )
  }

  func pollRelayStore() {
    heartbeatTick += 1
    if heartbeatTick >= 5 {
      store.touchHeartbeat()
      heartbeatTick = 0
    }

    guard let command = store.pendingCommand(after: lastHandledSequence) else {
      // A cold launch can arrive while an earlier request is finishing.
      // Once that work publishes idle, arm the return without requiring
      // another scene activation.
      preparePendingLaunchHandoffIfNeeded()
      return
    }

    lastHandledSequence = command.sequence
    store.markCommandHandled(sequence: command.sequence)
    handle(command)
  }

  func handle(_ envelope: RelayCommandEnvelope) {
    guard isRelayRunning else { return }
    let commandAge = Date().timeIntervalSince(envelope.createdAt)
    guard commandAge >= 0, commandAge <= 10 else { return }

    switch envelope.command {
    case .start:
      beginDictationFromKeyboardCommand(envelope)
    case .stop:
      guard activeRequestID == envelope.requestID else { return }
      scheduleFinishDictation(requestID: envelope.requestID)
    case .cancel:
      if activeRequestID == envelope.requestID {
        cancelDictation()
      } else if pendingLaunchRequest?.requestID == envelope.requestID
        || store.pendingLaunchRequest()?.requestID == envelope.requestID
      {
        discardPendingLaunchRequest()
        publish(.idle, message: "Ready — switch to the Gemini Voice keyboard")
      }
    case .cancelRecordingFromLiveActivity:
      guard status == .recording,
        activeRequestID == envelope.requestID
      else { return }
      cancelDictation()
    case .shutdownRelayFromLiveActivity:
      guard relaySessionID == envelope.requestID else { return }
      stopRelay()
    }
  }

  func preparePendingLaunchHandoffIfNeeded() {
    guard let request = pendingLaunchRequest else { return }
    guard isRelayRunning,
      status == .idle,
      activeRequestID == nil
    else {
      return
    }
    let age = Date().timeIntervalSince(request.createdAt)
    guard age >= 0,
      age <= RelayLaunchRequest.defaultMaximumAge
    else {
      discardPendingLaunchRequest()
      return
    }
    guard store.pendingLaunchRequest() == request else {
      pendingLaunchRequest = nil
      isKeyboardHandoffActive = false
      requiresManualKeyboardReturn = false
      return
    }
    isKeyboardHandoffActive = true
    // Once the bounded automatic return has been exhausted for this request,
    // the manual swipe-back guidance must stay on screen. Re-arming here on
    // every poll would clear that flag within 200 ms and loop the private
    // return attempts until the request expires. A later scene activation or
    // a new deep link resets the flag and gets a fresh bounded attempt.
    guard !requiresManualKeyboardReturn else { return }
    scheduleAutomaticReturnToKeyboard(
      requestID: request.requestID,
      originatingApplicationBundleIdentifier:
        request.originatingApplicationBundleIdentifier,
      delay: 0.35
    )
  }

  func recoverIdleStateForPendingLaunchIfNeeded() {
    guard pendingLaunchRequest != nil,
      isRelayRunning,
      activeRequestID == nil,
      status == .error
    else {
      return
    }

    // A failed prior Gemini request may leave an otherwise healthy warm
    // microphone relay displaying an error. A newly authorized keyboard
    // handoff is a fresh request, so make the relay available again before
    // scheduling the return.
    publish(.idle, message: "Ready — returning to the Gemini Voice keyboard")
  }
}
