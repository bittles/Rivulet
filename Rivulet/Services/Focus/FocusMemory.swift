//
//  FocusMemory.swift
//  Rivulet
//
//  Simple focus memory system for tvOS
//  Tracks last-focused item per memory key without scope validation
//

import SwiftUI

/// Simple focus memory system for tvOS section focus restoration
///
/// Use this for remembering and restoring focus within sections of a view
/// (e.g., seasons, episodes, cast & crew). For isolating focus between
/// completely separate views (sidebar, player, overlays), use FocusScopeManager.
///
/// Usage:
/// ```swift
/// @FocusState private var focusedItemId: String?
///
/// ScrollView(.horizontal) {
///     HStack {
///         ForEach(items) { item in
///             ItemCard(item: item)
///                 .focused($focusedItemId, equals: item.id)
///         }
///     }
/// }
/// .focusSection()
/// .remembersFocus(key: "mySectionKey", focusedId: $focusedItemId)
/// ```
@MainActor
final class FocusMemory {
    static let shared = FocusMemory()

    private var memory: [String: String] = [:]

    private init() {}

    /// Remember the currently focused item for a section
    func remember(_ itemId: String, for key: String) {
        memory[key] = itemId
    }

    /// Recall the last focused item for a section
    func recall(for key: String) -> String? {
        memory[key]
    }

    /// Forget the focus for a specific section
    func forget(key: String) {
        memory.removeValue(forKey: key)
    }

    /// Clear all focus memory
    func clear() {
        memory.removeAll()
    }

    /// Check if there's a remembered focus for a section
    func hasMemory(for key: String) -> Bool {
        memory[key] != nil
    }
}

// MARK: - Environment Key

private struct FocusMemoryKey: EnvironmentKey {
    static let defaultValue = FocusMemory.shared
}

extension EnvironmentValues {
    var focusMemory: FocusMemory {
        get { self[FocusMemoryKey.self] }
        set { self[FocusMemoryKey.self] = newValue }
    }
}

// MARK: - View Modifier

#if os(tvOS)

/// View modifier that remembers and restores focus for a section
///
/// Note: Uses onChange to redirect focus after tvOS picks a default.
/// This may cause a brief visual flash (1-2 frames) when redirecting focus.
/// This is a fundamental SwiftUI limitation - there's no way to intercept
/// focus BEFORE the visual update in pure SwiftUI.
struct FocusMemoryModifier: ViewModifier {
    let memoryKey: String
    var focusedId: FocusState<String?>.Binding
    @Environment(\.focusMemory) private var focusMemory

    func body(content: Content) -> some View {
        content
            .onChange(of: focusedId.wrappedValue) { oldValue, newValue in
                // Focus is entering this section (was nil, now has value)
                if oldValue == nil, let newValue = newValue {
                    // Check if we have a remembered value that's different
                    if let remembered = focusMemory.recall(for: memoryKey),
                       remembered != newValue {
                        // Redirect to remembered item instantly (no animation)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            focusedId.wrappedValue = remembered
                        }
                        return
                    }
                }

                // Remember the new focus (only if not nil)
                if let id = newValue {
                    focusMemory.remember(id, for: memoryKey)
                }
            }
    }
}

extension View {
    /// Remember and restore focus for this section
    ///
    /// This modifier tracks the currently focused item and restores it when
    /// the section is re-entered. Do NOT use `.scrollPosition()` with this
    /// modifier - let the tvOS focus engine handle scrolling naturally.
    ///
    /// - Parameters:
    ///   - key: Unique identifier for this section (e.g., "detailSeasons")
    ///   - focusedId: Binding to the @FocusState variable tracking focus
    func remembersFocus(key: String, focusedId: FocusState<String?>.Binding) -> some View {
        modifier(FocusMemoryModifier(memoryKey: key, focusedId: focusedId))
    }
}

#endif
