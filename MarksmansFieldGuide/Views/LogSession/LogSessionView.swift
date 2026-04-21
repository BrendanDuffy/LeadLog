import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Session Row State

/// Holds the in-progress form state for a single firearm entry within a session.
struct SessionRowState: Identifiable {
    let id = UUID()
    var firearm: Firearm? = nil
    var roundsText: String = ""
    var notes: String = ""
    var ammo: AmmoEntry? = nil
    var photoPath: String? = nil
    var selectedPhotoItem: PhotosPickerItem? = nil

    var rounds: Int? {
        let n = Int(roundsText)
        return (n != nil && n! > 0) ? n : nil
    }
}

// MARK: - LogSessionView

struct LogSessionView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Firearm> { $0.isRetired == false }, sort: \.manufacturer)
    private var activeFirearms: [Firearm]

    @Query(sort: \AmmoEntry.brand)
    private var allAmmo: [AmmoEntry]

    init() {}

    @State private var sessionDate = Date()
    @State private var rows: [SessionRowState] = [SessionRowState()]
    @State private var isSubmitting = false
    @State private var showDatePicker = false
    @State private var toast: ToastConfig? = nil

    var body: some View {
        ZStack(alignment: .top) {
            W.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                WesternHeader(title: "Log Session")
                GoldDivider()

                ScrollView {
                    VStack(spacing: 12) {
                        // ── Date Selector ──────────────────────────────────
                        ParchmentField(
                            label: "Date",
                            value: sessionDate.formatted(date: .long, time: .omitted),
                            iconType: .calendar
                        ) {
                            showDatePicker = true
                        }

                        // ── Firearm Rows ───────────────────────────────────
                        ForEach($rows) { $row in
                            let index = rows.firstIndex(where: { $0.id == row.id }) ?? 0
                            SessionRowCard(
                                row: $row,
                                index: index,
                                canRemove: rows.count > 1,
                                activeFirearms: activeFirearms,
                                allAmmo: allAmmo,
                                onRemove: { removeRow(id: row.id) }
                            )
                        }

                        // ── Add Another Firearm ────────────────────────────
                        Button {
                            haptic(.light)
                            rows.append(SessionRowState())
                        } label: {
                            WesternButtonLabel(text: "+ ADD ANOTHER FIREARM")
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                                )
                                .foregroundStyle(W.brass)
                        )

                        // ── Submit Button ──────────────────────────────────
                        Button {
                            Task { await submit() }
                        } label: {
                            ZStack {
                                Image("btn-log-session")
                                    .resizable()
                                    .scaledToFill()
                                if isSubmitting {
                                    ProgressView().tint(W.textDark)
                                } else {
                                    Text("LOG SESSION")
                                        .font(.rye(20))
                                        .tracking(2)
                                        .foregroundStyle(Color(rgb: 0x1A0E00))
                                        .shadow(color: Color(rgb: 0xFFEBB4).opacity(0.6), radius: 1, y: 1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isSubmitting || activeFirearms.isEmpty)
                        .opacity((isSubmitting || activeFirearms.isEmpty) ? 0.5 : 1.0)

                        Spacer().frame(height: 40)
                    }
                    .padding(16)
                }
                .background(
                    Image("texture-leather")
                        .resizable()
                        .scaledToFill()
                        .opacity(0.35)
                        .clipped()
                )
            }

            // ── Toast Overlay ──────────────────────────────────────────────
            if let config = toast {
                WesternToastView(config: config) {
                    withAnimation { toast = nil }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(date: $sessionDate)
        }
        .animation(.spring(duration: 0.3), value: toast?.id)
    }

    // MARK: - Actions

    private func removeRow(id: UUID) {
        haptic(.light)
        rows.removeAll { $0.id == id }
    }

    private func submit() async {
        // Validation
        for row in rows {
            if row.firearm == nil {
                showToast("Please select a firearm for each entry.", type: .error)
                haptic(.error)
                return
            }
            if row.rounds == nil {
                showToast("Please enter a valid number of rounds (greater than 0).", type: .error)
                haptic(.error)
                return
            }
        }

        // Duplicate firearm check
        let firearmIds = rows.compactMap { $0.firearm?.id }
        if Set(firearmIds).count != firearmIds.count {
            showToast("You've selected the same firearm more than once. Combine rounds into one entry.", type: .error)
            haptic(.error)
            return
        }

        isSubmitting = true
        haptic(.medium)

        let sessionId = "session-\(Date().timeIntervalSince1970)"
        var overLimitNames: [String] = []

        for row in rows {
            guard let firearm = row.firearm, let rounds = row.rounds else { continue }

            let entry = LogEntry(sessionId: sessionId, date: sessionDate, rounds: rounds)
            entry.firearm = firearm
            entry.firearmNameSnapshot = firearm.displayName
            entry.notes = row.notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : row.notes
            entry.photoPath = row.photoPath

            if let ammo = row.ammo {
                entry.ammo = ammo
                entry.ammoSnapshot = ammo.displayLabel
                ammo.quantity = max(0, ammo.quantity - rounds)
            }

            modelContext.insert(entry)

            // Check service limit after adding rounds
            if firearm.isOverLimit {
                overLimitNames.append(firearm.displayName)
            }
        }

        try? modelContext.save()

        isSubmitting = false
        haptic(.success)

        // Reset form
        sessionDate = Date()
        rows = [SessionRowState()]

        if overLimitNames.isEmpty {
            showToast("Session logged successfully.", type: .success)
        } else {
            let names = overLimitNames.joined(separator: ", ")
            showToast("Session logged. Service due for: \(names)", type: .info)
        }
    }

    private func showToast(_ message: String, type: ToastConfig.ToastType) {
        withAnimation {
            toast = ToastConfig(
                title: type == .success ? "Fine shooting, Marksman!" : "Hold up, Pardner.",
                message: message,
                type: type
            )
        }
    }
}

// MARK: - Session Row Card

struct SessionRowCard: View {
    @Binding var row: SessionRowState
    let index: Int
    let canRemove: Bool
    let activeFirearms: [Firearm]
    let allAmmo: [AmmoEntry]
    let onRemove: () -> Void

    @State private var showFirearmPicker = false
    @State private var showAmmoPicker = false

    var compatibleAmmo: [AmmoEntry] {
        guard let firearm = row.firearm else { return allAmmo }
        return allAmmo.filter { $0.isCompatible(with: firearm) }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                // ── Remove Button (only when multiple rows) ────────────
                if canRemove {
                    HStack {
                        Spacer()
                        Button("✕ Remove") {
                            haptic(.light)
                            onRemove()
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(W.error)
                    }
                }

                // ── Select Firearm ─────────────────────────────────────
                ParchmentField(
                    label: "Select Firearm",
                    value: row.firearm.map { "\($0.manufacturer) \($0.model)" } ?? "Tap to select",
                    iconType: .chevronDown
                ) {
                    showFirearmPicker = true
                }

                // ── Rounds Fired ───────────────────────────────────────
                ParchmentInputField(
                    label: "Rounds Fired",
                    text: $row.roundsText,
                    placeholder: "e.g. 50",
                    keyboardType: .numberPad
                )
                .onChange(of: row.roundsText) { _, new in
                    // Strip non-digits and cap at 99999
                    let digits = new.filter { $0.isNumber }
                    let capped = Int(digits).map { min($0, 99999) }.map { String($0) } ?? digits
                    if capped != new { row.roundsText = capped }
                }

                // ── Ammo Used (only shown if compatible ammo exists) ───
                if !compatibleAmmo.isEmpty {
                    ParchmentField(
                        label: "Ammo Used",
                        value: row.ammo.map { "\($0.caliber) — \($0.brand)" } ?? "Tap to select",
                        iconType: .ammo
                    ) {
                        showAmmoPicker = true
                    }
                }

                // ── Notes ──────────────────────────────────────────────
                ParchmentInputField(
                    label: "Notes",
                    text: $row.notes,
                    placeholder: "Optional session notes",
                    isMultiline: true,
                    maxLength: 120
                )

                // ── Target Photo ───────────────────────────────────────
                PhotoSection(row: $row)
            }
            .padding(.top, 28)
            .padding(.bottom, 32)
            .padding(.horizontal, 24)
        }
        .background(
            Image("card-leather-v2")
                .resizable()
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showFirearmPicker) {
            FirearmPickerSheet(
                firearms: activeFirearms,
                selected: row.firearm,
                onSelect: { firearm in
                    row.firearm = firearm
                    // Clear ammo if it's no longer compatible with the new firearm
                    if let ammo = row.ammo, !ammo.isCompatible(with: firearm) {
                        row.ammo = nil
                    }
                }
            )
        }
        .sheet(isPresented: $showAmmoPicker) {
            AmmoPickerSheet(
                ammoEntries: compatibleAmmo,
                selected: row.ammo,
                onSelect: { row.ammo = $0 }
            )
        }
    }
}

// MARK: - Photo Section

struct PhotoSection: View {
    @Binding var row: SessionRowState

    var body: some View {
        if let path = row.photoPath, let image = ImageStorage.load(path: path) {
            VStack(spacing: 8) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    haptic(.light)
                    if let p = row.photoPath { ImageStorage.delete(path: p) }
                    row.photoPath = nil
                    row.selectedPhotoItem = nil
                } label: {
                    Text("✕ Remove Photo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(W.error)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        } else {
            PhotosPicker(selection: $row.selectedPhotoItem, matching: .images) {
                Button {} label: {
                    HStack(spacing: 8) {
                        Image("icon-vintage-camera")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("ATTACH TARGET PHOTO")
                            .font(.rye(13))
                            .tracking(1.2)
                            .foregroundStyle(Color(rgb: 0xD4D4D8))
                            .shadow(color: .black, radius: 1, y: 1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                            .foregroundStyle(Color(rgb: 0xD4D4D8))
                    )
                }
                .buttonStyle(.plain)
            }
            .onChange(of: row.selectedPhotoItem) { _, newItem in
                Task {
                    guard let item = newItem,
                          let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    row.photoPath = ImageStorage.save(image, named: UUID().uuidString)
                }
            }
        }
    }
}

// MARK: - Firearm Picker Sheet

struct FirearmPickerSheet: View {
    let firearms: [Firearm]
    let selected: Firearm?
    let onSelect: (Firearm) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                W.leather
                Text("Select Firearm")
                    .font(.rye(20)).foregroundStyle(W.brass)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                HStack {
                    Spacer()
                    Button("Cancel") { haptic(.light); dismiss() }
                        .font(.rye(14)).foregroundStyle(W.muted)
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 56)

            GoldDivider()

            if firearms.isEmpty {
                Text("No firearms in inventory.\nAdd a firearm in the Inventory tab first.")
                    .font(.playfairRegular(15))
                    .foregroundStyle(W.muted)
                    .multilineTextAlignment(.center)
                    .padding(24)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(firearms, id: \.id) { firearm in
                            Button {
                                haptic(.light); onSelect(firearm); dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(firearm.displayName)
                                            .font(.playfairBold(16))
                                            .foregroundStyle(selected?.id == firearm.id ? W.brass : W.text)
                                        if let caliber = firearm.caliber {
                                            Text(caliber).font(.playfairRegular(13)).foregroundStyle(W.muted)
                                        }
                                    }
                                    Spacer()
                                    if selected?.id == firearm.id {
                                        Text("✓").font(.system(size: 18, weight: .bold)).foregroundStyle(W.brass)
                                    }
                                }
                                .padding(.vertical, 14).padding(.horizontal, 20)
                                .background(selected?.id == firearm.id ? W.brass.opacity(0.12) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(W.brass.opacity(0.2))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("card-leather-v2").resizable().scaledToFill().ignoresSafeArea()
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Ammo Picker Sheet

struct AmmoPickerSheet: View {
    let ammoEntries: [AmmoEntry]
    let selected: AmmoEntry?
    let onSelect: (AmmoEntry?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                W.leather
                Text("Select Ammo")
                    .font(.rye(20)).foregroundStyle(W.brass)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                HStack {
                    Spacer()
                    Button("Cancel") { haptic(.light); dismiss() }
                        .font(.rye(14)).foregroundStyle(W.muted)
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 56)

            GoldDivider()

            ScrollView {
                VStack(spacing: 0) {
                    Button {
                        haptic(.light); onSelect(nil); dismiss()
                    } label: {
                        HStack {
                            Text("None").font(.playfairBold(16))
                                .foregroundStyle(selected == nil ? W.brass : W.text)
                            Spacer()
                            if selected == nil {
                                Text("✓").font(.system(size: 18, weight: .bold)).foregroundStyle(W.brass)
                            }
                        }
                        .padding(.vertical, 14).padding(.horizontal, 20)
                        .background(selected == nil ? W.brass.opacity(0.12) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(W.brass.opacity(0.2))

                    ForEach(ammoEntries, id: \.id) { ammo in
                        Button {
                            haptic(.light); onSelect(ammo); dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ammo.brand).font(.playfairBold(16))
                                        .foregroundStyle(selected?.id == ammo.id ? W.brass : W.text)
                                    Text(ammo.displayLabel).font(.playfairRegular(13)).foregroundStyle(W.muted)
                                }
                                Spacer()
                                if selected?.id == ammo.id {
                                    Text("✓").font(.system(size: 18, weight: .bold)).foregroundStyle(W.brass)
                                }
                            }
                            .padding(.vertical, 14).padding(.horizontal, 20)
                            .background(selected?.id == ammo.id ? W.brass.opacity(0.12) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(W.brass.opacity(0.2))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("card-leather-v2").resizable().scaledToFill().ignoresSafeArea()
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Date Picker Sheet

struct DatePickerSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                W.leather
                Text("Select Date")
                    .font(.rye(20)).foregroundStyle(W.brass)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            }
            .frame(height: 56)

            GoldDivider()

            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(W.brass)
                .colorScheme(.dark)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Button {
                haptic(.light); dismiss()
            } label: {
                Text("Confirm Date")
                    .font(.playfairBold(17))
                    .foregroundStyle(W.textDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(W.brass)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("card-leather-v2").resizable().scaledToFill().ignoresSafeArea()
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
