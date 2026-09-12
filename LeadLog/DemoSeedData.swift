#if DEBUG
import SwiftData
import Foundation

/// One-time sample-data seeder used to prep clean, realistic data for App
/// Store screenshots. Never runs on a normal launch — only when
/// `-SeedAppStoreScreenshotData` is passed as a launch argument (same
/// convention as `-UITestForcePhoto`). When triggered, it wipes any existing
/// Firearm/AmmoEntry/LogEntry/ServiceRecord records and replaces them with a
/// curated dataset: 3 firearms in each of the 4 core categories, ammo sized
/// to match, and ~3 months of History spread across several range trips —
/// chosen to be recognizable to a new marksman rather than exotic.
///
/// The whole file is `#if DEBUG`-gated (not just the call site) since it has
/// no purpose in a Release build — App Store submissions are always compiled
/// Release, so this type doesn't exist at all in what gets submitted.
enum DemoSeedData {
    static func seedIfRequested(in container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("-SeedAppStoreScreenshotData") else { return }
        let context = ModelContext(container)
        wipeExisting(in: context)
        seed(in: context)
    }

    private static func wipeExisting(in context: ModelContext) {
        (try? context.fetch(FetchDescriptor<LogEntry>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<ServiceRecord>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<Firearm>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<AmmoEntry>()))?.forEach { context.delete($0) }
        try? context.save()
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func seed(in context: ModelContext) {
        // MARK: - Firearms (3 per core category, recognizable brands/models)

        let glock19 = Firearm(manufacturer: "Glock", model: "19 Gen 5", serialNumber: "BRQD421", roundsBeforeService: 500, category: .pistol, notes: "Everyday carry.")
        let mp9 = Firearm(manufacturer: "Smith & Wesson", model: "M&P9 2.0", serialNumber: "MPX88213", roundsBeforeService: 500, category: .pistol, notes: "Range gun, backup carry.")
        let p320 = Firearm(manufacturer: "Sig Sauer", model: "P320 Compact", serialNumber: "58412290", roundsBeforeService: 500, category: .pistol)

        let sw686 = Firearm(manufacturer: "Smith & Wesson", model: "686 Plus", serialNumber: "AXY0091", roundsBeforeService: 500, category: .revolver, notes: "Weekend range trips.")
        let rugerLCR = Firearm(manufacturer: "Ruger", model: "LCR", serialNumber: "548-77120", roundsBeforeService: 500, category: .revolver, notes: "Retired from the carry rotation.")
        rugerLCR.isRetired = true
        let taurusJudge = Firearm(manufacturer: "Taurus", model: "Judge", serialNumber: "JD002214", roundsBeforeService: 500, category: .revolver)

        let ruger1022 = Firearm(manufacturer: "Ruger", model: "10/22", serialNumber: "225-61190", roundsBeforeService: 1000, category: .rifle, notes: "First rifle — plinking and teaching new shooters.")
        let ddm4v7 = Firearm(manufacturer: "Daniel Defense", model: "DDM4 V7", serialNumber: "DD3120056", roundsBeforeService: 500, category: .rifle, notes: "Home defense / range.")
        let rem700 = Firearm(manufacturer: "Remington", model: "700 SPS", serialNumber: "70091124", roundsBeforeService: 200, category: .rifle, notes: "Deer season.")

        let mossberg500 = Firearm(manufacturer: "Mossberg", model: "500", serialNumber: "M50-88421", roundsBeforeService: 500, category: .shotgun, notes: "Home defense.")
        let rem870 = Firearm(manufacturer: "Remington", model: "870 Express", serialNumber: "87X-44290", roundsBeforeService: 500, category: .shotgun, notes: "Sporting clays.")
        let benelliM2 = Firearm(manufacturer: "Benelli", model: "M2", serialNumber: "BM2-77341", roundsBeforeService: 500, category: .shotgun)

        let firearms = [glock19, mp9, p320, sw686, rugerLCR, taurusJudge, ruger1022, ddm4v7, rem700, mossberg500, rem870, benelliM2]
        firearms.forEach { context.insert($0) }

        // MARK: - Ammo (sized to match the firearms above)

        let ammo9mm = AmmoEntry(caliber: "9mm", brand: "Federal", quantity: 350)
        ammo9mm.grains = 115; ammo9mm.ammoType = "FMJ"; ammo9mm.category = .pistol

        let ammo357 = AmmoEntry(caliber: ".357 Magnum", brand: "Federal", quantity: 120)
        ammo357.grains = 158; ammo357.ammoType = "JHP"; ammo357.category = .revolver

        let ammo38 = AmmoEntry(caliber: ".38 Special", brand: "Winchester", quantity: 150)
        ammo38.grains = 130; ammo38.ammoType = "FMJ"; ammo38.category = .revolver

        // Deliberately low stock (below the default 20-round threshold) to
        // show off the low-stock indicator in screenshots.
        let ammo45colt = AmmoEntry(caliber: ".45 Colt", brand: "Federal", quantity: 15)
        ammo45colt.grains = 225; ammo45colt.ammoType = "LSWC"; ammo45colt.category = .revolver

        let ammo22 = AmmoEntry(caliber: ".22 LR", brand: "CCI", quantity: 500)
        ammo22.grains = 40; ammo22.ammoType = "HP"; ammo22.category = .rifle

        let ammo556 = AmmoEntry(caliber: "5.56 NATO", brand: "Federal", quantity: 200)
        ammo556.grains = 55; ammo556.ammoType = "FMJ"; ammo556.category = .rifle

        let ammo308 = AmmoEntry(caliber: ".308 Winchester", brand: "Hornady", quantity: 60)
        ammo308.grains = 150; ammo308.ammoType = "SP"; ammo308.category = .rifle

        let ammo12gaBuck = AmmoEntry(caliber: "12 Gauge", brand: "Federal", quantity: 100)
        ammo12gaBuck.ammoType = "00 Buck"; ammo12gaBuck.category = .shotgun

        let ammo12gaTarget = AmmoEntry(caliber: "12 Gauge", brand: "Winchester", quantity: 250)
        ammo12gaTarget.ammoType = "Target Load"; ammo12gaTarget.category = .shotgun

        let ammoEntries = [ammo9mm, ammo357, ammo38, ammo45colt, ammo22, ammo556, ammo308, ammo12gaBuck, ammo12gaTarget]
        ammoEntries.forEach { context.insert($0) }

        // Compatibility + primary ammo, mirroring how a real user links things.
        ammo9mm.compatibleFirearms = [glock19, mp9, p320]
        glock19.primaryAmmo = ammo9mm; mp9.primaryAmmo = ammo9mm; p320.primaryAmmo = ammo9mm

        ammo357.compatibleFirearms = [sw686]
        sw686.primaryAmmo = ammo357

        ammo38.compatibleFirearms = [rugerLCR]
        rugerLCR.primaryAmmo = ammo38

        ammo45colt.compatibleFirearms = [taurusJudge]
        taurusJudge.primaryAmmo = ammo45colt

        ammo22.compatibleFirearms = [ruger1022]
        ruger1022.primaryAmmo = ammo22

        ammo556.compatibleFirearms = [ddm4v7]
        ddm4v7.primaryAmmo = ammo556

        ammo308.compatibleFirearms = [rem700]
        rem700.primaryAmmo = ammo308

        ammo12gaBuck.compatibleFirearms = [mossberg500, rem870, benelliM2]
        ammo12gaTarget.compatibleFirearms = [rem870, benelliM2, mossberg500]
        mossberg500.primaryAmmo = ammo12gaBuck
        rem870.primaryAmmo = ammo12gaTarget
        benelliM2.primaryAmmo = ammo12gaTarget

        // MARK: - History — ~3 months of range trips, spread across several days per month

        @discardableResult
        func logEntry(_ firearm: Firearm, _ ammo: AmmoEntry, _ d: Date, _ rounds: Int, sessionId: String, notes: String? = nil) -> LogEntry {
            let entry = LogEntry(sessionId: sessionId, date: d, rounds: rounds)
            entry.firearm = firearm
            entry.firearmNameSnapshot = firearm.displayName
            entry.ammo = ammo
            entry.ammoSnapshot = ammo.displayLabel
            entry.notes = notes
            context.insert(entry)
            return entry
        }
        func soloSession(_ d: Date) -> String { "seed-\(d.timeIntervalSince1970)" }

        // June
        let preServiceEntry = logEntry(ruger1022, ammo22, date(2026, 6, 15), 250, sessionId: soloSession(date(2026, 6, 15)), notes: "Teaching my nephew the basics.")
        logEntry(glock19, ammo9mm, date(2026, 6, 20), 100, sessionId: soloSession(date(2026, 6, 20)), notes: "Trigger control drills.")
        logEntry(mossberg500, ammo12gaBuck, date(2026, 6, 22), 75, sessionId: soloSession(date(2026, 6, 22)))
        logEntry(rugerLCR, ammo38, date(2026, 6, 25), 25, sessionId: soloSession(date(2026, 6, 25)))

        // Service the 10/22 on July 3rd, covering everything logged before it —
        // mirrors exactly what InventoryView's own "Mark as Serviced" does.
        let service1022 = ServiceRecord(servicedAt: date(2026, 7, 3), roundsAtService: 250, note: "Routine cleaning and inspection.")
        service1022.firearm = ruger1022
        context.insert(service1022)
        preServiceEntry.servicedAt = date(2026, 7, 3)
        preServiceEntry.servicedBy = service1022

        // July
        let julyRangeDay = soloSession(date(2026, 7, 5))
        logEntry(glock19, ammo9mm, date(2026, 7, 5), 80, sessionId: julyRangeDay, notes: "Range day with a buddy.")
        logEntry(mp9, ammo9mm, date(2026, 7, 5), 75, sessionId: julyRangeDay)
        logEntry(ddm4v7, ammo556, date(2026, 7, 8), 100, sessionId: soloSession(date(2026, 7, 8)), notes: "Zeroed at 100 yards.")
        logEntry(rugerLCR, ammo38, date(2026, 7, 15), 25, sessionId: soloSession(date(2026, 7, 15)))
        logEntry(sw686, ammo357, date(2026, 7, 18), 30, sessionId: soloSession(date(2026, 7, 18)))
        logEntry(ruger1022, ammo22, date(2026, 7, 20), 100, sessionId: soloSession(date(2026, 7, 20)))
        logEntry(glock19, ammo9mm, date(2026, 7, 25), 90, sessionId: soloSession(date(2026, 7, 25)), notes: "Failure-to-stop drills.")
        logEntry(rem870, ammo12gaTarget, date(2026, 7, 28), 50, sessionId: soloSession(date(2026, 7, 28)), notes: "Sporting clays league.")

        // August
        logEntry(mossberg500, ammo12gaBuck, date(2026, 8, 3), 75, sessionId: soloSession(date(2026, 8, 3)))
        logEntry(ruger1022, ammo22, date(2026, 8, 5), 100, sessionId: soloSession(date(2026, 8, 5)), notes: "Fun day at the range with the kids.")
        logEntry(taurusJudge, ammo45colt, date(2026, 8, 10), 30, sessionId: soloSession(date(2026, 8, 10)))
        let augQualDay = soloSession(date(2026, 8, 15))
        logEntry(glock19, ammo9mm, date(2026, 8, 15), 150, sessionId: augQualDay, notes: "Qualification day.")
        logEntry(p320, ammo9mm, date(2026, 8, 15), 80, sessionId: augQualDay)
        logEntry(benelliM2, ammo12gaTarget, date(2026, 8, 18), 60, sessionId: soloSession(date(2026, 8, 18)))
        logEntry(mp9, ammo9mm, date(2026, 8, 20), 75, sessionId: soloSession(date(2026, 8, 20)))
        logEntry(ddm4v7, ammo556, date(2026, 8, 22), 100, sessionId: soloSession(date(2026, 8, 22)), notes: "Practicing transitions.")
        logEntry(ruger1022, ammo22, date(2026, 8, 30), 100, sessionId: soloSession(date(2026, 8, 30)))

        // September
        logEntry(sw686, ammo357, date(2026, 9, 1), 30, sessionId: soloSession(date(2026, 9, 1)))
        logEntry(rem870, ammo12gaTarget, date(2026, 9, 2), 40, sessionId: soloSession(date(2026, 9, 2)))
        logEntry(rem700, ammo308, date(2026, 9, 8), 40, sessionId: soloSession(date(2026, 9, 8)), notes: "Sighted in for hunting season.")

        try? context.save()
    }
}
#endif
