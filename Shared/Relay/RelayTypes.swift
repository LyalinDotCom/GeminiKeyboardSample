import Foundation

enum RelayResultKind: String, Codable {
  case dictation
  case ocr
}

enum RelayOfflineReason: String, Codable {
  case stopped
  case idleTimeout
  case unavailable
}

struct RelayCommandEnvelope: Equatable {
  let sequence: Int
  let command: RelayCommand
  let requestID: String
  let dictationAction: RelayDictationAction
  let createdAt: Date
}

struct RelaySnapshot: Equatable {
  let commandSequence: Int
  let handledCommandSequence: Int
  let status: RelayStatus
  let heartbeat: Date?
  let message: String
  let offlineReason: RelayOfflineReason?
  let activeRequestID: String?
  let activeDictationAction: RelayDictationAction?
  let recordingStartedAt: Date?
  let audioLevel: Double
  let audioLevelUpdatedAt: Date?
  let resultSequence: Int
  let resultRequestID: String?
  let resultKind: RelayResultKind?
  let resultCreatedAt: Date?
  let transcript: String?

  func hostIsOnline(at date: Date = Date(), tolerance: TimeInterval = 3.5) -> Bool {
    guard let heartbeat else { return false }
    return date.timeIntervalSince(heartbeat) >= 0
      && date.timeIntervalSince(heartbeat) < tolerance
  }
}

/// Keeps a cold-launch dictation from starting until the keyboard is attached
/// to the returned text field. A time delay can make a handoff look smoother,
/// but only the keyboard lifecycle can establish a fresh insertion anchor.
enum RelayKeyboardStartGate {
  static func canIssueStart(
    requestID: String?,
    action: RelayDictationAction?,
    createdAt: Date?,
    pendingLaunchRequest: RelayLaunchRequest?,
    snapshot: RelaySnapshot,
    keyboardIsVisible: Bool,
    keyboardIsAttached: Bool,
    startAlreadyIssued: Bool,
    now: Date = Date()
  ) -> Bool {
    guard keyboardIsVisible,
      keyboardIsAttached,
      !startAlreadyIssued,
      snapshot.hostIsOnline(at: now),
      snapshot.status == .idle,
      snapshot.activeRequestID == nil,
      let requestID,
      let action,
      let createdAt,
      let pendingLaunchRequest
    else {
      return false
    }

    let age = now.timeIntervalSince(createdAt)
    return age.isFinite
      && age >= 0
      && age <= RelayLaunchRequest.defaultMaximumAge
      && pendingLaunchRequest.requestID.caseInsensitiveCompare(requestID) == .orderedSame
      && pendingLaunchRequest.dictationAction == action
      && pendingLaunchRequest.createdAt.timeIntervalSince1970
        == createdAt.timeIntervalSince1970
  }
}

enum RelayStartAuthorization: Equatable {
  case warm
  case pendingLaunch(RelayLaunchRequest)
  case reject
}

enum RelayStartAuthorizationPolicy {
  static func resolve(
    command: RelayCommandEnvelope,
    loadedPendingLaunch: RelayLaunchRequest?,
    storedPendingLaunch: RelayLaunchRequest?
  ) -> RelayStartAuthorization {
    if let storedPendingLaunch {
      guard
        storedPendingLaunch.requestID.caseInsensitiveCompare(command.requestID)
          == .orderedSame,
        storedPendingLaunch.dictationAction == command.dictationAction
      else {
        return .reject
      }
      return .pendingLaunch(storedPendingLaunch)
    }

    // If the app already observed this cold-launch request but its shared
    // authorization disappeared, Cancel or expiry won the race. Never
    // reinterpret that same stale Start command as an ordinary warm one.
    // A different request is a legitimate rapid retry after the stale
    // launch state is discarded by the controller.
    guard let loadedPendingLaunch else { return .warm }
    return loadedPendingLaunch.requestID.caseInsensitiveCompare(command.requestID)
      == .orderedSame ? .reject : .warm
  }
}

/// A deliberately small, property-list-backed protocol shared by the containing
/// app and keyboard process. Each logical update writes its sequence number last,
/// which lets readers treat the sequence as the commit marker.
