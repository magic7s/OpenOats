import XCTest
@testable import OpenOatsKit

@MainActor
final class MenuBarMeetingsModelTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testStartsEmptyUntilRefreshed() {
        let model = MenuBarMeetingsModel(provider: { [self] in [makeEvent(id: "a", startsIn: 600)] }, clock: { [base] in base })
        XCTAssertTrue(model.events.isEmpty)
        XCTAssertNil(model.featuredEvent)
    }

    func testRefreshLoadsEventsSortedByStart() {
        let model = MenuBarMeetingsModel(
            provider: { [self] in
                [makeEvent(id: "second", startsIn: 1200), makeEvent(id: "first", startsIn: 600)]
            },
            clock: { [base] in base }
        )
        model.refresh()
        XCTAssertEqual(model.events.map(\.id), ["first", "second"])
        XCTAssertEqual(model.featuredEvent?.id, "first")
    }

    func testRefreshWithNoEventsLeavesNothingFeatured() {
        let model = MenuBarMeetingsModel(provider: { [] }, clock: { [base] in base })
        model.refresh()
        XCTAssertTrue(model.events.isEmpty)
        XCTAssertNil(model.featuredEvent)
    }

    func testRefreshDropsEndedEvents() {
        let model = MenuBarMeetingsModel(
            provider: { [self] in
                [
                    makeEvent(id: "ended", startsIn: -600, duration: 300),
                    makeEvent(id: "running", startsIn: -300, duration: 1800),
                ]
            },
            clock: { [base] in base }
        )
        model.refresh()
        XCTAssertEqual(model.events.map(\.id), ["running"])
    }

    func testRefreshKeepsAtMostListLimitEvents() {
        let model = MenuBarMeetingsModel(
            provider: { [self] in
                (1...10).map { makeEvent(id: "e\($0)", startsIn: TimeInterval($0) * 600) }
            },
            clock: { [base] in base }
        )
        model.refresh()
        XCTAssertEqual(model.events.count, MenuBarNextMeeting.listLimit)
        XCTAssertEqual(model.events.first?.id, "e1")
    }

    func testRefreshKeepsFeaturedEventWhenListIsFull() {
        let model = MenuBarMeetingsModel(
            provider: { [self] in
                (1...5).map { makeEvent(id: "running\($0)", startsIn: TimeInterval(-$0) * 600, duration: 7200) }
                    + [makeEvent(id: "next", startsIn: 300)]
            },
            clock: { [base] in base }
        )
        model.refresh()
        XCTAssertEqual(model.featuredEvent?.id, "next")
        XCTAssertEqual(model.events.count, MenuBarNextMeeting.listLimit)
        XCTAssertEqual(model.events.last?.id, "next")
    }

    func testRefreshReadsClockAgain() {
        var current = base
        let model = MenuBarMeetingsModel(
            provider: { [self] in [makeEvent(id: "a", startsIn: 90 * 60)] },
            clock: { current }
        )
        model.refresh()
        XCTAssertNil(model.featuredEvent, "90 minutes away is outside the lookahead")

        current = base.addingTimeInterval(45 * 60)
        model.refresh()
        XCTAssertEqual(model.now, current)
        XCTAssertEqual(model.featuredEvent?.id, "a")
    }

    func testRequestRefreshChangesTokenWithoutFetching() {
        var fetches = 0
        let model = MenuBarMeetingsModel(provider: { fetches += 1; return [] }, clock: { [base] in base })
        let before = model.refreshToken
        model.requestRefresh()
        XCTAssertNotEqual(model.refreshToken, before)
        XCTAssertEqual(fetches, 0)
    }

    private func makeEvent(
        id: String,
        startsIn offset: TimeInterval,
        duration: TimeInterval = 30 * 60
    ) -> CalendarEvent {
        let start = base.addingTimeInterval(offset)
        return CalendarEvent(
            id: id,
            title: "Meeting \(id)",
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            organizer: nil,
            participants: [],
            isOnlineMeeting: false,
            meetingURL: nil
        )
    }
}
