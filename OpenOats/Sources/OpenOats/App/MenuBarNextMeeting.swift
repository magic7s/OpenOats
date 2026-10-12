import Foundation

/// Rules for the next-meeting readout in the menu bar and its popover.
/// Pure: every function takes `now` so the behaviour is testable without a clock.
enum MenuBarNextMeeting {
    /// A meeting is shown in the menu bar once it starts within this window.
    static let lookahead: TimeInterval = 60 * 60
    /// A meeting about to start takes over from a running one this long before its start.
    static let switchLead: TimeInterval = 10 * 60
    /// A running event longer than this never takes the menu bar text: it is a
    /// multi-day block that is not flagged all-day, not a meeting to walk into.
    static let maxRunningDuration: TimeInterval = 8 * 60 * 60
    /// Longest title shown in the menu bar, ellipsis included.
    static let maxTitleLength = 16
    /// How far ahead the popover lists events.
    static let listWindow: TimeInterval = 24 * 60 * 60
    /// Most events the popover lists.
    static let listLimit = 4

    struct JoinPlan: Equatable {
        let urlToOpen: URL?
        let startsRecording: Bool
        let showsMainWindow: Bool
    }

    /// The meeting the menu bar should show, if any. First match wins:
    /// a meeting starting within `switchLead`; else the most recently started
    /// meeting still running; else the next meeting within `lookahead`.
    static func featuredEvent(among events: [CalendarEvent], now: Date) -> CalendarEvent? {
        let next = ordered(events.filter { $0.startDate > now }).first
        if let next, next.startDate.timeIntervalSince(now) <= switchLead {
            return next
        }

        let running = ordered(events.filter { event in
            event.startDate <= now
                && event.endDate > now
                && event.endDate.timeIntervalSince(event.startDate) <= maxRunningDuration
        })
        if let latestStart = running.last?.startDate {
            return running.first { $0.startDate == latestStart }
        }

        if let next, next.startDate.timeIntervalSince(now) <= lookahead {
            return next
        }
        return nil
    }

    /// `in 7m`, or `now` under a minute. Whole minutes rounded down: never
    /// promise more time than there is.
    static func countdownText(until start: Date, now: Date) -> String {
        let minutes = wholeMinutes(from: now, to: start)
        guard minutes >= 1 else { return "now" }
        return "in \(durationText(minutes: minutes))"
    }

    /// `28m left`, or `<1m left` in the last minute. Rounded down like the countdown.
    static func remainingText(until end: Date, now: Date) -> String {
        let minutes = wholeMinutes(from: now, to: end)
        guard minutes >= 1 else { return "<1m left" }
        return "\(durationText(minutes: minutes)) left"
    }

    /// Countdown before the meeting starts, time left once it has.
    static func statusText(for event: CalendarEvent, now: Date) -> String {
        event.startDate > now
            ? countdownText(until: event.startDate, now: now)
            : remainingText(until: event.endDate, now: now)
    }

    /// One headed block of rows in the popover.
    struct ListSection: Equatable, Identifiable {
        /// Set for the featured meeting's own block; nil means "use the day's title".
        let header: String?
        let day: Date
        let events: [CalendarEvent]

        var id: String {
            header == nil ? "day-\(day.timeIntervalSince1970)" : "featured"
        }
    }

    /// The popover's rows: the featured meeting alone under its own header
    /// (`Starts in 5m`, `Happening now`), then every other event grouped by day.
    /// Compares whole events, not ids: occurrences of a recurring event share an id.
    static func listSections(
        for events: [CalendarEvent],
        featured: CalendarEvent?,
        now: Date,
        calendar: Calendar = .current
    ) -> [ListSection] {
        var sections: [ListSection] = []
        var rest = events
        if let featured, events.contains(featured) {
            sections.append(ListSection(
                header: headerText(for: featured, now: now),
                day: calendar.startOfDay(for: featured.startDate),
                events: [featured]
            ))
            rest.removeAll { $0 == featured }
        }

        let byDay = Dictionary(grouping: rest) { calendar.startOfDay(for: $0.startDate) }
        for day in byDay.keys.sorted() {
            sections.append(ListSection(header: nil, day: day, events: ordered(byDay[day] ?? [])))
        }
        return sections
    }

    /// Tooltip for a popover row, or nil when clicking it would do nothing
    /// (already recording and the event has no link to open).
    static func rowHelp(for event: CalendarEvent, isRecording: Bool) -> String? {
        switch (isRecording, event.meetingURL != nil) {
        case (false, true): return "Join and start recording"
        case (false, false): return "Start recording"
        case (true, true): return "Join meeting"
        case (true, false): return nil
        }
    }

    static func truncatedTitle(_ title: String, maxLength: Int = maxTitleLength) -> String {
        let collapsed = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return "Meeting" }
        guard collapsed.count > maxLength else { return collapsed }

        let head = collapsed.prefix(max(maxLength - 1, 1))
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Text shown beside the menu bar icon, or nil when only the icon should show.
    static func statusItemText(
        featured: CalendarEvent?,
        now: Date,
        isRecording: Bool,
        isEnabled: Bool
    ) -> String? {
        guard isEnabled, !isRecording, let featured else { return nil }
        return "\(truncatedTitle(featured.title)) • \(statusText(for: featured, now: now))"
    }

    static func headerText(for event: CalendarEvent, now: Date) -> String {
        guard event.startDate > now else { return "Happening now" }
        return "Starts \(countdownText(until: event.startDate, now: now))"
    }

    /// What clicking a meeting does. The link always opens; a recording starts
    /// only when none is running or finishing and the user has acknowledged
    /// recording consent. When a start is refused the main window explains why.
    static func joinPlan(
        for event: CalendarEvent,
        isRecording: Bool,
        isFinishingRecording: Bool,
        hasRecordingConsent: Bool
    ) -> JoinPlan {
        if isRecording {
            return JoinPlan(urlToOpen: event.meetingURL, startsRecording: false, showsMainWindow: false)
        }
        if isFinishingRecording {
            return JoinPlan(urlToOpen: event.meetingURL, startsRecording: false, showsMainWindow: true)
        }
        guard hasRecordingConsent else {
            return JoinPlan(urlToOpen: event.meetingURL, startsRecording: false, showsMainWindow: true)
        }
        return JoinPlan(urlToOpen: event.meetingURL, startsRecording: true, showsMainWindow: false)
    }

    private static func wholeMinutes(from now: Date, to date: Date) -> Int {
        Int((date.timeIntervalSince(now) / 60).rounded(.down))
    }

    private static func durationText(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    /// Start time first; on a tie an event with a meeting link beats one without
    /// (a real meeting over a focus block), then `id` keeps the order stable.
    private static func ordered(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            if (lhs.meetingURL != nil) != (rhs.meetingURL != nil) {
                return lhs.meetingURL != nil
            }
            return lhs.id < rhs.id
        }
    }
}
