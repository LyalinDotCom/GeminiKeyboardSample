import ActivityKit
import Foundation

struct VoiceRelayActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    enum Phase: String, Codable, Hashable {
      case standingBy
      case listening
      case transcribing
      case unavailable
    }

    let phase: Phase
    let title: String
    let subtitle: String
    let recordingStartedAt: Date?
    let controlToken: String

    var showsCancelControl: Bool {
      phase == .listening
    }
  }

  let relayID: String
}
