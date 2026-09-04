# Architecture

This sample uses a containing iOS app as a microphone relay for a custom keyboard. That split is mandatory because iOS keyboard extensions cannot record audio.

## Runtime flow

```text
Custom keyboard process
  │  start / finish / cancel + request ID
  ▼
Locked App Group store
  │
  ▼
Containing app relay
  ├─ AVAudioEngine → protected local WAV
  ├─ PCM converter → Gemini Live WebSocket
  └─ finalized WAV → Gemini batch fallback
  │
  ▼
Locked App Group result
  │  matching request + document guard
  ▼
UITextDocumentProxy.insertText
```

The keyboard and containing app are separate processes. `SharedRelayStore` therefore behaves like a tiny durable protocol, not ordinary in-process state. Writes are committed under file locks and exposed through monotonic sequence numbers. A reader never treats partially written fields as a new command or result.

## Source layout

- `App/Application`: app entry point, settings, Keychain storage, and deep-link intent.
- `App/Gemini/Batch`: Interactions API request construction and response parsing.
- `App/Gemini/Live`: Live WebSocket transport, message schema, transcript merging, buffering, and finalization.
- `App/Audio`: audio-session selection, engine lifecycle, route recovery, recording, and PCM streaming.
- `App/Recovery`: retryable finalized recordings and recent completed text.
- `App/Relay`: the containing-app coordinator, split into lifecycle, polling, dictation, recovery, host return, background-task, and publishing files.
- `App/UI`: the SwiftUI containing-app screen, split into focused cards.
- `KeyboardExtension/Controller`: the keyboard coordinator, split into layout, persistence, relay state, presentation, dictation, host resolution, and ordinary typing.
- `KeyboardExtension/Components`: reusable UIKit keyboard controls.
- `Shared/Relay`: cross-process messages, policy decisions, snapshots, and persistent store.
- `Shared/Gemini`: result cleanup and translation-language data shared with the keyboard.
- `Shared/Keyboard`: pure keyboard capitalization and page state.
- `LiveActivityExtension` and `LiveActivityShared`: the relay's Lock Screen and Dynamic Island surface.

## Why the coordinators use extensions

`RelayController` and `KeyboardViewController` are state-machine coordinators. Their ordering and generation checks are coupled to real iOS lifecycle behavior. Splitting that state into many independently owned objects would add asynchronous seams and risk changing the behavior this sample is meant to demonstrate.

The project instead keeps one source of truth for each process and divides its implementation into responsibility-named Swift extensions. Module-internal members are intentional: the extensions collaborate on one state machine, while unrelated targets still cannot access those details.

## Relay invariants

1. Every operation has a UUID request ID and creation time.
2. Cold-launch authorization is short-lived and can be claimed only once.
3. A committed command sequence is written after its payload. The app acknowledges the sequence only after handling it.
4. Cancel takes precedence over an unconsumed Start or Finish for the same request.
5. The keyboard inserts a result only when request identity and the active document anchor still match.
6. Acknowledging a result erases its text payload without allowing an old acknowledgement to erase a newer result.
7. Async work carries a generation or request guard so stale completion cannot publish into a newer operation.

## Audio and Gemini flow

`AudioCaptureEngine` owns `AVAudioSession` and `AVAudioEngine`. During a recording it writes the input to a local WAV and separately converts buffers to the format required by Gemini Live. `PCM16StreamChunker` turns converter output into fixed 3,200-byte packets: 1,600 frames, or about 100 ms, at 16 kHz mono Int16.

`GeminiLiveSpeechSession` is an actor. It serializes socket setup, queued audio, transcript events, Finish, Cancel, and close. Interim events are presentation-only. Final input transcription is authoritative for dictation. Finish drains the audio stream before sending end-of-activity messages, and it rejects a known-stale final when likely speech arrived after that final.

The local WAV remains available until the operation resolves. A non-cancellation Live failure uses the complete WAV with `gemini-3.5-transcribe`. Translation then uses the configured text model. Cancellation never activates fallback.

## Recovery model

In-progress and user-finalized filenames are distinct. Only Finish renames a clip into the finalized form and writes retry metadata. This prevents an app crash during ordinary recording from silently uploading abandoned speech after the next launch.

On success, completed text is durably added to a bounded history before audio deletion. If cleanup fails, the recording remains visible. Background-expiration and network failures settle into explicit saved-recording states instead of pretending the request completed.

## Personal-device handoff

The supported design is a warm relay: keep the containing app's audio session armed, then send commands without leaving the current text field.

When the relay is cold, the Debug sample attempts to open the containing app, determine the exact originating process, and return to it. Parts of that path use private or unsupported system behavior and are guarded by `GEMINI_PERSONAL_DEVICE`. Unknown identity always falls back to manual navigation; the sample never guesses a destination. Release excludes those bridges and asks the user to return to the original app manually.
