import SwiftUI
import UIKit

extension ContentView {
  var setupCard: some View {
    card {
      VStack(alignment: .leading, spacing: 14) {
        Label("One-time setup", systemImage: "keyboard")
          .font(.headline)

        instruction(1, "Open Settings › General › Keyboard › Keyboards.")
        instruction(2, "Tap Add New Keyboard, then choose Gemini Voice.")
        instruction(3, "Open Gemini Voice in the list and enable Allow Full Access.")
        instruction(
          4,
          "Open Gemini Voice once to arm the relay automatically, then select this keyboard with the globe key."
        )

        Button("Open Gemini Voice Settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.cyan)
      }
    }
  }

  var ocrCard: some View {
    card {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Label("Camera OCR", systemImage: "viewfinder")
            .font(.headline)
          Spacer()
          if relay.isProcessingImage {
            ProgressView()
              .tint(.cyan)
          }
        }

        Text(relay.ocrMessage)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.66))
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 10) {
          Button {
            relay.startOCRCapture(preferCamera: true)
          } label: {
            Label("Take Photo", systemImage: "camera.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(OCRButtonStyle(color: .purple))
          .disabled(relay.isProcessingImage)
          .accessibilityIdentifier("camera-ocr-button")

          Button {
            relay.startOCRCapture(preferCamera: false)
          } label: {
            Label("Choose Image", systemImage: "photo.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(OCRButtonStyle(color: .blue))
          .disabled(relay.isProcessingImage)
        }
      }
    }
  }
}
