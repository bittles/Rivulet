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

        // Add tap gesture recognizer for Menu button to intercept before UIKit navigation
        let menuTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(menuTapped))
        menuTapRecognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTapRecognizer)

        // Left/right arrow tap vs hold is handled via pressesBegan/pressesEnded
        // This gives us precise timing control without gesture recognizer delays
        print("🎮 [SETUP] PlayerContainerViewController configured for arrow key handling via pressesBegan/pressesEnded")
    }

    @objc private func menuTapped() {
        print("🎮 [MENU] Gesture recognizer intercepted Menu tap")
        handleMenuButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ensure we're first responder to intercept all button events
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // Notify when dismissed
        if isBeingDismissed || isMovingFromParent {
            onDismiss?()
        }
    }

    // MARK: - Button Interception

    /// Track if we're currently consuming a Menu press
    private var isHandlingMenuPress = false
    private var isHandlingSelectPress = false

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu {
                print("🎮 [MENU] PlayerContainerViewController received Menu press (began)")
                isHandlingMenuPress = true
                handleMenuButton()
                return  // Consume the event - don't pass to super
            }
            if press.type == .select {
                if let vm = viewModel {
                    if vm.isScrubbing {
                        // Commit scrub when select is pressed during scrubbing
                        print("🎮 [SELECT] Committing scrub")
                        isHandlingSelectPress = true
                        Task { await vm.commitScrub() }
                        return  // Consume the event
                    } else if vm.showInfoPanel {
                        // Handle select when info panel is open
                        print("🎮 [SELECT] PlayerContainerViewController received Select press")
                        isHandlingSelectPress = true
                        handleSelectButton()
                        return  // Consume the event
                    }
                }
            }
            // Left/right arrows are handled by SwiftUI's onMoveCommand
            // Siri Remote touchpad clicks don't generate UIPress events with arrow types
        }
        // Pass presses to SwiftUI for focus handling etc.
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu && isHandlingMenuPress {
                print("🎮 [MENU] PlayerContainerViewController consumed Menu press (ended)")
                isHandlingMenuPress = false
                return  // Consume the event - don't pass to super
            }
            if press.type == .select && isHandlingSelectPress {
                isHandlingSelectPress = false
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
        }
        super.pressesCancelled(presses, with: event)
    }

    /// Handle Menu button press with priority:
    /// 1. Cancel scrubbing if active
    /// 2. Close info panel if open
    /// 3. Hide controls if visible
    /// 4. Dismiss player if nothing else to close
    private func handleMenuButton() {
        guard let vm = viewModel else {
            print("🎮 [MENU] No viewModel - dismissing player")
            dismissPlayer()
            return
        }

        if vm.isScrubbing {
            print("🎮 [MENU] Cancelling scrub")
            vm.cancelScrub()
        } else if vm.showInfoPanel {
            print("🎮 [MENU] Closing info panel")
            withAnimation(.easeOut(duration: 0.3)) {
                vm.showInfoPanel = false
            }
        } else if vm.showControls {
            print("🎮 [MENU] Hiding controls")
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
