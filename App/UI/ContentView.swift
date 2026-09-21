import SwiftUI
import UIKit

struct ContentView: View {
  enum Screen: Hashable { case relay, history, settings }

  @ObservedObject var configuration: AppConfiguration
  @ObservedObject var relay: RelayController
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  @State var selectedScreen: Screen = .relay
  @State var recordingPendingDeletion: RecoverableRecording?
  @State var isClearHistoryPresented = false
  @State var copiedItemID: UUID?

  var body: some View {
    TabView(selection: $selectedScreen) {
      Tab("Relay", systemImage: "waveform", value: Screen.relay) {
        NavigationStack { relayScreen }
      }
      Tab("History", systemImage: "clock", value: Screen.history) {
        NavigationStack { historyScreen }
      }
      .badge(relay.recoverableRecordings.count)
      Tab("Settings", systemImage: "gearshape", value: Screen.settings) {
        NavigationStack { settingsScreen }
      }
    }
    .tint(.blue)
    .onChange(of: configuration.apiKeyOverride) { _, _ in
      relay.credentialAvailabilityDidChange()
    }
    .onChange(of: configuration.historyRetentionDays) { _, _ in
      relay.applyHistoryRetention()
    }
    .accessibilityHidden(relay.isKeyboardHandoffActive)
    .overlay {
      if relay.isKeyboardHandoffActive {
        keyboardHandoffOverlay
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: relay.isKeyboardHandoffActive)
    .onOpenURL(perform: relay.handleDeepLink)
    .sheet(isPresented: $relay.isNoteCapturePresented) {
      NoteCaptureSheet(relay: relay, retentionDays: configuration.historyRetentionDays) {
        selectedScreen = .history
        relay.dismissNoteCapture()
      }
    }
    .sheet(
      isPresented: Binding(
        get: { relay.isImagePickerPresented },
        set: { presented in
          if !presented && relay.isImagePickerPresented {
            relay.imagePickerDidCancel()
          }
        }
      )
    ) {
      ImagePicker(
        sourceType: relay.imagePickerSource,
        onImage: relay.imagePickerDidSelect,
        onCancel: relay.imagePickerDidCancel
      )
      .ignoresSafeArea()
    }
    .confirmationDialog(
      "Delete this saved recording?",
      isPresented: Binding(
        get: { recordingPendingDeletion != nil },
        set: { presented in
          if !presented { recordingPendingDeletion = nil }
        }
      ),
      titleVisibility: .visible
    ) {
      Button("Delete Recording", role: .destructive) {
        if let recordingPendingDeletion {
          relay.deleteRecording(recordingPendingDeletion)
        }
        recordingPendingDeletion = nil
      }
      Button("Keep Recording", role: .cancel) {
        recordingPendingDeletion = nil
      }
    } message: {
      Text("This permanently removes the local audio clip.")
    }
    .confirmationDialog("Clear history?", isPresented: $isClearHistoryPresented, titleVisibility: .visible) {
      Button("Clear History", role: .destructive) { relay.clearHistory() }
    } message: {
      Text("This removes completed text from this iPhone. Saved audio recordings will be kept.")
    }
  }
}

#Preview {
  let configuration = AppConfiguration()
  ContentView(
    configuration: configuration,
    relay: RelayController(configuration: configuration)
  )
}
