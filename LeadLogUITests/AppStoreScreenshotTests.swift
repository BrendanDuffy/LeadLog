//  AppStoreScreenshotTests.swift
//  Not part of the regression suite — run standalone against the seeded demo
//  data (launch with `-SeedAppStoreScreenshotData`, see DemoSeedData.swift)
//  to capture a curated set of marketing screenshots. Each `attach(_:)` call
//  becomes an XCTAttachment in the resulting .xcresult, exported afterward
//  via `xcresulttool export attachments`.
//
//  Split into 3 methods because light/dark is a simulator-level appearance
//  setting toggled externally (`simctl ui <device> appearance light|dark`)
//  between runs, not something one continuous test can flip mid-flight:
//   - testCaptureLightModeScreenshots: 8 shots, light mode, default accent —
//     the last one swaps the accent to Sky Blue to show off customization.
//   - testCaptureDarkModeScreenshots: 2 shots (Inventory, History), dark mode,
//     default accent — run with the simulator already set to dark appearance.

import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)"]
    }

    private func attach(_ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapTab(_ name: String) {
        let tab = app.buttons[name].firstMatch
        if tab.waitForExistence(timeout: 5) { tab.tap() }
    }

    func testCaptureLightModeScreenshots() throws {
        app.launch()
        sleep(2)

        // 1 — Log Session home: ready to log, Ammo Stock summary visible.
        tapTab("Log")
        sleep(1)
        attach("01-log-session")

        // 2 — Log Session with a firearm picked: service-due warning + ammo picker.
        let firearmField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Firearm")).firstMatch
        if firearmField.waitForExistence(timeout: 5) {
            firearmField.tap()
            let glockOption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Glock 19")).firstMatch
            if glockOption.waitForExistence(timeout: 5) { glockOption.tap() }
            sleep(1)
        }
        attach("02-log-session-service-warning")

        // 4 — Firearm detail sheet (Glock 19: progress bar near its limit).
        tapTab("Inventory")
        sleep(1)
        let glockRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Glock 19")).firstMatch
        if glockRow.waitForExistence(timeout: 5) {
            glockRow.tap()
            sleep(1)
        }
        attach("04-firearm-detail")
        let doneButton = app.buttons.matching(NSPredicate(format: "label == %@", "Done")).firstMatch
        if doneButton.waitForExistence(timeout: 3) { doneButton.tap() }
        sleep(1)

        // 5 — Inventory, Ammo tab grouped by Caliber (shows the low-stock badge).
        let tabDropdown = app.buttons["InventoryTabButton"].firstMatch
        if tabDropdown.waitForExistence(timeout: 5) {
            tabDropdown.tap()
            let ammoOption = app.buttons.matching(NSPredicate(format: "label == %@", "Ammo")).firstMatch
            if ammoOption.waitForExistence(timeout: 3) { ammoOption.tap() }
        }
        sleep(1)
        attach("05-inventory-ammo")

        // 7 — History grouped by Firearm.
        tapTab("History")
        sleep(1)
        let firearmSegment = app.buttons.matching(NSPredicate(format: "label == %@", "Firearm")).firstMatch
        if firearmSegment.waitForExistence(timeout: 3) { firearmSegment.tap() }
        sleep(1)
        attach("07-history-firearm")

        // 8 — A History entry's detail view. Switch back to Date grouping and
        // tap the newest entry, which is always the topmost row — List
        // virtualizes off-screen rows, so anything further down wouldn't
        // exist yet to tap without scrolling first.
        let dateSegment = app.buttons.matching(NSPredicate(format: "label == %@", "Date")).firstMatch
        if dateSegment.waitForExistence(timeout: 3) { dateSegment.tap() }
        sleep(1)
        let historyRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sighted in for hunting season")).firstMatch
        if historyRow.waitForExistence(timeout: 5) {
            historyRow.tap()
            sleep(1)
        }
        attach("08-history-entry-detail")
        let closeButton = app.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch
        if closeButton.waitForExistence(timeout: 3) { closeButton.tap() }
        sleep(1)

        // 9 — History's Retired filter (preserves the retired Ruger LCR's history).
        let historyFilterButton = app.buttons["HistoryRetiredFilterButton"]
        if historyFilterButton.waitForExistence(timeout: 5) {
            historyFilterButton.tap()
            let retiredOption = app.buttons.matching(NSPredicate(format: "label == %@", "Retired")).firstMatch
            if retiredOption.waitForExistence(timeout: 3) { retiredOption.tap() }
        }
        sleep(1)
        attach("09-history-retired-filter")

        // 10 — Settings, switched to the Sky Blue accent to show off customization.
        tapTab("Settings")
        sleep(1)
        let skyBlueSwatch = app.buttons["AccentPreset_skyblue"]
        if skyBlueSwatch.waitForExistence(timeout: 5) {
            skyBlueSwatch.tap()
            sleep(1)
            // Tapping an off-screen swatch in the horizontal picker only
            // auto-scrolls it minimally into a barely-hittable position — drag
            // it further left so the now-selected Sky Blue swatch is clearly
            // visible in frame, not just barely peeking in at the edge.
            let start = skyBlueSwatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: -150, dy: 0))
            start.press(forDuration: 0.05, thenDragTo: end)
            sleep(1)
        }
        attach("10-settings-customization")
    }

    /// Run with the simulator already switched to dark appearance
    /// (`xcrun simctl ui <device> appearance dark`) before launching.
    func testCaptureDarkModeScreenshots() throws {
        app.launch()
        sleep(2)

        // 3 — Inventory, Firearms grouped by Category, in Dark Mode.
        tapTab("Inventory")
        sleep(1)
        attach("03-inventory-firearms-dark")

        // 6 — History grouped by Date, in Dark Mode.
        tapTab("History")
        sleep(1)
        attach("06-history-date-dark")
    }
}
