import Foundation

struct PCM16StreamChunker {
  static let bytesPerFrame = 2
  static let targetFramesPerChunk = 1_600
  static let targetBytesPerChunk = bytesPerFrame * targetFramesPerChunk

  private(set) var bufferedData = Data()

  mutating func append(_ data: Data) -> [Data] {
    guard !data.isEmpty else { return [] }
    bufferedData.append(data)

    var chunks: [Data] = []
    while bufferedData.count >= Self.targetBytesPerChunk {
      chunks.append(Data(bufferedData.prefix(Self.targetBytesPerChunk)))
      bufferedData.removeFirst(Self.targetBytesPerChunk)
    }
    return chunks
  }

  mutating func finish() -> Data? {
    guard !bufferedData.isEmpty else { return nil }
    let finalChunk = bufferedData
    bufferedData.removeAll(keepingCapacity: true)
    return finalChunk
  }

  mutating func reset() {
    bufferedData.removeAll(keepingCapacity: true)
  }
}

struct RecoverableRecordingScanGate {
  private(set) var hasRun = false

  mutating func claim() -> Bool {
    guard !hasRun else { return false }
    hasRun = true
    return true
  }
}

enum AudioCaptureError: LocalizedError {
  case sharedContainerUnavailable
  case invalidInputFormat
  case relayNotRunning
  case alreadyRecording
  case notRecording
  case simulatorMicrophoneUnavailable
  case writeFailed(String)
  case sessionUnavailable(String)
  case secureStorageUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .sharedContainerUnavailable:
      return "The App Group container is unavailable. Check signing and the App Group capability."
    case .invalidInputFormat:
      return "The microphone returned an unsupported audio format."
    case .relayNotRunning:
      return "Start the audio relay first."
    case .alreadyRecording:
      return "A dictation is already recording."
    case .notRecording:
      return "There is no active dictation to stop."
    case .simulatorMicrophoneUnavailable:
      return
        "Microphone capture requires a physical iPhone. The settings UI remains available in Simulator."
    case .writeFailed(let message):
      return "Audio recording failed: \(message)"
    case .sessionUnavailable(let details):
      return "The microphone audio route could not start. \(details)"
    case .secureStorageUnavailable(let details):
      return "Secure recording storage is unavailable. \(details)"
    }
  }
}

struct CapturedAudioSegment {
  let requestID: String
  let url: URL
  let startedAt: Date
  let endedAt: Date

  var duration: TimeInterval {
    endedAt.timeIntervalSince(startedAt)
  }
}

/// The containing app owns this engine because Apple forbids microphone access
/// from custom keyboard extensions. The engine stays active while the relay is on,
/// allowing the app's declared audio background mode to receive keyboard commands.
