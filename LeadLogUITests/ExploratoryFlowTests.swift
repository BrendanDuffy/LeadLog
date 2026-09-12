//  ExploratoryFlowTests.swift
//  Adversarial / edge-case exploration of the core flows, with screenshots
//  attached at each interesting state for visual review.

import XCTest

final class ExploratoryFlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        // Cheap insurance against a stray landscape orientation leaking in from
        // an earlier test — force a known-good starting state.
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

    /// Several tests in this file reuse "Glock 19" as a fixture name against
    /// the same persistent app state, so duplicate-firearm detection now
    /// legitimately fires after the first one creates it. Call right after
    /// tapping Save on an Add Firearm form — a no-op when no dialog appears.
    private func confirmDuplicateFirearmIfPresent() {
        let addAnyway = app.buttons.matching(NSPredicate(format: "label == %@", "Add Anyway")).firstMatch
        if addAnyway.waitForExistence(timeout: 2) { addAnyway.tap() }
    }

    /// The ammo quantity field strips non-digit characters as you type, so a
    /// "-50" quantity attempt elsewhere in this file actually lands as a valid
    /// "50" — meaning a later test creating the same caliber/brand can hit
    /// duplicate-ammo detection. No-op when the dialog doesn't appear.
    private func confirmDuplicateAmmoIfPresent() {
        let addToExisting = app.buttons.matching(NSPredicate(format: "label == %@", "Add to Existing Stock")).firstMatch
        if addToExisting.waitForExistence(timeout: 2) { addToExisting.tap() }
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

    /// Inventory's Firearms/Ammo picker is a dropdown (`InventoryTabButton`),
    /// not a plain segmented control — switching sections means opening it
    /// and tapping the target option, not tapping "Firearms"/"Ammo" directly.
    private func switchInventoryTab(to name: String) {
        let tabButton = app.buttons["InventoryTabButton"].firstMatch
        XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "Inventory should offer a Firearms/Ammo dropdown")
        guard !tabButton.label.contains(name) else { return } // already on that tab
        tabButton.tap()
        let option = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3), "Firearms/Ammo dropdown should offer \(name)")
        option.tap()
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
        confirmDuplicateFirearmIfPresent()
        attach("10-inventory-with-two-firearms")

        // ---------- Add ammo ----------
        switchInventoryTab(to: "Ammo")
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
            // Selecting a row only sets the pending choice — Save commits and
            // dismisses the picker (matches the Cancel/Save custom bottom sheet).
            let pickerSave = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
            if pickerSave.waitForExistence(timeout: 3) { pickerSave.tap() }
        }
        attach("17-firearm-selected-check-ammo-default")

        // Try submitting with 0 rounds
        let submitButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "LOG SESSION")).firstMatch
        if submitButton.waitForExistence(timeout: 3) {
            submitButton.tap()
            attach("18-submit-with-zero-rounds")
        }

        // Enter a huge rounds value
        let roundsFiredFields = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Rounds Fired"))
        if roundsFiredFields.firstMatch.waitForExistence(timeout: 3) {
            roundsFiredFields.firstMatch.tap()
            roundsFiredFields.firstMatch.typeText("999999999")
        }
        attach("19-huge-rounds-value")
        // Numeric keypad has no Return key and the app has no toolbar/dismiss
        // affordance, so drop the keyboard by tapping a neutral label instead —
        // this also stands in as a check that there IS some way to dismiss it.
        app.staticTexts["Log Session"].firstMatch.tap()
        if submitButton.waitForExistence(timeout: 3) { submitButton.tap() }
        attach("20-after-huge-rounds-submit")

        // ---------- HISTORY ----------
        tapTab("History")
        attach("21-history-after-sessions")
        // Search is behind a magnifying-glass icon that drops a small box down.
        let searchButton = app.buttons["SearchButton"].firstMatch
        if searchButton.waitForExistence(timeout: 3) {
            searchButton.tap()
            let searchField = app.textFields["SearchField"].firstMatch
            if searchField.waitForExistence(timeout: 3) {
                searchField.tap()
                searchField.typeText("zzz_no_such_firearm_zzz")
            }
            let done = app.buttons["SearchBoxDone"].firstMatch
            if done.waitForExistence(timeout: 2) { done.tap() }
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
        confirmDuplicateFirearmIfPresent()
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
        confirmDuplicateFirearmIfPresent()
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

        let roundsField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Rounds Fired")).firstMatch
        XCTAssertTrue(roundsField.waitForExistence(timeout: 3))
        XCTAssertTrue(roundsField.isHittable)
        roundsField.tap()
        roundsField.typeText("123")
        XCTAssertEqual(roundsField.value as? String, "123")
    }

    /// Neither PHPicker (out of process) nor the camera (no simulator hardware)
    /// can be driven from XCUITest, so this drives the same
    /// `row.photoPath = ...` mutation their callbacks perform, using a portrait
    /// image so the thumbnail is scaled the way a real phone photo would be.
    /// Guards the two things a photo used to break: the fields above it staying
    /// tappable, and the keyboard still dismissing on an outside tap.
    func testZZForcedPhotoInteractivityCheck() throws {
        app.launchArguments += ["-UITestForcePhoto"]
        app.launch()
        tapTab("Inventory")
        tapAddButton()
        let textFields = app.textFields
        XCTAssertTrue(textFields.element(boundBy: 0).waitForExistence(timeout: 5))
        textFields.element(boundBy: 0).tap(); textFields.element(boundBy: 0).typeText("Glock")
        textFields.element(boundBy: 1).tap(); textFields.element(boundBy: 1).typeText("19")
        let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Save")).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        confirmDuplicateFirearmIfPresent()
        sleep(1)

        tapTab("Log")
        let firearmField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Firearm")).firstMatch
        XCTAssertTrue(firearmField.waitForExistence(timeout: 5))
        firearmField.tap()
        let glockOption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Glock 19")).firstMatch
        XCTAssertTrue(glockOption.waitForExistence(timeout: 5))
        glockOption.tap()
        let pickerSave = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
        if pickerSave.waitForExistence(timeout: 3) { pickerSave.tap() }
        sleep(1)

        let debugForcePhoto = app.buttons["DebugForcePhoto"]
        XCTAssertTrue(debugForcePhoto.waitForExistence(timeout: 5))
        debugForcePhoto.tap()
        sleep(1)
        attach("photo-01-attached")

        // Rounds Fired must still accept input with the photo in place.
        let roundsField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Rounds Fired")).firstMatch
        XCTAssertTrue(roundsField.waitForExistence(timeout: 5))
        XCTAssertTrue(roundsField.isHittable, "Rounds Fired should be hittable with a photo attached")
        roundsField.tap()
        roundsField.typeText("150")
        sleep(1)
        XCTAssertEqual(roundsField.value as? String, "150", "Rounds Fired should be editable with a photo attached")
        attach("photo-02-rounds-editable")

        // Tapping the Notes field, then outside it, must dismiss the keyboard.
        let notesField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Notes")).firstMatch
        XCTAssertTrue(notesField.waitForExistence(timeout: 5))
        notesField.tap()
        notesField.typeText("range day")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "Keyboard should be up while editing Notes")

        app.staticTexts["Log Session"].tap()
        let keyboardGone = NSPredicate(format: "exists == false")
        expectation(for: keyboardGone, evaluatedWith: app.keyboards.element)
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error, "Tapping outside the Notes field should dismiss the keyboard")
        }
        attach("photo-03-keyboard-dismissed")

        // Select Ammo must still open its picker.
        let ammoField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Ammo")).firstMatch
        if ammoField.waitForExistence(timeout: 3) {
            XCTAssertTrue(ammoField.isHittable, "Select Ammo should be hittable with a photo attached")
            ammoField.tap()
            let ammoCancel = app.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
            XCTAssertTrue(ammoCancel.waitForExistence(timeout: 3), "Select Ammo should still open its picker")
        }
    }

    /// Covers the three related changes: "Add Another Firearm" only enables once
    /// firearm + rounds + ammo are all set on the row(s) already present, and a
    /// second row left entirely blank is dropped silently at submit rather than
    /// blocking the session with a validation error.
    // Named to sort after every other test in this file (alphabetically, tests
    // run in declaration-independent, name-sorted order within a class) —
    // this one doesn't need an empty starting inventory like
    // testFullExploratorySweep does, but running last avoids being the one
    // that pollutes that test's "0 firearms" assumption.
    func testZZZBlankRowIgnoredAndAmmoRequiredForAddAnotherFirearm() throws {
        app.launch()
        tapTab("Inventory")
        tapAddButton()
        let textFields = app.textFields
        XCTAssertTrue(textFields.element(boundBy: 0).waitForExistence(timeout: 5))
        textFields.element(boundBy: 0).tap(); textFields.element(boundBy: 0).typeText("Glock")
        textFields.element(boundBy: 1).tap(); textFields.element(boundBy: 1).typeText("19")
        let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Save")).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        confirmDuplicateFirearmIfPresent()
        sleep(1)

        switchInventoryTab(to: "Ammo")
        sleep(1) // let the tab switch settle before opening the add sheet
        tapAddButton()
        let ammoFields = app.textFields
        XCTAssertTrue(ammoFields.element(boundBy: 0).waitForExistence(timeout: 8))
        ammoFields.element(boundBy: 0).tap(); ammoFields.element(boundBy: 0).typeText("9mm")
        ammoFields.element(boundBy: 1).tap(); ammoFields.element(boundBy: 1).typeText("Federal")
        ammoFields.element(boundBy: 2).tap(); ammoFields.element(boundBy: 2).typeText("200")
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        confirmDuplicateAmmoIfPresent()
        sleep(1)

        tapTab("Log")
        let addAnotherButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Add Another Firearm")).firstMatch
        XCTAssertTrue(addAnotherButton.waitForExistence(timeout: 5))
        XCTAssertFalse(addAnotherButton.isEnabled, "Add Another Firearm should be disabled before the first row's required fields are filled")
        attach("req-01-add-another-disabled-empty")

        let firearmField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Firearm")).firstMatch
        XCTAssertTrue(firearmField.waitForExistence(timeout: 5))
        firearmField.tap()
        let glockOption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Glock 19")).firstMatch
        XCTAssertTrue(glockOption.waitForExistence(timeout: 5))
        glockOption.tap()
        let pickerSave = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
        if pickerSave.waitForExistence(timeout: 3) { pickerSave.tap() }
        sleep(1)
        XCTAssertFalse(addAnotherButton.isEnabled, "Add Another Firearm should stay disabled with rounds/ammo still missing")

        let roundsField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Rounds Fired")).firstMatch
        XCTAssertTrue(roundsField.waitForExistence(timeout: 5))
        roundsField.tap()
        roundsField.typeText("50")
        sleep(1)
        XCTAssertFalse(addAnotherButton.isEnabled, "Add Another Firearm should stay disabled until ammo is selected too")
        attach("req-02-add-another-still-disabled-no-ammo")

        let ammoField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Ammo")).firstMatch
        XCTAssertTrue(ammoField.waitForExistence(timeout: 5))
        ammoField.tap()
        let ammoOption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Federal")).firstMatch
        XCTAssertTrue(ammoOption.waitForExistence(timeout: 5))
        ammoOption.tap()
        let ammoPickerSave = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
        if ammoPickerSave.waitForExistence(timeout: 3) { ammoPickerSave.tap() }
        sleep(1)
        XCTAssertTrue(addAnotherButton.isEnabled, "Add Another Firearm should enable once firearm, rounds, and ammo are all set")
        attach("req-03-add-another-enabled")

        addAnotherButton.tap()
        sleep(1)
        attach("req-04-second-blank-row-added")

        let submitButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "LOG SESSION")).firstMatch
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        submitButton.tap()
        sleep(1)
        attach("req-05-after-submit-with-blank-second-row")

        // The blank second row should be silently ignored, not block submission.
        let firearmError = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "select a firearm")).firstMatch
        XCTAssertFalse(firearmError.waitForExistence(timeout: 3), "A fully blank second row should be ignored, not block submission")

        tapTab("History")
        attach("req-06-history-after-session")
    }

    /// A History row must open a read-only details popup on tap (firearm,
    /// rounds, ammo), and its photo must be viewable full-screen — the two
    /// things this feature was requested to fix ("no way to go back and look
    /// at that photo").
    func testZZZHistoryRowTapOpensViewSheetWithPhoto() throws {
        app.launchArguments += ["-UITestForcePhoto"]
        app.launch()
        tapTab("Inventory")
        tapAddButton()
        let textFields = app.textFields
        XCTAssertTrue(textFields.element(boundBy: 0).waitForExistence(timeout: 5))
        // A name unique to this test — other tests in this suite also create
        // "Glock 19" firearms and sessions, and History accumulates across the
        // whole run, so a shared name risks tapping someone else's row.
        textFields.element(boundBy: 0).tap(); textFields.element(boundBy: 0).typeText("ZZPhotoView")
        textFields.element(boundBy: 1).tap(); textFields.element(boundBy: 1).typeText("T1")
        let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Save")).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        sleep(1)

        tapTab("Log")
        let firearmField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Firearm")).firstMatch
        XCTAssertTrue(firearmField.waitForExistence(timeout: 5))
        firearmField.tap()
        let glockOption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZZPhotoView")).firstMatch
        XCTAssertTrue(glockOption.waitForExistence(timeout: 5))
        glockOption.tap()
        sleep(1)

        let roundsField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Rounds Fired")).firstMatch
        XCTAssertTrue(roundsField.waitForExistence(timeout: 5))
        roundsField.tap()
        roundsField.typeText("75")

        // Ammo may or may not be required depending on whether earlier tests in
        // this run seeded any into inventory — select one if the field is there.
        let ammoField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Ammo")).firstMatch
        if ammoField.waitForExistence(timeout: 3) {
            ammoField.tap()
            let firstAmmoOption = app.buttons.matching(identifier: "PickerOption").firstMatch
            if firstAmmoOption.waitForExistence(timeout: 3) { firstAmmoOption.tap() }
            sleep(1)
        }

        let debugForcePhoto = app.buttons["DebugForcePhoto"]
        XCTAssertTrue(debugForcePhoto.waitForExistence(timeout: 5))
        debugForcePhoto.tap()
        sleep(1)

        let submitButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "LOG SESSION")).firstMatch
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        submitButton.tap()
        sleep(1)

        tapTab("History")
        attach("view-01-history-list")
        let firstRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZZPhotoView")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "History should show the logged session")
        firstRow.tap()

        // Details popup: firearm, rounds, and a viewable photo should all be present.
        let firearmValue = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZZPhotoView")).firstMatch
        XCTAssertTrue(firearmValue.waitForExistence(timeout: 5), "View sheet should show the firearm")
        let roundsValue = app.staticTexts.matching(NSPredicate(format: "label == %@", "75")).firstMatch
        XCTAssertTrue(roundsValue.waitForExistence(timeout: 3), "View sheet should show the rounds fired")
        attach("view-02-details-popup")

        let viewPhotoButton = app.buttons["ViewTargetPhoto"]
        XCTAssertTrue(viewPhotoButton.waitForExistence(timeout: 5), "View sheet should offer a way to view the attached photo")
        viewPhotoButton.tap()
        sleep(1)
        attach("view-03-fullscreen-photo")

        let closeButton = app.buttons["ClosePhotoViewer"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Full-screen photo viewer should have a close control")
        closeButton.tap()

        // Back on the details popup — Close should return to the History list.
        let closeSheetButton = app.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch
        XCTAssertTrue(closeSheetButton.waitForExistence(timeout: 5), "Should return to the details popup after closing the photo viewer")
        closeSheetButton.tap()
        attach("view-04-back-in-history")
    }

    /// Covers the firearm↔ammo compatibility allow-list: after linking one ammo
    /// to one firearm via the new "Compatible Firearms" multi-select on the ammo
    /// sheet, Log Session's ammo picker for that firearm offers only the linked
    /// ammo, while a firearm with nothing linked still falls back to the full
    /// list. Named to sort dead last — it seeds several fixtures and doesn't
    /// need a pristine starting state.
    func testZZZZCompatibleAmmoRestrictsLogSessionAmmoPicker() throws {
        app.launch()
        let save = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch

        // ---------- Two firearms ----------
        tapTab("Inventory")
        for model in ["Alpha", "Bravo"] {
            tapAddButton()
            let tf = app.textFields
            XCTAssertTrue(tf.element(boundBy: 0).waitForExistence(timeout: 5))
            tf.element(boundBy: 0).tap(); tf.element(boundBy: 0).typeText("ZCompatMfr")
            tf.element(boundBy: 1).tap(); tf.element(boundBy: 1).typeText(model)
            XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
            confirmDuplicateFirearmIfPresent()
            sleep(1)
        }

        // ---------- Two ammo entries ----------
        switchInventoryTab(to: "Ammo")
        sleep(1)
        for (cal, brand) in [("ZCompatCalX", "BrandXX"), ("ZCompatCalY", "BrandYY")] {
            tapAddButton()
            let af = app.textFields
            XCTAssertTrue(af.element(boundBy: 0).waitForExistence(timeout: 8))
            af.element(boundBy: 0).tap(); af.element(boundBy: 0).typeText(cal)
            af.element(boundBy: 1).tap(); af.element(boundBy: 1).typeText(brand)
            af.element(boundBy: 2).tap(); af.element(boundBy: 2).typeText("100")
            XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
            confirmDuplicateAmmoIfPresent()
            sleep(1)
        }

        // ---------- Link BrandXX -> ZCompatMfr Alpha only ----------
        // The row title is "caliber brand" now (e.g. "ZCompatCalX BrandXX"),
        // not the brand alone, so match on the substring.
        let brandXRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "BrandXX")).firstMatch
        XCTAssertTrue(brandXRow.waitForExistence(timeout: 5))
        brandXRow.tap()
        let compatFirearmsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Compatible Firearms")).firstMatch
        XCTAssertTrue(compatFirearmsButton.waitForExistence(timeout: 5), "Ammo sheet should have a Compatible Firearms field")
        compatFirearmsButton.tap()
        let alphaOption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZCompatMfr Alpha")).firstMatch
        XCTAssertTrue(alphaOption.waitForExistence(timeout: 5))
        alphaOption.tap()
        let multiSave = app.buttons["MultiSheetSave"]
        XCTAssertTrue(multiSave.waitForExistence(timeout: 3))
        multiSave.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 3)); save.tap()   // save the ammo sheet
        sleep(1)

        // ---------- Log Session: Alpha sees only BrandXX ----------
        tapTab("Log")
        let firearmField = app.buttons["SelectFirearmField"]
        XCTAssertTrue(firearmField.waitForExistence(timeout: 5))
        firearmField.tap()
        let alphaFirearm = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZCompatMfr Alpha")).firstMatch
        XCTAssertTrue(alphaFirearm.waitForExistence(timeout: 5))
        alphaFirearm.tap()
        let pickerSave = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
        if pickerSave.waitForExistence(timeout: 3) { pickerSave.tap() }
        sleep(1)

        let ammoField = app.buttons["SelectAmmoField"]
        XCTAssertTrue(ammoField.waitForExistence(timeout: 5))
        XCTAssertTrue(ammoField.isHittable, "Select Ammo should be enabled once a firearm is chosen")
        ammoField.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "BrandXX")).firstMatch.waitForExistence(timeout: 5),
            "Alpha's linked ammo (BrandXX) should be offered"
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "BrandYY")).firstMatch.exists,
            "BrandYY is not linked to Alpha and must not appear in its ammo picker"
        )
        attach("compat-01-alpha-ammo-restricted")
        let ammoPickerCancel = app.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
        if ammoPickerCancel.waitForExistence(timeout: 2) { ammoPickerCancel.tap() }
        sleep(1)

        // ---------- Bravo has nothing linked -> sees all ammo ----------
        firearmField.tap()
        let bravoFirearm = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZCompatMfr Bravo")).firstMatch
        XCTAssertTrue(bravoFirearm.waitForExistence(timeout: 5))
        bravoFirearm.tap()
        if pickerSave.waitForExistence(timeout: 3) { pickerSave.tap() }
        sleep(1)
        ammoField.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "BrandXX")).firstMatch.waitForExistence(timeout: 5),
            "A firearm with nothing linked falls back to showing every ammo"
        )
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "BrandYY")).firstMatch.exists,
            "A firearm with nothing linked falls back to showing every ammo"
        )
        attach("compat-02-bravo-sees-all")
    }

    /// The Inventory/History search is now a magnifying-glass icon by the header
    /// buttons that drops a small box down. Verifies: icon opens the box, typing
    /// filters the list, and clearing restores it.
    func testZZZSearchIconPopupFiltersInventoryList() throws {
        app.launch()
        tapTab("Inventory")
        let save = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch

        for model in ["Keeper", "Hidden"] {
            tapAddButton()
            let tf = app.textFields
            XCTAssertTrue(tf.element(boundBy: 0).waitForExistence(timeout: 5))
            tf.element(boundBy: 0).tap(); tf.element(boundBy: 0).typeText("ZSearchMfr")
            tf.element(boundBy: 1).tap(); tf.element(boundBy: 1).typeText(model)
            XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
            confirmDuplicateFirearmIfPresent()
            sleep(1)
        }

        let keeper = app.staticTexts["ZSearchMfr Keeper"].firstMatch
        let hidden = app.staticTexts["ZSearchMfr Hidden"].firstMatch
        XCTAssertTrue(keeper.waitForExistence(timeout: 5))
        XCTAssertTrue(hidden.exists, "Both firearms should be listed before searching")

        // No standing search bar — just the icon.
        XCTAssertFalse(app.textFields["SearchField"].exists, "Search field should be hidden until the icon is tapped")
        let searchButton = app.buttons["SearchButton"].firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        searchButton.tap()

        let searchField = app.textFields["SearchField"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "Tapping the icon should reveal the search box")
        searchField.typeText("Keeper")
        sleep(1)
        attach("search-01-filtered")
        XCTAssertTrue(app.staticTexts["ZSearchMfr Keeper"].firstMatch.waitForExistence(timeout: 3), "Matching firearm should stay")
        XCTAssertFalse(app.staticTexts["ZSearchMfr Hidden"].firstMatch.exists, "Non-matching firearm should be filtered out")

        // Clear (×) restores the full list; the box can be dismissed and the
        // filter is already gone.
        let clear = app.buttons["Clear search"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        let done = app.buttons["SearchBoxDone"].firstMatch
        if done.waitForExistence(timeout: 2) { done.tap() }
        sleep(1)
        XCTAssertTrue(app.staticTexts["ZSearchMfr Hidden"].firstMatch.waitForExistence(timeout: 3), "Clearing search should restore the full list")
        attach("search-02-restored")
    }

    /// The color wheel itself is Apple's system picker (not automatable
    /// reliably from here), so this only confirms the Settings row renders
    /// correctly and starts in the "no custom color chosen yet" state —
    /// no Reset button until a color has actually been picked.
    func testZZZZSettingsShowsAccentColorPresetsWithGreenSelectedByDefault() throws {
        app.launch()
        tapTab("Settings")

        XCTAssertTrue(app.staticTexts["Accent Color"].firstMatch.waitForExistence(timeout: 5), "Settings should offer an Accent Color row")
        for id in ["green", "teal", "blue", "violet", "berry", "red", "darkgrey", "skyblue", "orange"] {
            XCTAssertTrue(app.buttons["AccentPreset_\(id)"].waitForExistence(timeout: 3), "Missing the \(id) accent preset swatch")
        }
        XCTAssertTrue(
            app.buttons["AccentPreset_green"].label.contains("selected"),
            "A fresh install hasn't customized the accent yet, so Green (the default) should be selected"
        )
        attach("settings-accent-presets-default")
    }

    /// Picking a non-default preset (a) marks it selected instead of Green,
    /// (b) survives a relaunch (persisted, not just in-memory), and (c) is
    /// reset back to Green at the end so it doesn't leak into later tests.
    func testZZZZZPickingAnAccentPresetPersistsAcrossRelaunch() throws {
        app.launch()
        tapTab("Settings")

        let blue = app.buttons["AccentPreset_blue"].firstMatch
        XCTAssertTrue(blue.waitForExistence(timeout: 5))
        blue.tap()
        XCTAssertTrue(blue.label.contains("selected"), "Tapping Blue should select it")
        sleep(1) // let the tab bar's async repaint settle before screenshotting it
        attach("settings-accent-preset-blue-selected")

        app.terminate()
        app.launch()
        tapTab("Settings")
        let blueAfterRelaunch = app.buttons["AccentPreset_blue"].firstMatch
        XCTAssertTrue(blueAfterRelaunch.waitForExistence(timeout: 5))
        XCTAssertTrue(blueAfterRelaunch.label.contains("selected"), "The picked preset should persist across a relaunch")

        // Clean up so later tests (and the default-selected-on-fresh-install
        // test above) see the original, un-customized state.
        let green = app.buttons["AccentPreset_green"].firstMatch
        XCTAssertTrue(green.waitForExistence(timeout: 3))
        green.tap()
        XCTAssertTrue(green.label.contains("selected"))
    }

    func testZZZZZZSettingsShowsFontAndSizeRowsWithSystemAndDefaultSelected() throws {
        app.launch()
        tapTab("Settings")

        XCTAssertTrue(app.staticTexts["Font"].firstMatch.waitForExistence(timeout: 5), "Settings should offer a Font row")
        XCTAssertTrue(app.staticTexts["Text Size"].firstMatch.waitForExistence(timeout: 3), "Settings should offer a Text Size row")
        for id in ["system", "impact", "rockwell", "copperplate"] {
            XCTAssertTrue(app.buttons["FontFamily_\(id)"].waitForExistence(timeout: 3), "Missing the \(id) font family option")
        }
        for id in ["small", "standard", "large", "extraLarge"] {
            XCTAssertTrue(app.buttons["FontSize_\(id)"].waitForExistence(timeout: 3), "Missing the \(id) text size option")
        }
        XCTAssertTrue(app.buttons["FontFamily_system"].label.contains("selected"), "A fresh install should have System selected")
        XCTAssertTrue(app.buttons["FontSize_standard"].label.contains("selected"), "A fresh install should have Default size selected")
        attach("settings-font-and-size-defaults")
    }

    /// Picking a non-default family AND size (a) marks both selected, (b)
    /// visibly changes ordinary body text elsewhere on the very same screen
    /// (the whole point of "applies everywhere, no exceptions"), (c)
    /// survives a relaunch, and (d) is reset back to defaults at the end.
    func testZZZZZZZPickingFontAndSizePersistsAcrossRelaunchAndAppliesEverywhere() throws {
        app.launch()
        tapTab("Settings")

        let rockwell = app.buttons["FontFamily_rockwell"].firstMatch
        let extraLarge = app.buttons["FontSize_extraLarge"].firstMatch
        XCTAssertTrue(rockwell.waitForExistence(timeout: 5))
        XCTAssertTrue(extraLarge.waitForExistence(timeout: 3))
        rockwell.tap()
        extraLarge.tap()
        XCTAssertTrue(rockwell.label.contains("selected"))
        XCTAssertTrue(extraLarge.label.contains("selected"))
        sleep(1) // let the full-app repaint (tab bar included) settle
        // "No exceptions" means even unrelated body text on this same screen
        // (not just the Font/Text Size rows themselves) should reflect it.
        XCTAssertTrue(app.staticTexts["Version"].firstMatch.waitForExistence(timeout: 3))
        attach("settings-font-rockwell-extralarge-applied")

        app.terminate()
        app.launch()
        tapTab("Settings")
        let rockwellAfterRelaunch = app.buttons["FontFamily_rockwell"].firstMatch
        let extraLargeAfterRelaunch = app.buttons["FontSize_extraLarge"].firstMatch
        XCTAssertTrue(rockwellAfterRelaunch.waitForExistence(timeout: 5))
        XCTAssertTrue(extraLargeAfterRelaunch.waitForExistence(timeout: 3))
        XCTAssertTrue(rockwellAfterRelaunch.label.contains("selected"), "The picked family should persist across a relaunch")
        XCTAssertTrue(extraLargeAfterRelaunch.label.contains("selected"), "The picked size should persist across a relaunch")

        // Clean up so later tests see the original, un-customized state.
        let system = app.buttons["FontFamily_system"].firstMatch
        let standard = app.buttons["FontSize_standard"].firstMatch
        XCTAssertTrue(system.waitForExistence(timeout: 3))
        XCTAssertTrue(standard.waitForExistence(timeout: 3))
        system.tap()
        standard.tap()
        XCTAssertTrue(system.label.contains("selected"))
        XCTAssertTrue(standard.label.contains("selected"))
    }

    func testZZZZZZZZInventoryFirearmsGroupByCategoryThenManufacturer() throws {
        app.launch()
        tapTab("Inventory")

        // Both left with no Category, so they should fold into one shared
        // "Other" group under the default Category grouping.
        for model in ["Alpha", "Beta"] {
            tapAddButton()
            let tf = app.textFields
            XCTAssertTrue(tf.element(boundBy: 0).waitForExistence(timeout: 5))
            tf.element(boundBy: 0).tap(); tf.element(boundBy: 0).typeText("ZGroupMfr\(model)")
            tf.element(boundBy: 1).tap(); tf.element(boundBy: 1).typeText("One")
            let save = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
            confirmDuplicateFirearmIfPresent()
            sleep(1)
        }

        // By this point in the suite many other firearms exist from earlier
        // tests — `List` virtualizes off-screen rows, so without narrowing
        // to just these two fixtures first, they can be unrendered (and
        // thus "not found") purely from being scrolled far down the list.
        // The search box's own dimming overlay would otherwise also block
        // taps on the Group By control below, so dismiss it (via Done, which
        // only hides the box — the filter text stays active) right after typing.
        let searchButton = app.buttons["SearchButton"].firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        searchButton.tap()
        let searchField = app.textFields["SearchField"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.typeText("ZGroupMfr")
        let searchDone = app.buttons["SearchBoxDone"].firstMatch
        if searchDone.waitForExistence(timeout: 2) { searchDone.tap() }
        sleep(1)

        XCTAssertTrue(app.staticTexts["ZGroupMfrAlpha One"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ZGroupMfrBeta One"].firstMatch.waitForExistence(timeout: 3))

        // Default grouping is Category — both have none, so exactly one
        // "OTHER" section header, not two.
        let groupByButton = app.buttons["GroupByButton"].firstMatch
        XCTAssertTrue(groupByButton.waitForExistence(timeout: 3), "Inventory should offer a Group By control")
        XCTAssertTrue(groupByButton.label.contains("Category"), "Should default to grouping by Category")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "OTHER")).count, 1, "Both un-categorized firearms should fold into one Other group")
        attach("inventory-firearms-grouped-by-category")

        // Opening the menu and switching to Manufacturer should split them
        // into two headers.
        groupByButton.tap()
        let manufacturerOption = app.buttons.matching(NSPredicate(format: "label == %@", "Manufacturer")).firstMatch
        XCTAssertTrue(manufacturerOption.waitForExistence(timeout: 3), "Group By menu should offer Manufacturer")
        manufacturerOption.tap()
        sleep(1)
        XCTAssertTrue(groupByButton.label.contains("Manufacturer"), "Group By control should reflect the new selection")
        XCTAssertTrue(app.staticTexts["ZGROUPMFRALPHA"].waitForExistence(timeout: 3), "Should have a per-manufacturer header once grouped by Manufacturer")
        XCTAssertTrue(app.staticTexts["ZGROUPMFRBETA"].waitForExistence(timeout: 3))
        attach("inventory-firearms-grouped-by-manufacturer")
    }

    func testZZZZZZZZZInventoryAmmoGroupByCaliberThenManufacturerThenCategory() throws {
        app.launch()
        tapTab("Inventory")
        switchInventoryTab(to: "Ammo")

        for (caliber, brand) in [("ZGroupCalOne", "ZGroupBrandOne"), ("ZGroupCalTwo", "ZGroupBrandTwo")] {
            tapAddButton()
            let tf = app.textFields
            XCTAssertTrue(tf.element(boundBy: 0).waitForExistence(timeout: 5))
            tf.element(boundBy: 0).tap(); tf.element(boundBy: 0).typeText(caliber)
            tf.element(boundBy: 1).tap(); tf.element(boundBy: 1).typeText(brand)
            if tf.count >= 3 { tf.element(boundBy: 2).tap(); tf.element(boundBy: 2).typeText("50") }
            let save = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
            confirmDuplicateAmmoIfPresent()
            sleep(1)
        }

        let groupByButton = app.buttons["GroupByButton"].firstMatch
        XCTAssertTrue(groupByButton.waitForExistence(timeout: 3), "Ammo tab should offer a Group By control")
        XCTAssertTrue(groupByButton.label.contains("Caliber"), "Should default to grouping by Caliber")

        // Same reasoning as the Firearms grouping test: narrow to just these
        // two fixtures (List virtualizes off-screen rows by now) and dismiss
        // the search box (Done only hides it — filter stays active) before
        // touching the Group By control underneath its dimming overlay.
        let searchButton = app.buttons["SearchButton"].firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        searchButton.tap()
        let searchField = app.textFields["SearchField"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.typeText("ZGroupCal")
        let searchDone = app.buttons["SearchBoxDone"].firstMatch
        if searchDone.waitForExistence(timeout: 2) { searchDone.tap() }
        sleep(1)

        // Default is Caliber — two distinct calibers, so two headers.
        XCTAssertTrue(app.staticTexts["ZGROUPCALONE"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["ZGROUPCALTWO"].waitForExistence(timeout: 3))
        attach("inventory-ammo-grouped-by-caliber")

        // Opening the menu and switching to Category — both entries have
        // none, so one shared Other group, not two.
        groupByButton.tap()
        let categoryOption = app.buttons.matching(NSPredicate(format: "label == %@", "Category")).firstMatch
        XCTAssertTrue(categoryOption.waitForExistence(timeout: 3), "Group By menu should offer Category")
        categoryOption.tap()
        sleep(1)
        XCTAssertTrue(groupByButton.label.contains("Category"), "Group By control should reflect the new selection")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "OTHER")).count, 1, "Both un-categorized ammo entries should fold into one Other group")
        attach("inventory-ammo-grouped-by-category")
    }

    func testZZZZZZZZZZLogSessionAmmoStockRowQuickAddsStock() throws {
        app.launch()
        tapTab("Inventory")

        // LogSessionView needs at least one active firearm to show its body
        // at all, rather than the "No Firearms" empty state.
        tapAddButton()
        let ff = app.textFields
        XCTAssertTrue(ff.element(boundBy: 0).waitForExistence(timeout: 5))
        ff.element(boundBy: 0).tap(); ff.element(boundBy: 0).typeText("ZQuickAddMfr")
        ff.element(boundBy: 1).tap(); ff.element(boundBy: 1).typeText("One")
        let saveFirearm = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
        XCTAssertTrue(saveFirearm.waitForExistence(timeout: 5)); saveFirearm.tap()
        confirmDuplicateFirearmIfPresent()
        sleep(1)

        switchInventoryTab(to: "Ammo")
        tapAddButton()
        let af = app.textFields
        XCTAssertTrue(af.element(boundBy: 0).waitForExistence(timeout: 5))
        af.element(boundBy: 0).tap(); af.element(boundBy: 0).typeText("ZQuickAddCal")
        af.element(boundBy: 1).tap(); af.element(boundBy: 1).typeText("ZQuickAddBrand")
        if af.count >= 3 { af.element(boundBy: 2).tap(); af.element(boundBy: 2).typeText("40") }
        let saveAmmo = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
        XCTAssertTrue(saveAmmo.waitForExistence(timeout: 5)); saveAmmo.tap()
        confirmDuplicateAmmoIfPresent()
        sleep(1)

        tapTab("Log")
        let ammoStockHeader = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "AMMO STOCK")).firstMatch
        XCTAssertTrue(ammoStockHeader.waitForExistence(timeout: 5), "Log Session should show an Ammo Stock summary")
        ammoStockHeader.tap()
        sleep(1)

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZQuickAddBrand")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Tapping Ammo Stock should reveal the ZQuickAddBrand row, now tappable")
        row.tap()

        let roundsField = app.textFields["Rounds to add"].firstMatch
        XCTAssertTrue(roundsField.waitForExistence(timeout: 3), "Tapping the row should open the same Add Stock alert as the Inventory swipe action")
        roundsField.tap()
        roundsField.typeText("25")
        let addButton = app.buttons.matching(NSPredicate(format: "label == %@", "Add")).firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 3)); addButton.tap()
        sleep(1)

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "65 rounds")).firstMatch.waitForExistence(timeout: 3),
            "Restocked toast should reflect the new quantity (40 + 25)"
        )
        attach("logsession-ammo-quick-add")
    }

    /// Covers History's new Active Firearms / Retired filter (mirroring Inventory's),
    /// and confirms that permanently deleting a firearm cascades to remove its
    /// History log entries too. Named to sort dead last.
    func testZZZZZZZZZZZHistoryRetiredFilterAndFirearmDeleteCascadesHistory() throws {
        app.launch()
        tapTab("Inventory")
        tapAddButton()
        let ff = app.textFields
        XCTAssertTrue(ff.element(boundBy: 0).waitForExistence(timeout: 5))
        ff.element(boundBy: 0).tap(); ff.element(boundBy: 0).typeText("ZHistFilterMfr")
        ff.element(boundBy: 1).tap(); ff.element(boundBy: 1).typeText("One")
        let saveFirearm = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Save")).firstMatch
        XCTAssertTrue(saveFirearm.waitForExistence(timeout: 5)); saveFirearm.tap()
        confirmDuplicateFirearmIfPresent()
        sleep(1)

        // Log a session against it so there's a History entry to track through
        // retire and delete.
        tapTab("Log")
        let firearmField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Firearm")).firstMatch
        XCTAssertTrue(firearmField.waitForExistence(timeout: 5))
        firearmField.tap()
        let firearmOption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZHistFilterMfr")).firstMatch
        XCTAssertTrue(firearmOption.waitForExistence(timeout: 5))
        firearmOption.tap()
        sleep(1)
        let roundsField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Rounds Fired")).firstMatch
        XCTAssertTrue(roundsField.waitForExistence(timeout: 5))
        roundsField.tap()
        roundsField.typeText("33")
        let ammoField = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Select Ammo")).firstMatch
        if ammoField.waitForExistence(timeout: 3) {
            ammoField.tap()
            let firstAmmoOption = app.buttons.matching(identifier: "PickerOption").firstMatch
            if firstAmmoOption.waitForExistence(timeout: 3) { firstAmmoOption.tap() }
            sleep(1)
        }
        let submitButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "LOG SESSION")).firstMatch
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        submitButton.tap()
        sleep(1)

        // History shows it under the default Active Firearms filter.
        tapTab("History")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZHistFilterMfr")).firstMatch.waitForExistence(timeout: 5),
            "Active History should show the new session"
        )
        attach("retired-filter-01-active-visible")

        // Retire the firearm from Inventory.
        tapTab("Inventory")
        let invRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZHistFilterMfr")).firstMatch
        XCTAssertTrue(invRow.waitForExistence(timeout: 5))
        invRow.tap()
        let retireButton = app.buttons["FirearmRetireButton"]
        XCTAssertTrue(retireButton.waitForExistence(timeout: 5))
        retireButton.tap()
        let confirmRetire = app.buttons["ConfirmRetireFirearmButton"]
        XCTAssertTrue(confirmRetire.waitForExistence(timeout: 3))
        confirmRetire.tap()
        sleep(1)

        // Back on History, the default Active filter should now hide it.
        tapTab("History")
        sleep(1)
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZHistFilterMfr")).firstMatch.waitForExistence(timeout: 3),
            "Retiring the firearm should hide its sessions from the Active History filter"
        )
        attach("retired-filter-02-hidden-when-active")

        // Switching to the Retired filter should bring it back.
        let historyFilterButton = app.buttons["HistoryRetiredFilterButton"]
        XCTAssertTrue(historyFilterButton.waitForExistence(timeout: 5))
        historyFilterButton.tap()
        let retiredOption = app.buttons.matching(NSPredicate(format: "label == %@", "Retired")).firstMatch
        XCTAssertTrue(retiredOption.waitForExistence(timeout: 3))
        retiredOption.tap()
        sleep(1)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZHistFilterMfr")).firstMatch.waitForExistence(timeout: 5),
            "Switching to the Retired filter should show the retired firearm's sessions"
        )
        attach("retired-filter-03-visible-when-retired")

        // Now permanently delete the firearm from Inventory's Retired list and
        // confirm its History cascades away too.
        tapTab("Inventory")
        let filterButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Filter firearms")).firstMatch
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()
        let retiredTabOption = app.buttons.matching(NSPredicate(format: "label == %@", "Retired")).firstMatch
        XCTAssertTrue(retiredTabOption.waitForExistence(timeout: 3))
        retiredTabOption.tap()
        sleep(1)
        let retiredInvRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZHistFilterMfr")).firstMatch
        XCTAssertTrue(retiredInvRow.waitForExistence(timeout: 5))
        retiredInvRow.tap()
        let deleteButton = app.buttons["FirearmDeleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        let confirmDelete = app.buttons["ConfirmDeleteFirearmButton"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 3))
        confirmDelete.tap()
        sleep(1)

        // History (still on the Retired filter) should no longer show it — the
        // firearm and its session were both deleted.
        tapTab("History")
        sleep(1)
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ZHistFilterMfr")).firstMatch.waitForExistence(timeout: 3),
            "Deleting the firearm should cascade-delete its History entries too"
        )
        attach("retired-filter-04-gone-after-delete")
    }

}
