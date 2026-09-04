import AVFoundation
import Foundation

/// Main-queue lifecycle state is coordinated by `RelayController`. The realtime
/// audio tap enters `write(_:)` from AVFAudio and touches recording/streaming
/// state only while holding `fileLock`.
final class AudioCaptureEngine: @unchecked Sendable {
  static var isMicrophoneCaptureAvailable: Bool {
    #if targetEnvironment(simulator)
      false
    #else
      true
    #endif
  }

  struct SessionConfiguration {
    let name: String
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
  }

  var engine = AVAudioEngine()
  let fileLock = NSLock()
  var recoverableRecordingScanGate = RecoverableRecordingScanGate()

  var inputFormat: AVAudioFormat?
  var streamingConverter: AVAudioConverter?
  var streamingOutputFormat: AVAudioFormat?
  var streamingChunker = PCM16StreamChunker()
  var audioChunkHandler: (@Sendable (Data) -> Void)?
  var audioStreamingFailureHandler: (@Sendable (String) -> Void)?
  var didReportStreamingFailure = false
  var activeFile: AVAudioFile?
  var activeURL: URL?
  var activeRequestID: String?
  var activeAction: RelayDictationAction?
  var activeTranslationTargetCode: String?
  var activeStartedAt: Date?
  var writeFailure: Error?
  var tapInstalled = false
  var shouldBeRunning = false
  var isConfiguring = false
  var recoveryWorkItem: DispatchWorkItem?
  var observers: [NSObjectProtocol] = []
  var engineConfigurationObserver: NSObjectProtocol?
  var lastLevelPublishedAt: TimeInterval = 0
  var isRunning = false
  var activeConfigurationName = ""

  var recoveryHandler: ((Result<String, Error>) -> Void)?
  var levelHandler: ((Double) -> Void)?

  init() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] notification in
        self?.handleInterruption(notification)
      }
    )
    engineConfigurationObserver = center.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      self?.scheduleRecovery(reason: "audio route changed")
    }
    observers.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] _ in
        self?.replaceEngineAndRecover()
      }
    )
  }

  func start() throws {
    shouldBeRunning = true
    guard !isRunning, !engine.isRunning else { return }

    #if DEBUG && targetEnvironment(simulator)
      // UI handoff tests need the relay state machine to reach "recording"
      // even though Simulator has no supported microphone route. This is an
      // explicit, opt-in fake; normal Simulator launches retain the safe
      // nonfatal unavailable state.
      if ProcessInfo.processInfo.environment["GEMINI_SIMULATOR_HANDOFF_TEST"] == "1" {
        guard
          let format = AVAudioFormat(
            standardFormatWithSampleRate: 16_000,
            channels: 1
          )
        else {
          shouldBeRunning = false
          throw AudioCaptureError.invalidInputFormat
        }
        inputFormat = format
        isRunning = true
        activeConfigurationName = "Simulator handoff test"
        NSLog("AUDIO_RELAY_SIMULATOR_HANDOFF_TEST_READY")
        return
      }
    #endif

    guard Self.isMicrophoneCaptureAvailable else {
      shouldBeRunning = false
      NSLog("IOS_VALIDATION_FAILURE simulator microphone capture unavailable")
      throw AudioCaptureError.simulatorMicrophoneUnavailable
    }

    // Only a fresh relay instance reports leftovers from a prior process.
    // They are intentionally preserved so the containing app can retry them.
    if recoverableRecordingScanGate.claim() {
      reportRecoverableRecordings()
    }

    if tapInstalled || engine.isRunning {
      tearDownEngine()
    }

    isConfiguring = true
    defer { isConfiguring = false }

    var failures: [String] = []
    for configuration in sessionConfigurations {
      do {
        try startEngine(using: configuration)
        activeConfigurationName = configuration.name
        NSLog(
          "AUDIO_RELAY_SESSION_READY configuration=%@ route=%@",
          configuration.name,
          routeDescription
        )
        return
      } catch {
        failures.append("\(configuration.name): \(errorSummary(error))")
        NSLog(
          "AUDIO_RELAY_SESSION_FAILED configuration=%@ error=%@",
          configuration.name,
          errorSummary(error)
        )
        tearDownEngine()
      }
    }

    shouldBeRunning = false
    throw AudioCaptureError.sessionUnavailable(failures.joined(separator: "; "))
  }

  func stop() {
    shouldBeRunning = false
    recoveryWorkItem?.cancel()
    recoveryWorkItem = nil
    cancelSegment()
    tearDownEngine()
  }

  deinit {
    recoveryWorkItem?.cancel()
    observers.forEach(NotificationCenter.default.removeObserver)
    if let engineConfigurationObserver {
      NotificationCenter.default.removeObserver(engineConfigurationObserver)
    }
    stop()
  }
}
