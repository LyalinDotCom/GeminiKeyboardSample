import SwiftUI
import UIKit

struct ContentView: View {
  @ObservedObject var configuration: AppConfiguration
  @ObservedObject var relay: RelayController

  @State var settingsExpanded = false
  @State var recordingPendingDeletion: RecoverableRecording?

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.035, green: 0.05, blue: 0.10), Color(red: 0.08, green: 0.055, blue: 0.16),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      ScrollView {
        VStack(spacing: 18) {
          header
          relayCard
          ocrCard
          setupCard
          settingsCard
          savedRecordingsCard
          recentCard
          privacyFooter
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 36)
      }
    }
    .preferredColorScheme(.dark)
    .overlay {
      if relay.isKeyboardHandoffActive {
        keyboardHandoffOverlay
      }
    }
    .onOpenURL(perform: relay.handleDeepLink)
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
  }
}

#Preview {
  let configuration = AppConfiguration()
  ContentView(
    configuration: configuration,
    relay: RelayController(configuration: configuration)
  )
}
