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

/// Supplies an embedded Debug credential without reading the host Keychain.
private final class StubConfigurationBundle: Bundle, @unchecked Sendable {
  override func object(forInfoDictionaryKey key: String) -> Any? {
    key == "GeminiDefaultAPIKey" ? "test-api-key" : nil
  }
}

@MainActor
final class RelayControllerTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var directoryURL: URL!

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
    let configuration = AppConfiguration(
      defaults: defaults,
      bundle: try XCTUnwrap(StubConfigurationBundle(path: Bundle.main.bundlePath))
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
