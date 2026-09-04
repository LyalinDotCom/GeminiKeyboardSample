import AVFoundation
import Foundation

extension AudioCaptureEngine {
  var sessionConfigurations: [SessionConfiguration] {
    [
      SessionConfiguration(
        name: "AirPods high-quality",
        mode: .default,
        options: [.mixWithOthers, .allowBluetoothHFP, .bluetoothHighQualityRecording]
      ),
      SessionConfiguration(
        name: "Bluetooth mixed",
        mode: .default,
        options: [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP]
      ),
      SessionConfiguration(
        name: "Bluetooth hands-free",
        mode: .default,
        options: [.mixWithOthers, .allowBluetoothHFP]
      ),
      SessionConfiguration(
        name: "Built-in mixed",
        mode: .default,
        options: [.mixWithOthers]
      ),
    ]
  }

  func reportRecoverableRecordings() {
    guard let container = VoiceAppGroup.containerURL else { return }
    let directory = container.appendingPathComponent("Recordings", isDirectory: true)
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else { return }

    let recoverableCount = urls.filter {
      $0.lastPathComponent.hasPrefix("completed-")
        && $0.pathExtension.lowercased() == "wav"
    }.count
    if recoverableCount > 0 {
      NSLog("AUDIO_RECOVERABLE_RECORDINGS_PRESERVED count=%d", recoverableCount)
    }
  }

  func startEngine(using configuration: SessionConfiguration) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: configuration.mode,
      options: configuration.options
    )
    try? session.setPreferredSampleRate(16_000)
    try? session.setPreferredInputNumberOfChannels(1)
    try? session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true, options: [])

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw AudioCaptureError.invalidInputFormat
    }

    input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
      self?.write(buffer)
    }
    tapInstalled = true
    inputFormat = format
    configureStreamingConverter(from: format)

    engine.prepare()
    try engine.start()
    isRunning = true
  }

  func tearDownEngine() {
    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    if engine.isRunning {
      engine.stop()
    }
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: [.notifyOthersOnDeactivation]
    )
    fileLock.lock()
    inputFormat = nil
    streamingConverter = nil
    streamingOutputFormat = nil
    streamingChunker.reset()
    audioChunkHandler = nil
    audioStreamingFailureHandler = nil
    didReportStreamingFailure = false
    fileLock.unlock()
    isRunning = false
    activeConfigurationName = ""
  }

  func handleInterruption(_ notification: Notification) {
    guard shouldBeRunning,
      let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: rawType)
    else { return }

    switch type {
    case .began:
      NSLog("AUDIO_RELAY_INTERRUPTED route=%@", routeDescription)
      isRunning = false
    case .ended:
      scheduleRecovery(reason: "audio interruption ended")
    @unknown default:
      break
    }
  }

  func scheduleRecovery(reason: String) {
    guard shouldBeRunning, !isConfiguring else { return }
    recoveryWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.shouldBeRunning, !self.isConfiguring else { return }
      self.recover(reason: reason)
    }
    recoveryWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
  }

  func replaceEngineAndRecover() {
    guard shouldBeRunning else { return }
    recoveryWorkItem?.cancel()
    cancelSegment()
    tearDownEngine()
    if let engineConfigurationObserver {
      NotificationCenter.default.removeObserver(engineConfigurationObserver)
    }
    engine = AVAudioEngine()

    let center = NotificationCenter.default
    engineConfigurationObserver = center.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      self?.scheduleRecovery(reason: "audio route changed")
    }
    scheduleRecovery(reason: "media services reset")
  }

  func recover(reason: String) {
    let interruptedActiveSegment = hasActiveSegment
    if interruptedActiveSegment {
      cancelSegment()
    }
    tearDownEngine()

    do {
      try start()
      let message =
        interruptedActiveSegment
        ? "Audio recovered after \(reason); the interrupted dictation was cancelled"
        : "Audio recovered after \(reason)"
      NSLog("AUDIO_RELAY_RECOVERED reason=%@ route=%@", reason, routeDescription)
      recoveryHandler?(.success(message))
    } catch {
      NSLog("AUDIO_RELAY_RECOVERY_FAILED reason=%@ error=%@", reason, errorSummary(error))
      recoveryHandler?(.failure(error))
    }
  }

  var hasActiveSegment: Bool {
    fileLock.lock()
    defer { fileLock.unlock() }
    return activeFile != nil
  }

  var routeDescription: String {
    let route = AVAudioSession.sharedInstance().currentRoute
    let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
    let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
    return "input=[\(inputs.joined(separator: ","))] output=[\(outputs.joined(separator: ","))]"
  }

  func errorSummary(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
  }
}
