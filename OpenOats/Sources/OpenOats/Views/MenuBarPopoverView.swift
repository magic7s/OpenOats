import SwiftUI

struct MenuBarPopoverView: View {
    let coordinator: AppCoordinator
    let settings: AppSettings
    let meetings: MenuBarMeetingsModel
    let onJoinEvent: (CalendarEvent) -> Void
    let onToggleMeeting: () -> Void
    let onShowMainWindow: () -> Void
    let onCheckForUpdates: () -> Void
    let onShowSettings: () -> Void
    let onQuit: () -> Void

    @State private var elapsedSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?

    private var recordingStartedAt: Date? {
        if case .recording(let metadata) = coordinator.state {
            return metadata.startedAt
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLine
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            if settings.calendarIntegrationEnabled, !meetings.events.isEmpty {
                upcomingSection
                    .padding(.vertical, 6)

                Divider()
            }

            primaryAction
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            Button(action: onShowMainWindow) {
                HStack {
                    Text("Show OpenOats")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Button(action: onCheckForUpdates) {
                HStack {
                    Text("Check for Updates…")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Button(action: onShowSettings) {
                HStack {
                    Text("Settings…")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Button(action: onQuit) {
                HStack {
                    Text("Quit OpenOats")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
        }
        .frame(width: 280)
        .onAppear {
            if coordinator.isRecording {
                startTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: coordinator.isRecording) { _, recording in
            if recording {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if coordinator.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Recording - \(formattedTime)")
                    .font(.system(size: 13, weight: .medium))
            } else if settings.meetingAutoDetectEnabled {
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
                Text("Meeting detection on")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text("Idle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if coordinator.isRecording {
            Button(action: onToggleMeeting) {
                Text("Stop Recording")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OpenOatsProminentButtonStyle(color: .red))
            .controlSize(.regular)
        } else {
            Button(action: {
                guard settings.hasAcknowledgedRecordingConsent else {
                    onShowMainWindow()
                    return
                }
                onToggleMeeting()
            }) {
                Text("Start Recording")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OpenOatsProminentButtonStyle())
            .controlSize(.regular)
        }
    }

    private var upcomingSection: some View {
        let groups = UpcomingCalendarGrouping.groups(for: meetings.events)
        let featured = meetings.featuredEvent

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                Text(sectionHeader(for: group, featured: featured))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                ForEach(MenuBarNextMeeting.featuredFirst(group.events, featured: featured), id: \.self) { event in
                    Button(action: { onJoinEvent(event) }) {
                        eventRow(event)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .help(event.meetingURL == nil ? "Start recording" : "Join and start recording")
                }
            }
        }
    }

    private func sectionHeader(
        for group: UpcomingCalendarGrouping.DayGroup,
        featured: CalendarEvent?
    ) -> String {
        if let featured, group.events.contains(featured) {
            return MenuBarNextMeeting.headerText(for: featured, now: meetings.now)
        }
        return group.sectionTitle
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            if event.meetingURL != nil {
                Image(systemName: "video.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tint)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(timeRange(for: event))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func timeRange(for event: CalendarEvent) -> String {
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startTimer() {
        updateElapsed()
        stopTimer()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                updateElapsed()
            }
        }
    }

    private func updateElapsed() {
        if let start = recordingStartedAt {
            elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
        } else {
            elapsedSeconds = 0
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        elapsedSeconds = 0
    }
}
