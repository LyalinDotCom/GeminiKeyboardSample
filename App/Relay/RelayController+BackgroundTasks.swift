import AVFoundation
import Combine
import Foundation
import UIKit

extension RelayController {
  func scheduleFinishDictation(requestID: String) {
    guard pendingFinishWorkItem == nil,
      status == .recording,
      activeRequestID == requestID
    else { return }

    // Give a nearly simultaneous keyboard/Live Activity cancellation one
    // polling turn to supersede Finish before any network task can exist.
    maximumDurationWorkItem?.cancel()
    maximumDurationWorkItem = nil
    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor [weak self] in
        guard let self,
          self.status == .recording,
          self.activeRequestID == requestID
        else { return }
        self.finishDictationAndTranscribe(requestID: requestID)
      }
    }
    pendingFinishWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: workItem)
  }

  func beginTranscriptionBackgroundTaskIfNeeded() {
    guard transcriptionBackgroundTaskIdentifier == .invalid else { return }
    transcriptionBackgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
      withName: "Finish Gemini transcription"
    ) { [weak self] in
      Task { @MainActor [weak self] in
        self?.transcriptionBackgroundTimeExpired()
      }
    }
  }

  func transcriptionBackgroundTimeExpired() {
    transcriptionGeneration += 1
    transcriptionTask?.cancel()
    transcriptionTask = nil
    recoveryRetryTask?.cancel()
    recoveryRetryTask = nil
    cancelLiveStream()
    let message = "Processing timed out — recording saved. Retry in Gemini Voice."
    if isRelayRunning {
      publish(.error, message: message)
      markRelayActivityAndScheduleIdleShutdown()
    } else {
      statusMessage = message
    }
    endTranscriptionBackgroundTaskIfNeeded()
  }

  func endTranscriptionBackgroundTaskIfNeeded() {
    guard transcriptionBackgroundTaskIdentifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(transcriptionBackgroundTaskIdentifier)
    transcriptionBackgroundTaskIdentifier = .invalid
  }

  func beginOCRBackgroundTaskIfNeeded() {
    guard ocrBackgroundTaskIdentifier == .invalid else { return }
    ocrBackgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
      withName: "Finish Gemini OCR"
    ) { [weak self] in
      Task { @MainActor [weak self] in
        self?.endOCRBackgroundTaskIfNeeded()
      }
    }
  }

  func endOCRBackgroundTaskIfNeeded() {
    guard ocrBackgroundTaskIdentifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(ocrBackgroundTaskIdentifier)
    ocrBackgroundTaskIdentifier = .invalid
  }

  func applyPendingAudioRecoveryFailureIfNeeded() -> Bool {
    guard let error = pendingAudioRecoveryError else { return false }
    pendingAudioRecoveryError = nil
    pollTimer?.cancel()
    pollTimer = nil
    capture.stop()
    isRelayRunning = false
    idleShutdownWorkItem?.cancel()
    idleShutdownWorkItem = nil
    publishUnavailable(message: error.localizedDescription)
    return true
  }
}
