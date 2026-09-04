import Foundation

extension GeminiLiveSpeechSession {
  func finish() async throws -> String {
    try await withTaskCancellationHandler {
      try await finishAfterDrainingAudio()
    } onCancel: { [weak self] in
      Task { await self?.cancel() }
    }
  }

  func finishAfterDrainingAudio() async throws -> String {
    guard !isClosed else { return try completedText() }
    guard !isFinishing else {
      throw GeminiLiveSpeechError.connectionClosed("The stream is already finishing.")
    }
    isFinishing = true

    // Stop accepting new chunks, then wait until every chunk already yielded
    // by AudioCaptureEngine has reached the WebSocket before ending the turn.
    audioContinuation.finish()
    if let audioConsumerTask {
      do {
        try await geminiLiveWithTimeout(nanoseconds: 10_000_000_000) {
          await audioConsumerTask.value
        }
      } catch is CancellationError {
        await close(code: .goingAway)
        throw CancellationError()
      } catch {
        await close(code: .goingAway)
        throw GeminiLiveSpeechError.connectionClosed(
          "Live audio did not finish sending in time."
        )
      }
    }
    self.audioConsumerTask = nil

    if let terminalError {
      await close(code: .goingAway)
      throw terminalError
    }
    guard let socket, isConfigured else {
      await close(code: .goingAway)
      throw GeminiLiveSpeechError.connectionClosed("")
    }

    var transcriptionBoundarySentAt: Date?
    var finalInputRevisionAtBoundary: UInt64?
    var likelySpeechWasRecentAtBoundary = false
    do {
      switch mode {
      case .transcribe:
        let boundaryInitiatedAt = Date()
        likelySpeechWasRecentAtBoundary =
          lastLikelySpeechSentAt.map {
            boundaryInitiatedAt.timeIntervalSince($0) < 0.8
          } == true
        try await send(Self.activityEndMessage(), over: socket)
        // Snapshot only after the boundary send completes. A delayed
        // older segment delivered while the send is in flight remains
        // part of the baseline and cannot finalize the drained stream.
        finalInputRevisionAtBoundary = lastFinalInputRevision
        transcriptionBoundarySentAt = Date()
      case .translate:
        // A previous automatically detected translation turn may already
        // have completed. Only a generation completion observed after this
        // end-of-stream boundary can finalize the complete recording.
        generationComplete = false
        try await send(Self.audioStreamEndMessage(), over: socket)
      }
    } catch {
      terminalError = error
      await close(code: .goingAway)
      throw error
    }

    // Final transcription events normally arrive shortly after the explicit
    // push-to-talk boundary. The bounded wait guarantees batch fallback.
    for _ in 0..<100 {
      try Task.checkCancellation()
      if let terminalError {
        await close(code: .goingAway)
        throw terminalError
      }
      let text = selectedFinalText
      let finalEventIsStable: Bool
      switch mode {
      case .transcribe:
        // `inputTranscription` is the dedicated Transcribe Live
        // model's authoritative final event. Do not require the
        // conversational Live API's optional `turnComplete`, which
        // this speech-to-text endpoint is not documented to emit.
        // A newer interim means a later speech segment still needs its
        // own final. PCM energy is used only to distinguish a locally
        // established quiet pause from speech close to Finish; raw
        // packet arrival alone cannot invalidate an authoritative final.
        //
        // Require a final from the finished epoch. No delivery-time
        // threshold can prove that an older final includes speech near
        // Finish. If local PCM established a quiet pause before the
        // boundary, an authoritative earlier final remains usable. If
        // likely speech was recent, require a post-boundary final. This
        // avoids inferring server coverage from response arrival order.
        // If Gemini never sends the required newer event, the bounded
        // loop deliberately fails Live so the complete WAV is used.
        let hasUnfinalizedInterim =
          (lastInterimInputRevision ?? 0)
          > (lastFinalInputRevision ?? 0)
        let boundaryAge =
          transcriptionBoundarySentAt.map {
            Date().timeIntervalSince($0)
          } ?? 0
        let hasPostBoundaryFinal =
          lastFinalInputRevision.map { revision in
            guard let finalInputRevisionAtBoundary else { return true }
            return revision > finalInputRevisionAtBoundary
          } == true
        let finalQuietPeriodElapsed =
          lastFinalTextAt.map {
            Date().timeIntervalSince($0) >= 0.35
          } == true
        let finalIsSafeForFinishedAudio =
          hasPostBoundaryFinal
          || (!likelySpeechWasRecentAtBoundary && boundaryAge >= 0.5)
        finalEventIsStable =
          finalIsSafeForFinishedAudio
          && !hasUnfinalizedInterim
          && boundaryAge >= 0.35
          && finalQuietPeriodElapsed
      case .translate:
        // The Live API guarantees the last output transcription before
        // generationComplete. Unlike turnComplete, this does not wait for
        // the translated audio's assumed playback to finish.
        finalEventIsStable = generationComplete
      }
      if !text.isEmpty, finalEventIsStable {
        await close(code: .normalClosure)
        return text
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }

    await close(code: .goingAway)
    throw selectedFinalText.isEmpty
      ? GeminiLiveSpeechError.emptyResult
      : GeminiLiveSpeechError.connectionClosed(
        "Gemini did not confirm the final transcript."
      )
  }

  func cancel() async {
    audioContinuation.finish()
    audioConsumerTask?.cancel()
    audioConsumerTask = nil
    await close(code: .goingAway)
  }
}
