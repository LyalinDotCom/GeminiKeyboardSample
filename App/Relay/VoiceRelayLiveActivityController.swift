import ActivityKit
import Foundation

@MainActor
final class VoiceRelayLiveActivityOperationQueue {
  private var operationTask: Task<Void, Never>?

  func enqueue(_ operation: @escaping @MainActor () async -> Void) {
    let previousOperation = operationTask
    operationTask = Task { @MainActor in
      await previousOperation?.value
      await operation()
    }
  }

  func waitUntilIdle() async {
    await operationTask?.value
  }
}

@MainActor
final class VoiceRelayLiveActivityController {
  private var activityID: String?
  private let operationQueue = VoiceRelayLiveActivityOperationQueue()

  init() {
    activityID = Activity<VoiceRelayActivityAttributes>.activities.first?.id
  }

  func startOrUpdate(
    status: RelayStatus,
    message: String,
    action: RelayDictationAction? = nil,
    recordingStartedAt: Date? = nil,
    controlToken: String,
    relaySessionID: String
  ) {
    let state = contentState(
      status: status,
      message: message,
      action: action,
      recordingStartedAt: recordingStartedAt,
      controlToken: controlToken
    )

    operationQueue.enqueue { [weak self] in
      guard let self else { return }
      self.activityID = await Self.startOrUpdateActivity(
        activityID: self.activityID,
        state: state,
        relaySessionID: relaySessionID
      )
    }
  }

  func end(message: String) {
    let finalState = VoiceRelayActivityAttributes.ContentState(
      phase: .unavailable,
      title: "Relay stopped",
      subtitle: message,
      recordingStartedAt: nil,
      controlToken: UUID().uuidString
    )
    operationQueue.enqueue { [weak self] in
      guard let self, let activityID = self.activityID else { return }
      self.activityID = nil
      await Self.endActivity(
        activityID: activityID,
        finalState: finalState
      )
    }
  }

  private nonisolated static func startOrUpdateActivity(
    activityID: String?,
    state: VoiceRelayActivityAttributes.ContentState,
    relaySessionID: String
  ) async -> String? {
    if let activityID,
      let activity = Activity<VoiceRelayActivityAttributes>.activities.first(
        where: { $0.id == activityID }
      )
    {
      await activity.update(
        ActivityContent(state: state, staleDate: nil)
      )
      return activityID
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
    do {
      return try Activity.request(
        attributes: VoiceRelayActivityAttributes(relayID: relaySessionID),
        content: ActivityContent(state: state, staleDate: nil),
        pushType: nil
      ).id
    } catch {
      NSLog("LIVE_ACTIVITY_START_FAILED error=%@", error.localizedDescription)
      return nil
    }
  }

  private nonisolated static func endActivity(
    activityID: String,
    finalState: VoiceRelayActivityAttributes.ContentState
  ) async {
    guard
      let activity = Activity<VoiceRelayActivityAttributes>.activities.first(
        where: { $0.id == activityID }
      )
    else { return }
    await activity.end(
      ActivityContent(state: finalState, staleDate: nil),
      dismissalPolicy: .immediate
    )
  }

  private func contentState(
    status: RelayStatus,
    message: String,
    action: RelayDictationAction?,
    recordingStartedAt: Date?,
    controlToken: String
  ) -> VoiceRelayActivityAttributes.ContentState {
    switch status {
    case .recording:
      return VoiceRelayActivityAttributes.ContentState(
        phase: .listening,
        title: action == .translate ? "Listening to translate" : "Listening",
        subtitle: "Tap × to stop and discard the result",
        recordingStartedAt: recordingStartedAt,
        controlToken: controlToken
      )
    case .transcribing:
      return VoiceRelayActivityAttributes.ContentState(
        phase: .transcribing,
        title: action == .translate ? "Translating" : "Transcribing",
        subtitle: message,
        recordingStartedAt: nil,
        controlToken: controlToken
      )
    case .error, .offline:
      return VoiceRelayActivityAttributes.ContentState(
        phase: .unavailable,
        title: "Gemini Voice needs attention",
        subtitle: message,
        recordingStartedAt: nil,
        controlToken: controlToken
      )
    case .idle:
      return VoiceRelayActivityAttributes.ContentState(
        phase: .standingBy,
        title: "Standing by",
        subtitle: "Microphone ready · pauses after 2 minutes",
        recordingStartedAt: nil,
        controlToken: controlToken
      )
    }
  }
}
