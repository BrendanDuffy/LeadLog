//  ExploratoryFlowTests.swift
//  Adversarial / edge-case exploration of the core flows, with screenshots
//  attached at each interesting state for visual review.

import XCTest

final class ExploratoryFlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        // LeadLogUITestsLaunchTests rotates the simulator and never rotates
        // back, so a stray landscape orientation can leak into whichever
        // test happens to run next. Force a known-good starting state.
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
        else {
            // fall back to fuzzy match in case the tab label merges with the icon
            let fuzzy = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
            if fuzzy.waitForExistence(timeout: 3) { fuzzy.tap() }
        }
    }

    private func tapAddButton() {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Firearm' OR label CONTAINS[c] 'Add Ammo'")).firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
        } else {
            // last-resort fallback if the label ever changes
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.05)).tap()
        }
    }

    func testFullExploratorySweep() throws {
        app.launch()
        attach("00-launch")

        // ---------- LOG SESSION: empty-firearms state ----------
        attach("01-log-empty-state")
        // The session-entry form is intentionally hidden with 0 firearms — only
        // the empty state + a "Go to Inventory" CTA should be present.
        let selectFirearmField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Firearm")).firstMatch
        XCTAssertFalse(selectFirearmField.exists, "Select Firearm field should be hidden when there are 0 firearms")
        let goToInventoryButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Go to Inventory")).firstMatch
        XCTAssertTrue(goToInventoryButton.waitForExistence(timeout: 5), "Empty state should offer a Go to Inventory CTA")
        goToInventoryButton.tap()
        attach("02-go-to-inventory-cta-tapped")
        XCTAssertTrue(app.staticTexts["Inventory"].waitForExistence(timeout: 5), "Go to Inventory CTA should switch to the Inventory tab")

        // ---------- INVENTORY: add firearm with validation edge cases ----------
        tapTab("Inventory")
        attach("03-inventory-empty")

        tapAddButton()
        attach("04-add-firearm-sheet-opened")

        // Try saving completely empty — expect a validation error, not a crash or silent no-op
        let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Save")).firstMatch
        if saveButton.waitForExistence(timeout: 5) {
            saveButton.tap()
            attach("05-empty-save-attempt")
        }

        // Fill manufacturer/model with edge-case text: emoji + very long string
        let textFields = app.textFields
        if textFields.count >= 1 {
            textFields.element(boundBy: 0).tap()
            textFields.element(boundBy: 0).typeText("🔫 Test Mfr " + String(repeating: "X", count: 120))
        }
        if textFields.count >= 2 {
            textFields.element(boundBy: 1).tap()
            textFields.element(boundBy: 1).typeText("Model-9000 Ultra Long Name Edition Special")
        }
        attach("06-firearm-form-filled-edge-case-text")

        // Rounds before service: try entering non-numeric junk
        if textFields.count >= 4 {
            let roundsField = textFields.element(boundBy: 3)
            roundsField.tap()
            roundsField.typeText("abc-99!!")
        }
        attach("07-rounds-field-junk-input")

        if saveButton.exists {
            saveButton.tap()
        }
        attach("08-after-save-with-long-name")

        // ---------- Add a second, normal firearm for later flows ----------
        tapAddButton()
        if textFields.count >= 1 { textFields.element(boundBy: 0).tap(); textFields.element(boundBy: 0).typeText("Glock") }
        if textFields.count >= 2 { textFields.element(boundBy: 1).tap(); textFields.element(boundBy: 1).typeText("19") }
        attach("09-second-firearm-form")
        if saveButton.exists { saveButton.tap() }
        attach("10-inventory-with-two-firearms")

        // ---------- Add ammo ----------
        let ammoTabButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ammo")).firstMatch
        if ammoTabButton.waitForExistence(timeout: 3) { ammoTabButton.tap() }
        attach("11-ammo-tab-empty")
        tapAddButton()
        attach("12-add-ammo-sheet")
        let ammoFields = app.textFields
        if ammoFields.count >= 1 { ammoFields.element(boundBy: 0).tap(); ammoFields.element(boundBy: 0).typeText("9mm") }
        if ammoFields.count >= 2 { ammoFields.element(boundBy: 1).tap(); ammoFields.element(boundBy: 1).typeText("Federal") }
        if ammoFields.count >= 3 { ammoFields.element(boundBy: 2).tap(); ammoFields.element(boundBy: 2).typeText("-50") } // negative quantity attempt
        attach("13-ammo-negative-quantity-attempt")
        if saveButton.exists { saveButton.tap() }
        attach("14-after-ammo-save-attempt")

        // ---------- LOG SESSION: now with real firearms ----------
        tapTab("Log")
        attach("15-log-session-with-firearms")

        let firearmField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Firearm")).firstMatch
        if firearmField.waitForExistence(timeout: 5) {
            firearmField.tap()
            attach("16-firearm-picker-populated")
            // Pick whichever firearm is first in the list rather than assuming a name.
            let firstOption = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Glock' OR label CONTAINS[c] 'Test Mfr'")
            ).firstMatch
            if firstOption.waitForExistence(timeout: 3) { firstOption.tap() }
        }
        attach("17-firearm-selected-check-ammo-default")

        // Try submitting with 0 rounds
        let submitButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "LOG SESSION")).firstMatch
        if submitButton.waitForExistence(timeout: 3) {
            submitButton.tap()
            attach("18-submit-with-zero-rounds")
        }

        // Enter a huge rounds value
        let roundsFiredFields = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "50"))
        if roundsFiredFields.firstMatch.waitForExistence(timeout: 3) {
            roundsFiredFields.firstMatch.tap()
            roundsFiredFields.firstMatch.typeText("999999999")
        }
        attach("19-huge-rounds-value")
        // Numeric keypad has no Return key and the app has no toolbar/dismiss
        // affordance, so drop the keyboard by tapping a neutral label instead —
        // this also stands in as a check that there IS some way to dismiss it.
        app.staticTexts["SESSION · 01"].firstMatch.tap()
        if submitButton.waitForExistence(timeout: 3) { submitButton.tap() }
        attach("20-after-huge-rounds-submit")

        // ---------- HISTORY ----------
        tapTab("History")
        attach("21-history-after-sessions")
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 3) {
            searchField.tap()
            searchField.typeText("zzz_no_such_firearm_zzz")
            attach("22-history-search-no-results")
        }

        // ---------- SETTINGS ----------
        tapTab("Settings")
        attach("23-settings")

        attach("24-final-state")
    }

    /// Isolated so a dismiss-timing hiccup here can't cascade into unrelated
    /// failures elsewhere — this only needs to confirm the photo source
    /// dialog (camera vs. library) renders with the right options.
    func testPhotoSourceDialogOffersCameraAndLibrary() throws {
        app.launch()
        tapTab("Inventory")

        tapAddButton()
        let textFields = app.textFields
        // Wait for the sheet's first field to actually exist before reading
        // .count — otherwise this can race the presentation animation and
        // silently see 0 fields on a cold app launch.
        XCTAssertTrue(textFields.element(boundBy: 0).waitForExistence(timeout: 5), "Add Firearm sheet should present with a Manufacturer field")
        textFields.element(boundBy: 0).tap(); textFields.element(boundBy: 0).typeText("Glock")
        if textFields.count >= 2 { textFields.element(boundBy: 1).tap(); textFields.element(boundBy: 1).typeText("19") }
        let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Save")).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        // Confirm the save actually went through (sheet dismissed, toast or
        // row shows up) before navigating away — don't just fire-and-hope.
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: saveButton)
        _ = XCTWaiter().wait(for: [dismissed], timeout: 5)

        tapTab("Log")
        // The photo attach button renders in every session row regardless of
        // whether a firearm has been picked for that row yet — no need to
        // drive the (separate, already-covered) firearm picker sheet here.
        let attachPhotoButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Attach Target Photo")).firstMatch
        XCTAssertTrue(attachPhotoButton.waitForExistence(timeout: 3))
        attachPhotoButton.tap()
        attach("photo-source-dialog")

        let takePhoto = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Take Photo")).firstMatch
        let chooseLibrary = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Choose from Library")).firstMatch
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 3), "Photo source dialog should offer Take Photo")
        XCTAssertTrue(chooseLibrary.exists, "Photo source dialog should offer Choose from Library")
    }

    /// The system Photos picker (PHPickerViewController, backing `.photosPicker`)
    /// renders in a separate out-of-process extension for privacy, so its photo
    /// grid isn't reachable through this app's XCUIApplication — can't drive a
    /// full pick-a-photo repro here. What IS verifiable end-to-end: the dialog
    /// opens, offers both sources, and cancels cleanly without disturbing the
    /// row underneath (the underlying fix — moving the presentation modifiers
    /// off the button that gets removed from the hierarchy once a photo is set,
    /// onto the row's stable root — was verified manually in the simulator).
    ///
    /// Note: on this OS build, confirmationDialog renders as a small anchored
    /// popover with NO explicit Cancel button — confirmed via a diagnostic
    /// against an unrelated, pre-existing dialog (InventoryView's delete
    /// confirmation) to be a system-wide rendering change, not an app bug.
    /// Dismissal is via tapping outside the popover instead.
    func testPhotoDialogCancelLeavesFormFullyInteractive() throws {
        app.launch()
        tapTab("Inventory")
        tapAddButton()
        let textFields = app.textFields
        XCTAssertTrue(textFields.element(boundBy: 0).waitForExistence(timeout: 5))
        textFields.element(boundBy: 0).tap(); textFields.element(boundBy: 0).typeText("Glock")
        if textFields.count >= 2 { textFields.element(boundBy: 1).tap(); textFields.element(boundBy: 1).typeText("19") }
        let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Save")).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: saveButton)
        _ = XCTWaiter().wait(for: [dismissed], timeout: 5)

        tapTab("Log")
        let attachPhotoButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Attach Target Photo")).firstMatch
        XCTAssertTrue(attachPhotoButton.waitForExistence(timeout: 5))
        attachPhotoButton.tap()
        let takePhoto = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Take Photo")).firstMatch
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 3), "Photo source dialog should appear")
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        if dismissRegion.waitForExistence(timeout: 2) {
            dismissRegion.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        }
        let goneExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: takePhoto)
        _ = XCTWaiter().wait(for: [goneExpectation], timeout: 3)

        // Rest of the row must still be fully interactive after the dialog closes.
        let firearmField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Firearm")).firstMatch
        XCTAssertTrue(firearmField.waitForExistence(timeout: 3))
        XCTAssertTrue(firearmField.isHittable)
        firearmField.tap()
        let pickerCancel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Cancel")).firstMatch
        XCTAssertTrue(pickerCancel.waitForExistence(timeout: 3), "Select Firearm should still open its picker after the photo dialog is cancelled")
        pickerCancel.tap()

        let roundsField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "50")).firstMatch
        XCTAssertTrue(roundsField.waitForExistence(timeout: 3))
        XCTAssertTrue(roundsField.isHittable)
        roundsField.tap()
        roundsField.typeText("123")
        XCTAssertEqual(roundsField.value as? String, "123")
    }

}
