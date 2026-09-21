import SwiftUI

extension ContentView {
  var relayScreen: some View {
    ScrollView {
      VStack(spacing: 24) {
        relayHero
        if !configuration.hasUsableAPIKey {
          apiKeyRequiredCard
        } else if relay.status == .error {
          Label(relay.statusMessage, systemImage: "exclamationmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .accessibilityIdentifier("relay-error-message")
        }
        VStack(spacing: 12) {
          recordNoteCard
          translationShortcut
          ocrCard
        }
        if !relay.recoverableRecordings.isEmpty {
          Button { selectedScreen = .history } label: {
            HStack(spacing: 12) {
              Image(systemName: "waveform.badge.exclamationmark")
              Text("\(relay.recoverableRecordings.count) saved recording\(relay.recoverableRecordings.count == 1 ? "" : "s") to retry")
              Spacer()
              Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .font(.subheadline)
            .padding(18)
          }
          .buttonStyle(.plain)
          .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        }
      }
      .frame(maxWidth: 580)
      .padding(.horizontal, 20)
      .padding(.bottom, 28)
      .frame(maxWidth: .infinity)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationTitle("Relay")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink { setupScreen } label: { Image(systemName: "keyboard") }
          .accessibilityLabel("Keyboard setup")
      }
    }
  }

  var recordNoteCard: some View {
    Button {
      Task { await relay.startNoteCapture() }
    } label: {
      HStack(spacing: 14) {
        Image(systemName: "mic.badge.plus")
          .font(.title2)
          .frame(width: 48, height: 48)
          .glassEffect(.regular.tint(.blue.opacity(0.1)), in: .circle)
        VStack(alignment: .leading, spacing: 4) {
          Text("Record a note").font(.headline)
          Text("Say it. Save it. Copy it.")
            .font(.subheadline).foregroundStyle(Color.secondary)
        }
        Spacer(minLength: 4)
        Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
      }
      .padding(18)
      .background(Color.blue.opacity(0.06), in: .rect(cornerRadius: 22))
      .contentShape(.rect(cornerRadius: 22))
    }
    .buttonStyle(.plain)
    .foregroundStyle(.blue)
    .disabled(!relay.canStartNoteCapture)
    .accessibilityIdentifier("record-note-button")
    .accessibilityHint("Starts recording a voice note in this app.")
  }

  var relayHero: some View {
    VStack(spacing: 16) {
      statusPill.padding(.top, 8)
      RelayPowerControl(
        isRunning: relay.isRelayRunning,
        isStarting: relay.isRelayStarting,
        isRecording: relay.status == .recording,
        isTranscribing: relay.status == .transcribing,
        isEnabled: configuration.hasUsableAPIKey,
        audioLevel: relay.audioLevel,
        title: relayActionTitle,
        action: toggleRelay
      )
      VStack(spacing: 8) {
        Text(relayHeadline)
          .font(.title2.weight(.semibold))
          .contentTransition(.opacity)
        Text(relayExplanation)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: 320)
          .fixedSize(horizontal: false, vertical: true)
      }
      .multilineTextAlignment(.center)
      if relay.status == .recording {
        HStack(spacing: 16) {
          Button("Cancel", role: .cancel) { relay.cancelDictation() }
            .buttonStyle(.glass)
          Button("Finish", systemImage: "checkmark") {
            if let requestID = relay.activeRequestID {
              relay.finishDictationAndTranscribe(requestID: requestID)
            }
          }
          .buttonStyle(.glassProminent)
        }
        .controlSize(.large)
      }
      Group {
        if let deadline = relay.idleShutdownDeadline, deadline > Date() {
          HStack(spacing: 4) {
            Image(systemName: "timer")
            Text("Auto-pauses in")
            Text(timerInterval: Date()...deadline, countsDown: true)
              .monospacedDigit().fixedSize()
          }
        } else {
          Label(
            relay.isRelayRunning ? "Microphone active for your keyboard" : "Turns on when you open Gemini Voice",
            systemImage: relay.isRelayRunning ? "mic" : "arrow.up.forward.app"
          )
        }
      }
      .font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 4)
    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: relay.status)
  }

  var translationShortcut: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(spacing: 14))
    return layout {
      HStack(spacing: 14) {
        Image(systemName: "translate")
          .font(.title3).foregroundStyle(.blue).frame(width: 28)
        VStack(alignment: .leading, spacing: 3) {
          Text("Translate to").font(.subheadline.weight(.medium))
          Text("From your keyboard").font(.caption).foregroundStyle(.secondary)
        }
      }
      if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
      languagePicker.labelsHidden()
    }
    .padding(18)
    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
  }

  var apiKeyRequiredCard: some View {
    Button { selectedScreen = .settings } label: {
      HStack(spacing: 12) {
        Image(systemName: "key.fill").foregroundStyle(.blue)
        VStack(alignment: .leading, spacing: 4) {
          Text("Connect to Gemini").font(.subheadline.weight(.semibold))
          Text("Add your API key to get started.").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
      }
      .padding(18)
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("api-key-required-card")
  }

  var statusPill: some View {
    Label(statusTitle, systemImage: statusSymbol)
      .font(.subheadline.weight(.medium))
      .foregroundStyle(statusColor)
      .contentTransition(.symbolEffect(.replace))
  }

  var relayHeadline: String {
    if !configuration.hasUsableAPIKey { return "Connect Gemini to begin" }
    if relay.isRelayStarting { return "Getting ready…" }
    switch relay.status {
    case .recording: return "Listening"
    case .transcribing: return "Turning speech into text"
    case .error: return "Relay needs attention"
    case .idle where relay.isRelayRunning: return "Your keyboard is ready"
    default: return "Ready when you are"
    }
  }

  var relayExplanation: String {
    if !configuration.hasUsableAPIKey { return "Connect Gemini, then use your voice in any text field." }
    if relay.isRelayStarting { return "Preparing the microphone for your keyboard." }
    switch relay.status {
    case .recording: return "Finish when you’re done. Your words will appear in your text field."
    case .transcribing: return "Your finished text will appear in your keyboard and History."
    case .idle where relay.isRelayRunning: return "Switch to the Gemini Voice keyboard, then tap Dictate or Translate."
    default: return "Enable Relay to dictate and translate wherever you type."
    }
  }

  var relayActionTitle: String {
    if relay.isRelayStarting { return "Starting…" }
    if relay.status == .recording { return "Listening" }
    if relay.status == .transcribing { return "Finishing…" }
    return relay.isRelayRunning ? "Pause Relay" : "Enable Relay"
  }

  func toggleRelay() {
    if relay.isRelayRunning {
      relay.stopRelay()
    } else {
      Task { await relay.startRelay() }
    }
  }
}

/// Arming the keyboard is distinct from recording; only recording shows a waveform.
struct RelayPowerControl: View {
  let isRunning: Bool
  let isStarting: Bool
  let isRecording: Bool
  let isTranscribing: Bool
  let isEnabled: Bool
  let audioLevel: Double
  let title: String
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @ScaledMetric(relativeTo: .headline) private var controlDiameter = 172.0

  var body: some View {
    let diameter = min(controlDiameter, 270)
    ZStack {
      Circle()
        .stroke(Color.blue.opacity(isRunning ? 0.12 : 0.06), lineWidth: 1)
        .frame(width: diameter + 48, height: diameter + 48)
      Circle()
        .fill(Color.blue.opacity(isRunning ? 0.07 : 0.035))
        .frame(width: diameter + 24, height: diameter + 24)
        .scaleEffect(isRecording && !reduceMotion ? 1 + min(max(audioLevel, 0), 1) * 0.08 : 1)
      Button(action: action) {
        VStack(spacing: 14) {
          if isStarting || isTranscribing {
            ProgressView().controlSize(.large).tint(.blue).frame(height: 46)
          } else {
            Image(systemName: isRecording ? "waveform" : "power")
              .font(.system(size: 44, weight: .medium))
              .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isRecording && !reduceMotion)
              .contentTransition(.symbolEffect(.replace))
              .frame(height: 46)
          }
          Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(isEnabled ? Color.blue : Color.secondary)
        .frame(width: diameter, height: diameter)
        .background {
          if reduceTransparency {
            Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
          }
        }
        .glassEffect(.regular.tint(.blue.opacity(isRunning ? 0.14 : 0.025)).interactive(), in: .circle)
        .contentShape(Circle())
      }
      .buttonStyle(RelayPressStyle())
      .disabled(!isEnabled || isStarting || isRecording || isTranscribing)
      .accessibilityIdentifier("relay-control-button")
      .accessibilityLabel(title)
      .accessibilityValue(isRunning ? "Relay on" : "Relay off")
      .accessibilityHint(isRecording ? "Dictation in progress. Use Finish or Cancel below." : isRunning ? "Pauses until you next open the app." : "Prepares the microphone. Start dictation from the keyboard.")
    }
    .frame(height: diameter + 52)
    .sensoryFeedback(.impact(weight: .light), trigger: isRunning)
    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: isRunning)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: audioLevel)
  }
}

private struct RelayPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
  }
}
