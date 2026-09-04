import AVFoundation
import Foundation

extension AudioCaptureEngine {
  func beginSegment(
    requestID: String,
    action: RelayDictationAction,
    translationTargetCode: String,
    at date: Date = Date(),
    audioChunkHandler: (@Sendable (Data) -> Void)? = nil,
    audioStreamingFailureHandler: (@Sendable (String) -> Void)? = nil
  ) throws {
    guard isRunning, let format = inputFormat else {
      throw AudioCaptureError.relayNotRunning
    }
    guard let container = VoiceAppGroup.containerURL else {
      throw AudioCaptureError.sharedContainerUnavailable
    }

    fileLock.lock()
    defer { fileLock.unlock() }

    guard activeFile == nil else {
      throw AudioCaptureError.alreadyRecording
    }

    let recordings = container.appendingPathComponent("Recordings", isDirectory: true)
    try FileManager.default.createDirectory(
      at: recordings,
      withIntermediateDirectories: true
    )
    try Self.protectRecordingItem(at: recordings)

    let safeID = requestID.replacingOccurrences(
      of: "[^A-Za-z0-9-]",
      with: "-",
      options: .regularExpression
    )
    let url = recordings.appendingPathComponent("in-progress-dictation-\(safeID).wav")

    var settings = format.settings
    settings[AVFormatIDKey] = kAudioFormatLinearPCM
    settings[AVLinearPCMBitDepthKey] = 16
    settings[AVLinearPCMIsFloatKey] = false
    settings[AVLinearPCMIsBigEndianKey] = false

    let file = try AVAudioFile(
      forWriting: url,
      settings: settings,
      commonFormat: format.commonFormat,
      interleaved: format.isInterleaved
    )
    do {
      try Self.protectRecordingItem(at: url)
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw AudioCaptureError.secureStorageUnavailable(error.localizedDescription)
    }

    activeFile = file
    activeURL = url
    activeRequestID = requestID
    activeAction = action
    activeTranslationTargetCode = translationTargetCode
    activeStartedAt = date
    writeFailure = nil
    lastLevelPublishedAt = 0
    streamingConverter?.reset()
    streamingChunker.reset()
    self.audioChunkHandler = audioChunkHandler
    self.audioStreamingFailureHandler = audioStreamingFailureHandler
    didReportStreamingFailure = false
    if audioChunkHandler != nil, streamingConverter == nil {
      reportStreamingFailure("The microphone audio format could not be converted for Gemini Live.")
    }
  }

  func endSegment(at date: Date = Date()) throws -> CapturedAudioSegment {
    fileLock.lock()
    guard let url = activeURL,
      let requestID = activeRequestID,
      let action = activeAction,
      let translationTargetCode = activeTranslationTargetCode,
      let startedAt = activeStartedAt
    else {
      fileLock.unlock()
      throw AudioCaptureError.notRecording
    }

    let chunkHandler = audioChunkHandler
    var finalStreamingChunks: [Data] = []
    if chunkHandler != nil {
      for convertedTail in finishStreamingPCMData() {
        finalStreamingChunks.append(contentsOf: streamingChunker.append(convertedTail))
      }
    }
    if let finalStreamingChunk = streamingChunker.finish() {
      finalStreamingChunks.append(finalStreamingChunk)
    }
    streamingConverter?.reset()
    activeFile = nil
    activeURL = nil
    activeRequestID = nil
    activeAction = nil
    activeTranslationTargetCode = nil
    activeStartedAt = nil
    audioChunkHandler = nil
    audioStreamingFailureHandler = nil

    if let writeFailure, chunkHandler == nil {
      self.writeFailure = nil
      fileLock.unlock()
      throw AudioCaptureError.writeFailed(writeFailure.localizedDescription)
    }
    if let writeFailure {
      NSLog(
        "AUDIO_FALLBACK_RECORDING_FAILED request=%@ error=%@",
        requestID,
        errorSummary(writeFailure)
      )
    }
    self.writeFailure = nil

    fileLock.unlock()

    if let chunkHandler {
      finalStreamingChunks.forEach(chunkHandler)
    }

    let safeTarget = translationTargetCode.replacingOccurrences(
      of: "[^A-Za-z0-9-]",
      with: "-",
      options: .regularExpression
    )
    let safeID = requestID.replacingOccurrences(
      of: "[^A-Za-z0-9-]",
      with: "-",
      options: .regularExpression
    )
    let finalizedURL = url.deletingLastPathComponent().appendingPathComponent(
      "completed-\(action.rawValue)-\(safeTarget)-\(safeID).wav"
    )
    do {
      try FileManager.default.moveItem(at: url, to: finalizedURL)
      try Self.protectRecordingItem(at: finalizedURL)
    } catch {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: finalizedURL)
      throw AudioCaptureError.secureStorageUnavailable(error.localizedDescription)
    }

    return CapturedAudioSegment(
      requestID: requestID,
      url: finalizedURL,
      startedAt: startedAt,
      endedAt: date
    )
  }

  func cancelSegment() {
    fileLock.lock()
    let url = activeURL
    activeFile = nil
    activeURL = nil
    activeRequestID = nil
    activeAction = nil
    activeTranslationTargetCode = nil
    activeStartedAt = nil
    writeFailure = nil
    audioChunkHandler = nil
    audioStreamingFailureHandler = nil
    didReportStreamingFailure = false
    streamingChunker.reset()
    streamingConverter?.reset()
    fileLock.unlock()

    if let url {
      try? FileManager.default.removeItem(at: url)
    }
  }

  static func protectRecordingItem(at url: URL, fileManager: FileManager = .default) throws {
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutableURL = url
    try mutableURL.setResourceValues(values)
  }
}
