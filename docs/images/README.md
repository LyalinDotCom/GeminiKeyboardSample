# README images

The PNG screenshots are unmodified iOS Simulator captures of this sample on iOS 27. Voice-note text is an in-memory visual fixture; the keyboard example was typed into the app's practice editor.

- `relay.png`: Relay home and the in-app note entry point.
- `keyboard.png`: installed Gemini Voice keyboard with Dictate and Translate controls.
- `note-recording.png`: recording sheet with live-text preview.
- `note-saved.png`: saved note and its Copy/Share actions.

`gemini-voice-hero.png` is a marketing composition created with the Nano Banana CLI, model `gemini-3-pro-image-preview`, from the four screenshots above. Its framing and background are generated. The screen interiors were composited from the original captures afterward to preserve the exact interface and text; the original captures are also included separately. The exact prompt is in [`hero-prompt.txt`](hero-prompt.txt).

To recreate note states in a Debug Simulator build, set `GEMINI_VOICE_DISABLE_RELAY_AUTOSTART=1` and `GEMINI_VOICE_VISUAL_TEST_SCENARIO=note-recording` or `note-saved`. These fixtures do not run in Release or on a physical iPhone.
