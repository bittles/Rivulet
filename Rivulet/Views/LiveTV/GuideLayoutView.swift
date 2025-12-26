//
//  GuideLayoutView.swift
//  Rivulet
//
//  Traditional TV guide layout with timeline and channel rows
//

import SwiftUI

#if os(tvOS)

struct GuideLayoutView: View {
    @StateObject private var dataStore = LiveTVDataStore.shared
    @Environment(\.focusScopeManager) private var focusScopeManager
    @State private var selectedChannel: UnifiedChannel?
    @State private var guideStartTime: Date = Date()

    // Manual focus tracking (row = channel index, column = program index within that channel)
    @State private var focusedRow: Int = 0
    @State private var focusedColumn: Int = 0

    // Single focused button to capture all d-pad input
    @FocusState private var isGuideFocused: Bool

    // Layout constants
    private let channelColumnWidth: CGFloat = 240
    private let timeSlotWidth: CGFloat = 400  // Width per 30 minutes
    private let rowHeight: CGFloat = 90
    private let timeHeaderHeight: CGFloat = 50
    private let visibleHours: Int = 3  // 3 hours visible

    private var guideEndTime: Date {
        guideStartTime.addingTimeInterval(TimeInterval(visibleHours * 60 * 60))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if dataStore.isLoadingChannels && dataStore.channels.isEmpty {
                loadingView
            } else if dataStore.isLoadingEPG && dataStore.epg.isEmpty {
                loadingEPGView
            } else if dataStore.channels.isEmpty {
                emptyView
            } else {
                guideContent
            }
        }
        .onAppear {
            setupGuideStartTime()
            // Activate guide scope for focus management
            focusScopeManager.activate(.guide, savingCurrent: true, pushToStack: true)
        }
        .onDisappear {
            focusScopeManager.deactivate()
        }
        .task {
            // Load channels if needed
            if dataStore.channels.isEmpty && !dataStore.isLoadingChannels {
                await dataStore.loadChannels()
            }
            // Load EPG data
            if dataStore.epg.isEmpty && !dataStore.isLoadingEPG {
                await dataStore.loadEPG(startDate: Date(), hours: 6)
            }
        }
        .fullScreenCover(item: $selectedChannel) { channel in
            LiveTVPlayerView(channel: channel)
        }
    }

    // MARK: - Setup

    private func setupGuideStartTime() {
        // Round current time down to nearest 30 minutes
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let roundedMinute = (minute / 30) * 30
        guideStartTime = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: roundedMinute,
            second: 0,
            of: now
        ) ?? now
    }

    // MARK: - Loading Views

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading channels...")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var loadingEPGView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading TV Guide...")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tv.slash")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.white.opacity(0.3))

            VStack(spacing: 12) {
                Text("No Channels")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Add a Live TV source in Settings to see the guide.")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
        }
    }

    // MARK: - Guide Content

    private var guideContent: some View {
        // Single button container captures all focus and d-pad input
        Button {
            selectFocusedProgram()
        } label: {
            guideLayout
        }
        .buttonStyle(GuideContainerButtonStyle())
        .focused($isGuideFocused)
        .onAppear {
            isGuideFocused = true
        }
        .onMoveCommand { direction in
            handleNavigation(direction)
        }
    }

    private var guideLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("TV Guide")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                // Current time display
                Text(Date(), style: .time)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                // EPG status
                if dataStore.isLoadingEPG {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, 12)
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 40)
            .padding(.bottom, 24)

            // Time header row
            HStack(spacing: 0) {
                // Empty space for channel column
                Color.clear
                    .frame(width: channelColumnWidth, height: timeHeaderHeight)

                // Time slots header
                timeHeader
            }
            .padding(.horizontal, 60)

            // Channel rows with programs
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(dataStore.channels.enumerated()), id: \.element.id) { rowIndex, channel in
                            GuideChannelRow(
                                channel: channel,
                                guideStartTime: guideStartTime,
                                guideEndTime: guideEndTime,
                                visibleHours: visibleHours,
                                timeSlotWidth: timeSlotWidth,
                                rowHeight: rowHeight,
                                channelColumnWidth: channelColumnWidth,
                                isRowFocused: focusedRow == rowIndex,
                                focusedColumnIndex: focusedRow == rowIndex ? focusedColumn : nil
                            )
                            .id("row-\(rowIndex)")
                        }
                    }
                }
                .onChange(of: focusedRow) { _, newRow in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("row-\(newRow)", anchor: .center)
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Navigation

    private func handleNavigation(_ direction: MoveCommandDirection) {
        let channels = dataStore.channels
        guard !channels.isEmpty else { return }

        switch direction {
        case .up:
            if focusedRow > 0 {
                focusedRow -= 1
                // Clamp column to valid range for new row
                let programCount = programCount(for: focusedRow)
                focusedColumn = min(focusedColumn, max(0, programCount - 1))
            }

        case .down:
            if focusedRow < channels.count - 1 {
                focusedRow += 1
                // Clamp column to valid range for new row
                let programCount = programCount(for: focusedRow)
                focusedColumn = min(focusedColumn, max(0, programCount - 1))
            }

        case .left:
            if focusedColumn > 0 {
                focusedColumn -= 1
            }

        case .right:
            let programCount = programCount(for: focusedRow)
            if focusedColumn < programCount - 1 {
                focusedColumn += 1
            }

        @unknown default:
            break
        }
    }

    private func programCount(for rowIndex: Int) -> Int {
        guard rowIndex >= 0 && rowIndex < dataStore.channels.count else { return 1 }
        let channel = dataStore.channels[rowIndex]
        let programs = dataStore.getPrograms(for: channel, startDate: guideStartTime, endDate: guideEndTime)
        return max(1, programs.count)  // At least 1 for "no program" cell
    }

    private func selectFocusedProgram() {
        guard focusedRow >= 0 && focusedRow < dataStore.channels.count else { return }
        selectedChannel = dataStore.channels[focusedRow]
    }

    // MARK: - Time Header

    private var timeHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<(visibleHours * 2), id: \.self) { index in
                        let slotTime = guideStartTime.addingTimeInterval(TimeInterval(index * 30 * 60))

                        Text(formatTime(slotTime))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: timeSlotWidth, alignment: .leading)
                            .padding(.leading, 16)
                    }
                }

                // Current time indicator line
                currentTimeMarker
            }
            .frame(height: timeHeaderHeight)
            .background(Color(white: 0.1))
        }
        .disabled(true)  // Time header doesn't scroll independently
    }

    private var currentTimeMarker: some View {
        let now = Date()
        let offset = now.timeIntervalSince(guideStartTime)
        let xPosition = (offset / (30 * 60)) * timeSlotWidth

        return VStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)

            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: timeHeaderHeight - 12)
        }
        .offset(x: xPosition - 6)
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Guide Container Button Style (no focus highlight)

private struct GuideContainerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
        // No visual changes - we handle highlighting manually
    }
}

// MARK: - Guide Channel Row

private struct GuideChannelRow: View {
    let channel: UnifiedChannel
    let guideStartTime: Date
    let guideEndTime: Date
    let visibleHours: Int
    let timeSlotWidth: CGFloat
    let rowHeight: CGFloat
    let channelColumnWidth: CGFloat
    let isRowFocused: Bool
    let focusedColumnIndex: Int?

    @StateObject private var dataStore = LiveTVDataStore.shared

    private var programs: [UnifiedProgram] {
        dataStore.getPrograms(for: channel, startDate: guideStartTime, endDate: guideEndTime)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Channel info column
            channelHeader
                .frame(width: channelColumnWidth)

            // Programs row
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .leading) {
                    // Programs
                    programsRow

                    // Current time line (extends through content)
                    currentTimeLine
                }
                .frame(width: CGFloat(visibleHours * 2) * timeSlotWidth)
            }
        }
        .frame(height: rowHeight)
        .background(isRowFocused ? Color.white.opacity(0.05) : Color.clear)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Channel Header

    private var channelHeader: some View {
        HStack(spacing: 12) {
            // Channel logo
            if let logoURL = channel.logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 44)
                    default:
                        channelPlaceholder
                    }
                }
            } else {
                channelPlaceholder
            }

            // Channel info
            VStack(alignment: .leading, spacing: 4) {
                if let number = channel.channelNumber {
                    Text("\(number)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text(channel.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.06))
    }

    private var channelPlaceholder: some View {
        Image(systemName: "tv")
            .font(.system(size: 24))
            .foregroundStyle(.white.opacity(0.3))
            .frame(width: 60, height: 44)
    }

    // MARK: - Programs Row

    private var programsRow: some View {
        HStack(spacing: 2) {
            if programs.isEmpty {
                // No program data
                GuideProgramCellView(
                    title: "No Program Information",
                    timeRange: nil,
                    description: nil,
                    cellWidth: CGFloat(visibleHours * 2) * timeSlotWidth - 4,
                    rowHeight: rowHeight,
                    isFocused: isRowFocused && (focusedColumnIndex == 0 || focusedColumnIndex == nil),
                    isCurrentlyAiring: false
                )
            } else {
                ForEach(Array(programs.enumerated()), id: \.element.id) { columnIndex, program in
                    let cellWidth = calculateCellWidth(for: program)
                    let now = Date()
                    let isAiring = program.startTime <= now && program.endTime > now

                    GuideProgramCellView(
                        title: program.title,
                        timeRange: formatTimeRange(program),
                        description: program.description,
                        cellWidth: cellWidth,
                        rowHeight: rowHeight,
                        isFocused: isRowFocused && focusedColumnIndex == columnIndex,
                        isCurrentlyAiring: isAiring
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func calculateCellWidth(for program: UnifiedProgram) -> CGFloat {
        let visibleStart = max(program.startTime, guideStartTime)
        let visibleEnd = min(program.endTime, guideEndTime)
        let visibleDuration = visibleEnd.timeIntervalSince(visibleStart)
        let widthPerSecond = timeSlotWidth / (30 * 60)
        return max(visibleDuration * widthPerSecond, 80)  // Minimum 80pt width
    }

    private func formatTimeRange(_ program: UnifiedProgram) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: program.startTime)) - \(formatter.string(from: program.endTime))"
    }

    // MARK: - Current Time Line

    private var currentTimeLine: some View {
        let now = Date()
        guard now >= guideStartTime && now <= guideEndTime else {
            return AnyView(EmptyView())
        }

        let offset = now.timeIntervalSince(guideStartTime)
        let xPosition = (offset / (30 * 60)) * timeSlotWidth

        return AnyView(
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)
                .offset(x: xPosition)
        )
    }
}

// MARK: - Guide Program Cell View

private struct GuideProgramCellView: View {
    let title: String
    let timeRange: String?
    let description: String?
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    let isFocused: Bool
    let isCurrentlyAiring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let timeRange {
                Text(timeRange)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            if let description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: cellWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? .white : .clear, lineWidth: 3)
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var backgroundColor: Color {
        if isFocused {
            return .white.opacity(0.25)
        } else if isCurrentlyAiring {
            return Color(white: 0.15)
        } else {
            return Color(white: 0.08)
        }
    }
}

#else

// macOS/iOS version with standard focus handling
struct GuideLayoutView: View {
    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var selectedChannel: UnifiedChannel?
    @State private var guideStartTime: Date = Date()

    // Layout constants
    private let channelColumnWidth: CGFloat = 200
    private let timeSlotWidth: CGFloat = 300
    private let rowHeight: CGFloat = 70
    private let timeHeaderHeight: CGFloat = 40
    private let visibleHours: Int = 3

    private var guideEndTime: Date {
        guideStartTime.addingTimeInterval(TimeInterval(visibleHours * 60 * 60))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if dataStore.isLoadingChannels && dataStore.channels.isEmpty {
                ProgressView("Loading channels...")
            } else if dataStore.isLoadingEPG && dataStore.epg.isEmpty {
                ProgressView("Loading TV Guide...")
            } else if dataStore.channels.isEmpty {
                ContentUnavailableView(
                    "No Channels",
                    systemImage: "tv.slash",
                    description: Text("Add a Live TV source in Settings to see the guide.")
                )
            } else {
                guideContent
            }
        }
        .onAppear {
            setupGuideStartTime()
        }
        .task {
            if dataStore.channels.isEmpty && !dataStore.isLoadingChannels {
                await dataStore.loadChannels()
            }
            if dataStore.epg.isEmpty && !dataStore.isLoadingEPG {
                await dataStore.loadEPG(startDate: Date(), hours: 6)
            }
        }
        .sheet(item: $selectedChannel) { channel in
            Text("Playing: \(channel.name)")
        }
    }

    private func setupGuideStartTime() {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let roundedMinute = (minute / 30) * 30
        guideStartTime = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: roundedMinute,
            second: 0,
            of: now
        ) ?? now
    }

    private var guideContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("TV Guide")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Text(Date(), style: .time)
                    .foregroundStyle(.secondary)
            }
            .padding()

            // Time header
            HStack(spacing: 0) {
                Color.clear.frame(width: channelColumnWidth, height: timeHeaderHeight)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(0..<(visibleHours * 2), id: \.self) { index in
                            let slotTime = guideStartTime.addingTimeInterval(TimeInterval(index * 30 * 60))
                            Text(formatTime(slotTime))
                                .font(.caption)
                                .frame(width: timeSlotWidth, alignment: .leading)
                                .padding(.leading, 8)
                        }
                    }
                }
            }
            .background(Color.gray.opacity(0.1))

            // Channel rows
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 1) {
                    ForEach(dataStore.channels) { channel in
                        macOSChannelRow(channel: channel)
                    }
                }
            }
        }
    }

    private func macOSChannelRow(channel: UnifiedChannel) -> some View {
        HStack(spacing: 0) {
            // Channel info
            HStack(spacing: 8) {
                if let number = channel.channelNumber {
                    Text("\(number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(channel.name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(width: channelColumnWidth, alignment: .leading)
            .padding(.horizontal, 8)

            // Programs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let programs = dataStore.getPrograms(for: channel, startDate: guideStartTime, endDate: guideEndTime)
                    if programs.isEmpty {
                        Text("No Program Information")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: CGFloat(visibleHours * 2) * timeSlotWidth)
                    } else {
                        ForEach(programs) { program in
                            Button {
                                selectedChannel = channel
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(program.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(formatTime(program.startTime))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .frame(width: calculateWidth(for: program), alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(height: rowHeight)
    }

    private func calculateWidth(for program: UnifiedProgram) -> CGFloat {
        let visibleStart = max(program.startTime, guideStartTime)
        let visibleEnd = min(program.endTime, guideEndTime)
        let visibleDuration = visibleEnd.timeIntervalSince(visibleStart)
        let widthPerSecond = timeSlotWidth / (30 * 60)
        return max(visibleDuration * widthPerSecond, 60)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

#endif

#Preview {
    GuideLayoutView()
}
