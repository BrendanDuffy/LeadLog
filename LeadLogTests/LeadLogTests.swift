//  LeadLogTests.swift

import Testing
import SwiftData
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

    @Test("Ammo with empty compatibleFirearms is compatible with any firearm")
    @MainActor
    func ammoCompatibilityUniversal() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let firearm = Firearm(manufacturer: "Glock", model: "19")
        let ammo = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 100)
        ctx.insert(firearm); ctx.insert(ammo)
        try ctx.save()

        #expect(ammo.isCompatible(with: firearm) == true)
    }

    @Test("Ammo with compatibleFirearms restricts to listed firearms only")
    @MainActor
    func ammoCompatibilityRestricted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let f1 = Firearm(manufacturer: "Glock", model: "19")
        let f2 = Firearm(manufacturer: "SIG", model: "P365")
        let ammo = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 100)
        ammo.compatibleFirearms = [f1]
        ctx.insert(f1); ctx.insert(f2); ctx.insert(ammo)
        try ctx.save()

        #expect(ammo.isCompatible(with: f1) == true)
        #expect(ammo.isCompatible(with: f2) == false)
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

// MARK: - SessionSummary Tests

@Suite("SessionSummary Logic")
struct SessionSummaryTests {

    @Test("hasPhotos true when at least one entry has a photoPath")
    func hasPhotosDetected() {
        let e1 = LogEntry(sessionId: "s1", date: Date(), rounds: 50)
        let e2 = LogEntry(sessionId: "s1", date: Date(), rounds: 30)
        e2.photoPath = "/some/path.jpg"

        let session = SessionSummary(id: "s1", date: Date(), entries: [e1, e2])
        #expect(session.hasPhotos == true)
    }

    @Test("hasPhotos false when no entries have photos")
    func hasPhotosAbsent() {
        let e1 = LogEntry(sessionId: "s1", date: Date(), rounds: 50)
        let session = SessionSummary(id: "s1", date: Date(), entries: [e1])
        #expect(session.hasPhotos == false)
    }

    @Test("totalRounds sums all entries")
    func totalRoundsSums() {
        let e1 = LogEntry(sessionId: "s1", date: Date(), rounds: 50)
        let e2 = LogEntry(sessionId: "s1", date: Date(), rounds: 75)
        let session = SessionSummary(id: "s1", date: Date(), entries: [e1, e2])
        #expect(session.totalRounds == 125)
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
