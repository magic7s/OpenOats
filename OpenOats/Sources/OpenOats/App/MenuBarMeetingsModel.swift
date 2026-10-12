import Foundation
import Observation

/// Upcoming meetings for the menu bar item and its popover.
/// Events come from an injected provider so this type never touches EventKit.
@MainActor
@Observable
final class MenuBarMeetingsModel {
    /// Meetings that have not ended, earliest first, capped at `MenuBarNextMeeting.listLimit`.
    /// Always includes `featuredEvent`.
    private(set) var events: [CalendarEvent] = []
    /// The meeting the menu bar shows, chosen from every unended event.
    private(set) var featuredEvent: CalendarEvent?
    /// The time of the last refresh; countdowns are computed against it.
    private(set) var now: Date
    /// Changes whenever a refresh is requested. `MenuBarController` observes it.
    private(set) var refreshToken = 0

    @ObservationIgnored private let provider: () -> [CalendarEvent]
    @ObservationIgnored private let clock: () -> Date

    init(
        provider: @escaping () -> [CalendarEvent],
        clock: @escaping () -> Date = { Date() }
    ) {
        self.provider = provider
        self.clock = clock
        self.now = clock()
    }

    func refresh() {
        let current = clock()
        let live = provider()
            .filter { $0.endDate > current }
            .sorted { $0.startDate < $1.startDate }
        let featured = MenuBarNextMeeting.featuredEvent(among: live, now: current)

        // Running meetings sort first and can fill the list; the featured
        // meeting then takes the last row so it is never cut off.
        var listed = Array(live.prefix(MenuBarNextMeeting.listLimit))
        if let featured, !listed.isEmpty, !listed.contains(featured) {
            listed[listed.count - 1] = featured
        }

        now = current
        featuredEvent = featured
        events = listed
    }

    func requestRefresh() {
        refreshToken &+= 1
    }
}
