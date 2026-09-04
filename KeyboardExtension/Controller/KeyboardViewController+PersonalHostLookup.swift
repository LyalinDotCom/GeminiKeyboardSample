import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  #if GEMINI_PERSONAL_DEVICE
    func hostProcessIdentifierForHandoff() -> Int32? {
      let selector = NSSelectorFromString(
        ["_host", "ProcessIdentifier"].joined()
      )
      guard responds(to: selector) else {
        NSLog("GV_HANDOFF_HOST_LOOKUP unavailable-selector")
        return nil
      }

      typealias HostProcessIdentifier =
        @convention(c) (
          AnyObject,
          Selector
        ) -> Int32
      let processIdentifier = unsafeBitCast(
        method(for: selector),
        to: HostProcessIdentifier.self
      )(self, selector)
      guard processIdentifier > 1 else {
        NSLog("GV_HANDOFF_HOST_LOOKUP invalid-pid=%d", processIdentifier)
        return nil
      }
      return processIdentifier
    }

    /// iOS 26.4+ can publish the exact source bundle through UIKit's keyboard
    /// arbiter even when process inspection is sandboxed. The host PID is
    /// captured while this keyboard is still attached; only an arbiter record
    /// for that same PID is accepted.
    func keyboardArbiterClient(
      capturedHostProcessIdentifier: Int32
    ) -> NSObject? {
      let className = ["_UIKeyboard", "ArbiterClient"].joined()
      let sharedSelector = NSSelectorFromString(
        ["automaticShared", "ArbiterClient"].joined()
      )
      guard let arbiterClass = NSClassFromString(className),
        enableKeyboardArbiterForPersonalExtension(arbiterClass),
        let sharedMethod = class_getClassMethod(
          arbiterClass,
          sharedSelector
        )
      else {
        NSLog("GV_HANDOFF_HOST_LOOKUP keyboard-arbiter-unavailable")
        return nil
      }

      typealias SharedArbiterClient =
        @convention(c) (
          AnyObject,
          Selector
        ) -> AnyObject?
      let sharedArbiterClient = unsafeBitCast(
        method_getImplementation(sharedMethod),
        to: SharedArbiterClient.self
      )
      let classObject: AnyObject = arbiterClass
      guard
        let client = sharedArbiterClient(
          classObject,
          sharedSelector
        ) as? NSObject
      else {
        NSLog("GV_HANDOFF_HOST_LOOKUP keyboard-arbiter-client-missing")
        return nil
      }

      let checkConnectionSelector = NSSelectorFromString(
        ["check", "Connection"].joined()
      )
      guard client.responds(to: checkConnectionSelector) else {
        NSLog("GV_HANDOFF_HOST_LOOKUP keyboard-arbiter-check-missing")
        return nil
      }
      typealias CheckConnection =
        @convention(c) (
          AnyObject,
          Selector
        ) -> Void
      let checkConnection = unsafeBitCast(
        client.method(for: checkConnectionSelector),
        to: CheckConnection.self
      )
      checkConnection(client, checkConnectionSelector)

      NSLog(
        "GV_HANDOFF_HOST_LOOKUP keyboard-arbiter-start pid=%d",
        capturedHostProcessIdentifier
      )
      return client
    }

    /// UIKit disables the shared arbiter singleton inside third-party keyboard
    /// extensions. Current keyboard frameworks enable it before the singleton's
    /// one-time initialization so its read-only source state is available.
    func enableKeyboardArbiterForPersonalExtension(
      _ arbiterClass: AnyClass
    ) -> Bool {
      if Self.keyboardArbiterEnabledOverrideInstalled { return true }

      let enabledSelector = NSSelectorFromString("enabled")
      guard
        let enabledMethod = class_getClassMethod(
          arbiterClass,
          enabledSelector
        )
      else {
        NSLog("GV_HANDOFF_HOST_LOOKUP keyboard-arbiter-enabled-missing")
        return false
      }

      let enabledBlock: @convention(block) (AnyObject) -> Bool = { _ in true }
      method_setImplementation(
        enabledMethod,
        imp_implementationWithBlock(enabledBlock)
      )
      Self.keyboardArbiterEnabledOverrideInstalled = true
      NSLog("GV_HANDOFF_HOST_LOOKUP keyboard-arbiter-enabled")
      return true
    }

    func exactHostBundleIdentifier(
      from arbiterClient: NSObject,
      capturedHostProcessIdentifier: Int32
    ) -> String? {
      let now = Date()
      recentArbiterHosts = recentArbiterHosts.filter {
        now.timeIntervalSince($0.value.observedAt) < 2
      }

      let currentStateSelector = NSSelectorFromString(
        ["currentClient", "State"].joined()
      )
      if arbiterClient.responds(to: currentStateSelector) {
        typealias ObjectGetter =
          @convention(c) (
            AnyObject,
            Selector
          ) -> AnyObject?
        let currentState =
          unsafeBitCast(
            arbiterClient.method(for: currentStateSelector),
            to: ObjectGetter.self
          )(arbiterClient, currentStateSelector) as? NSObject

        if let currentState,
          let observation = keyboardArbiterObservation(from: currentState)
        {
          recentArbiterHosts[observation.processIdentifier] = (
            observation.bundleIdentifier,
            now
          )
          NSLog(
            "GV_HANDOFF_HOST_LOOKUP keyboard-arbiter-observed pid=%d bundle=%@",
            observation.processIdentifier,
            observation.bundleIdentifier
          )
        }
      }

      guard let cached = recentArbiterHosts[capturedHostProcessIdentifier],
        let exactBundleIdentifier =
          PersonalDeviceHostFallback.exactArbiterDestination(
            capturedHostProcessIdentifier: capturedHostProcessIdentifier,
            observedProcessIdentifier: capturedHostProcessIdentifier,
            sourceBundleIdentifier: cached.bundleIdentifier
          ),
        !isGeminiVoiceBundleIdentifier(exactBundleIdentifier)
      else {
        return nil
      }
      return exactBundleIdentifier
    }

    func keyboardArbiterObservation(
      from state: NSObject
    ) -> (processIdentifier: Int32, bundleIdentifier: String)? {
      let processIdentifierSelector = NSSelectorFromString(
        ["process", "Identifier"].joined()
      )
      let sourceBundleSelector = NSSelectorFromString(
        ["sourceBundle", "Identifier"].joined()
      )
      guard state.responds(to: processIdentifierSelector),
        state.responds(to: sourceBundleSelector)
      else {
        return nil
      }

      typealias ProcessIdentifier =
        @convention(c) (
          AnyObject,
          Selector
        ) -> Int32
      typealias ObjectGetter =
        @convention(c) (
          AnyObject,
          Selector
        ) -> AnyObject?
      let processIdentifier = unsafeBitCast(
        state.method(for: processIdentifierSelector),
        to: ProcessIdentifier.self
      )(state, processIdentifierSelector)
      guard processIdentifier > 1,
        let bundleIdentifier = unsafeBitCast(
          state.method(for: sourceBundleSelector),
          to: ObjectGetter.self
        )(state, sourceBundleSelector) as? String,
        RelayLaunchRequest.isValidBundleIdentifier(bundleIdentifier),
        !isGeminiVoiceBundleIdentifier(bundleIdentifier)
      else {
        return nil
      }
      return (processIdentifier, bundleIdentifier)
    }

    func pollKeyboardArbiter(
      _ arbiterClient: NSObject,
      capturedHostProcessIdentifier: Int32,
      requestID: String,
      generation: Int,
      deadline: Date,
      completion: @escaping (String?) -> Void
    ) {
      guard hostResolutionGeneration == generation,
        hostResolutionPendingForRequestID == requestID,
        activeRequestID == requestID,
        mode == .openingHost,
        keyboardIsVisible,
        view.window != nil
      else {
        return
      }

      if let bundleIdentifier = exactHostBundleIdentifier(
        from: arbiterClient,
        capturedHostProcessIdentifier: capturedHostProcessIdentifier
      ) {
        completion(
          recordPersonalResolvedHost(
            bundleIdentifier,
            route: "keyboard-arbiter"
          )
        )
        return
      }

      guard Date() < deadline else {
        if let defaults = UserDefaults(
          suiteName: VoiceAppGroup.identifier
        ) {
          defaults.set(requestID, forKey: "relay.handoff.request-id")
          defaults.set(
            Int(capturedHostProcessIdentifier),
            forKey: "relay.handoff.host-process-id"
          )
          defaults.synchronize()
        }
        completion(
          personalHostLookupUnavailable(
            reason: "keyboard-arbiter-timeout"
          )
        )
        return
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
        self?.pollKeyboardArbiter(
          arbiterClient,
          capturedHostProcessIdentifier: capturedHostProcessIdentifier,
          requestID: requestID,
          generation: generation,
          deadline: deadline,
          completion: completion
        )
      }
    }

    /// UIKit still exposes this ViewServices getter in the personal Debug
    /// runtime, although iOS 26.4 and later may return nil on hardware. Try it
    /// before the audit-token and process-identity paths.
    func hostBundleIdentifierFromViewServices() -> String? {
      let selector = NSSelectorFromString(
        ["_host", "ApplicationBundleIdentifier"].joined()
      )
      guard responds(to: selector),
        let rawValue = perform(selector)?.takeUnretainedValue(),
        let identifier = rawValue as? String,
        RelayLaunchRequest.isValidBundleIdentifier(identifier),
        !isGeminiVoiceBundleIdentifier(identifier)
      else {
        return nil
      }
      return identifier
    }

    /// Current iOS hardware can expose a host PID while denying its executable
    /// path. Ask SpringBoard for that already-known PID first. If exact lookup
    /// is restricted, compare the PID with Messages' running PID; neither route
    /// enumerates or guesses an unrelated originating application.
    func hostBundleIdentifierFromSpringBoard(
      processIdentifier: Int32
    ) -> (bundleIdentifier: String, route: String)? {
      let frameworkPath = [
        "/System/Library/PrivateFrameworks",
        "SpringBoardServices.framework",
        "SpringBoardServices",
      ].joined(separator: "/")
      guard
        let frameworkHandle = dlopen(
          frameworkPath,
          RTLD_LAZY | RTLD_LOCAL
        )
      else {
        return nil
      }
      defer { dlclose(frameworkHandle) }

      let copyIdentifierName = [
        "SBSCopyDisplayIdentifier",
        "ForProcessID",
      ].joined()
      if let copyIdentifierSymbol = dlsym(
        frameworkHandle,
        copyIdentifierName
      ) {
        typealias CopyDisplayIdentifier =
          @convention(c) (
            Int32
          ) -> Unmanaged<AnyObject>?
        let copyDisplayIdentifier = unsafeBitCast(
          copyIdentifierSymbol,
          to: CopyDisplayIdentifier.self
        )
        if let value = copyDisplayIdentifier(
          processIdentifier
        )?.takeRetainedValue() as? NSString {
          let identifier = value as String
          if RelayLaunchRequest.isValidBundleIdentifier(identifier),
            !isGeminiVoiceBundleIdentifier(identifier)
          {
            return (identifier, "springboard-display-id")
          }
        }
      }

      let processIDName = [
        "SBSProcessID",
        "ForDisplayIdentifier",
      ].joined()
      guard let processIDSymbol = dlsym(frameworkHandle, processIDName) else {
        return nil
      }
      typealias ProcessIDForDisplayIdentifier =
        @convention(c) (
          AnyObject,
          UnsafeMutablePointer<Int32>?
        ) -> Bool
      let processIDForDisplayIdentifier = unsafeBitCast(
        processIDSymbol,
        to: ProcessIDForDisplayIdentifier.self
      )
      var messagesProcessIdentifier: Int32 = 0
      let foundMessages = processIDForDisplayIdentifier(
        PersonalDeviceHostFallback.messagesBundleIdentifier as NSString,
        &messagesProcessIdentifier
      )
      guard foundMessages,
        messagesProcessIdentifier == processIdentifier
      else {
        return nil
      }
      return (
        PersonalDeviceHostFallback.messagesBundleIdentifier,
        "springboard-messages-pid"
      )
    }

    private func isGeminiVoiceBundleIdentifier(_ identifier: String) -> Bool {
      if identifier == Bundle.main.bundleIdentifier {
        return true
      }
      return identifier == Bundle.main.object(
        forInfoDictionaryKey: "GeminiVoiceContainingAppBundleIdentifier"
      ) as? String
    }

    func hostProcessName(
      for processIdentifier: Int32,
      processHandle: UnsafeMutableRawPointer
    ) -> String? {
      let processNameSymbol = ["proc", "name"].joined(separator: "_")
      guard let symbol = dlsym(processHandle, processNameSymbol) else {
        return nil
      }
      typealias ProcessName =
        @convention(c) (
          Int32,
          UnsafeMutableRawPointer,
          UInt32
        ) -> Int32
      let processName = unsafeBitCast(symbol, to: ProcessName.self)
      var nameBuffer = [CChar](repeating: 0, count: 1_024)
      let nameLength = nameBuffer.withUnsafeMutableBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return Int32(0) }
        return processName(
          processIdentifier,
          baseAddress,
          UInt32(bytes.count)
        )
      }
      guard nameLength > 0,
        let name = nameBuffer.withUnsafeBufferPointer({ buffer in
          buffer.baseAddress.flatMap(String.init(validatingUTF8:))
        }), !name.isEmpty
      else {
        return nil
      }
      return name
    }

    /// When no exact host or strict Messages process match is available, keep
    /// the one-time request armed and let the containing app show swipe-back
    /// guidance. Never turn an unknown application into Messages.
    func personalHostLookupUnavailable(
      reason: String,
      persist: Bool = true
    ) -> String? {
      NSLog(
        persist
          ? "GV_HANDOFF_HOST_LOOKUP manual-return reason=%@"
          : "GV_HANDOFF_HOST_LOOKUP continuing-arbiter reason=%@",
        reason
      )
      guard persist else { return nil }
      if let defaults = UserDefaults(suiteName: VoiceAppGroup.identifier) {
        defaults.set("manual-return", forKey: "relay.handoff.host-lookup")
        defaults.set(reason, forKey: "relay.handoff.host-lookup-reason")
        defaults.removeObject(forKey: "relay.handoff.origin-bundle-identifier")
        defaults.set(Date().timeIntervalSince1970, forKey: "relay.handoff.host-lookup-at")
        defaults.synchronize()
      }
      return nil
    }

    func recordPersonalResolvedHost(
      _ bundleIdentifier: String,
      route: String
    ) -> String {
      if let defaults = UserDefaults(suiteName: VoiceAppGroup.identifier) {
        defaults.set(
          "resolved-\(route)",
          forKey: "relay.handoff.host-lookup"
        )
        defaults.removeObject(forKey: "relay.handoff.host-lookup-reason")
        defaults.set(
          bundleIdentifier,
          forKey: "relay.handoff.origin-bundle-identifier"
        )
        defaults.set(
          Date().timeIntervalSince1970,
          forKey: "relay.handoff.host-lookup-at"
        )
        defaults.synchronize()
      }
      return bundleIdentifier
    }

    func hostSigningIdentifierFromAuditToken() -> String? {
      let auditTokenSelector = NSSelectorFromString(
        ["_host", "AuditToken"].joined()
      )
      guard responds(to: auditTokenSelector),
        let auditTokenValue = value(
          forKey: NSStringFromSelector(auditTokenSelector)
        ) as? NSValue
      else {
        return nil
      }

      var tokenSize = 0
      NSGetSizeAndAlignment(auditTokenValue.objCType, &tokenSize, nil)
      guard tokenSize == 32 else { return nil }

      var tokenBytes = [UInt8](repeating: 0, count: tokenSize)
      tokenBytes.withUnsafeMutableBytes { bytes in
        if let baseAddress = bytes.baseAddress {
          auditTokenValue.getValue(baseAddress, size: bytes.count)
        }
      }

      guard let processHandle = dlopen(nil, RTLD_LAZY) else { return nil }
      defer { dlclose(processHandle) }
      let createTaskName = ["SecTaskCreate", "WithAuditToken"].joined()
      let copyIdentifierName = ["SecTaskCopy", "SigningIdentifier"].joined()
      guard let createTaskSymbol = dlsym(processHandle, createTaskName),
        let copyIdentifierSymbol = dlsym(processHandle, copyIdentifierName)
      else {
        return nil
      }

      typealias CreateTask =
        @convention(c) (
          UnsafeRawPointer?,
          UnsafeRawPointer
        ) -> Unmanaged<AnyObject>?
      typealias CopySigningIdentifier =
        @convention(c) (
          AnyObject,
          UnsafeMutableRawPointer?
        ) -> Unmanaged<AnyObject>?
      let createTask = unsafeBitCast(createTaskSymbol, to: CreateTask.self)
      let copySigningIdentifier = unsafeBitCast(
        copyIdentifierSymbol,
        to: CopySigningIdentifier.self
      )

      return tokenBytes.withUnsafeBytes { bytes -> String? in
        guard let baseAddress = bytes.baseAddress,
          let task = createTask(nil, baseAddress)?.takeRetainedValue(),
          let identifier = copySigningIdentifier(
            task,
            nil
          )?.takeRetainedValue() as? NSString
        else {
          return nil
        }
        return identifier as String
      }
    }
  #endif
}
