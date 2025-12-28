//
//  GlassRowStyle.swift
//  Rivulet
//
//  Unified tvOS 26 liquid glass styling for list rows
//  Provides consistent focus behavior across the app
//

import SwiftUI

#if os(tvOS)

// MARK: - Glass Row Button Style

/// A unified button style for list rows that provides tvOS 26 liquid glass aesthetics.
/// Features: subtle scale on focus, glass background, smooth animations.
struct GlassRowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Glass Row Modifier

/// Applies consistent glass row styling with focus effects.
/// Use this on any row-style view for unified appearance.
struct GlassRowModifier: ViewModifier {
    @FocusState.Binding var isFocused: Bool
    var cornerRadius: CGFloat = 16
    var verticalPadding: CGFloat = 16
    var horizontalPadding: CGFloat = 20
    var showChevron: Bool = false

    func body(content: Content) -> some View {
        HStack(spacing: 16) {
            content

            if showChevron {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(isFocused ? 0.8 : 0.4))
            }
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, horizontalPadding)
        .background(
            GlassRowBackground(isFocused: isFocused, cornerRadius: cornerRadius)
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

// MARK: - Glass Row Background

/// The background view for glass rows - provides the liquid glass effect.
struct GlassRowBackground: View {
    let isFocused: Bool
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isFocused ? .white.opacity(0.18) : .white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? .white.opacity(0.3) : .white.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isFocused ? .white.opacity(0.1) : .clear,
                radius: 8,
                y: 2
            )
    }
}

// MARK: - Focusable Glass Row

/// A complete focusable glass row component for simple use cases.
/// Wraps content in a focusable button with glass styling.
struct FocusableGlassRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var cornerRadius: CGFloat = 16
    var showChevron: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                content()

                if showChevron {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(isFocused ? 0.8 : 0.4))
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                GlassRowBackground(isFocused: isFocused, cornerRadius: cornerRadius)
            )
        }
        .buttonStyle(GlassRowButtonStyle(cornerRadius: cornerRadius))
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

// MARK: - View Extension

extension View {
    /// Apply glass row styling to any view.
    /// - Parameters:
    ///   - isFocused: Binding to focus state
    ///   - cornerRadius: Corner radius for the glass background
    ///   - showChevron: Whether to show a navigation chevron
    func glassRow(
        isFocused: FocusState<Bool>.Binding,
        cornerRadius: CGFloat = 16,
        verticalPadding: CGFloat = 16,
        horizontalPadding: CGFloat = 20,
        showChevron: Bool = false
    ) -> some View {
        self.modifier(GlassRowModifier(
            isFocused: isFocused,
            cornerRadius: cornerRadius,
            verticalPadding: verticalPadding,
            horizontalPadding: horizontalPadding,
            showChevron: showChevron
        ))
    }
}

#endif
