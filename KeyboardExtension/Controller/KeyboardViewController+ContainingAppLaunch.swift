import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  func openContainingApp(for request: RelayLaunchRequest) {
    guard hostLaunchAttemptedForRequestID != request.requestID else { return }
    hostLaunchAttemptedForRequestID = request.requestID
    store.authorizeLaunchRequest(request)
    #if GEMINI_PERSONAL_DEVICE
      guard let url = request.makeURL(), let extensionContext else {
        handleContainingAppLaunchResult(false, requestID: request.requestID)
        return
      }

      extensionContext.open(url) { [weak self] opened in
        Task { @MainActor [weak self] in
          guard let self else { return }
          if opened {
            self.handleContainingAppLaunchResult(true, requestID: request.requestID)
          } else {
            self.openContainingAppThroughResponderChain(url) { [weak self] opened in
              self?.handleContainingAppLaunchResult(
                opened,
                requestID: request.requestID
              )
            }
          }
        }
      }
    #else
      // App Review Guideline 4.4.1 forbids keyboard extensions from launching
      // apps other than Settings. Keep the authorized request available so a
      // manual app open can still claim it, but ship no launch trampoline.
      handleContainingAppLaunchResult(false, requestID: request.requestID)
    #endif
  }

  #if GEMINI_PERSONAL_DEVICE
    /// UIKit does not officially advertise container-app launching for the
    /// custom-keyboard extension point. Current iOS releases reject the normal
    /// NSExtensionContext path, so use a responder-chain UIApplication URL
    /// opener as a personal-device fallback.
    func openContainingAppThroughResponderChain(
      _ url: URL,
      completion: @escaping (Bool) -> Void
    ) {
      let selector = NSSelectorFromString("openURL:options:completionHandler:")
      guard let applicationClass = NSClassFromString("UIApplication") else {
        completion(false)
        return
      }
      var responder: UIResponder? = self
      while let candidate = responder {
        if candidate.isKind(of: applicationClass),
          candidate.responds(to: selector)
        {
          typealias OpenURLImplementation =
            @convention(c) (
              AnyObject,
              Selector,
              NSURL,
              NSDictionary,
              @convention(block) (Bool) -> Void
            ) -> Void
          let implementation = candidate.method(for: selector)
          let openURL = unsafeBitCast(
            implementation,
            to: OpenURLImplementation.self
          )
          let completionBlock: @convention(block) (Bool) -> Void = { opened in
            NSLog(
              "GV_HANDOFF_LAUNCH_PATH modern-openURL result=%@",
              opened ? "true" : "false"
            )
            DispatchQueue.main.async { completion(opened) }
          }
          openURL(candidate, selector, url as NSURL, NSDictionary(), completionBlock)
          return
        }
        responder = candidate.next
      }
      completion(false)
    }
  #endif

  func handleContainingAppLaunchResult(_ opened: Bool, requestID: String) {
    guard !opened,
      mode == .openingHost,
      activeRequestID == requestID
    else { return }

    // Keep the App Group request alive. If iOS refuses to open the app from
    // a keyboard extension, manually opening Gemini Voice can still claim
    // this exact request and start recording without a second keyboard tap.
    hostLaunchFailureExpiresAt = trackedRequestCreatedAt?
      .addingTimeInterval(RelayLaunchRequest.defaultMaximumAge)
    refreshFromSharedState()
  }

  func resolveOriginatingApplicationBundleIdentifier(
    requestID: String,
    generation: Int,
    completion: @escaping (String?) -> Void
  ) {
    #if GEMINI_PERSONAL_DEVICE
      let capturedHostProcessIdentifier = hostProcessIdentifierForHandoff()
      let arbiterClient = capturedHostProcessIdentifier.flatMap {
        keyboardArbiterClient(capturedHostProcessIdentifier: $0)
      }

      if let capturedHostProcessIdentifier,
        let arbiterClient,
        let arbiterBundleIdentifier = exactHostBundleIdentifier(
          from: arbiterClient,
          capturedHostProcessIdentifier: capturedHostProcessIdentifier
        )
      {
        completion(
          recordPersonalResolvedHost(
            arbiterBundleIdentifier,
            route: "keyboard-arbiter"
          )
        )
        return
      }

      if let resolvedBundleIdentifier =
        originatingApplicationBundleIdentifierForHandoff(
          capturedHostProcessIdentifier: capturedHostProcessIdentifier,
          persistUnknown: arbiterClient == nil
        )
      {
        completion(resolvedBundleIdentifier)
        return
      }

      guard let capturedHostProcessIdentifier,
        let arbiterClient
      else {
        completion(nil)
        return
      }

      pollKeyboardArbiter(
        arbiterClient,
        capturedHostProcessIdentifier: capturedHostProcessIdentifier,
        requestID: requestID,
        generation: generation,
        deadline: Date().addingTimeInterval(1),
        completion: completion
      )
    #else
      completion(nil)
    #endif
  }

  /// The system does not expose a public host-app identifier to custom
  /// then ask Security for that process's signed identifier. A process-path
  /// lookup remains a fallback for OS versions where the token route changes.
  /// The value is carried only in the short-lived, authorized handoff request.
}
