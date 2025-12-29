//
//  NavigationEnvironment.swift
//  Rivulet
//
//  Environment keys and state objects for tvOS navigation
//

import SwiftUI
import Combine

#if os(tvOS)

// MARK: - Navigation Destination

/// Navigation destination for tvOS
enum TVDestination: Hashable, CaseIterable {
    case search
    case home
    case liveTV
    case settings

    static var allCases: [TVDestination] { [.search, .home, .liveTV, .settings] }
}

// MARK: - Environment Keys

/// Environment key for opening sidebar from content views
struct OpenSidebarAction: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openSidebar: () -> Void {
        get { self[OpenSidebarAction.self] }
        set { self[OpenSidebarAction.self] = newValue }
    }
}

// Note: Focus management is now handled by FocusScopeManager in Services/Focus/
// The isSidebarVisible environment key is kept for backward compatibility during migration

/// Environment key indicating sidebar is visible (derived from FocusScopeManager)
struct IsSidebarVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isSidebarVisible: Bool {
        get { self[IsSidebarVisibleKey.self] }
        set { self[IsSidebarVisibleKey.self] = newValue }
    }
}

// MARK: - Nested Navigation State

/// Preference key for nested navigation state (bubbles up from child views)
struct IsInNestedNavigationKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()  // True if any child is in nested nav
    }
}

/// Observable object to track nested navigation state across views
@MainActor
class NestedNavigationState: ObservableObject {
    @Published var isNested: Bool = false

    /// Action to go back from nested navigation (set by child views)
    var goBackAction: (() -> Void)?

    func goBack() {
        goBackAction?()
    }
}

/// Environment key for nested navigation state
private struct NestedNavigationStateKey: EnvironmentKey {
    static let defaultValue: NestedNavigationState = NestedNavigationState()
}

extension EnvironmentValues {
    var nestedNavigationState: NestedNavigationState {
        get { self[NestedNavigationStateKey.self] }
        set { self[NestedNavigationStateKey.self] = newValue }
    }
}

#endif
