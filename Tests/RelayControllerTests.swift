import UIKit
import XCTest

@testable import GeminiVoice

/// Answers every request with a completed Interactions response so the OCR
/// path can run end to end without touching the network.
private final class StubOCRURLProtocol: URLProtocol {
  static let extractedText = "Hello from OCR"

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let body: [String: Any] = [
      "status": "completed",
      "steps": [
        [
          "type": "model_output",
          "content": [["type": "text", "text": Self.extractedText]],
        ]
      ],
    ]
    let data = try! JSONSerialization.data(withJSONObject: body)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@MainActor
final class RelayControllerTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var directoryURL: URL!

  func testIdleDeadlineTracksSchedulingSuspensionAndStop() throws {
    let (controller, _) = try makeController()
    controller.isRelayRunning = true
    controller.status = .idle
    controller.scheduleIdleShutdownIfEligible()
    let deadline = try XCTUnwrap(controller.idleShutdownDeadline)
    XCTAssertEqual(deadline.timeIntervalSinceNow, 120, accuracy: 1)

    controller.markRelayActivityAndSuspendIdleShutdown()
    XCTAssertNil(controller.idleShutdownDeadline)
    controller.scheduleIdleShutdownIfEligible()
    XCTAssertNotNil(controller.idleShutdownDeadline)
    controller.stopRelay()
    XCTAssertNil(controller.idleShutdownDeadline)

    controller.isRelayRunning = true
    controller.status = .recording
    controller.scheduleIdleShutdownIfEligible()
    XCTAssertNil(controller.idleShutdownDeadline)
    controller.isRelayRunning = false
  }

  func testMaximumDictationDurationIsFiveMinutes() {
    XCTAssertEqual(RelayController.maximumDictationDuration, 5 * 60)
  }

  func testNoteSavesDurablyWithoutPublishingAKeyboardInsertion() throws {
    let (controller, store) = try makeController()
    let originalResult = store.snapshot().resultSequence
    let item = try controller.completeTranscription(
      "Remember to take the scenic route.", requestID: UUID().uuidString, action: .note
    )
    XCTAssertEqual(controller.noteCapturePhase, .saved(item))
    XCTAssertEqual(controller.history.first, item)
    XCTAssertEqual(TranscriptHistoryStore(directoryURL: directoryURL.appendingPathComponent("AppData")).items, [item])
    XCTAssertEqual(store.snapshot().resultSequence, originalResult)
    XCTAssertNil(store.snapshot().transcript)
  }

  func testNoteRetrySavesTextWithoutPublishingAKeyboardInsertion() async throws {
    let (controller, store) = try makeController()
    let requestID = UUID().uuidString
    let url = directoryURL.appendingPathComponent("Recordings/completed-note-en-\(requestID).wav")
    try Data([0, 1, 2, 3]).write(to: url)
    let recording = try controller.recoveryStore.stage(
      CapturedAudioSegment(requestID: requestID, url: url, startedAt: Date().addingTimeInterval(-2), endedAt: Date()),
      action: .note, translationTargetCode: "en"
    )
    XCTAssertEqual(recording.actionTitle, "Voice note")
    let reloaded = RecoverableRecordingStore(directoryURL: directoryURL.appendingPathComponent("Recordings"))
    XCTAssertEqual(reloaded.recordings.first?.action, .note)
    controller.retryRecording(recording)
    for _ in 0..<100 where controller.retryingRecordingID != nil {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertNil(controller.retryingRecordingID)
    XCTAssertEqual(controller.history.first?.text, StubOCRURLProtocol.extractedText)
    XCTAssertTrue(controller.recoveryStore.recordings.isEmpty)
    XCTAssertNil(store.snapshot().transcript)
  }

  func testHistoryRetentionDefaultsToThirtyDaysAndPersistsChanges() throws {
    let (controller, _) = try makeController()
    XCTAssertEqual(controller.configuration.historyRetentionDays, 30)
    try controller.historyStore.add(text: "Old note", createdAt: Date().addingTimeInterval(-10 * 86_400))
    try controller.historyStore.add(text: "New note")
    controller.configuration.historyRetentionDays = 7
    controller.applyHistoryRetention()
    XCTAssertEqual(controller.history.map(\.text), ["New note"])
    XCTAssertEqual(AppConfiguration(defaults: defaults).historyRetentionDays, 7)
  }

  func testCancelCommandStopsProcessingAndDeletesStagedRecording() throws {
    let (controller, store) = try makeController()
    let requestID = UUID().uuidString
    let recordingURL = directoryURL
      .appendingPathComponent("Recordings", isDirectory: true)
      .appendingPathComponent("completed-transcribe-en-\(requestID).wav")
    try FileManager.default.createDirectory(
      at: recordingURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data([0, 1, 2, 3]).write(to: recordingURL)
    let recording = try controller.recoveryStore.stage(
      CapturedAudioSegment(
        requestID: requestID,
        url: recordingURL,
        startedAt: Date().addingTimeInterval(-2),
        endedAt: Date()
      ),
      action: .transcribe,
      translationTargetCode: "en"
    )

    controller.isRelayRunning = true
    controller.processingRequestID = requestID
    controller.processingRecordingID = recording.id
    controller.transcriptionTask = Task {
      try? await Task.sleep(nanoseconds: 30_000_000_000)
    }
    controller.publish(
      .transcribing,
      message: "Finalizing live transcript…",
      activeRequestID: requestID,
      activeDictationAction: .transcribe
    )

    controller.handle(
      RelayCommandEnvelope(
        sequence: 1,
        command: .cancel,
        requestID: requestID,
        dictationAction: .transcribe,
        createdAt: Date()
      )
    )

    XCTAssertNil(controller.transcriptionTask)
    XCTAssertNil(controller.processingRequestID)
    XCTAssertNil(controller.processingRecordingID)
    XCTAssertTrue(controller.recoveryStore.recordings.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: recordingURL.path))
    XCTAssertEqual(store.snapshot().status, .idle)
    XCTAssertNil(store.snapshot().transcript)
  }

  override func setUpWithError() throws {
    try super.setUpWithError()
    suiteName = "GeminiVoiceRelayControllerTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: directoryURL)
    try super.tearDownWithError()
  }

  private func makeController() throws -> (RelayController, SharedRelayStore) {
    let bundleURL = directoryURL.appendingPathComponent("TestConfiguration.bundle")
    try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
    let bundleInfo = try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundleIdentifier": "com.example.GeminiVoiceSample.TestConfiguration",
        "GeminiDefaultAPIKey": "test-api-key",
      ],
      format: .xml,
      options: 0
    )
    try bundleInfo.write(to: bundleURL.appendingPathComponent("Info.plist"), options: .atomic)
    let configuration = AppConfiguration(
      defaults: defaults,
      bundle: try XCTUnwrap(Bundle(url: bundleURL))
    )
    let store = SharedRelayStore(defaults: defaults)
    store.resetForTesting()

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubOCRURLProtocol.self]
    let controller = RelayController(
      configuration: configuration,
      store: store,
      client: GeminiTranscriptionClient(session: URLSession(configuration: sessionConfiguration)),
      recoveryStore: RecoverableRecordingStore(
        directoryURL: directoryURL.appendingPathComponent("Recordings", isDirectory: true)
      ),
      historyStore: TranscriptHistoryStore(
        directoryURL: directoryURL.appendingPathComponent("AppData", isDirectory: true)
      )
    )
    return (controller, store)
  }

  func testOCRResultIsPersistedToHistoryAndSurvivesTheNextDictation() async throws {
    let (controller, store) = try makeController()
    let requestID = UUID().uuidString
    controller.startOCRCapture(preferCamera: false, requestID: requestID)
    XCTAssertTrue(controller.isImagePickerPresented)

    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    controller.imagePickerDidSelect(image)
    XCTAssertTrue(controller.isProcessingImage)

    for _ in 0..<100 where controller.isProcessingImage {
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertFalse(controller.isProcessingImage, controller.ocrMessage)

    let snapshot = store.snapshot()
    XCTAssertEqual(snapshot.transcript, StubOCRURLProtocol.extractedText)
    XCTAssertEqual(snapshot.resultRequestID, requestID)
    XCTAssertEqual(snapshot.resultKind, .ocr)

    XCTAssertEqual(controller.historyStore.items.first?.text, StubOCRURLProtocol.extractedText)
    XCTAssertEqual(controller.history.first?.text, StubOCRURLProtocol.extractedText)

    // A later dictation reloads the published list from the store. The OCR
    // entry must remain instead of being dropped as in-memory-only state.
    try controller.addToHistory("A later dictation")
    XCTAssertEqual(
      controller.history.map(\.text),
      ["A later dictation", StubOCRURLProtocol.extractedText]
    )

    let reloaded = TranscriptHistoryStore(
      directoryURL: directoryURL.appendingPathComponent("AppData", isDirectory: true)
    )
    XCTAssertEqual(
      reloaded.items.map(\.text),
      ["A later dictation", StubOCRURLProtocol.extractedText]
    )
  }

  #if GEMINI_PERSONAL_DEVICE
    func testManualReturnGuidanceIsNotReArmedByPolling() throws {
      let (controller, store) = try makeController()
      defer { controller.cancelAutomaticReturnToKeyboard() }

      let request = RelayLaunchRequest(
        requestID: UUID().uuidString,
        dictationAction: .transcribe,
        createdAt: Date(),
        originatingApplicationBundleIdentifier: "com.example.host"
      )
      XCTAssertTrue(store.authorizeLaunchRequest(request))
      // Mirror applicationDidBecomeActive: the controller holds the copy read
      // back from the store, whose timestamp went through a plist round trip.
      controller.pendingLaunchRequest = try XCTUnwrap(store.pendingLaunchRequest())
      controller.isRelayRunning = true
      controller.setLocalStatus(.idle, message: "Ready")

      // The bounded automatic return already gave up for this request.
      controller.requiresManualKeyboardReturn = true
      controller.preparePendingLaunchHandoffIfNeeded()
      XCTAssertTrue(controller.requiresManualKeyboardReturn)
      XCTAssertNil(controller.pendingHostReturn)
      XCTAssertTrue(controller.isKeyboardHandoffActive)
      XCTAssertNotNil(store.pendingLaunchRequest(), "The authorization must stay claimable")

      // A fresh activation clears the flag and gets a new bounded attempt.
      controller.requiresManualKeyboardReturn = false
      controller.preparePendingLaunchHandoffIfNeeded()
      XCTAssertEqual(
        controller.pendingHostReturn,
        RelayController.PendingHostReturn(
          requestID: request.requestID,
          bundleIdentifier: "com.example.host"
        )
      )
      XCTAssertEqual(controller.hostReturnAttemptCount, 0)
    }
  #endif
}
