import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Session Row State

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
    @EnvironmentObject private var router: AppRouter

    @Query(filter: #Predicate<Firearm> { $0.isRetired == false }, sort: \.manufacturer)
    private var activeFirearms: [Firearm]

    @Query(sort: \AmmoEntry.brand)
    private var allAmmo: [AmmoEntry]

    init() {}

    @State private var sessionDate = Date()
    @State private var rows: [SessionRowState] = [SessionRowState()]
    @State private var isSubmitting = false
    @State private var toast: ToastConfig? = nil
    @State private var outlierWarning: String? = nil
    @State private var outlierConfirmed = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "SESSION · 01", title: "Log Session") {
                DatePicker("", selection: $sessionDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .font(.lgMono(14.5))
                    .tint(Color.lgAccentText)
            }

            ScrollView {
                if activeFirearms.isEmpty {
                    VStack(spacing: 16) {
                        LgEmptyState(
                            title: "No Firearms",
                            message: "Add a firearm in the Inventory tab before logging a session."
                        )
                        Button("Go to Inventory") {
                            haptic(.light)
                            router.selectedTab = .inventory
                        }
                        .buttonStyle(LgOutlineButtonStyle(color: .lgAccentText))
                        .padding(.horizontal, 40)
                    }
                    .padding(.top, 20)
                } else {
                    VStack(spacing: 14) {
                        if !allAmmo.isEmpty {
                            AmmoStockSummaryView(ammo: allAmmo)
                        }

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

                        Button("+ Add Another Firearm") {
                            haptic(.light)
                            rows.append(SessionRowState())
                        }
                        .buttonStyle(LgDashedButtonStyle(disabled: !canAddAnotherRow))
                        .disabled(!canAddAnotherRow)

                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(Color.lgOnAccent)
                            } else {
                                Text("LOG SESSION")
                            }
                        }
                        .buttonStyle(LgPrimaryButtonStyle(disabled: isSubmitting))
                        .disabled(isSubmitting)
                        .padding(.bottom, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.lgBackground)
        }
        .background(Color.lgBackground)
        .overlay(alignment: .top) {
            if let config = toast {
                ToastView(config: config) {
                    withAnimation { toast = nil }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
        .animation(.spring(duration: 0.3), value: toast?.id)
        .confirmationDialog(
            "Check Rounds Fired",
            isPresented: Binding(get: { outlierWarning != nil }, set: { if !$0 { outlierWarning = nil } }),
            titleVisibility: .visible
        ) {
            Button("Yes, That's Correct") {
                outlierWarning = nil
                outlierConfirmed = true
                Task { await submit() }
            }
            Button("Let Me Edit", role: .cancel) { outlierWarning = nil }
        } message: {
            Text((outlierWarning ?? "") + "\n\nIs this correct?")
        }
    }

    // Every existing row must have its required fields (firearm + a valid
    // rounds count) filled in before another blank one can be added — stops
    // users from spamming the button into a pile of empty forms that would
    // only surface as validation errors at submit time.
    private var canAddAnotherRow: Bool {
        rows.allSatisfy { $0.firearm != nil && $0.rounds != nil }
    }

    // MARK: - Actions

    private func removeRow(id: UUID) {
        haptic(.light)
        rows.removeAll { $0.id == id }
    }

    private func submit() async {
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

        let firearmIds = rows.compactMap { $0.firearm?.id }
        if Set(firearmIds).count != firearmIds.count {
            showToast("You've selected the same firearm more than once. Combine rounds into one entry.", type: .error)
            haptic(.error)
            return
        }

        if !outlierConfirmed, let warning = detectRoundsOutlier() {
            outlierWarning = warning
            return
        }
        outlierConfirmed = false

        isSubmitting = true
        haptic(.medium)

        let sessionId = "session-\(Date().timeIntervalSince1970)"
        var overLimitNames: [String] = []

        var originalQuantities: [(ammo: AmmoEntry, quantity: Int)] = []
        for row in rows {
            if let ammo = row.ammo { originalQuantities.append((ammo, ammo.quantity)) }
        }

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

            if firearm.isOverLimit {
                overLimitNames.append(firearm.displayName)
            }
        }

        do {
            try modelContext.save()
        } catch {
            for (ammo, original) in originalQuantities { ammo.quantity = original }
            isSubmitting = false
            haptic(.error)
            showToast("Could not save session. Please try again.", type: .error)
            return
        }

        isSubmitting = false
        haptic(.success)

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
                title: type == .success ? "Success" : type == .error ? "Error" : "Note",
                message: message,
                type: type
            )
        }
    }

    /// Flags a row whose rounds count is way out of line with that firearm's
    /// usual sessions — e.g. a sudden 10,000 in a history of 500s. Needs at
    /// least 3 data points (that firearm's past sessions plus any other rows
    /// being logged right now) before it'll flag anything, so it won't nag
    /// on a firearm's very first couple of sessions.
    private func detectRoundsOutlier() -> String? {
        var flagged: [String] = []
        for (i, row) in rows.enumerated() {
            guard let firearm = row.firearm, let rounds = row.rounds else { continue }
            var baseline = firearm.logEntries.map { $0.rounds }
            for (j, other) in rows.enumerated() where j != i {
                if let r = other.rounds { baseline.append(r) }
            }
            guard RoundsFired.isOutlier(rounds: rounds, comparedTo: baseline) else { continue }
            let average = Double(baseline.reduce(0, +)) / Double(baseline.count)
            flagged.append("\(firearm.displayName): \(rounds) rounds (usually around \(Int(average.rounded())))")
        }
        guard !flagged.isEmpty else { return nil }
        return flagged.joined(separator: "\n")
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
    @State private var showPhotoSourceDialog = false
    @State private var showCamera = false
    @State private var showLibraryPickerTrigger = false
    @FocusState private var roundsFieldFocused: Bool

    var compatibleAmmo: [AmmoEntry] {
        guard let firearm = row.firearm else { return allAmmo }
        return allAmmo.filter { $0.isCompatible(with: firearm) }
    }

    var body: some View {
        LgCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("FIREARM \(String(format: "%02d", index + 1))")
                        .font(.lgMono(12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.lgTextSecondary)
                    Spacer()
                    if canRemove {
                        Button("Remove") {
                            haptic(.light)
                            onRemove()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.lgDanger)
                    }
                }

                Button { showFirearmPicker = true } label: {
                    HStack {
                        Text(row.firearm.map { "\($0.manufacturer) \($0.model)" } ?? "Select Firearm")
                            .foregroundStyle(row.firearm == nil ? Color.lgTextTertiary : Color.lgText)
                        Spacer()
                        Text("›").foregroundStyle(Color.lgTextTertiary).accessibilityHidden(true)
                    }
                    .font(.system(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())

                if let fw = row.firearm {
                    if fw.isOverLimit {
                        warningRow("Service overdue — \(fw.activeRounds) rounds since last service.", color: .lgDanger)
                    } else if fw.isNearLimit {
                        warningRow("Service due soon — \(fw.activeRounds) / \(fw.roundsBeforeService) rounds.", color: .lgWarning)
                    }
                }

                HStack {
                    Text("Rounds Fired")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color.lgTextSecondary)
                    Spacer()
                    TextField("e.g. 50", text: $row.roundsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.lgMono(19.5, weight: .bold))
                        .foregroundStyle(Color.lgText)
                        .frame(width: 100)
                        .focused($roundsFieldFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.lgInput)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.lgBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
                .onTapGesture { roundsFieldFocused = true }
                .onChange(of: row.roundsText) { _, new in
                    let capped = RoundsFired.clamp(new.filter { $0.isNumber })
                    if capped != new { row.roundsText = capped }
                }

                if !compatibleAmmo.isEmpty {
                    Button { showAmmoPicker = true } label: {
                        HStack {
                            Text(row.ammo.map { "\($0.caliber) — \($0.brand)" } ?? "Select Ammo (Optional)")
                                .foregroundStyle(row.ammo == nil ? Color.lgTextTertiary : Color.lgText)
                            Spacer()
                            Text("›").foregroundStyle(Color.lgTextTertiary).accessibilityHidden(true)
                        }
                        .font(.system(size: 15.5))
                    }
                    .buttonStyle(LgFieldButtonStyle())
                }

                TextField("Notes (optional)", text: $row.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 15))
                    .lgTextFieldStyle()
                    .onChange(of: row.notes) { _, new in
                        if new.count > 500 { row.notes = String(new.prefix(500)) }
                    }

                PhotoSection(row: $row) {
                    showPhotoSourceDialog = true
                }
            }
        }
        // Every presentation for this row — including the photo source dialog
        // below — lives here on the card's stable root, not on any subview
        // that gets conditionally removed (e.g. PhotoSection's own button
        // once a photo is set). Nesting a presentation deep inside a view
        // that disappears out from under it is what orphaned the earlier
        // photo dialog and left the rest of the row unresponsive to touches.
        .confirmationDialog("Attach Target Photo", isPresented: $showPhotoSourceDialog, titleVisibility: .hidden) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { row.selectedPhotoItem = nil; showLibraryPickerTrigger = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibraryPickerTrigger, selection: $row.selectedPhotoItem, matching: .images)
        .onChange(of: row.selectedPhotoItem) { _, newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                row.photoPath = try? ImageStorage.save(image, named: UUID().uuidString)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { captured in
                if let captured {
                    row.photoPath = try? ImageStorage.save(captured, named: UUID().uuidString)
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFirearmPicker) {
            SelectionSheet(
                title: "Select Firearm",
                options: activeFirearms.map { f in
                    PickerOption(id: f.id, title: f.displayName, subtitle: f.primaryAmmo?.displayLabel, isSelected: row.firearm?.id == f.id) {
                        let isChangingFirearm = row.firearm?.id != f.id
                        row.firearm = f
                        // Default to the firearm's primary ammo, but only when the firearm
                        // selection actually changed — don't clobber a manual override if
                        // the user just reopens the picker and re-confirms the same one.
                        if isChangingFirearm {
                            row.ammo = f.primaryAmmo
                        }
                        showFirearmPicker = false
                    }
                },
                emptyText: "Add a firearm in the Inventory tab first.",
                onCancel: { showFirearmPicker = false }
            )
        }
        .sheet(isPresented: $showAmmoPicker) {
            SelectionSheet(
                title: "Select Ammo",
                options: [PickerOption(id: "none", title: "None", subtitle: nil, isSelected: row.ammo == nil) {
                    row.ammo = nil; showAmmoPicker = false
                }] + compatibleAmmo.map { ammo in
                    PickerOption(id: ammo.id, title: ammo.brand, subtitle: ammo.displayLabel, isSelected: row.ammo?.id == ammo.id) {
                        row.ammo = ammo; showAmmoPicker = false
                    }
                },
                onCancel: { showAmmoPicker = false }
            )
        }
    }

    private func warningRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("!")
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(Color.lgOnStatusFill)
                .frame(width: 16, height: 16)
                .background(color)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Photo Section

struct PhotoSection: View {
    @Binding var row: SessionRowState
    let onAttachTapped: () -> Void

    var body: some View {
        if let path = row.photoPath, let image = ImageStorage.load(path: path) {
            VStack(spacing: 6) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .clipped()

                Button("Remove Photo") {
                    haptic(.light)
                    if let p = row.photoPath { ImageStorage.delete(path: p) }
                    row.photoPath = nil
                    row.selectedPhotoItem = nil
                }
                .buttonStyle(LgOutlineButtonStyle(color: .lgDanger))
            }
        } else {
            Button("Attach Target Photo", action: onAttachTapped)
                .buttonStyle(LgDashedButtonStyle())
        }
    }
}

// MARK: - Ammo Stock Summary View

struct AmmoStockSummaryView: View {
    let ammo: [AmmoEntry]
    @State private var expanded = false

    private var lowStockItems: [AmmoEntry] { ammo.filter { $0.isLowStock } }
    private var sorted: [AmmoEntry] { ammo.sorted { $0.isLowStock && !$1.isLowStock } }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                haptic(.light)
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("AMMO STOCK")
                        .font(.system(size: 12.5, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.lgTextSecondary)
                    if !lowStockItems.isEmpty {
                        LgFilledPill(label: "\(lowStockItems.count) LOW", color: .lgDanger)
                    }
                    Spacer()
                    Text(expanded ? "▲" : "▼")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.lgTextTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(sorted, id: \.id) { item in
                        Rectangle().fill(Color.lgSeparator).frame(height: 1)
                        HStack(spacing: 8) {
                            Text(item.brand)
                                .font(.system(size: 14.5))
                                .foregroundStyle(Color.lgText)
                            Text(item.caliber)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.lgTextSecondary)
                            Spacer()
                            Text("\(item.quantity) rds")
                                .font(.lgMono(15.5, weight: .semibold))
                                .foregroundStyle(item.isLowStock ? Color.lgDanger : Color.lgText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .background(Color.lgCard)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.lgBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
