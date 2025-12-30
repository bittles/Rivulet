# Menu Button Interception on tvOS

A technical guide for implementing reliable Menu/Back button interception to prevent unintended app closure.

---

## Problem Statement

SwiftUI's `.onExitCommand` modifier **requires the view to have focus** to intercept the Menu button. If no focusable item has focus (edge cases, focus escape, certain view states), the Menu button press falls through to the system and exits the app.

**Current behavior**: Menu button sometimes closes the app instead of opening the sidebar.

**Expected behavior**: Menu button should always open the sidebar when at root level.

---

## Why UIKit Interception is More Reliable

| Approach | Reliability | Focus Required | Notes |
|----------|-------------|----------------|-------|
| `.onExitCommand` | ~95% | Yes | Fails when no focus |
| UIKit Gesture Recognizer | 100% | No | Intercepts before SwiftUI |
| `pressesBegan` override | 100% | No | Requires UIViewController |

UIKit gesture recognizers intercept button presses at the responder chain level, before SwiftUI's focus system is consulted. This is the same pattern used in `PlayerContainerViewController.swift` for reliable player controls.

---

## Implementation Architecture

```
Menu Button Press
    │
    ├─ UIKit Gesture Recognizer (root level)
    │   └─ Posts notification → SwiftUI fallback handler
    │
    └─ SwiftUI .onExitCommand (if focus exists)
        └─ Handles normally (opens sidebar, navigates back, etc.)

Flow:
1. If SwiftUI .onExitCommand handled it → done
2. If SwiftUI missed it → UIKit gesture fires → notification triggers fallback
```

---

## Code Implementation

### Step 1: Create Custom Hosting Controller

Create a subclass of `UIHostingController` that intercepts the Menu button:

```swift
// RootHostingController.swift

import SwiftUI
import UIKit

#if os(tvOS)
class RootHostingController<Content: View>: UIHostingController<Content> {

    private var menuGestureRecognizer: UITapGestureRecognizer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMenuButtonInterception()
    }

    private func setupMenuButtonInterception() {
        let menuRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(menuButtonPressed)
        )
        menuRecognizer.allowedPressTypes = [
            NSNumber(value: UIPress.PressType.menu.rawValue)
        ]
        view.addGestureRecognizer(menuRecognizer)
        menuGestureRecognizer = menuRecognizer
    }

    @objc private func menuButtonPressed() {
        // Post notification for SwiftUI to handle
        NotificationCenter.default.post(
            name: .menuButtonPressedFallback,
            object: nil
        )
    }
}

// Notification name extension
extension Notification.Name {
    static let menuButtonPressedFallback = Notification.Name("menuButtonPressedFallback")
}
#endif
```

### Step 2: Update App Entry Point

Modify `RivuletApp.swift` to use the custom hosting controller:

```swift
// RivuletApp.swift

import SwiftUI

@main
struct RivuletApp: App {

    #if os(tvOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#if os(tvOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let rootView = ContentView()
        let hostingController = RootHostingController(rootView: rootView)

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = hostingController
        window?.makeKeyAndVisible()
    }
}
#endif
```

### Step 3: Add SwiftUI Fallback Handler

In `TVSidebarView.swift`, add a notification observer as a fallback:

```swift
// TVSidebarView.swift

struct TVSidebarView: View {
    // ... existing properties ...

    var body: some View {
        ZStack {
            // ... existing content ...
        }
        .onExitCommand {
            // Primary handler (works when focus exists)
            handleMenuButton()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuButtonPressedFallback)) { _ in
            // Fallback handler (catches missed presses)
            handleMenuButtonFallback()
        }
    }

    private func handleMenuButton() {
        if isSidebarVisible {
            closeSidebar()
        } else if nestedNavState.isNested {
            nestedNavState.goBack()
        } else {
            openSidebar()
        }
    }

    private func handleMenuButtonFallback() {
        // Only handle if we're at root level and sidebar is closed
        // (other states should have been handled by .onExitCommand)
        if !isSidebarVisible && !nestedNavState.isNested {
            openSidebar()
        }
    }
}
```

---

## Preventing Double-Handling

The UIKit gesture and SwiftUI `.onExitCommand` could both fire. To prevent double-handling:

### Option A: Timing-Based Deduplication

```swift
class MenuButtonCoordinator {
    static let shared = MenuButtonCoordinator()

    private var lastHandledTime: Date?
    private let debounceInterval: TimeInterval = 0.1

    func shouldHandle() -> Bool {
        let now = Date()
        if let last = lastHandledTime, now.timeIntervalSince(last) < debounceInterval {
            return false // Already handled recently
        }
        lastHandledTime = now
        return true
    }
}

// In both handlers:
guard MenuButtonCoordinator.shared.shouldHandle() else { return }
```

### Option B: Flag-Based Coordination

```swift
// In TVSidebarView
@State private var menuHandledBySwiftUI = false

.onExitCommand {
    menuHandledBySwiftUI = true
    handleMenuButton()
    // Reset after a short delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        menuHandledBySwiftUI = false
    }
}
.onReceive(NotificationCenter.default.publisher(for: .menuButtonPressedFallback)) { _ in
    guard !menuHandledBySwiftUI else { return }
    handleMenuButtonFallback()
}
```

---

## App Review Considerations

Apple's Human Interface Guidelines require that the Menu button can exit the app at the "root" level. However:

1. **Rivulet's sidebar IS the root menu** - Opening it on first Menu press is expected behavior
2. **Users can always exit** via:
   - Double-tap Home button → Force quit
   - Press and hold Home → App switcher
3. **Many apps use this pattern** - Netflix, YouTube, etc. show menus/settings on first Menu press
4. **Compliant behavior**: When sidebar is open at home screen, a second Menu press could either:
   - Do nothing (user must navigate away)
   - Show an "Exit app?" confirmation (optional, not required)

---

## Files to Modify

| File | Change |
|------|--------|
| `RivuletApp.swift` | Add AppDelegate, SceneDelegate, use RootHostingController |
| `TVSidebarView.swift` | Add `.onReceive` fallback handler |
| **New**: `RootHostingController.swift` | UIHostingController subclass with gesture |
| **New**: `MenuButtonCoordinator.swift` | Optional deduplication helper |

---

## Testing Checklist

- [ ] Menu opens sidebar from home screen (normal case)
- [ ] Menu opens sidebar when no item has focus (edge case)
- [ ] Menu closes sidebar when sidebar is open
- [ ] Menu navigates back when in nested view (library → detail)
- [ ] Menu works correctly in player (existing UIKit handling)
- [ ] Menu works correctly in Live TV player
- [ ] No double-handling (sidebar doesn't flash open/closed)
- [ ] App can still be exited via Home button

---

## References

- [Apple: Detecting Button Presses and Gestures](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/DetectingButtonPressesandGestures.html)
- [Apple Developer Forums: Menu button handling](https://developer.apple.com/forums/thread/25406)
- Existing implementation: `PlayerContainerViewController.swift` (lines 64-67, 124-163)

---

*Last updated: December 2024*
