import SwiftUI
import UIKit

extension ContentView {
  var setupScreen: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 14) {
          Image(systemName: "keyboard")
            .font(.system(size: 42, weight: .light))
            .foregroundStyle(.blue)
          Text("Your voice.\nIn any text field.")
            .font(.largeTitle.weight(.bold))
          Text("Add Gemini Voice to your keyboards once, then it’s always a globe tap away.")
            .foregroundStyle(.secondary)
        }
        VStack(spacing: 24) {
          instruction(1, "Add the keyboard", "In Settings, open General → Keyboard → Keyboards → Add New Keyboard. Choose Gemini Voice.")
          instruction(2, "Allow Full Access", "Tap Gemini Voice in your keyboard list and turn on Allow Full Access so it can connect to Relay.")
          instruction(3, "Make it yours", "Open Gemini Voice to enable Relay. In any text field, hold the globe key and choose Gemini Voice, then tap Dictate or Translate.")
        }
        .padding(22)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        Button(action: openSystemSettings) {
          Text("Open Settings").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
        }
        .buttonStyle(.glassProminent)
        NavigationLink("Try your keyboard") { KeyboardTryoutView() }
          .frame(maxWidth: .infinity)
        Text("Full Access lets the keyboard exchange text and commands with the app. Your API key stays in the app.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      .frame(maxWidth: 580)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationTitle("Keyboard Setup")
    .navigationBarTitleDisplayMode(.inline)
  }

  func instruction(_ number: Int, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(number)")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.blue)
        .frame(width: 30, height: 30)
        .background(.blue.opacity(0.08), in: .circle)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  var photoActionLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 12))
      : AnyLayout(HStackLayout(spacing: 12))
  }

  var ocrCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        Image(systemName: "text.viewfinder")
          .font(.title3).foregroundStyle(.blue).frame(width: 28)
        VStack(alignment: .leading, spacing: 3) {
          Text("Text from a photo").font(.subheadline.weight(.medium))
          Text("Copy text from a page or image.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if relay.isProcessingImage { ProgressView() }
      }
      photoActionLayout {
        Button { relay.startOCRCapture(preferCamera: true) } label: {
          Label("Camera", systemImage: "camera").frame(maxWidth: .infinity).padding(.vertical, 5)
        }
        .accessibilityIdentifier("camera-ocr-button")
        Button { relay.startOCRCapture(preferCamera: false) } label: {
          Label("Photos", systemImage: "photo").frame(maxWidth: .infinity).padding(.vertical, 5)
        }
        .accessibilityIdentifier("photo-ocr-button")
      }
      .font(.subheadline.weight(.medium))
      .buttonStyle(.glass)
      .disabled(relay.isProcessingImage || !configuration.hasUsableAPIKey)
      if relay.ocrMessage != "Capture a page, sign, receipt, or screen" {
        Text(relay.ocrMessage)
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(18)
    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
  }
}

struct KeyboardTryoutView: View {
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Hold the globe key and choose Gemini Voice. Then try Dictate or Translate.")
        .font(.subheadline).foregroundStyle(.secondary)
      TextEditor(text: $text)
        .padding(12)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .overlay(alignment: .topLeading) {
          if text.isEmpty {
            Text("Tap here to try your keyboard")
              .foregroundStyle(.tertiary)
              .padding(.horizontal, 17).padding(.vertical, 20)
              .allowsHitTesting(false)
          }
        }
        .accessibilityLabel("Keyboard practice text")
        .accessibilityIdentifier("keyboard-practice-text")
    }
    .padding(20)
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationTitle("Try Your Keyboard")
    .navigationBarTitleDisplayMode(.inline)
  }
}
