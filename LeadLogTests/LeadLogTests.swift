//  LeadLogTests.swift

import Testing
import SwiftData
import SwiftUI
import UIKit
import Foundation
@testable import LeadLog

// MARK: - In-memory container helper

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Firearm.self, LogEntry.self, AmmoEntry.self, ServiceRecord.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Firearm Business Logic Tests

@Suite("Firearm Business Logic")
@MainActor
struct FirearmTests {

    @Test("activeRounds sums only unserviced log entries")
    func activeRoundsExcludesServiced() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let firearm = Firearm(manufacturer: "Glock", model: "19")
        ctx.insert(firearm)

        let e1 = LogEntry(sessionId: "s1", date: Date(), rounds: 100)
        e1.firearm = firearm; ctx.insert(e1)

        let e2 = LogEntry(sessionId: "s2", date: Date(), rounds: 50)
        e2.firearm = firearm; e2.servicedAt = Date(); ctx.insert(e2)

        try ctx.save()
        #expect(firearm.activeRounds == 100)
    }

    @Test("progressPercent caps at 100 when over limit")
    func progressPercentCaps() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let firearm = Firearm(manufacturer: "Glock", model: "19")
        firearm.roundsBeforeService = 100; ctx.insert(firearm)

        let e1 = LogEntry(sessionId: "s1", date: Date(), rounds: 200)
        e1.firearm = firearm; ctx.insert(e1)
        try ctx.save()

        #expect(firearm.progressPercent == 100.0)
        #expect(firearm.progressPercent <= 100.0)
    }

    @Test("progressPercent returns zero when roundsBeforeService is zero")
    func progressPercentGuard() {
        let firearm = Firearm(manufacturer: "Glock", model: "19")
        firearm.roundsBeforeService = 0
        #expect(firearm.progressPercent == 0.0)
    }

    @Test("isOverLimit true when activeRounds meets service interval")
    func serviceDueAtLimit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let firearm = Firearm(manufacturer: "Glock", model: "19")
        firearm.roundsBeforeService = 500; ctx.insert(firearm)

        let e1 = LogEntry(sessionId: "s1", date: Date(), rounds: 500)
        e1.firearm = firearm; ctx.insert(e1)
        try ctx.save()

        #expect(firearm.isOverLimit == true)
        #expect(firearm.isNearLimit == false)
    }

    @Test("isNearLimit true between 80% and 100%")
    func nearLimitLogic() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let firearm = Firearm(manufacturer: "Glock", model: "19")
        firearm.roundsBeforeService = 500; ctx.insert(firearm)

        let e1 = LogEntry(sessionId: "s1", date: Date(), rounds: 420) // 84%
        e1.firearm = firearm; ctx.insert(e1)
        try ctx.save()

        #expect(firearm.isNearLimit == true)
        #expect(firearm.isOverLimit == false)
    }

    @Test("Retired firearm excluded from active filter")
    func retiredFirearmFilter() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let active = Firearm(manufacturer: "Glock", model: "17")
        let retired = Firearm(manufacturer: "Glock", model: "19")
        retired.isRetired = true
        ctx.insert(active); ctx.insert(retired)
        try ctx.save()

        let activeOnly = [active, retired].filter { !$0.isRetired }
        #expect(activeOnly.count == 1)
        #expect(activeOnly.first?.model == "17")
    }

    @Test("Mark as serviced creates ServiceRecord and stamps unserviced entries")
    func markAsServicedBehavior() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let firearm = Firearm(manufacturer: "Glock", model: "19")
        firearm.roundsBeforeService = 500; ctx.insert(firearm)

        let e1 = LogEntry(sessionId: "s1", date: Date(), rounds: 200)
        e1.firearm = firearm; ctx.insert(e1)

        let e2 = LogEntry(sessionId: "s2", date: Date(), rounds: 100)
        e2.firearm = firearm; ctx.insert(e2)
        try ctx.save()

        #expect(firearm.activeRounds == 300)

        // Replicate mark-as-serviced logic from FirearmDetailView
        let record = ServiceRecord(servicedAt: Date(), roundsAtService: firearm.activeRounds)
        record.firearm = firearm
        ctx.insert(record)
        for entry in firearm.logEntries where entry.servicedAt == nil {
            entry.servicedAt = Date()
        }
        try ctx.save()

        #expect(firearm.activeRounds == 0)
        #expect(firearm.serviceRecords.count == 1)
        #expect(firearm.serviceRecords.first?.roundsAtService == 300)
    }
}

// MARK: - Ammo Business Logic Tests

@Suite("Ammo Business Logic")
struct AmmoTests {

    @Test("Ammo quantity deduction does not go below zero")
    func ammoDeductNotBelowZero() {
        let ammo = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 30)
        let rounds = 50
        let deduction = min(rounds, ammo.quantity) // mirrors LogSession submit logic
        ammo.quantity -= deduction
        #expect(ammo.quantity >= 0)
        #expect(ammo.quantity == 0)
    }

    @Test("Ammo deduction with sufficient stock reduces correctly")
    func ammoDeductSufficientStock() {
        let ammo = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 100)
        let rounds = 50
        let deduction = min(rounds, ammo.quantity)
        ammo.quantity -= deduction
        #expect(ammo.quantity == 50)
    }

    @Test("isLowStock true when quantity at or below threshold")
    func lowStockFlag() {
        let ammo = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 50)
        ammo.lowStockThreshold = 50
        #expect(ammo.isLowStock == true)

        ammo.quantity = 51
        #expect(ammo.isLowStock == false)
    }

    @Test("isExplicitlyLinked reflects the compatibleFirearms list")
    @MainActor
    func explicitLinkReflectsList() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let f1 = Firearm(manufacturer: "Glock", model: "19")
        let f2 = Firearm(manufacturer: "SIG", model: "P365")
        let ammo = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 100)
        ammo.compatibleFirearms = [f1]
        ctx.insert(f1); ctx.insert(f2); ctx.insert(ammo)
        try ctx.save()

        #expect(ammo.isExplicitlyLinked(to: f1) == true)
        #expect(ammo.isExplicitlyLinked(to: f2) == false)
    }

    @Test("compatibleOptions: a firearm with links sees only its linked ammo")
    @MainActor
    func compatibleOptionsRestrictsWhenCurated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let glock = Firearm(manufacturer: "Glock", model: "19")
        let a1 = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 100)
        let a2 = AmmoEntry(caliber: ".45", brand: "Blazer", quantity: 100)
        a1.compatibleFirearms = [glock]
        ctx.insert(glock); ctx.insert(a1); ctx.insert(a2)
        try ctx.save()

        let options = AmmoEntry.compatibleOptions(for: glock, from: [a1, a2])
        #expect(options.map(\.id) == [a1.id])
    }

    @Test("compatibleOptions: a firearm with nothing linked falls back to all ammo")
    @MainActor
    func compatibleOptionsFallsBackWhenUncurated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let glock = Firearm(manufacturer: "Glock", model: "19")
        let sig = Firearm(manufacturer: "SIG", model: "P365")
        let a1 = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 100)
        let a2 = AmmoEntry(caliber: ".45", brand: "Blazer", quantity: 100)
        a1.compatibleFirearms = [sig] // curated, but not for `glock`
        ctx.insert(glock); ctx.insert(sig); ctx.insert(a1); ctx.insert(a2)
        try ctx.save()

        #expect(AmmoEntry.compatibleOptions(for: glock, from: [a1, a2]).count == 2)
        #expect(AmmoEntry.compatibleOptions(for: nil, from: [a1, a2]).count == 2)
    }

    @Test("displayLabel includes caliber, brand, grains, and type when present")
    func displayLabelFormatting() {
        let ammo = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 100)
        ammo.grains = 115
        ammo.ammoType = "FMJ"
        #expect(ammo.displayLabel.contains("9mm"))
        #expect(ammo.displayLabel.contains("Federal"))
        #expect(ammo.displayLabel.contains("115gr"))
        #expect(ammo.displayLabel.contains("FMJ"))
    }
}

// MARK: - RoundsFired Tests

@Suite("Rounds Fired Validation & Outlier Detection")
struct RoundsFiredTests {

    @Test("clamp caps at 99,999")
    func clampCapsAtMax() {
        #expect(RoundsFired.clamp("999999") == "99999")
        #expect(RoundsFired.clamp("100000") == "99999")
    }

    @Test("clamp truncates to 5 digits before parsing, so it can't overflow Int")
    func clampTruncatesBeforeParsing() {
        // A pasted 20-digit string would overflow Int(_:) if parsed whole;
        // clamp must truncate to 5 digits first so it still caps correctly.
        #expect(RoundsFired.clamp("99999999999999999999") == "99999")
    }

    @Test("clamp passes through valid values under the cap")
    func clampPassesThroughValidValues() {
        #expect(RoundsFired.clamp("50") == "50")
        #expect(RoundsFired.clamp("1") == "1")
        #expect(RoundsFired.clamp("0") == "0") // zero-rejection is a submit-time rule, not a clamp rule
    }

    @Test("isOutlier false with fewer than 3 baseline data points")
    func isOutlierRequiresMinimumHistory() {
        #expect(RoundsFired.isOutlier(rounds: 10000, comparedTo: []) == false)
        #expect(RoundsFired.isOutlier(rounds: 10000, comparedTo: [500, 500]) == false)
    }

    @Test("isOutlier true for a sudden huge value against a consistent history")
    func isOutlierDetectsSuddenSpike() {
        #expect(RoundsFired.isOutlier(rounds: 10000, comparedTo: [500, 500, 500]) == true)
    }

    @Test("isOutlier false for values in line with history")
    func isOutlierFalseForNormalValues() {
        #expect(RoundsFired.isOutlier(rounds: 550, comparedTo: [500, 500, 500]) == false)
        #expect(RoundsFired.isOutlier(rounds: 500, comparedTo: [400, 500, 600]) == false)
    }

    @Test("isOutlier false at exactly the 4x boundary, true just above it")
    func isOutlierBoundary() {
        // average of [500,500,500] is 500; 4x is 2000
        #expect(RoundsFired.isOutlier(rounds: 2000, comparedTo: [500, 500, 500]) == false)
        #expect(RoundsFired.isOutlier(rounds: 2001, comparedTo: [500, 500, 500]) == true)
    }
}

// MARK: - Accent Color Preference Tests

// .serialized: every test here reads/writes the same UserDefaults-backed
// preference (shared with the actual app, since unit tests run hosted
// inside it) — Swift Testing's default parallel execution would race those
// tests against each other and leak a stray value into the app's real
// defaults for whatever runs (or launches) next.
@Suite("User-selectable Accent Color", .serialized)
struct AccentColorPreferenceTests {

    /// Restores the "no custom color" state before and after each test, so
    /// tests don't leak preference state into each other or the app itself.
    init() { LgAccentPreference.userColor = nil }

    @Test("Defaults to the original lime accent when nothing has been chosen")
    func defaultsToOriginalLime() {
        #expect(LgAccentPreference.userColor == nil)
        #expect(LgAccentPreference.fill(dark: false).lgRGBHexValue == 0x4D9D00)
        #expect(LgAccentPreference.fill(dark: true).lgRGBHexValue == 0x7FD146)
        #expect(LgAccentPreference.text(dark: false).lgRGBHexValue == 0x207200)
    }

    @Test("A chosen color round-trips through persistence")
    func chosenColorRoundTrips() {
        defer { LgAccentPreference.userColor = nil }
        LgAccentPreference.userColor = Color(rgb: 0x2B6CE0) // an arbitrary blue
        #expect(LgAccentPreference.userColor?.lgRGBHexValue == 0x2B6CE0)
    }

    @Test("Derived fill/text bands follow the chosen hue, not the default green")
    func derivedBandsFollowChosenHue() {
        defer { LgAccentPreference.userColor = nil }
        LgAccentPreference.userColor = Color(rgb: 0x2B6CE0) // blue
        let fillHex = LgAccentPreference.fill(dark: false).lgRGBHexValue
        let textHex = LgAccentPreference.text(dark: false).lgRGBHexValue
        // No longer the stock green fallback.
        #expect(fillHex != 0x4D9D00)
        #expect(textHex != 0x207200)
        // The fitted text band is a darker version of the fitted fill band —
        // same relationship the original hand-picked green pair had.
        var fh: CGFloat = 0, fs: CGFloat = 0, fb: CGFloat = 0
        var th: CGFloat = 0, ts: CGFloat = 0, tb: CGFloat = 0
        var a: CGFloat = 0
        UIColor(LgAccentPreference.fill(dark: false)).getHue(&fh, saturation: &fs, brightness: &fb, alpha: &a)
        UIColor(LgAccentPreference.text(dark: false)).getHue(&th, saturation: &ts, brightness: &tb, alpha: &a)
        #expect(abs(fh - th) < 0.01) // same hue
        #expect(tb < fb) // text band is the darker one, in light mode
    }

    @Test("Clearing the preference restores the original lime exactly")
    func clearingRestoresDefault() {
        LgAccentPreference.userColor = Color(rgb: 0x2B6CE0)
        LgAccentPreference.userColor = nil
        #expect(LgAccentPreference.fill(dark: false).lgRGBHexValue == 0x4D9D00)
    }

    @Test("A near-gray pick still fits a legible, non-washed-out band")
    func nearGrayPickStaysLegible() {
        defer { LgAccentPreference.userColor = nil }
        // A *slightly* muted pick (not fully achromatic) still gets floored
        // to a legible saturation rather than fitting a washed-out band.
        LgAccentPreference.userColor = Color(rgb: 0xB08080) // dusty rose, s ≈ 0.27
        let mutedFillHex = LgAccentPreference.fill(dark: false).lgRGBHexValue
        var mh: CGFloat = 0, ms: CGFloat = 0, mb: CGFloat = 0, ma: CGFloat = 0
        UIColor(Color(rgb: mutedFillHex)).getHue(&mh, saturation: &ms, brightness: &mb, alpha: &ma)
        // The 0.35 floor, minus slack for 8-bit RGB round-trip quantization
        // (fill() -> Color -> persisted/read back as a 24-bit hex -> UIColor).
        #expect(ms >= 0.34)
    }

    @Test("A true gray pick (like the Dark Grey preset) stays gray, not tinted")
    func trueGrayPickStaysGray() {
        defer { LgAccentPreference.userColor = nil }
        LgAccentPreference.userColor = Color(rgb: 0x808080) // exactly R=G=B, saturation 0
        let fillHex = LgAccentPreference.fill(dark: false).lgRGBHexValue
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(rgb: fillHex)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Small slack for 8-bit RGB round-trip quantization — should stay
        // near-zero, not get floored/tinted like a deliberate pastel would.
        #expect(s < 0.05)
    }
}

// MARK: - Font Preference Tests

// .serialized for the same reason as AccentColorPreferenceTests: these all
// read/write the same UserDefaults-backed preference, shared with the real
// app process, and Swift Testing's default parallel execution would race them.
@Suite("User-selectable Font Family & Size", .serialized)
struct FontPreferenceTests {

    init() {
        LgFontPreference.family = .system
        LgFontPreference.sizeOption = .standard
    }

    @Test("Defaults to System family and Default (1x) size when nothing has been chosen")
    func defaultsToSystemAndStandard() {
        #expect(LgFontPreference.family == .system)
        #expect(LgFontPreference.family.postscriptName(for: .regular) == nil)
        #expect(LgFontPreference.sizeOption == .standard)
        #expect(LgFontPreference.resolvedSize(for: 16) == 16)
    }

    @Test("A chosen family round-trips through persistence")
    func chosenFamilyRoundTrips() {
        defer { LgFontPreference.family = .system }
        LgFontPreference.family = .rockwell
        #expect(LgFontPreference.family == .rockwell)
        #expect(LgFontPreference.family.postscriptName(for: .regular) == "Rockwell-Regular")
    }

    @Test("A chosen size round-trips through persistence and scales resolvedSize accordingly")
    func chosenSizeRoundTrips() {
        defer { LgFontPreference.sizeOption = .standard }
        LgFontPreference.sizeOption = .extraLarge
        #expect(LgFontPreference.sizeOption == .extraLarge)
        #expect(LgFontPreference.resolvedSize(for: 20) == 20 * LgFontSizeOption.extraLarge.scale)
    }

    @Test("resolvedSize applies the chosen size scale regardless of which family is active — no exceptions")
    func resolvedSizeAppliesScaleAcrossFamilies() {
        defer {
            LgFontPreference.family = .system
            LgFontPreference.sizeOption = .standard
        }
        LgFontPreference.family = .copperplate
        LgFontPreference.sizeOption = .large
        #expect(LgFontPreference.resolvedSize(for: 20) == 20 * LgFontSizeOption.large.scale)
        #expect(LgFontPreference.family == .copperplate)
    }

    @Test("All 4 family options produce distinct fonts, and all 4 size options are distinct")
    func allOptionsAreDistinct() {
        let regularFaces = LgFontFamily.allCases.map { $0.postscriptName(for: .regular) ?? "system" }
        #expect(Set(regularFaces).count == LgFontFamily.allCases.count)
        #expect(Set(LgFontSizeOption.allCases.map(\.scale)).count == LgFontSizeOption.allCases.count)
    }

    @Test("Named fonts map each weight to the correct static face")
    func namedFontWeightMapping() {
        #expect(LgFontFamily.system.postscriptName(for: .bold) == nil)
        #expect(LgFontFamily.impact.postscriptName(for: .regular) == "Impact")
        #expect(LgFontFamily.impact.postscriptName(for: .bold) == "Impact")
        #expect(LgFontFamily.rockwell.postscriptName(for: .regular) == "Rockwell-Regular")
        #expect(LgFontFamily.rockwell.postscriptName(for: .bold) == "Rockwell-Bold")
        #expect(LgFontFamily.rockwell.postscriptName(for: .heavy) == "Rockwell-Bold")
        #expect(LgFontFamily.copperplate.postscriptName(for: .regular) == "Copperplate")
        #expect(LgFontFamily.copperplate.postscriptName(for: .light) == "Copperplate-Light")
        #expect(LgFontFamily.copperplate.postscriptName(for: .bold) == "Copperplate-Bold")
    }
}
