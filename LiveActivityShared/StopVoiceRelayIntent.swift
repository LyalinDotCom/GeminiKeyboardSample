import ActivityKit
import AppIntents
import Foundation

private protocol ScopedVoiceRelayIntent {
  var controlToken: String { get }
  var relayCommand: RelayCommand { get }
}

extension ScopedVoiceRelayIntent {
  fileprivate func performScopedCommand() async throws {
    guard UUID(uuidString: controlToken) != nil else { return }

    let store = SharedRelayStore()
    let sequence = store.issue(
      relayCommand,
      requestID: controlToken,
      dictationAction: .transcribe
    )

    // The live-activity intent normally runs beside the active relay poller,
    // which acknowledges this within 200 ms. If iOS revived an otherwise
    // dead process, wait for its old heartbeat to expire and remove the
    // orphaned system surface directly.
    for _ in 0..<4 {
      try await Task.sleep(for: .seconds(1))
      let snapshot = store.snapshot()
      if snapshot.handledCommandSequence >= sequence {
        return
      }
      if !snapshot.hostIsOnline() {
        await endOrphanedActivity(store: store)
        return
      }
    }
  }

  fileprivate func endOrphanedActivity(store: SharedRelayStore) async {
    let message = "Microphone relay stopped"
    store.publishStatus(.offline, message: message)
    let finalState = VoiceRelayActivityAttributes.ContentState(
      phase: .unavailable,
      title: "Relay stopped",
      subtitle: message,
      recordingStartedAt: nil,
      controlToken: UUID().uuidString
    )
    for activity in Activity<VoiceRelayActivityAttributes>.activities
    where activity.content.state.controlToken == controlToken {
      await activity.end(
        ActivityContent(state: finalState, staleDate: nil),
        dismissalPolicy: .immediate
      )
    }
  }
}

struct CancelVoiceRecordingIntent: LiveActivityIntent, AudioRecordingIntent, ScopedVoiceRelayIntent
{
  static let title: LocalizedStringResource = "Cancel Gemini Voice Recording"
  static let description = IntentDescription(
    "Discards the recording shown by this Live Activity without sending it."
  )
  static var openAppWhenRun: Bool { false }

  @Parameter(title: "Control Token")
  var controlToken: String

  fileprivate var relayCommand: RelayCommand { .cancelRecordingFromLiveActivity }

  init() {
    controlToken = ""
  }

  init(controlToken: String) {
    self.controlToken = controlToken
  }

  func perform() async throws -> some IntentResult {
    try await performScopedCommand()
    return .result()
  }
}

struct StopVoiceRelayIntent: LiveActivityIntent, AudioRecordingIntent, ScopedVoiceRelayIntent {
  static let title: LocalizedStringResource = "Stop Gemini Voice Relay"
  static let description = IntentDescription(
    "Turns off the standing microphone relay shown by this Live Activity."
  )
  static var openAppWhenRun: Bool { false }

  @Parameter(title: "Control Token")
  var controlToken: String

  fileprivate var relayCommand: RelayCommand { .shutdownRelayFromLiveActivity }

  init() {
    controlToken = ""
  }

  init(controlToken: String) {
    self.controlToken = controlToken
  }

  func perform() async throws -> some IntentResult {
    try await performScopedCommand()
    return .result()
  }
}
