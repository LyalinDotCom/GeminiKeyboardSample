import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct GeminiVoiceActivityWidgetBundle: WidgetBundle {
  var body: some Widget {
    GeminiVoiceActivityWidget()
  }
}

struct GeminiVoiceActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: VoiceRelayActivityAttributes.self) { context in
      lockScreenView(context)
        .activityBackgroundTint(Color.black.opacity(0.94))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          brandIcon
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text(context.state.title)
              .font(.headline)
            Text(context.state.subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          stopButton(for: context.state, compact: true)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if context.state.phase == .listening,
            let startedAt = context.state.recordingStartedAt
          {
            Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.red)
          }
        }
      } compactLeading: {
        Image(systemName: phaseSymbol(context.state.phase))
          .foregroundStyle(phaseColor(context.state.phase))
      } compactTrailing: {
        if context.state.phase == .listening,
          let startedAt = context.state.recordingStartedAt
        {
          Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .font(.caption2.monospacedDigit())
            .frame(width: 42)
        } else {
          Image(systemName: "mic.fill")
            .foregroundStyle(phaseColor(context.state.phase))
        }
      } minimal: {
        Image(systemName: phaseSymbol(context.state.phase))
          .foregroundStyle(phaseColor(context.state.phase))
      }
      .keylineTint(phaseColor(context.state.phase))
    }
  }

  private func lockScreenView(
    _ context: ActivityViewContext<VoiceRelayActivityAttributes>
  ) -> some View {
    HStack(spacing: 14) {
      brandIcon

      VStack(alignment: .leading, spacing: 3) {
        Text(context.state.title)
          .font(.headline)
          .foregroundStyle(.white)
        Text(context.state.subtitle)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.68))
          .lineLimit(2)
        if context.state.phase == .listening,
          let startedAt = context.state.recordingStartedAt
        {
          Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.red)
        }
      }

      Spacer(minLength: 8)
      stopButton(for: context.state, compact: false)
    }
    .padding(16)
  }

  private var brandIcon: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .fill(
          LinearGradient(
            colors: [.cyan, .blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Image(systemName: "waveform.badge.mic")
        .font(.system(size: 23, weight: .semibold))
        .foregroundStyle(.white)
    }
    .frame(width: 52, height: 52)
  }

  @ViewBuilder
  private func stopButton(
    for state: VoiceRelayActivityAttributes.ContentState,
    compact: Bool
  ) -> some View {
    if state.showsCancelControl {
      Button(intent: CancelVoiceRecordingIntent(controlToken: state.controlToken)) {
        controlImage(systemName: "xmark", compact: compact)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Stop recording and discard the result")
    } else {
      Button(intent: StopVoiceRelayIntent(controlToken: state.controlToken)) {
        controlImage(systemName: "power", compact: compact)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Stop relay")
    }
  }

  private func controlImage(systemName: String, compact: Bool) -> some View {
    Image(systemName: systemName)
      .font(.system(size: compact ? 17 : 24, weight: .semibold))
      .foregroundStyle(.black)
      .frame(width: compact ? 36 : 54, height: compact ? 36 : 54)
      .background(.white, in: Circle())
  }

  private func phaseSymbol(
    _ phase: VoiceRelayActivityAttributes.ContentState.Phase
  ) -> String {
    switch phase {
    case .standingBy: "mic.fill"
    case .listening: "waveform"
    case .transcribing: "ellipsis"
    case .unavailable: "exclamationmark.triangle.fill"
    }
  }

  private func phaseColor(
    _ phase: VoiceRelayActivityAttributes.ContentState.Phase
  ) -> Color {
    switch phase {
    case .standingBy: .green
    case .listening: .red
    case .transcribing: .cyan
    case .unavailable: .orange
    }
  }
}
