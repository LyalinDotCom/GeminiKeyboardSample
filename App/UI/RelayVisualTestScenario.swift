#if DEBUG && targetEnvironment(simulator)
  import Foundation

  extension RelayController {
    /// In-memory fixtures for Simulator screenshots. Never starts audio or writes personal data.
    func applyVisualTestScenario() {
      switch ProcessInfo.processInfo.environment["GEMINI_VOICE_VISUAL_TEST_SCENARIO"] {
      case "history":
        history = [
          TranscriptHistoryItem(
            text: "Let’s take the scenic route. We can stop for coffee on the way.",
            createdAt: Date().addingTimeInterval(-300)),
          TranscriptHistoryItem(
            text: "The best ideas tend to arrive when you’re away from your desk. Make a little room for them.",
            createdAt: Date().addingTimeInterval(-3600)),
          TranscriptHistoryItem(
            text: "Saturday farmers market\n9 AM – 2 PM\nFresh flowers, local produce, and good coffee.",
            createdAt: Date().addingTimeInterval(-86400)),
        ]
      case "recording":
        isRelayRunning = true
        status = .recording
        audioLevel = 0.55
      case "handoff":
        isRelayRunning = true
        status = .idle
        isKeyboardHandoffActive = true
        requiresManualKeyboardReturn = true
      case "note-recording":
        isRelayRunning = true
        status = .recording
        activeDictationAction = .note
        activeStartedAt = Date().addingTimeInterval(-24)
        audioLevel = 0.65
        noteCapturePhase = .recording
        notePreviewText = "Let’s take the scenic route this weekend. Stop for coffee, find a trail by the water, and leave the afternoon open."
        isNoteCapturePresented = true
      case "note-saved":
        let item = TranscriptHistoryItem(
          text: "Let’s take the scenic route this weekend.\n\nStop for coffee, find a trail by the water, and leave the afternoon open.\n\nBring the camera. Some days are worth slowing down for.", createdAt: Date())
        history = [item]
        noteCapturePhase = .saved(item)
        isNoteCapturePresented = true
      default:
        break
      }
    }
  }
#endif
