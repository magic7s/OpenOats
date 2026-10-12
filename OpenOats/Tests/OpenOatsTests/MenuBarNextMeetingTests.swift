import XCTest
@testable import OpenOatsKit

final class MenuBarNextMeetingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Countdown

    func testCountdownShowsWholeMinutes() {
        XCTAssertEqual(countdown(secondsAway: 7 * 60), "in 7m")
    }

    func testCountdownRoundsPartialMinuteDown() {
        XCTAssertEqual(countdown(secondsAway: 6 * 60 + 10), "in 6m")
        XCTAssertEqual(countdown(secondsAway: 6 * 60 + 59), "in 6m")
        XCTAssertEqual(countdown(secondsAway: 60), "in 1m")
    }

    func testCountdownReadsNowUnderOneMinuteAndAfterStart() {
        XCTAssertEqual(countdown(secondsAway: 59), "now")
        XCTAssertEqual(countdown(secondsAway: 1), "now")
        XCTAssertEqual(countdown(secondsAway: 0), "now")
        XCTAssertEqual(countdown(secondsAway: -30), "now")
    }

    func testCountdownSwitchesToHoursAtSixtyMinutes() {
        XCTAssertEqual(countdown(secondsAway: 59 * 60 + 30), "in 59m")
        XCTAssertEqual(countdown(secondsAway: 60 * 60), "in 1h")
        XCTAssertEqual(countdown(secondsAway: 80 * 60 + 45), "in 1h 20m")
    }

    // MARK: - Time left

    func testRemainingRoundsPartialMinuteDown() {
        XCTAssertEqual(remaining(secondsLeft: 28 * 60 + 10), "28m left")
        XCTAssertEqual(remaining(secondsLeft: 60), "1m left")
    }

    func testRemainingSwitchesToHoursAtSixtyMinutes() {
        XCTAssertEqual(remaining(secondsLeft: 60 * 60), "1h left")
        XCTAssertEqual(remaining(secondsLeft: 65 * 60 + 30), "1h 5m left")
    }

    func testRemainingNeverReadsZeroMinutes() {
        XCTAssertEqual(remaining(secondsLeft: 59), "<1m left")
        XCTAssertEqual(remaining(secondsLeft: 0), "<1m left")
    }

    // MARK: - Title truncation

    func testTruncatedTitleKeepsShortTitle() {
        XCTAssertEqual(MenuBarNextMeeting.truncatedTitle("Standup"), "Standup")
    }

    func testTruncatedTitleKeepsTitleExactlyAtLimit() {
        let title = String(repeating: "a", count: 16)
        XCTAssertEqual(MenuBarNextMeeting.truncatedTitle(title), title)
    }

    func testTruncatedTitleCutsLongTitleToLimitWithEllipsis() {
        let result = MenuBarNextMeeting.truncatedTitle("Review the Quarterly Numbers")
        XCTAssertEqual(result, "Review the Quar…")
        XCTAssertEqual(result.count, 16)
    }

    func testTruncatedTitleDropsSpaceBeforeEllipsis() {
        XCTAssertEqual(MenuBarNextMeeting.truncatedTitle("Quarterly Plan A Session"), "Quarterly Plan…")
    }

    func testTruncatedTitleCollapsesLineBreaksAndRuns() {
        XCTAssertEqual(MenuBarNextMeeting.truncatedTitle("  Team\n\nSync  "), "Team Sync")
    }

    func testTruncatedTitleFallsBackForBlankTitle() {
        XCTAssertEqual(MenuBarNextMeeting.truncatedTitle(""), "Meeting")
        XCTAssertEqual(MenuBarNextMeeting.truncatedTitle(" \n "), "Meeting")
    }

    func testTruncatedTitleCountsEmojiAsOneCharacter() {
        let title = String(repeating: "👨‍👩‍👧", count: 20)
        let result = MenuBarNextMeeting.truncatedTitle(title)
        XCTAssertEqual(result, String(repeating: "👨‍👩‍👧", count: 15) + "…")
    }

    // MARK: - Featured event

    func testFeaturedIsNilForNoEvents() {
        XCTAssertNil(MenuBarNextMeeting.featuredEvent(among: [], now: now))
    }

    func testFeaturedPicksEarliestUpcomingWithinLookahead() {
        let events = [
            makeEvent(id: "later", startsIn: 40 * 60),
            makeEvent(id: "sooner", startsIn: 10 * 60),
        ]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "sooner")
    }

    func testFeaturedIncludesEventAtLookaheadBoundary() {
        let events = [makeEvent(id: "edge", startsIn: 60 * 60)]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "edge")
    }

    func testFeaturedExcludesEventPastLookaheadBoundary() {
        let events = [makeEvent(id: "far", startsIn: 60 * 60 + 1)]
        XCTAssertNil(MenuBarNextMeeting.featuredEvent(among: events, now: now))
    }

    func testFeaturedKeepsRunningMeetingUntilItEnds() {
        let events = [makeEvent(id: "running", startsIn: -40 * 60, duration: 60 * 60)]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "running")
    }

    func testFeaturedPrefersRunningMeetingOverOneFurtherOut() {
        let events = [
            makeEvent(id: "next", startsIn: 30 * 60),
            makeEvent(id: "running", startsIn: -40 * 60, duration: 60 * 60),
        ]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "running")
    }

    func testFeaturedPrefersMostRecentlyStartedOfParallelMeetings() {
        let events = [
            makeEvent(id: "earlier", startsIn: -30 * 60, duration: 60 * 60),
            makeEvent(id: "later", startsIn: -5 * 60, duration: 60 * 60),
        ]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "later")
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events.reversed(), now: now)?.id, "later")
    }

    func testFeaturedPrefersRunningEventWithMeetingLinkOnTie() {
        let link = URL(string: "https://zoom.us/j/123")!
        let events = [
            makeEvent(id: "a-focus-block", startsIn: -5 * 60),
            makeEvent(id: "b-real-meeting", startsIn: -5 * 60, meetingURL: link),
        ]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "b-real-meeting")
    }

    func testFeaturedSwitchesToNextMeetingAtSwitchLead() {
        let events = [
            makeEvent(id: "running", startsIn: -20 * 60, duration: 60 * 60),
            makeEvent(id: "next", startsIn: 10 * 60),
        ]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "next")
    }

    func testFeaturedKeepsRunningMeetingBeforeSwitchLead() {
        let events = [
            makeEvent(id: "running", startsIn: -20 * 60, duration: 60 * 60),
            makeEvent(id: "next", startsIn: 10 * 60 + 1),
        ]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "running")
    }

    func testFeaturedSkipsRunningEventLongerThanMaxDuration() {
        let travel = makeEvent(id: "travel", startsIn: -60 * 60, duration: 48 * 60 * 60)
        XCTAssertNil(MenuBarNextMeeting.featuredEvent(among: [travel], now: now))

        let events = [travel, makeEvent(id: "next", startsIn: 30 * 60)]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "next")
    }

    func testFeaturedIncludesRunningEventAtMaxDuration() {
        let events = [makeEvent(id: "workshop", startsIn: -60 * 60, duration: 8 * 60 * 60)]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "workshop")
    }

    func testFeaturedCountsDownToLongEventThatHasNotStarted() {
        let events = [makeEvent(id: "travel", startsIn: 20 * 60, duration: 48 * 60 * 60)]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "travel")
    }

    func testFeaturedIgnoresEndedEvent() {
        let events = [makeEvent(id: "done", startsIn: -5 * 60, duration: 2 * 60)]
        XCTAssertNil(MenuBarNextMeeting.featuredEvent(among: events, now: now))
    }

    func testFeaturedPrefersEventWithMeetingLinkOnTie() {
        let link = URL(string: "https://zoom.us/j/123")!
        let events = [
            makeEvent(id: "a-focus-block", startsIn: 10 * 60),
            makeEvent(id: "b-real-meeting", startsIn: 10 * 60, meetingURL: link),
        ]
        XCTAssertEqual(MenuBarNextMeeting.featuredEvent(among: events, now: now)?.id, "b-real-meeting")
        XCTAssertEqual(
            MenuBarNextMeeting.featuredEvent(among: events.reversed(), now: now)?.id,
            "b-real-meeting"
        )
    }

    // MARK: - Status item text

    func testStatusItemTextJoinsTitleAndCountdown() {
        let event = makeEvent(id: "e", title: "Review the Quarterly Numbers", startsIn: 8 * 60)
        XCTAssertEqual(
            MenuBarNextMeeting.statusItemText(featured: event, now: now, isRecording: false, isEnabled: true),
            "Review the Quar… • in 8m"
        )
    }

    func testStatusItemTextShowsTimeLeftForRunningMeeting() {
        let event = makeEvent(id: "e", title: "Standup", startsIn: -2 * 60, duration: 30 * 60 + 10)
        XCTAssertEqual(
            MenuBarNextMeeting.statusItemText(featured: event, now: now, isRecording: false, isEnabled: true),
            "Standup • 28m left"
        )
    }

    func testStatusItemTextIsNilWhenDisabled() {
        let event = makeEvent(id: "e", startsIn: 8 * 60)
        XCTAssertNil(
            MenuBarNextMeeting.statusItemText(featured: event, now: now, isRecording: false, isEnabled: false)
        )
    }

    func testStatusItemTextIsNilWhileRecording() {
        let event = makeEvent(id: "e", startsIn: 8 * 60)
        XCTAssertNil(
            MenuBarNextMeeting.statusItemText(featured: event, now: now, isRecording: true, isEnabled: true)
        )
    }

    func testStatusItemTextIsNilWithoutFeaturedEvent() {
        XCTAssertNil(
            MenuBarNextMeeting.statusItemText(featured: nil, now: now, isRecording: false, isEnabled: true)
        )
    }

    // MARK: - Header text

    func testHeaderTextForUpcomingAndRunningEvents() {
        XCTAssertEqual(
            MenuBarNextMeeting.headerText(for: makeEvent(id: "e", startsIn: 7 * 60), now: now),
            "Starts in 7m"
        )
        XCTAssertEqual(
            MenuBarNextMeeting.headerText(for: makeEvent(id: "e", startsIn: 30), now: now),
            "Starts now"
        )
        XCTAssertEqual(
            MenuBarNextMeeting.headerText(for: makeEvent(id: "e", startsIn: -60), now: now),
            "Happening now"
        )
    }

    // MARK: - Popover order

    func testFeaturedFirstMovesFeaturedEventToFront() {
        let running = makeEvent(id: "running", startsIn: -20 * 60, duration: 60 * 60)
        let next = makeEvent(id: "next", startsIn: 5 * 60)
        let later = makeEvent(id: "later", startsIn: 90 * 60)
        XCTAssertEqual(
            MenuBarNextMeeting.featuredFirst([running, next, later], featured: next).map(\.id),
            ["next", "running", "later"]
        )
    }

    func testFeaturedFirstLeavesOrderWhenFeaturedIsAbsent() {
        let first = makeEvent(id: "first", startsIn: 5 * 60)
        let second = makeEvent(id: "second", startsIn: 90 * 60)
        XCTAssertEqual(MenuBarNextMeeting.featuredFirst([first, second], featured: nil).map(\.id), ["first", "second"])
        let elsewhere = makeEvent(id: "elsewhere", startsIn: 30 * 60)
        XCTAssertEqual(
            MenuBarNextMeeting.featuredFirst([first, second], featured: elsewhere).map(\.id),
            ["first", "second"]
        )
    }

    // MARK: - Join plan

    func testJoinPlanOpensLinkAndRecordsWhenIdle() {
        let link = URL(string: "https://zoom.us/j/123")!
        let plan = MenuBarNextMeeting.joinPlan(
            for: makeEvent(id: "e", startsIn: 60, meetingURL: link),
            isRecording: false,
            hasRecordingConsent: true
        )
        XCTAssertEqual(
            plan,
            MenuBarNextMeeting.JoinPlan(urlToOpen: link, startsRecording: true, showsMainWindow: false)
        )
    }

    func testJoinPlanRecordsEventWithoutLink() {
        let plan = MenuBarNextMeeting.joinPlan(
            for: makeEvent(id: "e", startsIn: 60),
            isRecording: false,
            hasRecordingConsent: true
        )
        XCTAssertEqual(
            plan,
            MenuBarNextMeeting.JoinPlan(urlToOpen: nil, startsRecording: true, showsMainWindow: false)
        )
    }

    func testJoinPlanOnlyOpensLinkWhileRecording() {
        let link = URL(string: "https://zoom.us/j/123")!
        let plan = MenuBarNextMeeting.joinPlan(
            for: makeEvent(id: "e", startsIn: 60, meetingURL: link),
            isRecording: true,
            hasRecordingConsent: true
        )
        XCTAssertEqual(
            plan,
            MenuBarNextMeeting.JoinPlan(urlToOpen: link, startsRecording: false, showsMainWindow: false)
        )
    }

    func testJoinPlanShowsMainWindowInsteadOfRecordingWithoutConsent() {
        let link = URL(string: "https://zoom.us/j/123")!
        let plan = MenuBarNextMeeting.joinPlan(
            for: makeEvent(id: "e", startsIn: 60, meetingURL: link),
            isRecording: false,
            hasRecordingConsent: false
        )
        XCTAssertEqual(
            plan,
            MenuBarNextMeeting.JoinPlan(urlToOpen: link, startsRecording: false, showsMainWindow: true)
        )
    }

    // MARK: - Helpers

    private func countdown(secondsAway: TimeInterval) -> String {
        MenuBarNextMeeting.countdownText(until: now.addingTimeInterval(secondsAway), now: now)
    }

    private func remaining(secondsLeft: TimeInterval) -> String {
        MenuBarNextMeeting.remainingText(until: now.addingTimeInterval(secondsLeft), now: now)
    }

    private func makeEvent(
        id: String,
        title: String = "Meeting",
        startsIn offset: TimeInterval,
        duration: TimeInterval = 30 * 60,
        meetingURL: URL? = nil
    ) -> CalendarEvent {
        let start = now.addingTimeInterval(offset)
        return CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            organizer: nil,
            participants: [],
            isOnlineMeeting: meetingURL != nil,
            meetingURL: meetingURL
        )
    }
}
