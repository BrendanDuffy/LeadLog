import SwiftData
import Foundation

// MARK: - Rounds validation & outlier detection

enum RoundsFired {
    static let maxValue = 99_999

    /// Clamps free-typed digits to a positive whole number, capped at maxValue.
    /// Callers are expected to have already stripped non-digit characters.
    static func clamp(_ digits: String) -> String {
        guard !digits.isEmpty else { return digits }
        if let n = Int(digits) {
            return String(min(n, maxValue))
        }
        // Int(_:) overflowed — the digit string is far longer than maxValue
        // could ever be, so it's definitely over the cap.
        return String(maxValue)
    }

    /// True when `rounds` is way out of line with `baseline` (e.g. a sudden
    /// 10,000 in a history of 500s) — needs at least 3 data points before it'll
    /// flag anything, so a firearm's first couple of sessions never trigger it.
    static func isOutlier(rounds: Int, comparedTo baseline: [Int]) -> Bool {
        guard baseline.count >= 3 else { return false }
        let average = Double(baseline.reduce(0, +)) / Double(baseline.count)
        guard average > 0 else { return false }
        return Double(rounds) > average * 4
    }
}

// MARK: - FirearmCategory

/// Classifies a firearm by type, and an ammo entry by which firearm type it's for.
enum FirearmCategory: String, Codable, CaseIterable, Identifiable {
    case pistol = "Pistol"
    case revolver = "Revolver"
    case rifle = "Rifle"
    case shotgun = "Shotgun"
    case other = "Other"

    var id: String { rawValue }
}

// MARK: - Firearm

@Model
final class Firearm {
    @Attribute(.unique) var id: String
    var manufacturer: String
    var model: String
    var serialNumber: String?
    var roundsBeforeService: Int
    var photoPath: String?
    var isRetired: Bool
    var retiredAt: Date?
    var soundCategory: String?
    var category: FirearmCategory?
    var notes: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \LogEntry.firearm)
    var logEntries: [LogEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.firearm)
    var serviceRecords: [ServiceRecord] = []

    // Many-to-many inverse: declared on AmmoEntry side
    @Relationship(inverse: \AmmoEntry.compatibleFirearms)
    var compatibleAmmo: [AmmoEntry] = []

    /// Primary ammo linked to this firearm
    @Relationship var primaryAmmo: AmmoEntry?

    init(
        manufacturer: String,
        model: String,
        serialNumber: String? = nil,
        roundsBeforeService: Int = 500,
        soundCategory: String? = nil,
        category: FirearmCategory? = nil,
        notes: String? = nil
    ) {
        self.id = UUID().uuidString
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.roundsBeforeService = roundsBeforeService
        self.soundCategory = soundCategory
        self.category = category
        self.notes = notes
        self.isRetired = false
        self.createdAt = Date()
    }

    var displayName: String { "\(manufacturer) \(model)" }

    /// Total rounds fired since last service (entries with no servicedAt date)
    var activeRounds: Int {
        logEntries.filter { $0.servicedAt == nil }.reduce(0) { $0 + $1.rounds }
    }

    var progressPercent: Double {
        guard roundsBeforeService > 0 else { return 0 }
        return min(Double(activeRounds) / Double(roundsBeforeService) * 100.0, 100.0)
    }

    var isOverLimit: Bool {
        roundsBeforeService > 0 && activeRounds >= roundsBeforeService
    }

    var isNearLimit: Bool {
        !isOverLimit && progressPercent >= 80
    }
}

// MARK: - LogEntry

/// A single firearm's log within a session.
/// Multiple entries share the same sessionId when logging multiple firearms at once.
@Model
final class LogEntry {
    @Attribute(.unique) var id: String
    /// Groups all entries logged together in one session
    var sessionId: String
    var date: Date
    var rounds: Int
    var notes: String?
    var photoPath: String?
    var tags: [String]
    /// Snapshot of the firearm name at log time (preserved if firearm is deleted)
    var firearmNameSnapshot: String?
    /// Snapshot of the ammo label at log time (e.g. "Federal 9mm 115gr FMJ")
    var ammoSnapshot: String?
    /// Set when this entry's rounds are marked as serviced
    var servicedAt: Date?
    var createdAt: Date

    var firearm: Firearm?
    var ammo: AmmoEntry?

    init(sessionId: String, date: Date, rounds: Int) {
        self.id = UUID().uuidString
        self.sessionId = sessionId
        self.date = date
        self.rounds = rounds
        self.tags = []
        self.createdAt = Date()
    }
}

// MARK: - AmmoEntry

@Model
final class AmmoEntry {
    @Attribute(.unique) var id: String
    var caliber: String
    var brand: String
    var grains: Int?
    var ammoType: String?
    var quantity: Int
    var lowStockThreshold: Int
    var photoPath: String?
    var createdAt: Date
    /// Which firearm category this ammo is typically used in.
    var category: FirearmCategory?

    /// Firearms this ammo is compatible with (many-to-many)
    var compatibleFirearms: [Firearm] = []

    init(caliber: String, brand: String, quantity: Int) {
        self.id = UUID().uuidString
        self.caliber = caliber
        self.brand = brand
        self.quantity = quantity
        self.lowStockThreshold = 20
        self.createdAt = Date()
    }

    var isLowStock: Bool { quantity <= lowStockThreshold }

    var displayLabel: String {
        var parts = [caliber, brand]
        if let g = grains { parts.append("\(g)gr") }
        if let t = ammoType { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    /// Returns true if this ammo is compatible with the given firearm,
    /// or has no restrictions (empty list = universal)
    func isCompatible(with firearm: Firearm) -> Bool {
        compatibleFirearms.isEmpty || compatibleFirearms.contains(where: { $0.id == firearm.id })
    }
}

// MARK: - ServiceRecord

@Model
final class ServiceRecord {
    @Attribute(.unique) var id: String
    var servicedAt: Date
    var roundsAtService: Int
    var note: String?

    var firearm: Firearm?

    init(servicedAt: Date = Date(), roundsAtService: Int, note: String? = nil) {
        self.id = UUID().uuidString
        self.servicedAt = servicedAt
        self.roundsAtService = roundsAtService
        self.note = note
    }
}
