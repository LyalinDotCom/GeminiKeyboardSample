import XCTest

@testable import GeminiVoice

final class RelayIdleShutdownPolicyTests: XCTestCase {
  func testIdleRelayStopsAtTwoMinutes() {
    XCTAssertTrue(
      RelayIdleShutdownPolicy.canStop(
        relayIsRunning: true,
        operationIsBusy: false,
        hasPendingHandoff: false,
        hasPendingCommand: false
      )
    )
    XCTAssertEqual(RelayIdleShutdownPolicy.timeout, 120)
  }

  func testBusyOperationAndPendingHandoffSuspendShutdown() {
    XCTAssertFalse(
      RelayIdleShutdownPolicy.canStop(
        relayIsRunning: true,
        operationIsBusy: true,
        hasPendingHandoff: false,
        hasPendingCommand: false
      )
    )
    XCTAssertFalse(
      RelayIdleShutdownPolicy.canStop(
        relayIsRunning: true,
        operationIsBusy: false,
        hasPendingHandoff: true,
        hasPendingCommand: false
      )
    )
    XCTAssertFalse(
      RelayIdleShutdownPolicy.canStop(
        relayIsRunning: true,
        operationIsBusy: false,
        hasPendingHandoff: false,
        hasPendingCommand: true
      )
    )
  }

  func testStoppedRelayNeverSchedulesAnotherDeadline() {
    XCTAssertFalse(
      RelayIdleShutdownPolicy.canStop(
        relayIsRunning: false,
        operationIsBusy: false,
        hasPendingHandoff: false,
        hasPendingCommand: false
      )
    )
  }
}
