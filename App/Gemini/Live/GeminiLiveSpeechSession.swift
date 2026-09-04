import Foundation

actor GeminiLiveSpeechSession {
  enum Mode: Equatable, Sendable {
    case transcribe
    case translate(targetLanguageCode: String)
  }

  enum ServerEvent: Equatable {
    case setupComplete
    case interimInput(String)
    case finalInput(String)
    case finalOutput(String)
    case generationComplete
    case turnComplete
    case serviceError(String)
  }

  typealias SocketFactory = @Sendable (GeminiLiveEndpoint) -> any GeminiLiveSocket

  static let transcriptionModel = "gemini-3.5-transcribe-live"
  static let translationModel = "gemini-3.5-live-translate-preview"

  let mode: Mode
  let progressHandler: (@Sendable (String) -> Void)?
  let socketFactory: SocketFactory
  nonisolated let audioStream: AsyncStream<Data>
  nonisolated let audioContinuation: AsyncStream<Data>.Continuation

  var socket: (any GeminiLiveSocket)?
  var receiveTask: Task<Void, Never>?
  var audioConsumerTask: Task<Void, Never>?
  var pendingAudio: [Data] = []
  var pendingAudioByteCount = 0
  var isConfigured = false
  var isFlushingPendingAudio = false
  var setupCompleted = false
  var isFinishing = false
  var isClosed = false
  var finalInputText = ""
  var finalOutputText = ""
  var lastFinalTextAt: Date?
  var transcriptEventRevision: UInt64 = 0
  var lastInterimInputRevision: UInt64?
  var lastFinalInputRevision: UInt64?
  var lastLikelySpeechSentAt: Date?
  var generationComplete = false
  var terminalError: Error?

  init(
    mode: Mode,
    socketFactory: @escaping SocketFactory = { endpoint in
      URLSessionGeminiLiveSocket(endpoint: endpoint)
    },
    progressHandler: (@Sendable (String) -> Void)? = nil
  ) {
    let streamPair = AsyncStream<Data>.makeStream(
      bufferingPolicy: .bufferingNewest(500)
    )
    self.mode = mode
    self.socketFactory = socketFactory
    self.progressHandler = progressHandler
    self.audioStream = streamPair.stream
    self.audioContinuation = streamPair.continuation
  }

  func connect(credential: GeminiLiveCredential) async throws {
    guard socket == nil, !isClosed else {
      throw GeminiLiveSpeechError.alreadyConnected
    }

    let endpoint = try Self.endpoint(credential: credential)
    let socket = socketFactory(endpoint)
    self.socket = socket
    await socket.start()

    receiveTask = Task { [weak self] in
      await self?.receiveMessages()
    }
    audioConsumerTask = Task { [weak self, audioStream] in
      for await data in audioStream {
        guard !Task.isCancelled else { return }
        await self?.acceptAudio(data)
      }
    }

    do {
      try await send(Self.setupMessage(for: mode), over: socket)
      for _ in 0..<50 {
        try Task.checkCancellation()
        if let terminalError { throw terminalError }
        if setupCompleted { break }
        try await Task.sleep(nanoseconds: 100_000_000)
      }
      guard setupCompleted else {
        throw GeminiLiveSpeechError.connectionClosed(
          "Gemini did not acknowledge the streaming setup."
        )
      }

      if case .transcribe = mode {
        try await send(Self.activityStartMessage(), over: socket)
      }
      try await flushPendingAudio(over: socket)
      isConfigured = true
    } catch {
      terminalError = error
      await close(code: .goingAway)
      throw error
    }
  }

  nonisolated func enqueueAudio(_ data: Data) {
    guard !data.isEmpty else { return }
    switch audioContinuation.yield(data) {
    case .enqueued:
      break
    case .dropped:
      Task { await markAudioBackpressureFailure() }
    case .terminated:
      break
    @unknown default:
      Task { await markAudioBackpressureFailure() }
    }
  }

  func invalidateAudioStream(_ reason: String) {
    guard terminalError == nil, !isClosed else { return }
    terminalError = GeminiLiveSpeechError.service(reason)
  }
}
