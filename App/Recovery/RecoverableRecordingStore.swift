import Foundation

struct RecoverableRecording: Codable, Equatable, Identifiable {
  let id: UUID
  let requestID: String
  let fileName: String
  let action: RelayDictationAction
  let translationTargetCode: String
  let createdAt: Date
  let duration: TimeInterval
  var lastError: String
  var retryCount: Int
  var transcriptSaved: Bool?

  var actionTitle: String {
    action == .translate ? "Translation" : "Dictation"
  }
}

/// Keeps completed microphone segments until Gemini has returned a usable result.
/// The JSON contains metadata only; audio remains in the app-group Recordings folder.
final class RecoverableRecordingStore {
  private static let metadataFileName = "recoverable-recordings.json"

  private let fileManager: FileManager
  private let directoryURL: URL?
  private let metadataURL: URL?
  private(set) var recordings: [RecoverableRecording] = []

  init(
    directoryURL: URL? = VoiceAppGroup.containerURL?.appendingPathComponent(
      "Recordings",
      isDirectory: true
    ),
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    self.directoryURL = directoryURL
    metadataURL = directoryURL?.appendingPathComponent(Self.metadataFileName)
    loadAndRecoverOrphans()
  }

  @discardableResult
  func stage(
    _ segment: CapturedAudioSegment,
    action: RelayDictationAction,
    translationTargetCode: String
  ) throws -> RecoverableRecording {
    guard let intent = Self.recoveryIntent(from: segment.url.lastPathComponent),
      intent.requestID.caseInsensitiveCompare(segment.requestID) == .orderedSame,
      intent.action == action,
      intent.translationTargetCode == translationTargetCode
    else {
      throw RecoverableRecordingStoreError.invalidFinalizedRecording
    }
    if let index = recordings.firstIndex(where: {
      $0.fileName == segment.url.lastPathComponent
    }) {
      let updated = RecoverableRecording(
        id: recordings[index].id,
        requestID: segment.requestID,
        fileName: segment.url.lastPathComponent,
        action: action,
        translationTargetCode: translationTargetCode,
        createdAt: segment.endedAt,
        duration: max(0, segment.duration),
        lastError: "Waiting for transcription",
        retryCount: recordings[index].retryCount,
        transcriptSaved: recordings[index].transcriptSaved
      )
      recordings[index] = updated
      try persist()
      return updated
    }

    try protectAudio(at: segment.url)
    let recording = RecoverableRecording(
      id: UUID(),
      requestID: segment.requestID,
      fileName: segment.url.lastPathComponent,
      action: action,
      translationTargetCode: translationTargetCode,
      createdAt: segment.endedAt,
      duration: max(0, segment.duration),
      lastError: "Waiting for transcription",
      retryCount: 0,
      transcriptSaved: nil
    )
    recordings.insert(recording, at: 0)
    do {
      try persist()
    } catch {
      recordings.removeAll { $0.id == recording.id }
      throw error
    }
    return recording
  }

  func markFailed(id: UUID, message: String, incrementRetryCount: Bool = false) {
    guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
    recordings[index].lastError = message
    if incrementRetryCount {
      recordings[index].retryCount += 1
    }
    try? persist()
  }

  func markTranscriptSaved(id: UUID, cleanupError: String) {
    guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
    recordings[index].transcriptSaved = true
    recordings[index].lastError = cleanupError
    try? persist()
  }

  func remove(id: UUID) throws {
    guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
    let recording = recordings[index]
    if let url = fileURL(for: recording) {
      if fileManager.fileExists(atPath: url.path) {
        do {
          try fileManager.removeItem(at: url)
        } catch {
          throw RecoverableRecordingStoreError.couldNotDeleteAudio(
            error.localizedDescription
          )
        }
      }
      guard !fileManager.fileExists(atPath: url.path) else {
        throw RecoverableRecordingStoreError.couldNotDeleteAudio(
          "The file is still present."
        )
      }
    }
    recordings.remove(at: index)
    do {
      try persist()
    } catch {
      recordings.insert(recording, at: min(index, recordings.count))
      throw error
    }
  }

  func fileURL(for recording: RecoverableRecording) -> URL? {
    guard recording.fileName == URL(fileURLWithPath: recording.fileName).lastPathComponent,
      !recording.fileName.isEmpty
    else { return nil }
    return directoryURL?.appendingPathComponent(recording.fileName)
  }

  private func loadAndRecoverOrphans() {
    guard let directoryURL else { return }
    do {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      try protectAudio(at: directoryURL)
    } catch {
      NSLog("RECOVERABLE_RECORDING_DIRECTORY_FAILED error=%@", error.localizedDescription)
      return
    }

    if let metadataURL,
      let data = try? Data(contentsOf: metadataURL),
      let decoded = try? JSONDecoder().decode([RecoverableRecording].self, from: data)
    {
      recordings = decoded.filter { recording in
        guard let url = fileURL(for: recording) else { return false }
        return fileManager.fileExists(atPath: url.path)
      }
    }

    let trackedNames = Set(recordings.map(\.fileName))
    let orphanURLs =
      (try? fileManager.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    for url in orphanURLs
    where url.pathExtension.lowercased() == "wav"
      && !trackedNames.contains(url.lastPathComponent)
    {
      if url.lastPathComponent.hasPrefix("in-progress-")
        || url.lastPathComponent.hasPrefix("dictation-")
      {
        try? fileManager.removeItem(at: url)
        continue
      }
      guard let intent = Self.recoveryIntent(from: url.lastPathComponent) else {
        continue
      }
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
      try? protectAudio(at: url)
      recordings.append(
        RecoverableRecording(
          id: UUID(),
          requestID: intent.requestID,
          fileName: url.lastPathComponent,
          action: intent.action,
          translationTargetCode: intent.translationTargetCode,
          createdAt: values?.contentModificationDate ?? Date(),
          duration: 0,
          lastError: "Recovered after Gemini Voice closed before transcription finished",
          retryCount: 0,
          transcriptSaved: nil
        )
      )
    }

    recordings.sort { $0.createdAt > $1.createdAt }
    try? persist()
  }

  private func persist() throws {
    guard let directoryURL, let metadataURL else { return }
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(recordings).write(to: metadataURL, options: .atomic)
    try protectAudio(at: metadataURL)
  }

  private func protectAudio(at url: URL) throws {
    try AudioCaptureEngine.protectRecordingItem(at: url, fileManager: fileManager)
  }

  static func recoveryIntent(
    from fileName: String
  ) -> (requestID: String, action: RelayDictationAction, translationTargetCode: String)? {
    guard fileName.hasPrefix("completed-"), fileName.hasSuffix(".wav") else { return nil }
    let stem = String(fileName.dropFirst("completed-".count).dropLast(".wav".count))
    guard stem.count > 38 else { return nil }
    let requestStart = stem.index(stem.endIndex, offsetBy: -36)
    let requestID = String(stem[requestStart...])
    guard UUID(uuidString: requestID) != nil else { return nil }
    let prefix = String(stem[..<requestStart]).trimmingCharacters(
      in: CharacterSet(charactersIn: "-"))
    guard let separator = prefix.firstIndex(of: "-") else { return nil }
    let actionText = String(prefix[..<separator])
    let target = String(prefix[prefix.index(after: separator)...])
    guard let action = RelayDictationAction(rawValue: actionText), !target.isEmpty else {
      return nil
    }
    return (requestID, action, target)
  }
}

enum RecoverableRecordingStoreError: LocalizedError {
  case invalidFinalizedRecording
  case couldNotDeleteAudio(String)

  var errorDescription: String? {
    switch self {
    case .invalidFinalizedRecording:
      return "The recording was not finalized and cannot be retried."
    case .couldNotDeleteAudio(let details):
      return "The saved audio could not be deleted. \(details)"
    }
  }
}

enum RecoverableRecordingStatus {
  static func keyboardMessage(for error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorTimedOut:
        return "Timed out — recording saved. Retry in Gemini Voice."
      case NSURLErrorNotConnectedToInternet,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorDNSLookupFailed:
        return "Connection failed — recording saved. Retry in Gemini Voice."
      default:
        break
      }
    }
    return "Transcription failed — recording saved. Retry in Gemini Voice."
  }
}
