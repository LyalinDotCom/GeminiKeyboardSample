import SwiftUI

extension ContentView {
  var settingsScreen: some View {
    Form {
      Section {
        NavigationLink {
          HistoryRetentionSettings(configuration: configuration)
        } label: {
          LabeledContent("Keep history", value: "\(configuration.historyRetentionDays) days")
        }
        .accessibilityIdentifier("history-retention-link")
      } header: {
        Text("Notes & history")
      } footer: {
        Text("Saved text is kept on this iPhone for the number of days you choose.")
      }

      Section {
        languagePicker
      } header: {
        Text("Translation")
      } footer: {
        Text("Tap Translate on the keyboard to turn your speech into this language.")
      }

      Section {
        NavigationLink { connectionScreen } label: {
          Label {
            HStack {
              Text("Gemini connection")
              Spacer()
              Text(configuration.hasUsableAPIKey ? "Key added" : "Add key")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
          } icon: { Image(systemName: "key").foregroundStyle(.blue) }
        }
        .accessibilityIdentifier("gemini-connection-link")
        NavigationLink { setupScreen } label: {
          settingsLabel("Keyboard setup", symbol: "keyboard")
        }
        NavigationLink { KeyboardTryoutView() } label: {
          settingsLabel("Try your keyboard", symbol: "text.cursor")
        }
        Button(action: openSystemSettings) {
          settingsLabel("Microphone & permissions", symbol: "mic")
        }
        .foregroundStyle(.primary)
      } header: {
        Text("Setup")
      }

      Section {
        LabeledContent("Start automatically", value: "On app open")
        LabeledContent("Pause when idle", value: "After 2 minutes")
      } header: {
        Text("Relay")
      } footer: {
        Text("The microphone stays available while Relay is on. Start from the keyboard, or record a note right here in the app.")
      }

      Section {
        NavigationLink { modelsScreen } label: {
          settingsLabel("Models", symbol: "sparkles")
        }
        NavigationLink { privacyScreen } label: {
          settingsLabel("Audio & privacy", symbol: "hand.raised")
        }
      }
      Section {
        HStack {
          Spacer()
          VStack(spacing: 6) {
            Image(systemName: "waveform").font(.title2).foregroundStyle(.blue)
            Text("Gemini Voice").font(.subheadline.weight(.semibold))
            Text("Voice, wherever you type.").font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 12)
          Spacer()
        }
        .listRowBackground(Color.clear)
      }
    }
    .navigationTitle("Settings")
  }

  func settingsLabel(_ title: String, symbol: String) -> some View {
    Label { Text(title).foregroundStyle(.primary) } icon: {
      Image(systemName: symbol).foregroundStyle(.blue)
    }
  }

  var connectionScreen: some View {
    Form {
      Section {
        Label(configuration.hasUsableAPIKey ? "API key configured" : "Add your Gemini API key",
              systemImage: configuration.hasUsableAPIKey ? "checkmark.circle.fill" : "key")
          .foregroundStyle(configuration.hasUsableAPIKey ? Color.blue : Color.primary)
        SecureField("API key override", text: $configuration.apiKeyOverride)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("api-key-field")
        if !configuration.apiKeyOverride.isEmpty {
          Button("Clear override", role: .destructive) { configuration.clearAPIKeyOverride() }
        }
      } header: {
        Text("API key")
      } footer: {
        Text("An override is stored in this iPhone’s Keychain. Leave it empty to use the key supplied with your personal build.")
      }
      if let warning = configuration.credentialPersistenceWarning {
        Section { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
      }
      Section {
        Text(configuration.embeddedKeyDescription)
          .foregroundStyle(.secondary)
      } header: {
        Text("This build")
      }
    }
    .navigationTitle("Gemini Connection")
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
  }

  var modelsScreen: some View {
    Form {
      Section("Live speech") {
        modelRow("Dictation", model: configuration.liveTranscriptionModel, identifier: "active-transcription-model")
        modelRow("Translation", model: configuration.liveTranslationModel, identifier: "active-translation-model")
      }
      Section("Fallback & images") {
        modelRow("Saved audio", model: configuration.transcriptionModel)
        modelRow("Photo text", model: configuration.ocrModel)
      }
    }
    .navigationTitle("Models")
    .navigationBarTitleDisplayMode(.inline)
  }

  func modelRow(_ title: String, model: String, identifier: String = "") -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
      Text(model).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(model)
    .accessibilityIdentifier(identifier)
  }

  var privacyScreen: some View {
    Form {
      Section("When Relay is on") {
        Text("iOS shows microphone access because the audio session stays ready for your keyboard. Enabling Relay does not start a dictation.")
      }
      Section("While you dictate or translate") {
        Text("Microphone audio streams to Google Gemini Live. Keyboard dictation inserts the result; voice notes save it here for you to copy. Cancel stops streaming and discards the recording.")
      }
      Section("Saved on your iPhone") {
        Text("A temporary recording provides a fallback if the live connection fails. It is deleted after success, or kept in History for you to retry or delete.")
        Text("Completed text is kept in History for \(configuration.historyRetentionDays) days, or until you delete it. Change the number of days in Settings. Your API key is not shared with the keyboard.")
      }
    }
    .navigationTitle("Audio & Privacy")
    .navigationBarTitleDisplayMode(.inline)
  }
}
