# Gemini implementation guide

This folder contains the provider-specific code. Audio capture, recovery, keyboard messaging, and UI live outside it so the Gemini protocol can be read independently.

## Batch transcription

- `Batch/GeminiTranscriptionClient.swift` creates Interactions API requests for audio transcription, translation, and image text extraction. It validates credentials and inline payload limits before networking.
- `Batch/GeminiInteractionResponse.swift` defines service errors and parses completed interaction steps into plain text.

Batch audio is a complete WAV produced by `App/Audio`. Requests set `store: false`. The inline size limit is deliberately below common transport limits; production applications should use the Files API or a backend for larger recordings.

## Live transcription

- `Live/GeminiLiveTransport.swift` defines credentials and the small socket abstraction used by production code and tests.
- `Live/GeminiLiveSpeechSession.swift` owns actor state, connection setup, and the bounded audio stream.
- `Live/GeminiLiveProtocol.swift` contains endpoint construction, JSON message builders, server-event parsing, transcript merging, and speech-energy classification.
- `Live/GeminiLiveSpeechSession+Streaming.swift` sends queued audio and consumes server events.
- `Live/GeminiLiveSpeechSession+Finalization.swift` drains audio and chooses an authoritative final transcript.
- `Live/GeminiLiveTimeout.swift` races individual async operations against bounded timeouts without trapping the app process.

The socket abstraction makes protocol behavior testable without a real network. `Tests/GeminiLiveSpeechSessionTests.swift` covers setup schema, ordering, transcript merging, stale-final rejection, cancellation, and translation completion.

## Authentication boundary

The sample accepts a directly supplied API key for a personal Debug build. That is intentionally convenient and intentionally not production-safe. A production architecture should proxy batch calls through an authenticated backend and mint constrained, short-lived ephemeral tokens for direct Live connections.

Both clients send the API key as the `x-goog-api-key` request header. The Live WebSocket accepts that header on the handshake, so the key never appears in a URL that URLSession, proxies, or crash logs might record. Ephemeral tokens use the `access_token` query form that the constrained Live endpoint documents.
