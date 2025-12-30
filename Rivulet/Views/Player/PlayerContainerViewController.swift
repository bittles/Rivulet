//
//  PlayerContainerViewController.swift
//  Rivulet
//
//  UIViewController wrapper for video player that intercepts Menu button on tvOS.
//  This bypasses SwiftUI's fullScreenCover gesture handling to give us full control.
//

import SwiftUI
import UIKit

#if os(tvOS)

/// Container view controller that hosts the SwiftUI player view and intercepts button presses.
/// This allows us to handle Menu button presses before SwiftUI dismisses the player.
class PlayerContainerViewController: UIViewController {

    // MARK: - Properties

    private var hostingController: UIHostingController<AnyView>?

    /// Reference to the player view model for handling Menu button logic
    weak var viewModel: UniversalPlayerViewModel?

    /// Callback when player is dismissed (to update SwiftUI state)
    var onDismiss: (() -> Void)?

    // MARK: - Initialization

    init<Content: View>(rootView: Content, viewModel: UniversalPlayerViewModel? = nil) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .fullScreen

        let hosting = UIHostingController(rootView: AnyView(rootView))
        hosting.view.backgroundColor = .black
        self.hostingController = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        if let hosting = hostingController {
            addChild(hosting)
            view.addSubview(hosting.view)
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            hosting.didMove(toParent: self)
        }

        // Menu button is handled via pressesBegan (not gesture recognizer)
        // to avoid double-firing issues
        // Left/right arrow tap vs hold is also handled via pressesBegan/pressesEnded
        // This gives us precise timing control without gesture recognizer delays
        print("🎮 [SETUP] PlayerContainerViewController configured for button handling via pressesBegan/pressesEnded")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ensure we're first responder to intercept all button events
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    /// Override dismiss to intercept system-triggered dismissals (e.g., from Menu button)
    /// and only allow dismissal when we've explicitly decided to dismiss.
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        // If we just handled a menu action that closed something, block this dismiss
        if blockNextDismiss {
            print("🎮 [DISMISS INTERCEPT] Blocked - menu action already handled this press")
            blockNextDismiss = false
            return
        }

        // Check if we have something to close before allowing dismiss
        if let vm = viewModel {
            if vm.postVideoState != .hidden {
                print("🎮 [DISMISS INTERCEPT] Post-video visible - dismissing normally")
                vm.dismissPostVideo()
                super.dismiss(animated: flag, completion: completion)
                return
            }
            if vm.isScrubbing {
                print("🎮 [DISMISS INTERCEPT] Scrubbing active - cancelling scrub instead")
                vm.cancelScrub()
                return
            }
            if vm.showInfoPanel {
                print("🎮 [DISMISS INTERCEPT] Info panel open - closing it instead")
                withAnimation(.easeOut(duration: 0.3)) {
                    vm.showInfoPanel = false
                }
                return
            }
            if vm.showControls {
                print("🎮 [DISMISS INTERCEPT] Controls visible - hiding them instead")
                withAnimation(.easeOut(duration: 0.25)) {
                    vm.showControls = false
                }
                return
            }
        }
        // Nothing to close, allow normal dismiss
        print("🎮 [DISMISS INTERCEPT] Nothing to close - allowing dismiss")
        super.dismiss(animated: flag, completion: completion)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // Notify when dismissed
        if isBeingDismissed || isMovingFromParent {
            onDismiss?()
        }
    }

    // MARK: - Button Interception

    /// Track if we're currently consuming presses
    private var isHandlingMenuPress = false
    private var isHandlingSelectPress = false
    private var isHandlingLeftArrow = false
    private var isHandlingRightArrow = false
    private var arrowHoldTimer: Timer?
    private var didStartScrubbing = false
    private let holdThreshold: TimeInterval = 0.4

    /// Flag to block dismiss calls that occur immediately after we handled a menu action
    /// This prevents the double-handling issue where handleMenuButton() closes something,
    /// then SwiftUI's responder chain also calls dismiss().
    private var blockNextDismiss = false

    /// Siri Remote touchpad click types (undocumented but discovered via logging)
    /// These are different from standard UIPress.PressType arrow values
    private let siriRemoteTouchpadRight: Int = 2079
    private let siriRemoteTouchpadLeft: Int = 2080

    /// Check if a press is a left arrow (standard or Siri Remote touchpad)
    private func isLeftArrowPress(_ press: UIPress) -> Bool {
        return press.type == .leftArrow || press.type.rawValue == siriRemoteTouchpadLeft
    }

    /// Check if a press is a right arrow (standard or Siri Remote touchpad)
    private func isRightArrowPress(_ press: UIPress) -> Bool {
        return press.type == .rightArrow || press.type.rawValue == siriRemoteTouchpadRight
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu {
                isHandlingMenuPress = true
                handleMenuButton()
                return
            }
            if press.type == .select {
                if let vm = viewModel {
                    if vm.isScrubbing {
                        print("🎮 [SELECT] Committing scrub")
                        isHandlingSelectPress = true
                        Task { await vm.commitScrub() }
                        return
                    } else if vm.showInfoPanel {
                        isHandlingSelectPress = true
                        handleSelectButton()
                        return
                    }
                }
            }
            // Handle left arrow (standard or Siri Remote touchpad type 2080)
            if isLeftArrowPress(press) {
                if let vm = viewModel, !vm.showInfoPanel {
                    print("🎮 [LEFT] Press began - starting hold detection")
                    handleArrowBegan(forward: false)
                    return
                }
            }
            // Handle right arrow (standard or Siri Remote touchpad type 2079)
            if isRightArrowPress(press) {
                if let vm = viewModel, !vm.showInfoPanel {
                    print("🎮 [RIGHT] Press began - starting hold detection")
                    handleArrowBegan(forward: true)
                    return
                }
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu && isHandlingMenuPress {
                isHandlingMenuPress = false
                return
            }
            if press.type == .select && isHandlingSelectPress {
                isHandlingSelectPress = false
                return
            }
            // Handle left arrow end (standard or Siri Remote touchpad)
            if isLeftArrowPress(press) && isHandlingLeftArrow {
                print("🎮 [LEFT] Press ended")
                handleArrowEnded(forward: false)
                return
            }
            // Handle right arrow end (standard or Siri Remote touchpad)
            if isRightArrowPress(press) && isHandlingRightArrow {
                print("🎮 [RIGHT] Press ended")
                handleArrowEnded(forward: true)
                return
            }
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu && isHandlingMenuPress {
                isHandlingMenuPress = false
                return
            }
            if press.type == .select && isHandlingSelectPress {
                isHandlingSelectPress = false
                return
            }
            if isLeftArrowPress(press) && isHandlingLeftArrow {
                cancelArrowHandling()
                return
            }
            if isRightArrowPress(press) && isHandlingRightArrow {
                cancelArrowHandling()
                return
            }
        }
        super.pressesCancelled(presses, with: event)
    }

    // MARK: - Arrow Key Tap vs Hold Detection

    private func handleArrowBegan(forward: Bool) {
        guard let vm = viewModel else { return }

        // If already scrubbing, adjust speed/direction
        if vm.isScrubbing {
            print("🎮 [ARROW] Already scrubbing - adjusting")
            vm.scrubInDirection(forward: forward)
            vm.showControlsTemporarily()
            return
        }

        // Track this press
        if forward {
            isHandlingRightArrow = true
        } else {
            isHandlingLeftArrow = true
        }
        didStartScrubbing = false

        // Start hold timer
        arrowHoldTimer?.invalidate()
        arrowHoldTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self = self, let vm = self.viewModel else { return }
            print("🎮 [ARROW HOLD] Timer fired after \(self.holdThreshold)s - starting scrub")
            self.didStartScrubbing = true
            Task { @MainActor in
                vm.scrubInDirection(forward: forward)
                vm.showControlsTemporarily()
            }
        }
        print("🎮 [ARROW] Started hold timer (\(holdThreshold)s)")
    }

    private func handleArrowEnded(forward: Bool) {
        arrowHoldTimer?.invalidate()
        arrowHoldTimer = nil

        if forward {
            isHandlingRightArrow = false
        } else {
            isHandlingLeftArrow = false
        }

        guard let vm = viewModel else { return }

        if didStartScrubbing {
            print("🎮 [ARROW] Was a hold - scrubbing is active")
            didStartScrubbing = false
        } else {
            print("🎮 [ARROW] Was a tap - seeking \(forward ? "+10s" : "-10s")")
            Task { await vm.seekRelative(by: forward ? 10 : -10) }
            vm.showControlsTemporarily()
        }
    }

    private func cancelArrowHandling() {
        arrowHoldTimer?.invalidate()
        arrowHoldTimer = nil
        isHandlingLeftArrow = false
        isHandlingRightArrow = false
        didStartScrubbing = false
    }

    /// Handle Menu button press with priority:
    /// 1. Dismiss post-video overlay if showing
    /// 2. Cancel scrubbing if active
    /// 3. Close info panel if open
    /// 4. Hide controls if visible
    /// 5. Dismiss player if nothing else to close
    private func handleMenuButton() {
        guard let vm = viewModel else {
            print("🎮 [MENU] No viewModel - dismissing player")
            dismissPlayer()
            return
        }

        print("🎮 [MENU] State check: postVideo=\(vm.postVideoState), scrubbing=\(vm.isScrubbing), infoPanel=\(vm.showInfoPanel), controls=\(vm.showControls)")

        if vm.postVideoState != .hidden {
            print("🎮 [MENU] Dismissing post-video overlay and player")
            vm.dismissPostVideo()
            dismissPlayer()
        } else if vm.isScrubbing {
            print("🎮 [MENU] Cancelling scrub")
            blockNextDismiss = true  // Block any subsequent dismiss from SwiftUI
            vm.cancelScrub()
        } else if vm.showInfoPanel {
            print("🎮 [MENU] Closing info panel")
            blockNextDismiss = true  // Block any subsequent dismiss from SwiftUI
            withAnimation(.easeOut(duration: 0.3)) {
                vm.showInfoPanel = false
            }
        } else if vm.showControls {
            print("🎮 [MENU] Hiding controls")
            blockNextDismiss = true  // Block any subsequent dismiss from SwiftUI
            withAnimation(.easeOut(duration: 0.25)) {
                vm.showControls = false
            }
        } else {
            print("🎮 [MENU] Nothing to close - dismissing player")
            dismissPlayer()
        }
    }

    /// Handle Select button press when info panel is open
    private func handleSelectButton() {
        guard let vm = viewModel else { return }
        vm.selectFocusedSetting()
    }

    private func dismissPlayer() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
}

#endif
