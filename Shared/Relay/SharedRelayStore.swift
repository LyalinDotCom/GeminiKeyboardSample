import Darwin
import Foundation

final class SharedRelayStore {
  private struct PendingLaunchRecord: Codable {
    static let currentVersion = 2

    let version: Int
    let requestID: String
    let action: String
    let createdAt: TimeInterval
    let originatingApplicationBundleIdentifier: String?
  }

  private enum Key {
    static let commandSequence = "relay.command.sequence"
    static let commandName = "relay.command.name"
    static let commandRequestID = "relay.command.request-id"
    static let commandDictationAction = "relay.command.dictation-action"
    static let commandCreatedAt = "relay.command.created-at"
    static let handledCommandSequence = "relay.command.handled-sequence"

    // A single encoded value is the commit marker for a pending keyboard-to-app
    // launch. The legacy keys are retained only so an upgrade can clear them.
    static let pendingLaunchRequest = "relay.launch.pending-request"
    static let legacyLaunchRequestID = "relay.launch.request-id"
    static let legacyLaunchRequestAction = "relay.launch.request-action"
    static let legacyLaunchRequestCreatedAt = "relay.launch.request-created-at"

    static let status = "relay.status"
    static let heartbeat = "relay.heartbeat"
    static let message = "relay.message"
    static let offlineReason = "relay.offline-reason"
    static let activeRequestID = "relay.active-request-id"
    static let activeDictationAction = "relay.active-dictation-action"
    static let recordingStartedAt = "relay.recording-started-at"
    static let audioLevel = "relay.audio-level"
    static let audioLevelUpdatedAt = "relay.audio-level-updated-at"

    static let resultSequence = "relay.result.sequence"
    static let resultRequestID = "relay.result.request-id"
    static let resultKind = "relay.result.kind"
    static let resultCreatedAt = "relay.result.created-at"
    static let transcript = "relay.result.transcript"
  }

  private static let launchRequestLock = NSLock()
  private static let commandLock = NSLock()
  private static let resultLock = NSLock()
  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  convenience init() {
    let shared = UserDefaults(suiteName: VoiceAppGroup.identifier) ?? .standard
    self.init(defaults: shared)
  }

  var sharedContainerIsAvailable: Bool {
    VoiceAppGroup.containerURL != nil
  }

  @discardableResult
  func issue(
    _ command: RelayCommand,
    requestID: String,
    dictationAction: RelayDictationAction = .transcribe,
    at date: Date = Date()
  ) -> Int {
    withCommandLock {
      let committedSequence = defaults.integer(forKey: Key.commandSequence)
      let handledSequence = defaults.integer(forKey: Key.handledCommandSequence)
      let pendingCommand = defaults.string(forKey: Key.commandName)
        .flatMap(RelayCommand.init(rawValue:))
      let pendingRequestID = defaults.string(forKey: Key.commandRequestID)

      // A discard that is waiting to be handled must never be replaced by
      // Finish for the same clip. This makes cancel win a cross-process
      // race between the keyboard and Live Activity.
      if committedSequence > handledSequence,
        pendingRequestID == requestID,
        pendingCommand?.discardsRecording == true,
        !command.discardsRecording
      {
        return committedSequence
      }

      let sequence = committedSequence + 1
      defaults.set(command.rawValue, forKey: Key.commandName)
      defaults.set(requestID, forKey: Key.commandRequestID)
      defaults.set(dictationAction.rawValue, forKey: Key.commandDictationAction)
      defaults.set(date.timeIntervalSince1970, forKey: Key.commandCreatedAt)
      defaults.set(sequence, forKey: Key.commandSequence)
      flush()
      return sequence
    }
  }

  func pendingCommand(after sequence: Int) -> RelayCommandEnvelope? {
    withCommandLock {
      let committedSequence = defaults.integer(forKey: Key.commandSequence)
      guard committedSequence > sequence,
        let rawCommand = defaults.string(forKey: Key.commandName),
        let command = RelayCommand(rawValue: rawCommand),
        let requestID = defaults.string(forKey: Key.commandRequestID)
      else {
        return nil
      }

      let timestamp = defaults.double(forKey: Key.commandCreatedAt)
      return RelayCommandEnvelope(
        sequence: committedSequence,
        command: command,
        requestID: requestID,
        dictationAction: defaults.string(forKey: Key.commandDictationAction)
          .flatMap(RelayDictationAction.init(rawValue:)) ?? .transcribe,
        createdAt: Date(timeIntervalSince1970: timestamp)
      )
    }
  }

  func markCommandHandled(sequence: Int) {
    withCommandLock {
      let handledSequence = defaults.integer(forKey: Key.handledCommandSequence)
      defaults.set(max(sequence, handledSequence), forKey: Key.handledCommandSequence)
      flush()
    }
  }

  /// Stores a pending launch as one property-list value so the containing app
  /// never observes a request assembled from partially-written fields.
  @discardableResult
  func authorizeLaunchRequest(_ request: RelayLaunchRequest) -> Bool {
    guard request.hasValidStoredFields else { return false }

    let record = PendingLaunchRecord(
      version: PendingLaunchRecord.currentVersion,
      requestID: request.requestID,
      action: request.dictationAction.rawValue,
      createdAt: request.createdAt.timeIntervalSince1970,
      originatingApplicationBundleIdentifier: request.originatingApplicationBundleIdentifier
    )
    guard let data = try? PropertyListEncoder().encode(record) else { return false }

    return withLaunchRequestLock {
      defaults.set(data, forKey: Key.pendingLaunchRequest)
      clearLegacyLaunchRequestKeys()
      flush()
      return true
    }
  }

  /// Returns a fresh pending launch without claiming it. Invalid, future, and
  /// expired records are removed so they cannot repeatedly trigger app startup.
  func pendingLaunchRequest(
    now: Date = Date(),
    maximumAge: TimeInterval = RelayLaunchRequest.defaultMaximumAge
  ) -> RelayLaunchRequest? {
    guard maximumAge.isFinite, maximumAge >= 0 else { return nil }

    return withLaunchRequestLock {
      readFreshPendingLaunchRequest(now: now, maximumAge: maximumAge)
    }
  }

  /// Claims a fresh pending launch exactly once within this process. When an
  /// expected request is supplied, a mismatch leaves the stored request intact.
  func claimPendingLaunchRequest(
    matching expectedRequest: RelayLaunchRequest? = nil,
    now: Date = Date(),
    maximumAge: TimeInterval = RelayLaunchRequest.defaultMaximumAge
  ) -> RelayLaunchRequest? {
    guard maximumAge.isFinite, maximumAge >= 0 else { return nil }

    return withLaunchRequestLock {
      guard
        let pending = readFreshPendingLaunchRequest(
          now: now,
          maximumAge: maximumAge
        )
      else {
        return nil
      }
      if let expectedRequest, !pending.exactlyMatches(expectedRequest) {
        return nil
      }

      clearStoredLaunchRequest()
      return pending
    }
  }

  func consumeLaunchAuthorization(
    for request: RelayLaunchRequest,
    now: Date = Date(),
    maximumAge: TimeInterval = RelayLaunchRequest.defaultMaximumAge
  ) -> Bool {
    claimPendingLaunchRequest(
      matching: request,
      now: now,
      maximumAge: maximumAge
    ) != nil
  }

  func clearLaunchAuthorization(for requestID: String) {
    withLaunchRequestLock {
      guard
        let pending = readFreshPendingLaunchRequest(
          now: Date(),
          maximumAge: RelayLaunchRequest.defaultMaximumAge
        ), pending.requestID.caseInsensitiveCompare(requestID) == .orderedSame
      else {
        return
      }
      clearStoredLaunchRequest()
    }
  }

  func publishStatus(
    _ status: RelayStatus,
    message: String,
    offlineReason: RelayOfflineReason? = nil,
    activeRequestID: String? = nil,
    activeDictationAction: RelayDictationAction? = nil,
    recordingStartedAt: Date? = nil,
    heartbeat: Date = Date()
  ) {
    defaults.set(status.rawValue, forKey: Key.status)
    defaults.set(message, forKey: Key.message)
    setOptional(status == .offline ? offlineReason?.rawValue : nil, forKey: Key.offlineReason)
    defaults.set(heartbeat.timeIntervalSince1970, forKey: Key.heartbeat)
    setOptional(activeRequestID, forKey: Key.activeRequestID)
    setOptional(activeDictationAction?.rawValue, forKey: Key.activeDictationAction)
    setOptional(recordingStartedAt?.timeIntervalSince1970, forKey: Key.recordingStartedAt)
    if status != .recording {
      defaults.set(0, forKey: Key.audioLevel)
      defaults.removeObject(forKey: Key.audioLevelUpdatedAt)
    }
    flush()
  }

  func publishAudioLevel(_ level: Double, requestID: String) {
    guard defaults.string(forKey: Key.status) == RelayStatus.recording.rawValue,
      defaults.string(forKey: Key.activeRequestID) == requestID
    else {
      return
    }
    defaults.set(min(max(level, 0), 1), forKey: Key.audioLevel)
    defaults.set(Date().timeIntervalSince1970, forKey: Key.audioLevelUpdatedAt)
    flush()
  }

  func touchHeartbeat(_ date: Date = Date()) {
    defaults.set(date.timeIntervalSince1970, forKey: Key.heartbeat)
    flush()
  }

  @discardableResult
  func publishTranscript(
    _ transcript: String,
    requestID: String,
    kind: RelayResultKind = .dictation,
    at date: Date = Date()
  ) -> Int {
    withResultLock {
      let sequence = defaults.integer(forKey: Key.resultSequence) + 1
      defaults.set(requestID, forKey: Key.resultRequestID)
      defaults.set(kind.rawValue, forKey: Key.resultKind)
      defaults.set(date.timeIntervalSince1970, forKey: Key.resultCreatedAt)
      defaults.set(transcript, forKey: Key.transcript)
      defaults.set(sequence, forKey: Key.resultSequence)
      flush()
      return sequence
    }
  }

  /// Removes sensitive result payload only when the caller consumed the
  /// currently committed result. The monotonically increasing sequence is
  /// retained so an older acknowledgement cannot hide a newer transcript.
  func acknowledgeResult(sequence: Int) {
    withResultLock {
      guard defaults.integer(forKey: Key.resultSequence) == sequence else {
        return
      }
      defaults.removeObject(forKey: Key.resultRequestID)
      defaults.removeObject(forKey: Key.resultKind)
      defaults.removeObject(forKey: Key.resultCreatedAt)
      defaults.removeObject(forKey: Key.transcript)
      flush()
    }
  }

  func snapshot() -> RelaySnapshot {
    let heartbeatValue = defaults.double(forKey: Key.heartbeat)
    let startedAtValue = defaults.double(forKey: Key.recordingStartedAt)
    let audioLevelUpdatedAtValue = defaults.double(forKey: Key.audioLevelUpdatedAt)
    let resultCreatedAtValue = defaults.double(forKey: Key.resultCreatedAt)

    return RelaySnapshot(
      commandSequence: defaults.integer(forKey: Key.commandSequence),
      handledCommandSequence: defaults.integer(forKey: Key.handledCommandSequence),
      status: RelayStatus(rawValue: defaults.string(forKey: Key.status) ?? "") ?? .offline,
      heartbeat: heartbeatValue > 0 ? Date(timeIntervalSince1970: heartbeatValue) : nil,
      message: defaults.string(forKey: Key.message) ?? "Relay is offline",
      offlineReason: defaults.string(forKey: Key.offlineReason)
        .flatMap(RelayOfflineReason.init(rawValue:)),
      activeRequestID: defaults.string(forKey: Key.activeRequestID),
      activeDictationAction: defaults.string(forKey: Key.activeDictationAction)
        .flatMap(RelayDictationAction.init(rawValue:)),
      recordingStartedAt: startedAtValue > 0 ? Date(timeIntervalSince1970: startedAtValue) : nil,
      audioLevel: defaults.double(forKey: Key.audioLevel),
      audioLevelUpdatedAt: audioLevelUpdatedAtValue > 0
        ? Date(timeIntervalSince1970: audioLevelUpdatedAtValue)
        : nil,
      resultSequence: defaults.integer(forKey: Key.resultSequence),
      resultRequestID: defaults.string(forKey: Key.resultRequestID),
      resultKind: defaults.string(forKey: Key.resultKind).flatMap(RelayResultKind.init(rawValue:)),
      resultCreatedAt: resultCreatedAtValue > 0
        ? Date(timeIntervalSince1970: resultCreatedAtValue) : nil,
      transcript: defaults.string(forKey: Key.transcript)
    )
  }

  func resetForTesting() {
    [
      Key.commandSequence, Key.commandName, Key.commandRequestID,
      Key.commandCreatedAt, Key.commandDictationAction,
      Key.handledCommandSequence, Key.status,
      Key.pendingLaunchRequest,
      Key.legacyLaunchRequestID, Key.legacyLaunchRequestAction,
      Key.legacyLaunchRequestCreatedAt,
      Key.heartbeat, Key.message, Key.offlineReason, Key.activeRequestID,
      Key.activeDictationAction,
      Key.recordingStartedAt, Key.audioLevel, Key.audioLevelUpdatedAt,
      Key.resultSequence, Key.resultRequestID,
      Key.resultKind, Key.resultCreatedAt, Key.transcript,
    ].forEach(defaults.removeObject(forKey:))
    flush()
  }

  private func setOptional(_ value: Any?, forKey key: String) {
    if let value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  private func readFreshPendingLaunchRequest(
    now: Date,
    maximumAge: TimeInterval
  ) -> RelayLaunchRequest? {
    guard let storedValue = defaults.object(forKey: Key.pendingLaunchRequest) else {
      return nil
    }
    guard let data = storedValue as? Data,
      let record = try? PropertyListDecoder().decode(
        PendingLaunchRecord.self,
        from: data
      ),
      record.version == PendingLaunchRecord.currentVersion,
      let action = RelayDictationAction(rawValue: record.action)
    else {
      clearStoredLaunchRequest()
      return nil
    }

    let request = RelayLaunchRequest(
      requestID: record.requestID,
      dictationAction: action,
      createdAt: Date(timeIntervalSince1970: record.createdAt),
      originatingApplicationBundleIdentifier: record.originatingApplicationBundleIdentifier
    )
    let age = now.timeIntervalSince(request.createdAt)
    guard request.hasValidStoredFields,
      age.isFinite,
      age >= 0,
      age <= maximumAge
    else {
      clearStoredLaunchRequest()
      return nil
    }
    return request
  }

  private func clearStoredLaunchRequest() {
    defaults.removeObject(forKey: Key.pendingLaunchRequest)
    clearLegacyLaunchRequestKeys()
    flush()
  }

  private func clearLegacyLaunchRequestKeys() {
    defaults.removeObject(forKey: Key.legacyLaunchRequestID)
    defaults.removeObject(forKey: Key.legacyLaunchRequestAction)
    defaults.removeObject(forKey: Key.legacyLaunchRequestCreatedAt)
  }

  private func withCommandLock<T>(_ operation: () -> T) -> T {
    Self.commandLock.lock()
    defer { Self.commandLock.unlock() }

    guard let containerURL = VoiceAppGroup.containerURL else {
      return operation()
    }

    let lockURL = containerURL.appendingPathComponent("relay-command.lock")
    if !FileManager.default.fileExists(atPath: lockURL.path) {
      _ = FileManager.default.createFile(atPath: lockURL.path, contents: Data())
    }
    guard let handle = try? FileHandle(forUpdating: lockURL) else {
      return operation()
    }

    _ = flock(handle.fileDescriptor, LOCK_EX)
    defer {
      _ = flock(handle.fileDescriptor, LOCK_UN)
      handle.closeFile()
    }
    defaults.synchronize()
    return operation()
  }

  private func withResultLock<T>(_ operation: () -> T) -> T {
    Self.resultLock.lock()
    defer { Self.resultLock.unlock() }

    guard let containerURL = VoiceAppGroup.containerURL else {
      return operation()
    }

    let lockURL = containerURL.appendingPathComponent("relay-result.lock")
    if !FileManager.default.fileExists(atPath: lockURL.path) {
      _ = FileManager.default.createFile(atPath: lockURL.path, contents: Data())
    }
    guard let handle = try? FileHandle(forUpdating: lockURL) else {
      return operation()
    }

    _ = flock(handle.fileDescriptor, LOCK_EX)
    defer {
      _ = flock(handle.fileDescriptor, LOCK_UN)
      handle.closeFile()
    }
    defaults.synchronize()
    return operation()
  }

  /// `UserDefaults` is shared across related processes, so an in-process lock is
  /// insufficient for the read/verify/remove claim. A tiny App Group lock file
  /// prevents a keyboard cancellation or replacement request from racing an
  /// app-side claim. The local lock remains the fallback for unit tests and for
  /// a misconfigured build where the shared container is unavailable.
  private func withLaunchRequestLock<T>(_ operation: () -> T) -> T {
    Self.launchRequestLock.lock()
    defer { Self.launchRequestLock.unlock() }

    guard let containerURL = VoiceAppGroup.containerURL else {
      return operation()
    }

    let lockURL = containerURL.appendingPathComponent("relay-launch.lock")
    if !FileManager.default.fileExists(atPath: lockURL.path) {
      _ = FileManager.default.createFile(atPath: lockURL.path, contents: Data())
    }
    guard let handle = try? FileHandle(forUpdating: lockURL) else {
      return operation()
    }

    _ = flock(handle.fileDescriptor, LOCK_EX)
    defer {
      _ = flock(handle.fileDescriptor, LOCK_UN)
      handle.closeFile()
    }
    defaults.synchronize()
    return operation()
  }

  private func flush() {
    // synchronize() is intentionally used for low-latency cross-process IPC.
    // The sequence-number commit marker still protects readers from partial updates.
    defaults.synchronize()
  }
}
