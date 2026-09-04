import SwiftUI

@main
struct GeminiVoiceApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var configuration: AppConfiguration
  @StateObject private var relay: RelayController

  init() {
    #if DEBUG
      if ProcessInfo.processInfo.environment["GEMINI_VOICE_NONFATAL_DIAGNOSTIC"] == "1" {
        NSLog("IOS_VALIDATION_FAILURE deliberate nonfatal launch diagnostic")
      }
    #endif
    let configuration = AppConfiguration()
    _configuration = StateObject(wrappedValue: configuration)
    _relay = StateObject(
      wrappedValue: RelayController(configuration: configuration)
    )
  }

  var body: some Scene {
    WindowGroup {
      ContentView(configuration: configuration, relay: relay)
        .task {
          guard scenePhase == .active else { return }
          await handleActiveSceneIfEnabled()
        }
        .onChange(of: scenePhase) { _, newPhase in
          switch newPhase {
          case .active:
            Task { await handleActiveSceneIfEnabled() }
          case .background:
            relay.applicationDidEnterBackground()
          case .inactive:
            break
          @unknown default:
            break
          }
        }
    }
  }

  @MainActor
  private func handleActiveSceneIfEnabled() async {
    let environment = ProcessInfo.processInfo.environment
    guard environment["GEMINI_VOICE_DISABLE_RELAY_AUTOSTART"] != "1" else { return }
    #if DEBUG
      guard environment["XCTestConfigurationFilePath"] == nil else { return }
    #endif
    await relay.applicationDidBecomeActive()
  }
}
