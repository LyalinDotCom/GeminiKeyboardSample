import Foundation
import XCTest

@testable import GeminiVoice

private actor MockGeminiLiveSocket: GeminiLiveSocket {
  private var sentTexts: [String] = []
  private var queuedResults: [Result<Data, Error>] = []
  private var receivers: [CheckedContinuation<Data, Error>] = []
  private(set) var didStart = false
  private(set) var closeCode: URLSessionWebSocketTask.CloseCode?

  func start() async {
    didStart = true
  }

  func send(text: String) async throws {
    sentTexts.append(text)
  }

  func receive() async throws -> Data {
    if !queuedResults.isEmpty {
      return try queuedResults.removeFirst().get()
    }
    return try await withCheckedThrowingContinuation { continuation in
      receivers.append(continuation)
    }
  }

  func close(code: URLSessionWebSocketTask.CloseCode) async {
    closeCode = code
    let pendingReceivers = receivers
    receivers.removeAll()
    for receiver in pendingReceivers {
      receiver.resume(throwing: CancellationError())
    }
  }

  func enqueueJSONObject(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object)
    if !receivers.isEmpty {
      receivers.removeFirst().resume(returning: data)
    } else {
      queuedResults.append(.success(data))
    }
  }

  func sentJSONObjects() throws -> [[String: Any]] {
    try sentTexts.map { text in
      let data = Data(text.utf8)
      return try XCTUnwrap(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
      )
    }
  }

  func hasSentAudioStreamEnd() -> Bool {
    sentTexts.contains { text in
      guard
        let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8)))
          as? [String: Any],
        let realtimeInput = object["realtimeInput"] as? [String: Any]
      else {
        return false
      }
      return realtimeInput["audioStreamEnd"] as? Bool == true
    }
  }

  func hasSentActivityEnd() -> Bool {
    sentTexts.contains { text in
      guard
        let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8)))
          as? [String: Any],
        let realtimeInput = object["realtimeInput"] as? [String: Any]
      else {
        return false
      }
      return realtimeInput["activityEnd"] != nil
    }
  }

  func sentAudioMessageCount() -> Int {
    sentTexts.reduce(into: 0) { count, text in
      guard
        let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8)))
          as? [String: Any],
        let realtimeInput = object["realtimeInput"] as? [String: Any],
        realtimeInput["audio"] != nil
      else {
        return
      }
      count += 1
    }
  }
}

private final class EndpointCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var endpoint: GeminiLiveEndpoint?

  var value: GeminiLiveEndpoint? {
    lock.lock()
    defer { lock.unlock() }
    return endpoint
  }

  func record(_ endpoint: GeminiLiveEndpoint) {
    lock.lock()
    self.endpoint = endpoint
    lock.unlock()
  }
}

final class GeminiLiveSpeechSessionTests: XCTestCase {
  func testTranscriptionSetupUsesDocumentedLiveModelAndManualPushToTalk() throws {
    let message = GeminiLiveSpeechSession.setupMessage(for: .transcribe)
    let setup = try XCTUnwrap(message["setup"] as? [String: Any])
    XCTAssertEqual(setup["model"] as? String, "models/gemini-3.5-transcribe-live")

    let generation = try XCTUnwrap(setup["generationConfig"] as? [String: Any])
    XCTAssertEqual(generation["responseModalities"] as? [String], ["TEXT"])

    let transcription = try XCTUnwrap(
      setup["inputAudioTranscription"] as? [String: Any]
    )
    XCTAssertEqual(transcription["mode"] as? String, "SMART")
    XCTAssertEqual(transcription["languageCodes"] as? [String], [])

    let realtime = try XCTUnwrap(setup["realtimeInputConfig"] as? [String: Any])
    let detection = try XCTUnwrap(
      realtime["automaticActivityDetection"] as? [String: Any]
    )
    XCTAssertEqual(detection["disabled"] as? Bool, true)
  }

  func testTranslationTranscriptTogglesAreInsideGenerationConfig() throws {
    let message = GeminiLiveSpeechSession.setupMessage(
      for: .translate(targetLanguageCode: "pl")
    )
    let setup = try XCTUnwrap(message["setup"] as? [String: Any])
    XCTAssertEqual(
      setup["model"] as? String,
      "models/gemini-3.5-live-translate-preview"
    )
    XCTAssertNil(setup["inputAudioTranscription"])
    XCTAssertNil(setup["outputAudioTranscription"])

    let generation = try XCTUnwrap(setup["generationConfig"] as? [String: Any])
    XCTAssertEqual(generation["responseModalities"] as? [String], ["AUDIO"])
    XCTAssertNotNil(generation["inputAudioTranscription"])
    XCTAssertNotNil(generation["outputAudioTranscription"])
    let translation = try XCTUnwrap(
      generation["translationConfig"] as? [String: Any]
    )
    XCTAssertEqual(translation["targetLanguageCode"] as? String, "pl")
    XCTAssertEqual(translation["echoTargetLanguage"] as? Bool, true)
  }

  func testAPIKeyTravelsInHeaderAndNeverInTheURL() throws {
    let endpoint = try GeminiLiveSpeechSession.endpoint(
      credential: .apiKey("development-key")
    )
    XCTAssertTrue(endpoint.url.path.hasSuffix("GenerativeService.BidiGenerateContent"))
    XCTAssertEqual(endpoint.headers, ["x-goog-api-key": "development-key"])
    XCTAssertNil(endpoint.url.query)
    XCTAssertFalse(endpoint.url.absoluteString.contains("development-key"))
  }

  func testEphemeralTokenUsesConstrainedMethodWithDocumentedQuery() throws {
    let endpoint = try GeminiLiveSpeechSession.endpoint(
      credential: .ephemeralToken("auth_tokens/short-lived")
    )
    XCTAssertTrue(
      endpoint.url.path.hasSuffix("GenerativeService.BidiGenerateContentConstrained")
    )
    XCTAssertTrue(endpoint.headers.isEmpty)
    XCTAssertEqual(
      URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)?.queryItems,
      [URLQueryItem(name: "access_token", value: "auth_tokens/short-lived")]
    )
  }

  func testPlaceholderCredentialsAreRejectedBeforeConnecting() {
    for placeholder in ["", "   ", "YOUR_GEMINI_API_KEY", "__GEMINI_API_KEY__"] {
      XCTAssertThrowsError(
        try GeminiLiveSpeechSession.endpoint(credential: .apiKey(placeholder))
      ) { error in
        guard case GeminiLiveSpeechError.missingCredential? = error as? GeminiLiveSpeechError
        else {
          return XCTFail("Expected missingCredential for \(placeholder.debugDescription)")
        }
      }
    }
  }

  func testConnectHandsTheResolvedEndpointToTheSocketFactory() async throws {
    let socket = MockGeminiLiveSocket()
    let capturedEndpoint = EndpointCapture()
    let session = GeminiLiveSpeechSession(
      mode: .transcribe,
      socketFactory: { endpoint in
        capturedEndpoint.record(endpoint)
        return socket
      }
    )
    try await socket.enqueueJSONObject(["setupComplete": [:]])
    try await session.connect(credential: .apiKey("development-key"))

    let endpoint = try XCTUnwrap(capturedEndpoint.value)
    XCTAssertEqual(endpoint.headers["x-goog-api-key"], "development-key")
    XCTAssertNil(endpoint.url.query)
    await session.cancel()
  }

  func testParserReadsIncrementalAndFinalServerEvents() throws {
    let data = Data(
      """
      {
        "serverContent": {
          "interimInputTranscription": {"text": "Hello"},
          "inputTranscription": {"text": "Hello world"},
          "outputTranscription": {"text": "Cześć świecie"},
          "generationComplete": true,
          "turnComplete": true
        }
      }
      """.utf8
    )

    XCTAssertEqual(
      try GeminiLiveSpeechSession.events(from: data),
      [
        .interimInput("Hello"),
        .finalInput("Hello world"),
        .finalOutput("Cześć świecie"),
        .generationComplete,
        .turnComplete,
      ]
    )
  }

  func testTranslationFinishRequiresGenerationCompleteAfterAudioStreamEnd() async throws {
    let socket = MockGeminiLiveSocket()
    try await socket.enqueueJSONObject(["setupComplete": [:]])
    let oldTranslationReceived = expectation(description: "older translation received")
    let session = GeminiLiveSpeechSession(
      mode: .translate(targetLanguageCode: "pl"),
      socketFactory: { _ in socket },
      progressHandler: { text in
        if text == "Starszy tekst." {
          oldTranslationReceived.fulfill()
        }
      }
    )

    try await session.connect(credential: .apiKey("development-key"))
    session.enqueueAudio(Data(repeating: 0x5A, count: 3_200))
    try await socket.enqueueJSONObject(
      [
        "serverContent": [
          "outputTranscription": ["text": "Starszy tekst."],
          "generationComplete": true,
          "turnComplete": true,
        ]
      ]
    )
    await fulfillment(of: [oldTranslationReceived], timeout: 1)

    let finishTask = Task { try await session.finish() }
    for _ in 0..<100 {
      if await socket.hasSentAudioStreamEnd() { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let sentAudioStreamEnd = await socket.hasSentAudioStreamEnd()
    XCTAssertTrue(sentAudioStreamEnd)

    // Give the old implementation time to incorrectly accept the completion
    // that arrived before audioStreamEnd.
    try await Task.sleep(nanoseconds: 100_000_000)
    try await socket.enqueueJSONObject(
      [
        "serverContent": [
          "outputTranscription": ["text": "Nowszy tekst."],
          "generationComplete": true,
          "turnComplete": true,
        ]
      ]
    )

    let result = try await finishTask.value
    XCTAssertEqual(result, "Starszy tekst. Nowszy tekst.")
  }

  func testFinishDrainsAudioAndUsesAuthoritativeFinalWithoutTurnComplete() async throws {
    let socket = MockGeminiLiveSocket()
    try await socket.enqueueJSONObject(["setupComplete": [:]])
    let session = GeminiLiveSpeechSession(
      mode: .transcribe,
      socketFactory: { _ in socket }
    )

    try await session.connect(credential: .apiKey("development-key"))
    session.enqueueAudio(Data(repeating: 0x5A, count: 3_200))

    let finishTask = Task { try await session.finish() }
    for _ in 0..<100 {
      if await socket.hasSentActivityEnd() { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let sentActivityEnd = await socket.hasSentActivityEnd()
    XCTAssertTrue(sentActivityEnd)

    try await socket.enqueueJSONObject(
      [
        "serverContent": [
          "inputTranscription": ["text": "A final transcript."]
        ]
      ]
    )

    let result = try await finishTask.value
    XCTAssertEqual(result, "A final transcript.")

    let messages = try await socket.sentJSONObjects()
    XCTAssertEqual(messages.count, 4)
    XCTAssertNotNil(messages[0]["setup"])
    XCTAssertNotNil(
      (messages[1]["realtimeInput"] as? [String: Any])?["activityStart"]
    )
    XCTAssertNotNil(
      (messages[2]["realtimeInput"] as? [String: Any])?["audio"]
    )
    XCTAssertNotNil(
      (messages[3]["realtimeInput"] as? [String: Any])?["activityEnd"]
    )
  }

  func testFinishWaitsForNewFinalWhenInterimFollowsAnEarlierFinal() async throws {
    let socket = MockGeminiLiveSocket()
    try await socket.enqueueJSONObject(["setupComplete": [:]])
    let firstFinalReceived = expectation(description: "first final received")
    let session = GeminiLiveSpeechSession(
      mode: .transcribe,
      socketFactory: { _ in socket },
      progressHandler: { text in
        if text == "First segment." {
          firstFinalReceived.fulfill()
        }
      }
    )

    try await session.connect(credential: .apiKey("development-key"))
    session.enqueueAudio(Data(repeating: 0x11, count: 3_200))
    for _ in 0..<100 {
      if await socket.sentAudioMessageCount() == 1 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let firstAudioMessageCount = await socket.sentAudioMessageCount()
    XCTAssertEqual(firstAudioMessageCount, 1)

    try await socket.enqueueJSONObject(
      ["serverContent": ["inputTranscription": ["text": "First segment."]]]
    )
    await fulfillment(of: [firstFinalReceived], timeout: 1)

    session.enqueueAudio(Data(repeating: 0x22, count: 3_200))
    try await socket.enqueueJSONObject(
      ["serverContent": ["interimInputTranscription": ["text": "Second"]]]
    )
    let finishTask = Task { try await session.finish() }
    for _ in 0..<100 {
      if await socket.hasSentActivityEnd() { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let sentActivityEnd = await socket.hasSentActivityEnd()
    XCTAssertTrue(sentActivityEnd)

    // The newer interim proves that a later speech segment is not final.
    try await Task.sleep(nanoseconds: 500_000_000)
    let prematureCloseCode = await socket.closeCode
    XCTAssertNil(prematureCloseCode)

    try await socket.enqueueJSONObject(
      ["serverContent": ["inputTranscription": ["text": "Second segment."]]]
    )
    let result = try await finishTask.value
    XCTAssertEqual(result, "First segment. Second segment.")
  }

  func testFinishAcceptsFinalBeforeTrailingSilenceWithoutDuplicateEvent() async throws {
    let socket = MockGeminiLiveSocket()
    try await socket.enqueueJSONObject(["setupComplete": [:]])
    let finalReceived = expectation(description: "final received")
    let session = GeminiLiveSpeechSession(
      mode: .transcribe,
      socketFactory: { _ in socket },
      progressHandler: { text in
        if text == "Already finalized." {
          finalReceived.fulfill()
        }
      }
    )

    try await session.connect(credential: .apiKey("development-key"))
    session.enqueueAudio(Data(repeating: 0x33, count: 3_200))
    for _ in 0..<100 {
      if await socket.sentAudioMessageCount() == 1 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let audioMessageCount = await socket.sentAudioMessageCount()
    XCTAssertEqual(audioMessageCount, 1)

    try await socket.enqueueJSONObject(
      ["serverContent": ["inputTranscription": ["text": "Already finalized."]]]
    )
    await fulfillment(of: [finalReceived], timeout: 1)

    // Microphone capture keeps producing PCM during trailing silence. That
    // must not invalidate an authoritative finalized speech segment.
    session.enqueueAudio(Data(repeating: 0x00, count: 3_200))
    for _ in 0..<100 {
      if await socket.sentAudioMessageCount() == 2 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let audioMessageCountAfterSilence = await socket.sentAudioMessageCount()
    XCTAssertEqual(audioMessageCountAfterSilence, 2)

    // Establish the local quiet interval before Finish. The server does not
    // need to duplicate an already authoritative final after pure silence.
    try await Task.sleep(nanoseconds: 850_000_000)

    let finishTask = Task { try await session.finish() }

    // The established quiet interval lets the authoritative final complete
    // without a duplicate server event.
    let result = try await finishTask.value
    XCTAssertEqual(result, "Already finalized.")
    let sentActivityEnd = await socket.hasSentActivityEnd()
    XCTAssertTrue(sentActivityEnd)
  }

  func testFinishDoesNotDropSpeechAfterAnEarlierFinalWhenInterimIsLate() async throws {
    let socket = MockGeminiLiveSocket()
    try await socket.enqueueJSONObject(["setupComplete": [:]])
    let firstFinalReceived = expectation(description: "first final received")
    let session = GeminiLiveSpeechSession(
      mode: .transcribe,
      socketFactory: { _ in socket },
      progressHandler: { text in
        if text == "First part." {
          firstFinalReceived.fulfill()
        }
      }
    )

    try await session.connect(credential: .apiKey("development-key"))
    session.enqueueAudio(Data(repeating: 0x11, count: 3_200))
    for _ in 0..<100 {
      if await socket.sentAudioMessageCount() == 1 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let firstAudioMessageCount = await socket.sentAudioMessageCount()
    XCTAssertEqual(firstAudioMessageCount, 1)
    // The user speaks the final phrase before a delayed final for only the
    // first phrase arrives. Arrival order must not make that stale event
    // look as though it covers the tail audio.
    session.enqueueAudio(Data(repeating: 0x22, count: 3_200))
    for _ in 0..<100 {
      if await socket.sentAudioMessageCount() == 2 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    try await socket.enqueueJSONObject(
      ["serverContent": ["inputTranscription": ["text": "First part."]]]
    )
    await fulfillment(of: [firstFinalReceived], timeout: 1)

    let finishTask = Task { try await session.finish() }
    for _ in 0..<100 {
      if await socket.hasSentActivityEnd() { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let sentActivityEnd = await socket.hasSentActivityEnd()
    XCTAssertTrue(sentActivityEnd)

    // This is deliberately beyond the old 1.5-second acceptance threshold.
    // The pre-boundary final must never win merely because time elapsed.
    try await Task.sleep(nanoseconds: 1_700_000_000)
    let prematureCloseCode = await socket.closeCode
    XCTAssertNil(prematureCloseCode)

    try await socket.enqueueJSONObject(
      ["serverContent": ["inputTranscription": ["text": "Last words."]]]
    )
    let result = try await finishTask.value
    XCTAssertEqual(result, "First part. Last words.")
  }

  func testLikelySpeechClassifierUsesTheWaveformSilenceFloor() {
    XCTAssertFalse(
      GeminiLiveSpeechSession.containsLikelySpeech(
        Data(repeating: 0, count: 3_200)
      )
    )
    XCTAssertTrue(
      GeminiLiveSpeechSession.containsLikelySpeech(
        Data(repeating: 0x11, count: 3_200)
      )
    )
  }

  func testTranscriptMergeHandlesCumulativeAndSegmentedUpdates() {
    XCTAssertEqual(
      GeminiLiveSpeechSession.mergedTranscript(
        existing: "Hello",
        update: "Hello world"
      ),
      "Hello world"
    )
    XCTAssertEqual(
      GeminiLiveSpeechSession.mergedTranscript(
        existing: "Hello world.",
        update: "Next sentence."
      ),
      "Hello world. Next sentence."
    )
  }
}
