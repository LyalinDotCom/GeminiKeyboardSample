import Foundation
import XCTest

@testable import GeminiVoice

final class RelayProtocolTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var store: SharedRelayStore!

  override func setUp() {
    super.setUp()
    suiteName = "GeminiVoiceTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    store = SharedRelayStore(defaults: defaults)
    store.resetForTesting()
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    store = nil
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testCommandSequenceActsAsCommitMarker() {
    XCTAssertNil(store.pendingCommand(after: 0))

    let date = Date(timeIntervalSince1970: 1_234)
    let sequence = store.issue(
      .start,
      requestID: "request-1",
      dictationAction: .translate,
      at: date
    )
    let command = store.pendingCommand(after: 0)

    XCTAssertEqual(sequence, 1)
    XCTAssertEqual(command?.sequence, 1)
    XCTAssertEqual(command?.command, .start)
    XCTAssertEqual(command?.requestID, "request-1")
    XCTAssertEqual(command?.dictationAction, .translate)
    XCTAssertEqual(command?.createdAt, date)
    XCTAssertNil(store.pendingCommand(after: 1))
  }

  func testCancelCommandPreservesRequestAndTranslationAction() {
    let date = Date(timeIntervalSince1970: 4_321)
    let sequence = store.issue(
      .cancel,
      requestID: "translation-request",
      dictationAction: .translate,
      at: date
    )
    let command = store.pendingCommand(after: 0)

    XCTAssertEqual(sequence, 1)
    XCTAssertEqual(command?.command, .cancel)
    XCTAssertEqual(command?.requestID, "translation-request")
    XCTAssertEqual(command?.dictationAction, .translate)
    XCTAssertEqual(command?.createdAt, date)
  }

  func testLiveActivityControlsUseDistinctNonSendingCommands() {
    let recordingID = UUID().uuidString
    let relaySessionID = UUID().uuidString
    var sequence = store.issue(
      .cancelRecordingFromLiveActivity,
      requestID: recordingID,
      dictationAction: .transcribe
    )
    var command = store.pendingCommand(after: 0)

    XCTAssertEqual(sequence, 1)
    XCTAssertEqual(command?.command, .cancelRecordingFromLiveActivity)
    XCTAssertNotEqual(command?.command, .stop)

    sequence = store.issue(
      .shutdownRelayFromLiveActivity,
      requestID: relaySessionID,
      dictationAction: .transcribe
    )
    command = store.pendingCommand(after: 1)

    XCTAssertEqual(sequence, 2)
    XCTAssertEqual(command?.command, .shutdownRelayFromLiveActivity)
    XCTAssertNotEqual(command?.command, .stop)
  }

  func testAudioLevelIsClampedAndResetOutsideRecording() {
    store.publishStatus(
      .recording,
      message: "Listening",
      activeRequestID: "active-request",
      activeDictationAction: .transcribe,
      recordingStartedAt: Date()
    )
    store.publishAudioLevel(1.8, requestID: "active-request")

    var snapshot = store.snapshot()
    XCTAssertEqual(snapshot.audioLevel, 1, accuracy: 0.0001)
    XCTAssertNotNil(snapshot.audioLevelUpdatedAt)

    store.publishAudioLevel(0.2, requestID: "different-request")
    snapshot = store.snapshot()
    XCTAssertEqual(snapshot.audioLevel, 1, accuracy: 0.0001)

    store.publishStatus(.idle, message: "Ready")
    snapshot = store.snapshot()
    XCTAssertEqual(snapshot.audioLevel, 0, accuracy: 0.0001)
    XCTAssertNil(snapshot.audioLevelUpdatedAt)
  }

  func testOfflineReasonIsStructuredAndClearedWhenRelayReturnsOnline() {
    store.publishStatus(
      .offline,
      message: "Relay paused after 2 minutes — tap Dictate to restart",
      offlineReason: .idleTimeout
    )
    XCTAssertEqual(store.snapshot().offlineReason, .idleTimeout)

    store.publishStatus(.idle, message: "Ready")
    XCTAssertNil(store.snapshot().offlineReason)
  }

  func testCancelSupersedesAnUnconsumedStartForTheSameRequest() {
    store.issue(
      .start,
      requestID: "quick-cancel",
      dictationAction: .transcribe
    )
    let sequence = store.issue(
      .cancel,
      requestID: "quick-cancel",
      dictationAction: .transcribe
    )
    let command = store.pendingCommand(after: 0)

    XCTAssertEqual(sequence, 2)
    XCTAssertEqual(command?.sequence, 2)
    XCTAssertEqual(command?.command, .cancel)
    XCTAssertEqual(command?.requestID, "quick-cancel")
  }

  func testPendingCancelCannotBeOverwrittenByFinishForSameRecording() {
    let requestID = UUID().uuidString
    let cancelSequence = store.issue(
      .cancelRecordingFromLiveActivity,
      requestID: requestID,
      dictationAction: .translate
    )
    let finishSequence = store.issue(
      .stop,
      requestID: requestID,
      dictationAction: .translate
    )
    let command = store.pendingCommand(after: 0)

    XCTAssertEqual(cancelSequence, 1)
    XCTAssertEqual(finishSequence, cancelSequence)
    XCTAssertEqual(command?.command, .cancelRecordingFromLiveActivity)
    XCTAssertEqual(command?.requestID, requestID)
  }

  func testConcurrentCommandIssuanceProducesUniqueSequences() {
    let issueCount = 40
    let resultLock = NSLock()
    var sequences: [Int] = []

    DispatchQueue.concurrentPerform(iterations: issueCount) { index in
      let sequence = store.issue(
        .start,
        requestID: "request-\(index)",
        dictationAction: .transcribe
      )
      resultLock.lock()
      sequences.append(sequence)
      resultLock.unlock()
    }

    XCTAssertEqual(Set(sequences).count, issueCount)
    XCTAssertEqual(sequences.min(), 1)
    XCTAssertEqual(sequences.max(), issueCount)
  }

  func testLaunchRequestURLRoundTrip() throws {
    let createdAt = Date(timeIntervalSince1970: 1_750_000_000.125)
    let request = RelayLaunchRequest(
      requestID: "F86B6228-7B53-4D7D-9DB2-39B09C463776",
      dictationAction: .translate,
      createdAt: createdAt,
      originatingApplicationBundleIdentifier: "com.example.Host"
    )

    let url = try XCTUnwrap(request.makeURL())
    let decoded = RelayLaunchRequest.parse(
      url,
      now: createdAt.addingTimeInterval(29)
    )

    XCTAssertEqual(url.scheme, "geminivoice")
    XCTAssertEqual(url.host, "dictate")
    XCTAssertEqual(decoded, request)
  }

  func testOriginatingApplicationBundleIdentifierValidationRejectsGuesses() {
    XCTAssertTrue(
      RelayLaunchRequest.isValidBundleIdentifier("com.example.Host")
    )
    XCTAssertFalse(RelayLaunchRequest.isValidBundleIdentifier("Messages"))
    XCTAssertFalse(RelayLaunchRequest.isValidBundleIdentifier(".com.example.Host"))
    XCTAssertFalse(RelayLaunchRequest.isValidBundleIdentifier("com.example.Host/unsafe"))
  }

  func testHostReturnPolicyNeverInventsAMissingDestination() {
    XCTAssertEqual(
      RelayHostReturnPolicy.decision(
        originatingApplicationBundleIdentifier: nil,
        containingApplicationBundleIdentifier: "com.example.GeminiVoice"
      ),
      .manual
    )
    XCTAssertEqual(
      RelayHostReturnPolicy.decision(
        originatingApplicationBundleIdentifier: "com.example.GeminiVoice",
        containingApplicationBundleIdentifier: "com.example.GeminiVoice"
      ),
      .manual
    )
    XCTAssertEqual(
      RelayHostReturnPolicy.decision(
        originatingApplicationBundleIdentifier: "com.example.Notes",
        containingApplicationBundleIdentifier: "com.example.GeminiVoice"
      ),
      .automatic(bundleIdentifier: "com.example.Notes")
    )
  }

  #if GEMINI_PERSONAL_DEVICE
    func testPersonalDeviceMessagesFallbackRequiresExactProcessName() {
      XCTAssertEqual(
        PersonalDeviceHostFallback.destination(
          resolvedBundleIdentifier: nil,
          hostProcessName: "MobileSMS"
        ),
        PersonalDeviceHostFallback.messagesBundleIdentifier
      )
      for untrustedProcessName in [nil, "", "Messages", "MobileSafari", "MobileSMSHelper"] {
        XCTAssertNil(
          PersonalDeviceHostFallback.destination(
            resolvedBundleIdentifier: nil,
            hostProcessName: untrustedProcessName
          )
        )
      }
      XCTAssertTrue(
        RelayLaunchRequest.isValidBundleIdentifier(
          PersonalDeviceHostFallback.messagesBundleIdentifier
        )
      )
    }

    func testPersonalDeviceExactHostWinsWithoutMessagesFallback() {
      XCTAssertEqual(
        PersonalDeviceHostFallback.destination(
          resolvedBundleIdentifier: "com.example.Notes",
          hostProcessName: "MobileSMS"
        ),
        "com.example.Notes"
      )
      XCTAssertNil(
        PersonalDeviceHostFallback.destination(
          resolvedBundleIdentifier: "not-a-bundle",
          hostProcessName: nil
        )
      )
    }

    func testPersonalDeviceArbiterRequiresExactCapturedHostProcess() {
      XCTAssertEqual(
        PersonalDeviceHostFallback.exactArbiterDestination(
          capturedHostProcessIdentifier: 321,
          observedProcessIdentifier: 321,
          sourceBundleIdentifier: "com.example.Notes"
        ),
        "com.example.Notes"
      )
      XCTAssertNil(
        PersonalDeviceHostFallback.exactArbiterDestination(
          capturedHostProcessIdentifier: 321,
          observedProcessIdentifier: 654,
          sourceBundleIdentifier: "com.apple.MobileSMS"
        )
      )
      XCTAssertNil(
        PersonalDeviceHostFallback.exactArbiterDestination(
          capturedHostProcessIdentifier: 0,
          observedProcessIdentifier: 0,
          sourceBundleIdentifier: "com.apple.MobileSMS"
        )
      )
      XCTAssertNil(
        PersonalDeviceHostFallback.exactArbiterDestination(
          capturedHostProcessIdentifier: 321,
          observedProcessIdentifier: 321,
          sourceBundleIdentifier: "not-a-bundle"
        )
      )
    }
  #endif

  func testLaunchRequestRequiresCanonicalUUIDID() throws {
    let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
    let uppercaseID = "F86B6228-7B53-4D7D-9DB2-39B09C463776"
    let lowercaseID = uppercaseID.lowercased()

    let uppercase = RelayLaunchRequest(
      requestID: uppercaseID,
      dictationAction: .transcribe,
      createdAt: createdAt
    )
    let lowercase = RelayLaunchRequest(
      requestID: lowercaseID,
      dictationAction: .transcribe,
      createdAt: createdAt
    )

    XCTAssertNotNil(uppercase.makeURL())
    XCTAssertNotNil(lowercase.makeURL())
    XCTAssertEqual(
      RelayLaunchRequest.parse(
        try XCTUnwrap(lowercase.makeURL()),
        now: createdAt
      ),
      lowercase
    )

    for invalidID in [
      "request-1",
      "F86B62287B534D7D9DB239B09C463776",
      "{F86B6228-7B53-4D7D-9DB2-39B09C463776}",
      " F86B6228-7B53-4D7D-9DB2-39B09C463776",
    ] {
      XCTAssertNil(
        RelayLaunchRequest(
          requestID: invalidID,
          dictationAction: .transcribe,
          createdAt: createdAt
        ).makeURL(),
        invalidID
      )
    }
  }

  func testLaunchRequestRejectsMalformedURLs() throws {
    let timestamp = "1750000000"
    let requestID = "F86B6228-7B53-4D7D-9DB2-39B09C463776"
    let malformedURLs = [
      "other://dictate?requestID=\(requestID)&action=transcribe&createdAt=\(timestamp)",
      "geminivoice://other?requestID=\(requestID)&action=transcribe&createdAt=\(timestamp)",
      "geminivoice://dictate",
      "geminivoice://dictate?requestID=&action=transcribe&createdAt=\(timestamp)",
      "geminivoice://dictate?requestID=request-1&action=transcribe&createdAt=\(timestamp)",
      "geminivoice://dictate?requestID=\(requestID)&action=unknown&createdAt=\(timestamp)",
      "geminivoice://dictate?requestID=\(requestID)&action=transcribe&createdAt=not-a-date",
      "geminivoice://dictate?requestID=\(requestID)&action=transcribe&createdAt=\(timestamp)&extra=value",
      "geminivoice://dictate?requestID=\(requestID)&action=transcribe&createdAt=\(timestamp)&originBundleID=not%20a%20bundle",
      "geminivoice://dictate?requestID=\(requestID)&action=transcribe&action=translate",
    ]
    let now = Date(timeIntervalSince1970: 1_750_000_001)

    for rawURL in malformedURLs {
      let url = try XCTUnwrap(URL(string: rawURL), rawURL)
      XCTAssertNil(RelayLaunchRequest.parse(url, now: now), rawURL)
    }
  }

  func testLaunchRequestRejectsExpiredAndFutureRequests() throws {
    let now = Date(timeIntervalSince1970: 1_750_000_100)
    let boundaryRequest = RelayLaunchRequest(
      requestID: "9C9C43B8-A961-41C5-902B-103FA938D1B5",
      dictationAction: .transcribe,
      createdAt: now.addingTimeInterval(-30)
    )
    let expiredRequest = RelayLaunchRequest(
      requestID: "6B2C8B51-41A5-4E24-9A58-879F6D5054AE",
      dictationAction: .transcribe,
      createdAt: now.addingTimeInterval(-31)
    )
    let futureRequest = RelayLaunchRequest(
      requestID: "086790F4-FC7A-4C18-BA76-AC281A4507D8",
      dictationAction: .transcribe,
      createdAt: now.addingTimeInterval(1)
    )

    XCTAssertEqual(
      RelayLaunchRequest.parse(try XCTUnwrap(boundaryRequest.makeURL()), now: now),
      boundaryRequest
    )
    XCTAssertNil(
      RelayLaunchRequest.parse(try XCTUnwrap(expiredRequest.makeURL()), now: now)
    )
    XCTAssertNil(
      RelayLaunchRequest.parse(try XCTUnwrap(futureRequest.makeURL()), now: now)
    )
    XCTAssertEqual(
      RelayLaunchRequest.parse(
        try XCTUnwrap(expiredRequest.makeURL()),
        now: now,
        maximumAge: 31
      ),
      expiredRequest
    )
  }

  func testPendingLaunchRequestCanBePeekedWithoutConsumption() {
    let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
    let request = RelayLaunchRequest(
      requestID: "F86B6228-7B53-4D7D-9DB2-39B09C463776",
      dictationAction: .translate,
      createdAt: createdAt,
      originatingApplicationBundleIdentifier: "com.example.Host"
    )

    XCTAssertTrue(store.authorizeLaunchRequest(request))
    XCTAssertEqual(
      store.pendingLaunchRequest(now: createdAt.addingTimeInterval(29)),
      request
    )
    XCTAssertEqual(
      store.pendingLaunchRequest(now: createdAt.addingTimeInterval(29)),
      request
    )
  }

  func testMismatchedClaimDoesNotConsumePendingLaunchRequest() {
    let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
    let request = RelayLaunchRequest(
      requestID: "F86B6228-7B53-4D7D-9DB2-39B09C463776",
      dictationAction: .translate,
      createdAt: createdAt
    )
    let wrongRequest = RelayLaunchRequest(
      requestID: "9C9C43B8-A961-41C5-902B-103FA938D1B5",
      dictationAction: .translate,
      createdAt: createdAt
    )

    XCTAssertTrue(store.authorizeLaunchRequest(request))
    XCTAssertNil(
      store.claimPendingLaunchRequest(
        matching: wrongRequest,
        now: createdAt.addingTimeInterval(1)
      )
    )
    XCTAssertEqual(
      store.pendingLaunchRequest(now: createdAt.addingTimeInterval(1)),
      request
    )
    XCTAssertEqual(
      store.claimPendingLaunchRequest(
        matching: request,
        now: createdAt.addingTimeInterval(29)
      ),
      request
    )
  }

  func testPendingLaunchRequestCanOnlyBeClaimedOnce() {
    let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
    let request = RelayLaunchRequest(
      requestID: "F86B6228-7B53-4D7D-9DB2-39B09C463776",
      dictationAction: .transcribe,
      createdAt: createdAt
    )

    XCTAssertTrue(store.authorizeLaunchRequest(request))
    XCTAssertEqual(
      store.claimPendingLaunchRequest(now: createdAt.addingTimeInterval(1)),
      request
    )
    XCTAssertNil(
      store.claimPendingLaunchRequest(now: createdAt.addingTimeInterval(1))
    )
  }

  func testExpiredPendingLaunchRequestIsCleared() {
    let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
    let request = RelayLaunchRequest(
      requestID: "F86B6228-7B53-4D7D-9DB2-39B09C463776",
      dictationAction: .transcribe,
      createdAt: createdAt
    )

    XCTAssertTrue(store.authorizeLaunchRequest(request))
    XCTAssertNil(
      store.pendingLaunchRequest(now: createdAt.addingTimeInterval(31))
    )
    XCTAssertNil(defaults.object(forKey: "relay.launch.pending-request"))
  }

  func testMalformedPendingLaunchRequestIsCleared() {
    defaults.set(Data("not a property list".utf8), forKey: "relay.launch.pending-request")

    XCTAssertNil(store.pendingLaunchRequest())
    XCTAssertNil(defaults.object(forKey: "relay.launch.pending-request"))
  }

  func testDeferredStartRequiresReturnedAttachedKeyboardAndMatchingRelay() {
    let now = Date(timeIntervalSince1970: 1_750_000_010)
    let request = RelayLaunchRequest(
      requestID: "F86B6228-7B53-4D7D-9DB2-39B09C463776",
      dictationAction: .transcribe,
      createdAt: now.addingTimeInterval(-1),
      originatingApplicationBundleIdentifier: "com.example.Host"
    )
    store.publishStatus(.idle, message: "Ready", heartbeat: now)
    let snapshot = store.snapshot()

    let canStart: (Bool, Bool, Bool, RelayLaunchRequest?, Date) -> Bool = {
      visible, attached, alreadyIssued, pending, evaluationDate in
      RelayKeyboardStartGate.canIssueStart(
        requestID: request.requestID,
        action: request.dictationAction,
        createdAt: request.createdAt,
        pendingLaunchRequest: pending,
        snapshot: snapshot,
        keyboardIsVisible: visible,
        keyboardIsAttached: attached,
        startAlreadyIssued: alreadyIssued,
        now: evaluationDate
      )
    }

    XCTAssertTrue(canStart(true, true, false, request, now))
    XCTAssertFalse(canStart(false, true, false, request, now))
    XCTAssertFalse(canStart(true, false, false, request, now))
    XCTAssertFalse(canStart(true, true, true, request, now))
    XCTAssertFalse(canStart(true, true, false, nil, now))
    XCTAssertFalse(
      canStart(
        true,
        true,
        false,
        RelayLaunchRequest(
          requestID: UUID().uuidString,
          dictationAction: .transcribe,
          createdAt: request.createdAt
        ),
        now
      )
    )
    XCTAssertFalse(canStart(true, true, false, request, now.addingTimeInterval(31)))
  }

  func testColdStartAuthorizationCannotFallBackToWarmAfterCancelRace() {
    let request = RelayLaunchRequest(
      requestID: "F86B6228-7B53-4D7D-9DB2-39B09C463776",
      dictationAction: .translate,
      createdAt: Date(timeIntervalSince1970: 1_750_000_000)
    )
    let command = RelayCommandEnvelope(
      sequence: 1,
      command: .start,
      requestID: request.requestID,
      dictationAction: .translate,
      createdAt: request.createdAt
    )

    XCTAssertEqual(
      RelayStartAuthorizationPolicy.resolve(
        command: command,
        loadedPendingLaunch: nil,
        storedPendingLaunch: nil
      ),
      .warm
    )
    XCTAssertEqual(
      RelayStartAuthorizationPolicy.resolve(
        command: command,
        loadedPendingLaunch: request,
        storedPendingLaunch: request
      ),
      .pendingLaunch(request)
    )
    XCTAssertEqual(
      RelayStartAuthorizationPolicy.resolve(
        command: command,
        loadedPendingLaunch: request,
        storedPendingLaunch: nil
      ),
      .reject,
      "Cleared authorization means Cancel or expiry won; stale Start must not record"
    )

    let retryCommand = RelayCommandEnvelope(
      sequence: 2,
      command: .start,
      requestID: UUID().uuidString,
      dictationAction: .transcribe,
      createdAt: request.createdAt.addingTimeInterval(1)
    )
    XCTAssertEqual(
      RelayStartAuthorizationPolicy.resolve(
        command: retryCommand,
        loadedPendingLaunch: request,
        storedPendingLaunch: nil
      ),
      .warm,
      "A distinct request remains a valid warm retry after cancelling the stale launch"
    )

    let wrongAction = RelayLaunchRequest(
      requestID: request.requestID,
      dictationAction: .transcribe,
      createdAt: request.createdAt
    )
    XCTAssertEqual(
      RelayStartAuthorizationPolicy.resolve(
        command: command,
        loadedPendingLaunch: request,
        storedPendingLaunch: wrongAction
      ),
      .reject
    )
  }

  func testStatusAndTranscriptRoundTrip() {
    let now = Date(timeIntervalSince1970: 9_000)
    store.publishStatus(
      .recording,
      message: "Listening",
      activeRequestID: "abc",
      activeDictationAction: .translate,
      recordingStartedAt: now,
      heartbeat: now
    )
    let resultSequence = store.publishTranscript(
      "hello world",
      requestID: "abc",
      kind: .dictation,
      at: now
    )

    let snapshot = store.snapshot()
    XCTAssertEqual(snapshot.status, .recording)
    XCTAssertEqual(snapshot.message, "Listening")
    XCTAssertEqual(snapshot.activeRequestID, "abc")
    XCTAssertEqual(snapshot.activeDictationAction, .translate)
    XCTAssertEqual(snapshot.recordingStartedAt, now)
    XCTAssertTrue(snapshot.hostIsOnline(at: now.addingTimeInterval(2)))
    XCTAssertFalse(snapshot.hostIsOnline(at: now.addingTimeInterval(5)))
    XCTAssertEqual(resultSequence, 1)
    XCTAssertEqual(snapshot.resultSequence, 1)
    XCTAssertEqual(snapshot.resultRequestID, "abc")
    XCTAssertEqual(snapshot.resultKind, .dictation)
    XCTAssertEqual(snapshot.resultCreatedAt, now)
    XCTAssertEqual(snapshot.transcript, "hello world")
  }

  func testAcknowledgingCurrentResultClearsSensitivePayloadButRetainsSequence() {
    let sequence = store.publishTranscript(
      "sensitive dictated text",
      requestID: UUID().uuidString
    )

    store.acknowledgeResult(sequence: sequence)

    let snapshot = store.snapshot()
    XCTAssertEqual(snapshot.resultSequence, sequence)
    XCTAssertNil(snapshot.resultRequestID)
    XCTAssertNil(snapshot.resultKind)
    XCTAssertNil(snapshot.resultCreatedAt)
    XCTAssertNil(snapshot.transcript)
  }

  func testOlderAcknowledgementCannotClearNewerResult() {
    let olderSequence = store.publishTranscript(
      "older text",
      requestID: UUID().uuidString
    )
    let newerRequestID = UUID().uuidString
    let newerSequence = store.publishTranscript(
      "newer text",
      requestID: newerRequestID
    )

    store.acknowledgeResult(sequence: olderSequence)

    let snapshot = store.snapshot()
    XCTAssertEqual(snapshot.resultSequence, newerSequence)
    XCTAssertEqual(snapshot.resultRequestID, newerRequestID)
    XCTAssertEqual(snapshot.transcript, "newer text")
  }
}
