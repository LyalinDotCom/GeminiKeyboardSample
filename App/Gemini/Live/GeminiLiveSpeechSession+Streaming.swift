import Foundation

extension GeminiLiveSpeechSession {
  var selectedFinalText: String {
    switch mode {
    case .transcribe:
      return TranscriptFormatter.cleaned(finalInputText)
    case .translate:
      return TranscriptFormatter.cleaned(finalOutputText)
    }
  }

  func completedText() throws -> String {
    let text = selectedFinalText
    guard !text.isEmpty else { throw GeminiLiveSpeechError.emptyResult }
    return text
  }

  func acceptAudio(_ data: Data) async {
    guard !data.isEmpty, !isClosed, terminalError == nil else { return }
    guard isConfigured, !isFlushingPendingAudio, let socket else {
      bufferPendingAudio(data)
      return
    }

    do {
      try await sendAudio(data, over: socket)
    } catch {
      terminalError = GeminiLiveSpeechError.connectionClosed("The audio stream was interrupted.")
    }
  }

  func bufferPendingAudio(_ data: Data) {
    // Slightly more than 45 seconds of 16 kHz mono Int16 PCM. This bounds
    // memory if setup stalls while the microphone continues recording.
    let maximumBufferedBytes = 1_500_000
    guard pendingAudioByteCount + data.count <= maximumBufferedBytes else {
      terminalError = GeminiLiveSpeechError.service(
        "Gemini Live took too long to connect. The saved recording will be used instead."
      )
      pendingAudio.removeAll(keepingCapacity: false)
      pendingAudioByteCount = 0
      return
    }
    pendingAudio.append(data)
    pendingAudioByteCount += data.count
  }

  func markAudioBackpressureFailure() {
    guard terminalError == nil, !isClosed else { return }
    terminalError = GeminiLiveSpeechError.service(
      "Live audio could not keep up. The saved recording will be used instead."
    )
  }

  func flushPendingAudio(over socket: any GeminiLiveSocket) async throws {
    isFlushingPendingAudio = true
    defer { isFlushingPendingAudio = false }

    while !pendingAudio.isEmpty {
      let batch = pendingAudio
      pendingAudio.removeAll(keepingCapacity: true)
      pendingAudioByteCount = 0
      for chunk in batch {
        try Task.checkCancellation()
        try await sendAudio(chunk, over: socket)
      }
    }
  }

  func sendAudio(_ data: Data, over socket: any GeminiLiveSocket) async throws {
    try await send(Self.audioMessage(data), over: socket)
    if Self.containsLikelySpeech(data) {
      lastLikelySpeechSentAt = Date()
    }
  }

  func send(
    _ object: [String: Any],
    over socket: any GeminiLiveSocket
  ) async throws {
    let data: Data
    do {
      data = try JSONSerialization.data(withJSONObject: object)
    } catch {
      throw GeminiLiveSpeechError.invalidMessage
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw GeminiLiveSpeechError.invalidMessage
    }
    do {
      try await geminiLiveWithTimeout(nanoseconds: 8_000_000_000) {
        try await socket.send(text: text)
      }
    } catch is GeminiLiveTimeoutError {
      await socket.close(code: .goingAway)
      throw GeminiLiveSpeechError.connectionClosed(
        "The streaming connection stopped responding."
      )
    }
  }

  func receiveMessages() async {
    guard let socket else { return }
    while !Task.isCancelled, !isClosed {
      do {
        let data = try await socket.receive()
        try process(data)
      } catch is CancellationError {
        return
      } catch {
        guard !isClosed else { return }
        terminalError =
          error is GeminiLiveSpeechError
          ? error
          : GeminiLiveSpeechError.connectionClosed("The network connection ended.")
        return
      }
    }
  }

  func process(_ data: Data) throws {
    for event in try Self.events(from: data) {
      switch event {
      case .setupComplete:
        setupCompleted = true
      case .interimInput(let text):
        if case .transcribe = mode,
          !TranscriptFormatter.cleaned(text).isEmpty
        {
          transcriptEventRevision += 1
          lastInterimInputRevision = transcriptEventRevision
          progressHandler?(text)
        }
      case .finalInput(let text):
        guard !TranscriptFormatter.cleaned(text).isEmpty else { continue }
        finalInputText = Self.mergedTranscript(existing: finalInputText, update: text)
        transcriptEventRevision += 1
        lastFinalInputRevision = transcriptEventRevision
        lastFinalTextAt = Date()
        if case .transcribe = mode { progressHandler?(finalInputText) }
      case .finalOutput(let text):
        finalOutputText = Self.mergedTranscript(existing: finalOutputText, update: text)
        lastFinalTextAt = Date()
        if case .translate = mode { progressHandler?(finalOutputText) }
      case .generationComplete:
        generationComplete = true
      case .turnComplete:
        break
      case .serviceError(let message):
        terminalError = GeminiLiveSpeechError.service(message)
      }
    }
  }

  func close(code: URLSessionWebSocketTask.CloseCode) async {
    guard !isClosed else { return }
    isClosed = true
    audioContinuation.finish()
    audioConsumerTask?.cancel()
    audioConsumerTask = nil
    receiveTask?.cancel()
    receiveTask = nil
    if let socket {
      await socket.close(code: code)
    }
    socket = nil
    pendingAudio.removeAll(keepingCapacity: false)
    pendingAudioByteCount = 0
  }
}
