//
//  SettingsComponents.swift
//  Rivulet
//
//  Reusable settings UI components for tvOS
//

import SwiftUI

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title.uppercased())
                .font(.system(size: 21, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 12)

            VStack(spacing: 2) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

// MARK: - Settings Row (Navigation)

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    var focusTrigger: Int? = nil  // When non-nil and changes, claim focus

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 20) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 64, height: 64)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Text - white for dark glass background
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 23))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? .white.opacity(0.15) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .onChange(of: focusTrigger) { _, newValue in
            if newValue != nil {
                isFocused = true
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Settings Info Row (Display Only)

struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Text(value)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 20) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 64, height: 64)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Text - white for dark glass background
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 23))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // On/Off text
            Text(isOn ? "On" : "Off")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(isOn ? .green : .white.opacity(0.5))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? .white.opacity(0.15) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            isOn.toggle()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Settings Action Row (Button)

struct SettingsActionRow: View {
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(isDestructive ? .red : .white)
            Spacer()
        }
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFocused ? (isDestructive ? .red.opacity(0.25) : .white.opacity(0.15)) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Connect Button

struct ConnectButton: View {
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "link")
                .font(.system(size: 26, weight: .semibold))
            Text("Connect to Plex")
                .font(.system(size: 28, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? Color.blue : Color.blue.opacity(0.85))
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .shadow(color: .blue.opacity(isFocused ? 0.4 : 0), radius: 12, y: 4)
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
