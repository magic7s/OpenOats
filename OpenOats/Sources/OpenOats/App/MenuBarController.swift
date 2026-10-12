import AppKit
import EventKit
import Observation
import SwiftUI

private final class MenuBarStatusItemActionTarget: NSObject {
    weak var controller: MenuBarController?

    init(controller: MenuBarController) {
        self.controller = controller
    }

    @objc func togglePopover(_ sender: Any?) {
        let controller = controller
        Task { @MainActor in
            controller?.togglePopoverFromStatusItem()
        }
    }
}

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let coordinator: AppCoordinator
    private let settings: AppSettings
    private let onToggleMeeting: () -> Void
    private lazy var statusItemActionTarget = MenuBarStatusItemActionTarget(controller: self)
    private var iconUpdateTask: Task<Void, Never>?
    private let meetings: MenuBarMeetingsModel
    private var refreshTickTask: Task<Void, Never>?
    private var calendarChangeTask: Task<Void, Never>?
    private var hasConfiguredButton = false

    var onShowMainWindow: (() -> Void)?
    var onQuitApp: (() -> Void)?

    init(
        coordinator: AppCoordinator,
        settings: AppSettings,
        upcomingEvents: @escaping () -> [CalendarEvent],
        onCheckForUpdates: @escaping () -> Void,
        onToggleMeeting: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.onToggleMeeting = onToggleMeeting
        self.meetings = MenuBarMeetingsModel(provider: upcomingEvents)

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 160)
        popover.behavior = .transient
        popover.animates = true

        let popoverView = MenuBarPopoverView(
            coordinator: coordinator,
            settings: settings,
            onToggleMeeting: onToggleMeeting,
            onShowMainWindow: { [weak self] in
                self?.popover.performClose(nil)
                self?.onShowMainWindow?()
            },
            onCheckForUpdates: { [weak self] in
                self?.popover.performClose(nil)
                onCheckForUpdates()
            },
            onShowSettings: { [weak self] in
                self?.popover.performClose(nil)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            onQuit: { [weak self] in
                self?.popover.performClose(nil)
                self?.onQuitApp?()
            }
        )
        popover.contentViewController = NSHostingController(rootView: popoverView)

        refreshStatusItem()

        startIconObservation()
        startRefreshTick()
        startCalendarChangeObservation()
    }

    deinit {
        iconUpdateTask?.cancel()
        refreshTickTask?.cancel()
        calendarChangeTask?.cancel()
    }

    func togglePopoverFromStatusItem() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            meetings.refresh()
            updateIcon()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func startIconObservation() {
        iconUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                meetings.refresh()
                updateIcon()
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.coordinator.isRecording
                        _ = self.settings.showMenuBarIcon
                        _ = self.settings.showNextMeetingInMenuBar
                        _ = self.settings.calendarIntegrationEnabled
                        _ = self.settings.excludedCalendarIDs
                        _ = self.meetings.refreshToken
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// Wakes just after each wall-clock minute so the countdown changes on the minute.
    private func startRefreshTick() {
        refreshTickTask = Task { [weak self] in
            while !Task.isCancelled {
                let secondsIntoMinute = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(60 - secondsIntoMinute + 0.5))
                guard !Task.isCancelled else { break }
                self?.meetings.requestRefresh()
            }
        }
    }

    private func startCalendarChangeObservation() {
        calendarChangeTask = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: .EKEventStoreChanged)
                .map { _ in () }
            for await _ in changes {
                self?.meetings.requestRefresh()
            }
        }
    }

    private func updateIcon() {
        statusItem.isVisible = settings.showMenuBarIcon
        refreshStatusItem()
        guard let button = statusItem.button else { return }

        button.image = Self.makeConcentricCirclesIcon(filled: coordinator.isRecording)
        button.image?.isTemplate = true

        let text = MenuBarNextMeeting.statusItemText(
            featured: meetings.featuredEvent,
            now: meetings.now,
            isRecording: coordinator.isRecording,
            isEnabled: settings.showNextMeetingInMenuBar && settings.calendarIntegrationEnabled
        )
        button.title = text.map { " \($0)" } ?? ""
        button.imagePosition = text == nil ? .imageOnly : .imageLeading
    }

    func refreshStatusItem() {
        guard let button = statusItem.button else {
            DiagnosticsSupport.record(category: "menu", message: "Status item button unavailable")
            return
        }

        if !hasConfiguredButton {
            button.target = statusItemActionTarget
            button.action = #selector(MenuBarStatusItemActionTarget.togglePopover(_:))
            hasConfiguredButton = true
            DiagnosticsSupport.record(category: "menu", message: "Status item button configured")
        }

        if button.image == nil {
            button.image = Self.makeConcentricCirclesIcon(filled: coordinator.isRecording)
            button.image?.isTemplate = true
        }
    }

    private static func makeConcentricCirclesIcon(filled: Bool) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let outerRadius: CGFloat = size / 2 - 1
            let ringWidth: CGFloat = 2.2
            let innerRadius: CGFloat = outerRadius * 0.38

            NSColor.black.setStroke()

            // Outer ring
            let outerPath = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - outerRadius,
                    y: center.y - outerRadius,
                    width: outerRadius * 2,
                    height: outerRadius * 2
                )
            )
            outerPath.lineWidth = ringWidth
            if filled {
                NSColor.black.setFill()
                outerPath.fill()
                // Draw inner part in white to create ring effect
                let gapRadius = outerRadius - ringWidth
                let gapPath = NSBezierPath(
                    ovalIn: NSRect(
                        x: center.x - gapRadius,
                        y: center.y - gapRadius,
                        width: gapRadius * 2,
                        height: gapRadius * 2
                    )
                )
                NSColor.white.setFill()
                gapPath.fill()
                // Inner filled circle
                let innerPath = NSBezierPath(
                    ovalIn: NSRect(
                        x: center.x - innerRadius,
                        y: center.y - innerRadius,
                        width: innerRadius * 2,
                        height: innerRadius * 2
                    )
                )
                NSColor.black.setFill()
                innerPath.fill()
            } else {
                outerPath.stroke()
                // Inner ring
                let innerPath = NSBezierPath(
                    ovalIn: NSRect(
                        x: center.x - innerRadius,
                        y: center.y - innerRadius,
                        width: innerRadius * 2,
                        height: innerRadius * 2
                    )
                )
                innerPath.lineWidth = ringWidth
                innerPath.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "OpenOats"
        return image
    }
}
