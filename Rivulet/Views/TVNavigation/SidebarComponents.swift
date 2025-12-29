//
//  SidebarComponents.swift
//  Rivulet
//
//  Reusable UI components for the tvOS sidebar
//

import SwiftUI

#if os(tvOS)

// MARK: - Sidebar Row (non-focusable, for use with single-focus sidebar)

struct SidebarRow: View {
    let icon: String
    let title: String
    let isHighlighted: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 26)

            Text(title)
                .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 4)

            if isSelected {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
            }
        }
        .foregroundStyle(.white.opacity(isHighlighted || isSelected ? 1.0 : 0.6))
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHighlighted ? .white.opacity(0.15) : .clear)
        )
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.15), value: isHighlighted)
    }
}

// MARK: - Sidebar Button (focusable, legacy component)

struct SidebarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var onFocusChange: ((Bool) -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 24)

            Text(title)
                .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 4)

            if isSelected {
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
        }
        .foregroundStyle(.white.opacity(isFocused || isSelected ? 1.0 : 0.7))
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 11)
        .glassEffect(
            isFocused ? .regular.tint(.white.opacity(0.15)) : .identity,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, 16)
        .focusable()
        .focused($isFocused)
        .onChange(of: isFocused) { _, newValue in
            // Navigate immediately when focus is gained
            // This happens instantly with cached data
            if newValue {
                onFocusChange?(newValue)
            }
        }
        .onTapGesture {
            // Tap just closes sidebar - navigation already happened on focus
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Left Edge Trigger (opens sidebar when focus reaches left edge)

struct LeftEdgeTrigger: View {
    let action: () -> Void
    var isDisabled: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            action()
        } label: {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 32)
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .focusable(!isDisabled)  // Prevent focus when disabled
        .focused($isFocused)
        .onChange(of: isFocused) { _, newValue in
            if newValue && !isDisabled {
                action()
            }
        }
    }
}

// MARK: - Sidebar Container Button Style (no focus highlight)

struct SidebarContainerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
        // No visual changes on focus or press - we handle highlighting manually via SidebarRow
    }
}

// MARK: - Conditional Exit Command Modifier

/// Conditionally attaches onExitCommand only when sidebar is visible
struct SidebarExitCommand: ViewModifier {
    let isSidebarVisible: Bool
    let closeAction: () -> Void

    func body(content: Content) -> some View {
        if isSidebarVisible {
            content.onExitCommand(perform: closeAction)
        } else {
            content
        }
    }
}

extension View {
    func ifSidebarVisible(_ isVisible: Bool, close: @escaping () -> Void) -> some View {
        self.modifier(SidebarExitCommand(isSidebarVisible: isVisible, closeAction: close))
    }
}

#endif
