# Gemini Voice Keyboard for iOS

A complete iOS sample for push-to-talk transcription with Gemini 3.5 Transcribe. It combines a containing app, a custom keyboard, Gemini Live streaming, a batch fallback, durable recovery, and careful cross-process coordination.

> [!IMPORTANT]
> This is a personal developer sample, not a production SDK or an App Store-ready product. The Debug configuration includes optional private iOS integration that makes the cold keyboard handoff unusually smooth on a personal device. Apple requires App Store apps to use public APIs, so that path may be rejected. Release compiles the private handoff code out, but still needs a backend before Gemini requests can work securely.

## What this sample demonstrates

- Real-time microphone transcription with `gemini-3.5-transcribe-live` over the Gemini Live WebSocket API, including manual push-to-talk activity boundaries and a finalization rule that never inserts a stale transcript.
- Live speech translation with `gemini-3.5-live-translate-preview`, keeping only the output transcription.
- Batch transcription with `gemini-3.5-transcribe`, image text extraction, and text translation through the Interactions API.
- Conversion of any input route to 16 kHz, mono, little-endian PCM in roughly 100 ms chunks.
- A custom keyboard that controls microphone capture in its containing app through an App Group, because Apple never gives keyboard extensions microphone access.
- One-time request authorization, freshness checks, command ordering, cancellation precedence, and safe transcript insertion anchored to the original text field.
- A protected local WAV written alongside Live streaming, then deleted after success or retained for an explicit retry after failure.
- Recovery across connection loss, audio-route changes, app backgrounding, process termination, and device switching between built-in and Bluetooth inputs.

If you are here for the Gemini code, start with [Gemini integration](#gemini-integration). If you are here to learn how a keyboard can drive a microphone at all, start with [The keyboard and voice relay](#the-keyboard-and-voice-relay).

## Gemini integration

The Gemini implementation is intentionally self-contained under [`App/Gemini`](App/Gemini), with a file-by-file guide in [`App/Gemini/README.md`](App/Gemini/README.md).

| Area | Purpose |
| --- | --- |
| [`Live`](App/Gemini/Live) | Opens the WebSocket, sends setup/audio/activity messages, merges interim/final transcripts, and finalizes safely. |
| [`Batch`](App/Gemini/Batch) | Builds Interactions API requests, validates responses, and reports service errors. |
| [`Audio`](App/Audio) | Owns `AVAudioSession` and `AVAudioEngine`, handles route recovery, writes WAV files, and produces Live PCM chunks. |
| [`Recovery`](App/Recovery) | Tracks finalized recordings that may be retried and stores a bounded result history. |

### Models

| Use | Model | API |
| --- | --- | --- |
| Live dictation | `gemini-3.5-transcribe-live` | Live WebSocket, `BidiGenerateContent` |
| Live translation | `gemini-3.5-live-translate-preview` | Live WebSocket, `BidiGenerateContent` |
| Batch dictation fallback and retry | `gemini-3.5-transcribe` | Interactions API |
| Text translation after batch dictation | `gemini-3.7-flash` | Interactions API |
| Image text extraction | `gemini-3.7-flash` | Interactions API |

Model names and preview APIs change. Check Google's [audio transcription](https://ai.google.dev/gemini-api/docs/transcribe) and [Live transcription](https://ai.google.dev/gemini-api/docs/live-api/live-transcribe) documentation before adopting the sample.

### Authentication

Every request, batch or Live, sends the API key as the `x-goog-api-key` request header. The Live WebSocket accepts that header on the handshake, so the key never appears in a URL that URLSession, proxies, or crash logs might record. Ephemeral tokens use the documented `access_token` query form on `BidiGenerateContentConstrained`.

A Debug build embeds the key from `Config/Secrets.xcconfig` into the app's `Info.plist`. An optional override entered in the app is kept in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The keyboard and the Live Activity never see the key. Release builds contain no credential at all; production needs an authenticated backend proxy for batch and backend-issued [ephemeral tokens](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens) for Live.

### Live transcription flow

`GeminiLiveSpeechSession` is an actor that serializes socket setup, queued audio, transcript events, Finish, Cancel, and close.

1. **Connect and configure.** Open the socket, send the setup message, and wait up to 5 s for `setupComplete`. Automatic activity detection is disabled so the user's Finish tap, not server VAD, defines the utterance.

   ```json
   {
     "setup": {
       "model": "models/gemini-3.5-transcribe-live",
       "generationConfig": { "responseModalities": ["TEXT"] },
       "realtimeInputConfig": { "automaticActivityDetection": { "disabled": true } },
       "inputAudioTranscription": { "languageCodes": [], "mode": "SMART" }
     }
   }
   ```

2. **Open the activity.** Send `{"realtimeInput": {"activityStart": {}}}` once, then stream audio. Chunks that arrive before setup completes are buffered, bounded at about 47 s of PCM.

   ```json
   { "realtimeInput": { "audio": { "data": "<base64 PCM>", "mimeType": "audio/pcm;rate=16000" } } }
   ```

   Each chunk is 3,200 bytes: 1,600 frames of 16 kHz mono Int16, about 100 ms. `PCM16StreamChunker` produces the same packet size regardless of the microphone route.

3. **Consume server events.** `serverContent.interimInputTranscription` updates the keyboard preview only. `serverContent.inputTranscription` is the authoritative final and is merged with the previous finals. `error` and `goAway` become terminal errors.

4. **Finish.** Drain every queued chunk (up to 10 s), send `{"realtimeInput": {"activityEnd": {}}}`, then wait up to 10 s for a final that is safe to use. A final is accepted only when all of these hold:
   - No interim is newer than the latest final.
   - If likely speech, measured as PCM energy above the −52 dB waveform floor, was sent within 0.8 s of Finish, a final that arrived **after** the boundary is required. Otherwise a final that arrived before the boundary is accepted once the boundary is 0.5 s old.
   - At least 0.35 s has passed since the last final text and since the boundary.

   If Gemini never sends the required event, Live deliberately fails and the complete WAV is transcribed with the batch API instead.

5. **Cancel.** Close the socket, delete the temporary WAV, insert nothing. Cancel cannot recall audio already sent.

### Live translation flow

The translation model speaks the translation, so the setup asks for audio output plus transcriptions and the app keeps only the output text:

```json
{
  "setup": {
    "model": "models/gemini-3.5-live-translate-preview",
    "generationConfig": {
      "responseModalities": ["AUDIO"],
      "inputAudioTranscription": {},
      "outputAudioTranscription": {},
      "translationConfig": { "targetLanguageCode": "es", "echoTargetLanguage": true }
    }
  }
}
```

Finish sends `{"realtimeInput": {"audioStreamEnd": true}}` and waits for `generationComplete`, which the Live API guarantees arrives after the last `outputTranscription`. Waiting for `turnComplete` would also wait for the assumed playback of audio the app never plays.

### Batch requests

All batch calls go to `POST https://generativelanguage.googleapis.com/v1beta/interactions` with `store: false`, a 90 s request timeout, and inline payloads validated before networking (14,000,000 bytes for audio, 10,000,000 for images). Production applications should use the Files API or a backend for larger inputs.

```json
{
  "model": "gemini-3.5-transcribe",
  "store": false,
  "input": [{ "type": "audio", "data": "<base64 WAV>", "mime_type": "audio/wav" }],
  "generation_config": { "transcription_config": { "mode": "smart" } }
}
```

A response is accepted only when `status` is `completed`; partial text from an incomplete or failed interaction is never used. Text is read from `steps[].content[].text` for `model_output` steps. Translation sends a `system_instruction` that tells the model to treat the input purely as text to translate, uses `response_format: {"type": "text"}` and `thinking_level: "low"`, and unwraps the JSON envelopes the model occasionally returns. OCR sends a text prompt plus a JPEG downscaled to 2,400 px.

### Failure, fallback, and retry

- Only a user-finished recording becomes retryable. Finish renames the in-progress WAV to a `completed-<action>-<target>-<requestID>.wav` file whose name encodes the retry intent, so a crash during ordinary recording never uploads abandoned speech after relaunch.
- Any non-cancellation Live failure, including a stale or missing final, falls back to the complete WAV. Cancel never activates fallback.
- A successful result is written to **Recent results** before the audio is deleted. If cleanup fails, the recording stays visible with the transcript marked as saved.
- Failed recordings are protected with `completeUntilFirstUserAuthentication`, excluded from backup, and listed under **Saved recordings** for an explicit retry.
- Network errors are mapped to short keyboard messages that distinguish timeouts from connectivity loss.

## The keyboard and voice relay

Apple does not give custom keyboard extensions microphone access, even with Full Access. The containing app therefore owns `AVAudioEngine` and acts as a microphone relay; the keyboard only sends authenticated commands and inserts a matching result. Getting that to feel like a native dictation key took a lot of trial and error. This section is the map.

```text
Custom keyboard process
  │  start / finish / cancel + request ID
  ▼
Locked App Group store (UserDefaults + flock, sequence numbers as commit markers)
  │
  ▼
Containing app relay (background audio mode keeps it alive)
  ├─ AVAudioEngine → protected local WAV
  ├─ PCM converter → Gemini Live WebSocket
  └─ finalized WAV → Gemini batch fallback
  │
  ▼
Locked App Group result
  │  matching request + document anchor
  ▼
UITextDocumentProxy.insertText
```

### The three flows

**Warm relay.** Gemini Voice has been opened once, so its audio session is armed and the app stays alive in the background under the `audio` background mode. The keyboard writes a Start command, the app begins capturing within one 200 ms poll and publishes `recording`, the keyboard shows the waveform and live preview, and Finish or Cancel complete the round trip without ever leaving the text field. This is the supported, public-API path.

**Cold handoff.** If the relay is offline, the keyboard has to get the app running. It writes a one-shot launch authorization to the App Group, opens `geminivoice://dictate?...` with the request ID, and the app arms the microphone and tries to return to the host app. Recording does **not** start on a timer; it starts only after the keyboard is attached to the returned text field again and has captured a fresh insertion anchor. Release builds stop at "return to your app manually" because App Review Guideline 4.4.1 forbids keyboards from launching other apps. Debug builds behind `GEMINI_PERSONAL_DEVICE` use private UIKit, SpringBoard, Security, and LaunchServices behavior to identify the exact host process and go back to it.

**Recovery.** Route changes, interruptions, media-services resets, backgrounding, background-time expiry, and process death all settle into explicit states: idle, a saved recording, or an offline message. Nothing pretends a request completed.

### Lessons that felt like black magic

- **Background audio keeps the relay alive.** A `playAndRecord` session with `mixWithOthers` stays active while the keyboard is in another app. iOS shows the microphone indicator the whole time, which the app explains in its privacy footer.
- **Route fallbacks are ordered.** The engine tries Bluetooth high-quality, Bluetooth mixed, hands-free, and built-in mixed in order and rebuilds the graph after `AVAudioEngineConfigurationChange`, interruptions, and media-services resets, with a 0.35 s debounce so a storm of notifications does not thrash the session.
- **The App Group store is a protocol, not state.** Both processes poll shared `UserDefaults` every 200 ms. Each logical write commits its sequence number last, under a `flock` on a lock file in the container, so a reader never sees a half-written command or result. The app heartbeats every second and the keyboard treats it as online for 3.5 s.
- **Cancel wins.** A discard command waiting to be handled cannot be replaced by Finish for the same request, so a keyboard Cancel and a Live Activity Cancel cannot race a Finish into an upload.
- **Authorization is one-shot and short-lived.** A launch request is valid for 30 s, can be claimed exactly once, and the keyboard's Start is rejected if the app already observed the request and its authorization disappeared. A Start older than 10 s is dropped.
- **Wait for the keyboard to settle before Start.** Host apps replace the text proxy just after the keyboard appears. The keyboard waits 0.22 s after `viewDidAppear` and restarts a 0.16 s quiet window on every `textDidChange` before it captures the insertion anchor and issues Start.
- **Anchor the result to the document.** The keyboard records the `documentIdentifier` plus SHA-256 fingerprints of the text before and after the cursor. A result is inserted automatically only when request ID, document, and both fingerprints still match; otherwise it is offered as **Insert latest**. No document text is ever stored or sent.
- **Persist the keyboard's own state.** Keyboard extensions are killed constantly. The tracked request, action, anchor, and cancelling flag are saved in the extension's defaults so a recreated keyboard resumes the same request instead of starting a second one.
- **Scope Live Activity controls.** The Lock Screen and Dynamic Island buttons carry a control token that is the active request ID while listening and the relay session ID otherwise, so a stale surface cannot cancel a newer recording.
- **Stop after two idle minutes.** The relay shuts itself down after two minutes without dictation, unless a handoff or command is pending, so the microphone indicator does not live forever.
- **Give async work a generation.** Every task, timer, and callback carries a generation or request guard so a stale completion cannot publish into a newer operation.

[Architecture](docs/ARCHITECTURE.md) lists the invariants the two processes rely on. The coordinators, `RelayController` and `KeyboardViewController`, are split into responsibility-named extensions so each path is easy to find without adding asynchronous seams to a tuned state machine.

## Requirements

- Xcode 26.6 or later
- iOS 26 or later
- A physical iPhone for microphone and custom-keyboard behavior
- An Apple Developer team with three bundle identifiers and one shared App Group
- A Gemini API key for personal development
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) when regenerating the committed project

## Configure a personal build

1. Copy the local configuration:

   ```sh
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```

2. In `Config/Secrets.xcconfig`, set your Apple team, unique bundle identifiers, App Group identifier, and Gemini API key.

3. Register the same bundle IDs and App Group in your Apple Developer account. All three targets must use the same App Group.

4. Regenerate the project:

   ```sh
   xcodegen generate
   ```

`Config/Secrets.xcconfig` is ignored by Git. The Debug API key is still compiled into the app and can be extracted from the installed binary. Use a restricted key, set billing limits, and treat this only as a personal-device convenience.

## Build and test

Run the complete simulator suite:

```sh
./Scripts/test.sh
```

The unit tests cover the Live protocol against a mock socket, the batch client against a mock URL session, the relay store's ordering and claim rules, recovery and history persistence, and the relay controller's OCR and handoff paths. Microphone capture is simulator-unavailable by design.

Deploy a signed Debug build to an available paired iPhone:

```sh
xcrun devicectl list devices
./Scripts/deploy-device.sh <core-device-identifier-or-hardware-udid>
```

The deploy script resolves the corresponding Xcode destination, builds, verifies the signature, installs the containing app with both extensions, and launches it.

After the first install:

1. Open **Settings → General → Keyboard → Keyboards → Add New Keyboard**.
2. Add **Gemini Voice** and enable **Allow Full Access**. App Group communication requires it.
3. Open Gemini Voice once and allow microphone access.
4. Switch to the keyboard in a normal text field, tap **Dictate**, speak, and tap the send arrow.

Custom keyboards do not appear in secure password fields, some phone-pad fields, or apps that block third-party keyboards.

## Security and App Store caveats

- Google says not to ship long-lived API keys in mobile apps. Production batch requests need an authenticated backend proxy. Direct Live connections should use backend-issued [ephemeral tokens](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens).
- The personal Debug handoff dynamically accesses private UIKit, SpringBoard, Security, and LaunchServices behavior. It is isolated behind `GEMINI_PERSONAL_DEVICE` and absent from Release.
- Apple states that App Store apps may use only public APIs. Release uses the supported manual return path, but distribution still requires a fresh privacy, background-audio, authentication, and App Review assessment.
- Full Access lets the keyboard use networking and the App Group. This keyboard never sends keystrokes or surrounding document text to Gemini; it stores only short-lived request metadata and SHA-256 context fingerprints.
- Review the included privacy manifests and make your own App Store privacy disclosures. Data handling can differ by Gemini service tier and account configuration.

Relevant primary documentation:

- [Gemini audio transcription](https://ai.google.dev/gemini-api/docs/transcribe)
- [Gemini Live transcription](https://ai.google.dev/gemini-api/docs/live-api/live-transcribe)
- [Gemini API key security](https://ai.google.dev/gemini-api/docs/api-key)
- [Apple custom keyboard open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## Project policy

This repository is provided as an unsupported, read-only sample. There is no support commitment, roadmap, or guarantee that a current model, iOS release, signing setup, or private integration will keep working. Contributions are not accepted; fork or copy the code and adapt it for your own use.

## License

Licensed under the [Apache License 2.0](LICENSE). You may use, modify, and redistribute the sample subject to that license.
