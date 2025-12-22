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
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 15, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 10)

            VStack(spacing: 2) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.85))  // Solid white base for contrast
            )
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Text - dark colors for contrast on white glass background
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color(white: 0.1))

                Text(subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(white: 0.4))
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFocused ? .black.opacity(0.1) : .clear)
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
                .font(.system(size: 19))
                .foregroundStyle(Color(white: 0.2))

            Spacer()

            Text(value)
                .font(.system(size: 19))
                .foregroundStyle(Color(white: 0.45))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Text - dark colors for contrast on white glass background
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color(white: 0.1))

                Text(subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(white: 0.4))
            }

            Spacer()

            // On/Off text (Apple tvOS Settings style)
            Text(isOn ? "On" : "Off")
                .font(.system(size: 19))
                .foregroundStyle(Color(white: 0.45))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFocused ? .black.opacity(0.1) : .clear)
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
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(isDestructive ? Color(red: 0.75, green: 0.15, blue: 0.15) : Color(white: 0.15))
            Spacer()
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? (isDestructive ? .red.opacity(0.12) : .black.opacity(0.1)) : .clear)
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
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 20, weight: .semibold))
            Text("Connect to Plex")
                .font(.system(size: 21, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
