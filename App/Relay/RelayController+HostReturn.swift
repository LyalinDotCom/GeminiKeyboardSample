import AVFoundation
import Combine
import Darwin
import Foundation
import ObjectiveC
import UIKit

extension RelayController {
  func scheduleAutomaticReturnToKeyboard(
    requestID: String,
    originatingApplicationBundleIdentifier: String?,
    delay: TimeInterval
  ) {
    #if GEMINI_PERSONAL_DEVICE
      let returnDecision = RelayHostReturnPolicy.decision(
        originatingApplicationBundleIdentifier:
          originatingApplicationBundleIdentifier,
        containingApplicationBundleIdentifier: Bundle.main.bundleIdentifier
      )
      let bundleIdentifier: String?
      if case .automatic(let exactBundleIdentifier) = returnDecision {
        bundleIdentifier = exactBundleIdentifier
      } else {
        bundleIdentifier = nil
      }

      // The system's own Back-to-app navigation action identifies the exact
      // previous scene and does not require a bundle guess. Keep the overlay
      // in its returning state while that short-lived action is available.
      requiresManualKeyboardReturn = false

      let hostReturn = PendingHostReturn(
        requestID: requestID,
        bundleIdentifier: bundleIdentifier
      )
      if pendingHostReturn == hostReturn {
        if returnToKeyboardWorkItem == nil, hostReturnAttemptCount < 2 {
          schedulePendingHostReturnIfReady(delay: delay)
        }
        return
      }
      cancelAutomaticReturnToKeyboard()
      pendingHostReturn = hostReturn
      hostReturnAttemptCount = 0
      systemNavigationReturnDeadline = nil
      systemNavigationReturnAccepted = false
      schedulePendingHostReturnIfReady(delay: delay)
    #endif
  }

  func manualReturnRequired(for _: RelayLaunchRequest) -> Bool {
    #if GEMINI_PERSONAL_DEVICE
      // Even without a discovered bundle, iOS may provide an exact system
      // previous-app action after opening this deep link. Show manual return
      // only after that bounded attempt (and any exact bundle fallback) fails.
      return false
    #else
      return true
    #endif
  }

  #if GEMINI_PERSONAL_DEVICE
    func schedulePendingHostReturnIfReady(delay: TimeInterval = 0) {
      guard let pendingHostReturn,
        hostReturnAttemptCount < 2,
        isRelayRunning,
        status == .idle,
        activeRequestID == nil,
        pendingLaunchRequest?.requestID == pendingHostReturn.requestID
      else {
        return
      }

      guard UIApplication.shared.applicationState == .active else {
        NSLog("GV_HANDOFF_RETURN_PATH waiting-for-active")
        publishHandoffDiagnostic(
          event: "waiting-for-active",
          requestID: pendingHostReturn.requestID,
          bundleIdentifier: pendingHostReturn.bundleIdentifier
        )
        return
      }

      if systemNavigationReturnDeadline == nil {
        // Start the bounded lookup only after Gemini Voice is active; a
        // deadline created during the foreground animation could expire
        // before UIKit publishes its previous-app action.
        systemNavigationReturnDeadline = Date().addingTimeInterval(1.2)
      }

      returnToKeyboardWorkItem?.cancel()
      returnToKeyboardGeneration += 1
      let returnGeneration = returnToKeyboardGeneration
      let workItem = DispatchWorkItem { [weak self] in
        guard let self,
          self.returnToKeyboardGeneration == returnGeneration
        else {
          return
        }
        self.returnToKeyboardWorkItem = nil
        self.attemptPendingHostReturn(pendingHostReturn)
      }
      returnToKeyboardWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func attemptPendingHostReturn(_ pendingHostReturn: PendingHostReturn) {
      guard self.pendingHostReturn == pendingHostReturn,
        isRelayRunning,
        status == .idle,
        activeRequestID == nil,
        pendingLaunchRequest?.requestID == pendingHostReturn.requestID,
        UIApplication.shared.applicationState == .active
      else {
        return
      }

      if !systemNavigationReturnAccepted {
        let systemNavigation = Self.returnThroughSystemNavigationAction(
          expectedBundleIdentifier: pendingHostReturn.bundleIdentifier
        )
        NSLog(
          "GV_HANDOFF_RETURN_PATH system-navigation stage=%@ result=%@",
          systemNavigation.stage,
          systemNavigation.accepted ? "true" : "false"
        )
        publishHandoffDiagnostic(
          event: "system-navigation-\(systemNavigation.stage)",
          requestID: pendingHostReturn.requestID,
          bundleIdentifier: pendingHostReturn.bundleIdentifier,
          result: systemNavigation.accepted
        )

        if systemNavigation.accepted {
          systemNavigationReturnAccepted = true
          // SpringBoard performs the exact previous-scene transition
          // asynchronously. If it is dropped, use an exact bundle only
          // as a fallback; otherwise show truthful swipe-back guidance.
          schedulePendingHostReturnIfReady(delay: 0.7)
          return
        }

        if let deadline = systemNavigationReturnDeadline,
          Date() < deadline
        {
          schedulePendingHostReturnIfReady(delay: 0.08)
          return
        }
      }

      guard let bundleIdentifier = pendingHostReturn.bundleIdentifier else {
        NSLog("GV_HANDOFF_RETURN_UNAVAILABLE exact-system-action-missing")
        publishHandoffDiagnostic(
          event: "manual-return-no-exact-destination",
          requestID: pendingHostReturn.requestID,
          result: false
        )
        scheduleManualReturnFallbackIfStillForeground(
          pendingHostReturn,
          delay: 0
        )
        return
      }

      hostReturnAttemptCount += 1
      let activation = Self.reactivateApplication(
        bundleIdentifier: bundleIdentifier
      )
      NSLog(
        "GV_HANDOFF_RETURN_PATH host-reactivation bundle=%@ attempt=%d stage=%@ result=%@",
        bundleIdentifier,
        hostReturnAttemptCount,
        activation.stage,
        activation.accepted ? "true" : "false"
      )
      publishHandoffDiagnostic(
        event: "host-reactivation-\(activation.stage)",
        requestID: pendingHostReturn.requestID,
        bundleIdentifier: bundleIdentifier,
        attempt: hostReturnAttemptCount,
        result: activation.accepted
      )

      // A successful LaunchServices return is asynchronous. If SpringBoard
      // accepted but dropped the first request while Gemini's foreground
      // transition was settling, retry once from the now-active app process.
      if hostReturnAttemptCount < 2,
        UIApplication.shared.applicationState == .active
      {
        schedulePendingHostReturnIfReady(delay: 0.35)
        return
      }

      // LaunchServices acceptance only means the private request was queued;
      // it does not prove that SpringBoard switched scenes. After the final
      // attempt, allow a short transition window, then give truthful manual
      // guidance if Gemini Voice is still the foreground app. Keep the launch
      // authorization intact so the returned keyboard can still claim it.
      scheduleManualReturnFallbackIfStillForeground(
        pendingHostReturn,
        delay: activation.accepted ? 0.6 : 0
      )
    }

    func scheduleManualReturnFallbackIfStillForeground(
      _ pendingHostReturn: PendingHostReturn,
      delay: TimeInterval
    ) {
      returnToKeyboardWorkItem?.cancel()
      returnToKeyboardGeneration += 1
      let returnGeneration = returnToKeyboardGeneration
      let workItem = DispatchWorkItem { [weak self] in
        guard let self,
          self.returnToKeyboardGeneration == returnGeneration,
          self.pendingHostReturn == pendingHostReturn,
          self.pendingLaunchRequest?.requestID == pendingHostReturn.requestID,
          self.status == .idle,
          self.activeRequestID == nil,
          UIApplication.shared.applicationState == .active
        else {
          return
        }
        self.returnToKeyboardWorkItem = nil
        self.requiresManualKeyboardReturn = true
        self.publishHandoffDiagnostic(
          event: "manual-return-after-reactivation",
          requestID: pendingHostReturn.requestID,
          bundleIdentifier: pendingHostReturn.bundleIdentifier,
          attempt: self.hostReturnAttemptCount,
          result: false
        )
        self.cancelAutomaticReturnToKeyboard()
      }
      returnToKeyboardWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Invoke the same exact previous-scene action shown by iOS as the
    /// "Back to <app>" system affordance. Unlike a bundle launch, this action
    /// is supplied by the OS for the transition that opened Gemini Voice and
    /// preserves the originating scene when available.
    static func returnThroughSystemNavigationAction(
      expectedBundleIdentifier: String?
    )
      -> HostReactivationResult
    {
      let application = UIApplication.shared
      let actionSelector = NSSelectorFromString(
        ["_systemNavigation", "Action"].joined()
      )
      guard application.responds(to: actionSelector) else {
        return HostReactivationResult(
          accepted: false,
          stage: "selector-missing"
        )
      }

      typealias ObjectGetter =
        @convention(c) (
          AnyObject,
          Selector
        ) -> AnyObject?
      let action =
        unsafeBitCast(
          application.method(for: actionSelector),
          to: ObjectGetter.self
        )(application, actionSelector) as? NSObject
      guard let action else {
        return HostReactivationResult(
          accepted: false,
          stage: "action-pending"
        )
      }

      let destinationsSelector = NSSelectorFromString("destinations")
      guard action.responds(to: destinationsSelector),
        let destinations = unsafeBitCast(
          action.method(for: destinationsSelector),
          to: ObjectGetter.self
        )(action, destinationsSelector) as? [NSNumber],
        destinations.contains(where: { $0.uintValue == 0 })
      else {
        return HostReactivationResult(
          accepted: false,
          stage: "back-destination-missing"
        )
      }

      let canSendSelector = NSSelectorFromString(
        ["canSend", "Response"].joined()
      )
      guard action.responds(to: canSendSelector) else {
        return HostReactivationResult(
          accepted: false,
          stage: "capability-missing"
        )
      }
      typealias BoolGetter =
        @convention(c) (
          AnyObject,
          Selector
        ) -> Bool
      let canSend = unsafeBitCast(
        action.method(for: canSendSelector),
        to: BoolGetter.self
      )(action, canSendSelector)
      guard canSend else {
        return HostReactivationResult(
          accepted: false,
          stage: "not-ready"
        )
      }

      let bundleSelector = NSSelectorFromString(
        ["bundleIdFor", "Destination:"].joined()
      )
      if action.responds(to: bundleSelector) {
        typealias DestinationObjectGetter =
          @convention(c) (
            AnyObject,
            Selector,
            UInt
          ) -> AnyObject?
        let bundleIdentifier =
          unsafeBitCast(
            action.method(for: bundleSelector),
            to: DestinationObjectGetter.self
          )(action, bundleSelector, 0) as? String
        if let bundleIdentifier,
          !RelayLaunchRequest.isValidBundleIdentifier(bundleIdentifier)
        {
          return HostReactivationResult(
            accepted: false,
            stage: "invalid-destination"
          )
        }
        if bundleIdentifier == Bundle.main.bundleIdentifier {
          return HostReactivationResult(
            accepted: false,
            stage: "self-destination-rejected"
          )
        }
        if let expectedBundleIdentifier,
          let bundleIdentifier,
          bundleIdentifier != expectedBundleIdentifier
        {
          return HostReactivationResult(
            accepted: false,
            stage: "origin-mismatch"
          )
        }
      }

      let sendSelector = NSSelectorFromString(
        ["sendResponseFor", "Destination:"].joined()
      )
      guard action.responds(to: sendSelector) else {
        return HostReactivationResult(
          accepted: false,
          stage: "send-selector-missing"
        )
      }
      typealias SendResponse =
        @convention(c) (
          AnyObject,
          Selector,
          UInt
        ) -> Bool
      let accepted = unsafeBitCast(
        action.method(for: sendSelector),
        to: SendResponse.self
      )(action, sendSelector, 0)
      return HostReactivationResult(
        accepted: accepted,
        stage: accepted ? "accepted" : "api-return-false"
      )
    }

    /// LaunchServices' bundle-only open reactivates an existing app without a
    /// URL payload that would reset its navigation. This is private SPI and is
    /// intentionally absent from Release/App Store builds.
    static func reactivateApplication(
      bundleIdentifier: String
    ) -> HostReactivationResult {
      let workspaceClassName = ["LSApplication", "Workspace"].joined()
      let defaultWorkspaceSelector = NSSelectorFromString(
        ["default", "Workspace"].joined()
      )
      let openApplicationSelector = NSSelectorFromString(
        ["openApplication", "WithBundleID:"].joined()
      )

      var workspaceClass: AnyClass? = NSClassFromString(workspaceClassName)
      var frameworkLoadFailed = false
      if workspaceClass == nil {
        frameworkLoadFailed = coreServicesFrameworkHandle == nil
        workspaceClass = NSClassFromString(workspaceClassName)
      }

      guard let workspaceClass else {
        return HostReactivationResult(
          accepted: false,
          stage: frameworkLoadFailed ? "framework-load-failed" : "class-missing"
        )
      }
      guard
        let defaultWorkspaceMethod = class_getClassMethod(
          workspaceClass,
          defaultWorkspaceSelector
        )
      else {
        return HostReactivationResult(accepted: false, stage: "default-method-missing")
      }

      typealias DefaultWorkspace =
        @convention(c) (
          AnyObject,
          Selector
        ) -> AnyObject?
      let defaultWorkspace = unsafeBitCast(
        method_getImplementation(defaultWorkspaceMethod),
        to: DefaultWorkspace.self
      )
      let classObject: AnyObject = workspaceClass
      guard
        let workspace = defaultWorkspace(
          classObject,
          defaultWorkspaceSelector
        ) as? NSObject
      else {
        return HostReactivationResult(accepted: false, stage: "workspace-missing")
      }
      guard workspace.responds(to: openApplicationSelector) else {
        return HostReactivationResult(accepted: false, stage: "selector-missing")
      }

      typealias OpenApplication =
        @convention(c) (
          AnyObject,
          Selector,
          NSString
        ) -> Bool
      let openApplication = unsafeBitCast(
        workspace.method(for: openApplicationSelector),
        to: OpenApplication.self
      )
      let accepted = openApplication(
        workspace,
        openApplicationSelector,
        bundleIdentifier as NSString
      )
      return HostReactivationResult(
        accepted: accepted,
        stage: accepted ? "accepted" : "api-return-false"
      )
    }

    func publishHandoffDiagnostic(
      event: String,
      requestID: String,
      bundleIdentifier: String? = nil,
      attempt: Int? = nil,
      result: Bool? = nil
    ) {
      guard let defaults = UserDefaults(suiteName: VoiceAppGroup.identifier) else {
        return
      }
      defaults.set(event, forKey: "relay.handoff.event")
      defaults.set(requestID, forKey: "relay.handoff.request-id")
      defaults.set(Date().timeIntervalSince1970, forKey: "relay.handoff.at")
      defaults.set(
        UIApplication.shared.applicationState.rawValue,
        forKey: "relay.handoff.application-state"
      )
      if let bundleIdentifier {
        defaults.set(bundleIdentifier, forKey: "relay.handoff.bundle-identifier")
      } else {
        defaults.removeObject(forKey: "relay.handoff.bundle-identifier")
      }
      if let attempt {
        defaults.set(attempt, forKey: "relay.handoff.attempt")
      } else {
        defaults.removeObject(forKey: "relay.handoff.attempt")
      }
      if let result {
        defaults.set(result, forKey: "relay.handoff.result")
      } else {
        defaults.removeObject(forKey: "relay.handoff.result")
      }
      defaults.synchronize()
    }
  #endif
}
