import SwiftUI
import SwiftData
import UIKit

// MARK: - Session Row State

struct SessionRowState: Identifiable {
    let id = UUID()
    var firearm: Firearm? = nil
    var roundsText: String = ""
    var notes: String = ""
    var ammo: AmmoEntry? = nil
    var photoPath: String? = nil

    var rounds: Int? {
        let n = Int(roundsText)
        return (n != nil && n! > 0) ? n : nil
    }

    /// A row nobody has touched — every field still at its default. Used both
    /// to drop spare rows silently at submit and to decide whether removing a
    /// row needs a confirmation.
    var isBlank: Bool {
        firearm == nil
            && rounds == nil
            && roundsText.isEmpty
            && ammo == nil
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photoPath == nil
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
    // Quick-add ammo stock, tapped straight from the Ammo Stock summary —
    // same "Add Stock" flow as the swipe action on the Inventory Ammo tab.
    @State private var ammoToRestock: AmmoEntry? = nil
    @State private var restockText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Log Session") {
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
                            router.selectedTab = .inventory
                        }
                        .buttonStyle(LgOutlineButtonStyle(color: .lgAccentText))
                        .padding(.horizontal, 40)
                    }
                    .padding(.top, 20)
                } else {
                    VStack(spacing: 14) {
                        if !allAmmo.isEmpty {
                            AmmoStockSummaryView(ammo: allAmmo) { ammo in
                                haptic(.light)
                                ammoToRestock = ammo
                                restockText = ""
                            }
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
            .scrollDismissesKeyboard(.interactively)
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
        .alert(
            "Add Stock",
            isPresented: Binding(get: { ammoToRestock != nil }, set: { if !$0 { ammoToRestock = nil } })
        ) {
            TextField("Rounds to add", text: $restockText)
                .keyboardType(.numberPad)
            Button("Add") {
                if let a = ammoToRestock { applyRestock(to: a) }
                ammoToRestock = nil
            }
            Button("Cancel", role: .cancel) { ammoToRestock = nil }
        } message: {
            if let a = ammoToRestock {
                Text("\(a.brand) \(a.caliber) is currently at \(a.quantity) rounds. How many are you adding?")
            }
        }
        // The alert's TextField auto-focuses on presentation. The app-wide
        // KeyboardDismissGesture lives on the key window, so it still sees a
        // tap landing on that already-focused field and — same as the search
        // box bug — reads "nothing changed focus" as an outside tap and
        // resigns it. Suspend it for as long as this alert is up.
        .onChange(of: ammoToRestock?.id) { _, newValue in
            KeyboardDismissGesture.shared.isSuspended = (newValue != nil)
        }
    }

    private func applyRestock(to ammo: AmmoEntry) {
        guard let amount = Int(restockText.trimmingCharacters(in: .whitespaces)), amount > 0 else { return }
        ammo.quantity += amount
        do {
            try modelContext.save()
            toast = ToastConfig(title: "Restocked", message: "\(ammo.brand) \(ammo.caliber) now at \(ammo.quantity) rounds.", type: .success)
        } catch {
            toast = ToastConfig(title: "Error", message: "Could not save changes. Please try again.", type: .error)
        }
    }

    // Every existing row must have its required fields (firearm, a valid
    // rounds count, and ammo — unless nothing compatible is in inventory to
    // pick) filled in before another blank one can be added — stops users
    // from spamming the button into a pile of empty forms that would only
    // surface as validation errors at submit time.
    private var canAddAnotherRow: Bool {
        rows.allSatisfy(isRowComplete)
    }

    private func compatibleAmmo(for firearm: Firearm?) -> [AmmoEntry] {
        AmmoEntry.compatibleOptions(for: firearm, from: allAmmo)
    }

    private func isRowComplete(_ row: SessionRowState) -> Bool {
        guard row.firearm != nil, row.rounds != nil else { return false }
        let compatible = compatibleAmmo(for: row.firearm)
        return row.ammo != nil || compatible.isEmpty
    }

    // A row nobody touched is dropped silently rather than treated as an
    // incomplete entry, so adding a spare row and not getting to it doesn't
    // block logging the ones you did fill in.
    private func isRowBlank(_ row: SessionRowState) -> Bool { row.isBlank }

    // MARK: - Actions

    private func removeRow(id: UUID) {
        haptic(.light)
        rows.removeAll { $0.id == id }
    }

    private func submit() async {
        let activeRows = rows.filter { !isRowBlank($0) }

        if activeRows.isEmpty {
            showToast("Please select a firearm for each entry.", type: .error)
            haptic(.error)
            return
        }

        for row in activeRows {
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
            if row.ammo == nil && !compatibleAmmo(for: row.firearm).isEmpty {
                showToast("Please select ammo for each entry.", type: .error)
                haptic(.error)
                return
            }
        }

        let firearmIds = activeRows.compactMap { $0.firearm?.id }
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
        for row in activeRows {
            if let ammo = row.ammo { originalQuantities.append((ammo, ammo.quantity)) }
        }

        for row in activeRows {
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

    @Environment(\.modelContext) private var modelContext

    @State private var showFirearmPicker = false
    @State private var showAmmoPicker = false
    @State private var showPhotoSourceDialog = false
    @State private var showCamera = false
    @State private var showLibraryPickerTrigger = false
    @State private var showRemoveRowConfirm = false
    @State private var showRemovePhotoConfirm = false
    @State private var ammoToRestock: AmmoEntry? = nil
    @State private var restockText = ""
    @State private var roundsNotice: String? = nil
    @FocusState private var roundsFieldFocused: Bool

    var compatibleAmmo: [AmmoEntry] {
        AmmoEntry.compatibleOptions(for: row.firearm, from: allAmmo)
    }

    private var ammoButtonLabel: String {
        row.ammo?.caliber ?? "Select Ammo"
    }

    var body: some View {
        LgCard {
            VStack(alignment: .leading, spacing: 8) {
                if canRemove {
                    HStack {
                        Spacer()
                        Button("Remove") {
                            haptic(.light)
                            // A still-blank row is the common "added one by
                            // mistake" case — drop it with no friction. Only
                            // prompt when there's entered data to lose.
                            if row.isBlank { onRemove() } else { showRemoveRowConfirm = true }
                        }
                        .font(LgFontPreference.font(size: 14, weight: .semibold))
                        .foregroundStyle(Color.lgDanger)
                    }
                }

                Button { showFirearmPicker = true } label: {
                    HStack {
                        Text(row.firearm.map { "\($0.manufacturer) \($0.model)" } ?? "Select Firearm")
                            .foregroundStyle(row.firearm == nil ? Color.lgTextTertiary : Color.lgText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text("›").foregroundStyle(Color.lgTextTertiary).accessibilityHidden(true)
                    }
                    .font(LgFontPreference.font(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())
                .accessibilityIdentifier("SelectFirearmField")

                if let fw = row.firearm {
                    if fw.isOverLimit {
                        warningRow("Service overdue: \(fw.activeRounds) rounds since last service.", color: .lgDanger)
                    } else if fw.isNearLimit {
                        warningRow("Service due soon: \(fw.activeRounds) / \(fw.roundsBeforeService) rounds.", color: .lgWarning)
                    }
                }

                TextField(
                    "Rounds Fired",
                    text: $row.roundsText,
                    prompt: Text("Rounds Fired")
                        .font(LgFontPreference.font(size: 15.5))
                        .foregroundStyle(Color.lgTextTertiary)
                )
                .keyboardType(.numberPad)
                .font(.lgMono(19.5, weight: .bold))
                .foregroundStyle(Color.lgText)
                .focused($roundsFieldFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.lgInput)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.lgBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture { roundsFieldFocused = true }
                .onChange(of: row.roundsText) { _, new in
                    let digitsOnly = new.filter { $0.isNumber }
                    let capped = RoundsFired.clamp(digitsOnly)
                    guard capped != new else { return }
                    row.roundsText = capped
                    if capped != digitsOnly {
                        flashInputNotice($roundsNotice, "Capped at \(RoundsFired.maxValue.formatted())")
                    } else if digitsOnly != new {
                        flashInputNotice($roundsNotice, "Numbers only")
                    }
                }
                .inputNotice(roundsNotice)

                if !allAmmo.isEmpty {
                    // Shown but disabled until a firearm is picked — which ammo
                    // is offered depends on that firearm's compatibility list.
                    Button { showAmmoPicker = true } label: {
                        HStack {
                            Text(ammoButtonLabel)
                                .foregroundStyle(row.ammo == nil ? Color.lgTextTertiary : Color.lgText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text("›").foregroundStyle(Color.lgTextTertiary).accessibilityHidden(true)
                        }
                        .font(LgFontPreference.font(size: 15.5))
                    }
                    .buttonStyle(LgFieldButtonStyle(disabled: row.firearm == nil))
                    .disabled(row.firearm == nil)
                    .accessibilityIdentifier("SelectAmmoField")
                }

                TextField("Notes (optional)", text: $row.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .font(LgFontPreference.font(size: 15))
                    .lgTextFieldStyle()
                    .onChange(of: row.notes) { _, new in
                        if new.count > 500 { row.notes = String(new.prefix(500)) }
                    }

                PhotoSection(
                    row: $row,
                    onAttachTapped: { showPhotoSourceDialog = true },
                    onRemoveTapped: { showRemovePhotoConfirm = true }
                )

                // Test-only seam: PHPicker runs out of process and the simulator
                // has no camera, so neither photo path can be driven from a UI
                // test. This performs the identical `row.photoPath` mutation
                // their callbacks do, which is what the regression test needs to
                // reach. Never compiled into a release build.
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-UITestForcePhoto") {
                    Button("DEBUG Force Photo") {
                        // Portrait, like an actual phone photo — this is the
                        // aspect that overflows a fill-scaled thumbnail.
                        let size = CGSize(width: 3024, height: 4032)
                        let renderer = UIGraphicsImageRenderer(size: size)
                        let img = renderer.image { ctx in
                            UIColor.red.setFill()
                            ctx.fill(CGRect(origin: .zero, size: size))
                        }
                        row.photoPath = try? ImageStorage.save(img, named: UUID().uuidString)
                    }
                    .accessibilityIdentifier("DebugForcePhoto")
                }
                #endif
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
            Button("Choose from Library") { showLibraryPickerTrigger = true }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove Photo?", isPresented: $showRemovePhotoConfirm, titleVisibility: .visible) {
            Button("Remove Photo", role: .destructive) {
                if let p = row.photoPath { ImageStorage.delete(path: p) }
                row.photoPath = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the target photo from this entry.")
        }
        .confirmationDialog("Remove This Firearm?", isPresented: $showRemoveRowConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { onRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This row has details entered. Removing it discards them.")
        }
        .fullScreenCover(isPresented: $showLibraryPickerTrigger) {
            PhotoLibraryPickerView { image in
                if let image {
                    row.photoPath = try? ImageStorage.save(image, named: UUID().uuidString)
                }
                showLibraryPickerTrigger = false
            }
            .ignoresSafeArea()
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
        .lgBottomSheet(isPresented: $showFirearmPicker) {
            SelectionSheet(
                title: "Select Firearm",
                options: activeFirearms.map { f in
                    PickerOption(id: f.id, title: f.displayName, subtitle: f.primaryAmmo?.caliber, isSelected: row.firearm?.id == f.id) {
                        let isChangingFirearm = row.firearm?.id != f.id
                        row.firearm = f
                        // Default to the firearm's primary ammo, but only when the firearm
                        // selection actually changed — don't clobber a manual override if
                        // the user just reopens the picker and re-confirms the same one.
                        // Skip it if that primary ammo isn't compatible with the new firearm.
                        if isChangingFirearm {
                            let options = AmmoEntry.compatibleOptions(for: f, from: allAmmo)
                            row.ammo = f.primaryAmmo.flatMap { p in
                                options.contains(where: { $0.id == p.id }) ? p : nil
                            }
                        }
                    }
                },
                emptyText: "Add a firearm in the Inventory tab first.",
                onCancel: { showFirearmPicker = false },
                onSave: { showFirearmPicker = false }
            )
        }
        .lgBottomSheet(isPresented: $showAmmoPicker) {
            SelectionSheet(
                title: "Select Ammo",
                options: compatibleAmmo.map { ammo in
                    PickerOption(
                        id: ammo.id, title: ammo.brand, subtitle: ammo.caliber, isSelected: row.ammo?.id == ammo.id,
                        onSelect: { row.ammo = ammo },
                        quickAction: PickerQuickAction(icon: "plus.circle") {
                            ammoToRestock = ammo
                            restockText = ""
                        }
                    )
                },
                onCancel: { showAmmoPicker = false },
                onSave: { showAmmoPicker = false }
            )
        }
        .alert(
            "Add Stock",
            isPresented: Binding(get: { ammoToRestock != nil }, set: { if !$0 { ammoToRestock = nil } })
        ) {
            TextField("Rounds to add", text: $restockText)
                .keyboardType(.numberPad)
            Button("Add") {
                if let ammo = ammoToRestock, let amount = Int(restockText.trimmingCharacters(in: .whitespaces)), amount > 0 {
                    ammo.quantity += amount
                    try? modelContext.save()
                    haptic(.success)
                }
                ammoToRestock = nil
            }
            Button("Cancel", role: .cancel) { ammoToRestock = nil }
        } message: {
            if let ammo = ammoToRestock {
                Text("\(ammo.brand) \(ammo.caliber) is currently at \(ammo.quantity) rounds. How many are you adding?")
            }
        }
    }

    private func warningRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("!")
                .font(LgFontPreference.font(size: 11.5, weight: .heavy))
                .foregroundStyle(Color.lgOnStatusFill)
                .frame(width: 16, height: 16)
                .background(color)
                .clipShape(Circle())
            Text(text)
                .font(LgFontPreference.font(size: 14))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Photo Section

struct PhotoSection: View {
    @Binding var row: SessionRowState
    let onAttachTapped: () -> Void
    /// The actual removal + its confirmation live on SessionRowCard's stable
    /// root — this button only signals intent, so the confirmation isn't
    /// orphaned when this branch disappears on removal.
    let onRemoveTapped: () -> Void

    var body: some View {
        if let path = row.photoPath, let image = ImageStorage.load(path: path) {
            VStack(spacing: 6) {
                LgPhotoThumbnail(image: image, height: 96, cornerRadius: 10)

                Button("Remove Photo") {
                    haptic(.light)
                    onRemoveTapped()
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
    /// Tapping a row opens the same "Add Stock" quick-add flow as swiping
    /// left on the Ammo Inventory tab.
    var onTapRow: (AmmoEntry) -> Void
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
                        .font(LgFontPreference.font(size: 12.5, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.lgTextSecondary)
                    if !lowStockItems.isEmpty {
                        LgFilledPill(label: "\(lowStockItems.count) LOW", color: .lgDanger)
                    }
                    Spacer()
                    Text(expanded ? "▲" : "▼")
                        .font(LgFontPreference.font(size: 12.5))
                        .foregroundStyle(Color.lgTextTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                // Without this, the Spacer's middle stretch isn't part of the
                // button's actual hit-testable shape — a real finger usually
                // lands on the visible text either side of it, but a tap
                // targeting the frame's center (as automated taps do) falls
                // in that dead zone and silently does nothing.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(sorted, id: \.id) { item in
                        Rectangle().fill(Color.lgSeparator).frame(height: 1)
                        Button {
                            onTapRow(item)
                        } label: {
                            HStack(spacing: 8) {
                                Text(item.brand)
                                    .font(LgFontPreference.font(size: 14.5))
                                    .foregroundStyle(Color.lgText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(item.caliber)
                                    .font(LgFontPreference.font(size: 13))
                                    .foregroundStyle(Color.lgTextSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.quantity) rds")
                                    .font(.lgMono(15.5, weight: .semibold))
                                    .foregroundStyle(item.isLowStock ? Color.lgDanger : Color.lgText)
                                Image(systemName: "plus.circle")
                                    .font(LgFontPreference.font(size: 14))
                                    .foregroundStyle(Color.lgAccentText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.brand) \(item.caliber), \(item.quantity) rounds. Tap to add stock.")
                    }
                }
            }
        }
        .background(Color.lgCard)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.lgBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
