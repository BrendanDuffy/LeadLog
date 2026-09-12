import SwiftUI
import SwiftData

// MARK: - Inventory Tab Enum

private enum InventoryTab: String, CaseIterable {
    case firearms = "Firearms"
    case ammo = "Ammo"
}

// MARK: - Grouping
// Mirrors History's "GROUP BY" pattern: Inventory is always shown grouped
// into sections, never a flat list. A firearm/ammo entry with no Category
// assigned (it's an optional field) folds into the same "Other" group as
// entries explicitly categorized Other, rather than getting its own
// "Uncategorized" bucket.

private enum FirearmGroupMode: String, CaseIterable {
    case category = "Category"
    case manufacturer = "Manufacturer"
}

private enum AmmoGroupMode: String, CaseIterable {
    case caliber = "Caliber"
    case manufacturer = "Manufacturer"
    case category = "Category"
}

private struct FirearmGroup: Identifiable {
    let id: String
    let title: String
    let firearms: [Firearm]
}

private struct AmmoGroup: Identifiable {
    let id: String
    let title: String
    let ammo: [AmmoEntry]
}

/// Trims and substitutes `fallback` for an empty string — used for the
/// free-text manufacturer/caliber group keys (Category already has its own
/// nil-folds-into-"Other" handling).
private func lgGroupKey(_ raw: String, fallback: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? fallback : trimmed
}

// MARK: - InventoryView

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Firearm.manufacturer) private var allFirearms: [Firearm]
    @Query(sort: \AmmoEntry.brand) private var allAmmo: [AmmoEntry]

    @State private var selectedTab: InventoryTab = .firearms
    @State private var firearmGroupMode: FirearmGroupMode = .category
    @State private var ammoGroupMode: AmmoGroupMode = .caliber
    @State private var showRetired = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showAddFirearmSheet = false
    @State private var showAddAmmoSheet = false
    @State private var selectedFirearm: Firearm? = nil
    @State private var firearmToEdit: Firearm? = nil
    @State private var selectedAmmo: AmmoEntry? = nil
    @State private var toast: ToastConfig? = nil
    @State private var firearmsToDelete: Firearm? = nil
    @State private var firearmsToRetire: Firearm? = nil
    @State private var ammoToDelete: AmmoEntry? = nil
    @State private var ammoToRestock: AmmoEntry? = nil
    @State private var restockText = ""

    private var displayedFirearms: [Firearm] {
        let base = allFirearms.filter { showRetired ? $0.isRetired : !$0.isRetired }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { f in
            f.manufacturer.lowercased().contains(q) ||
            f.model.lowercased().contains(q) ||
            (f.serialNumber ?? "").lowercased().contains(q) ||
            (f.category?.rawValue.lowercased() ?? "").contains(q)
        }
    }

    private var displayedAmmo: [AmmoEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allAmmo }
        return allAmmo.filter { a in
            a.brand.lowercased().contains(q) ||
            a.caliber.lowercased().contains(q) ||
            (a.ammoType ?? "").lowercased().contains(q)
        }
    }

    private var searchPrompt: String {
        selectedTab == .firearms ? "Search by name, serial, or category" : "Search by brand, caliber, or type"
    }

    /// A small pill button (icon + current selection) that expands into a
    /// menu of grouping options — replaces the old always-visible segmented
    /// control, which competed visually with the Firearms/Ammo tabs above it.
    /// Firearms/Ammo picker — a dropdown matching `groupByControl`'s exact
    /// look, replacing the old two-segment toggle so the pair reads as one
    /// consistent row of controls rather than two different-looking things.
    private var tabDropdown: some View {
        Menu {
            ForEach(InventoryTab.allCases, id: \.self) { tab in
                Button {
                    haptic(.light)
                    selectedTab = tab
                } label: {
                    Label(tab.rawValue, systemImage: selectedTab == tab ? "checkmark" : "")
                }
            }
        } label: {
            groupByPillLabel(text: selectedTab.rawValue)
        }
        .accessibilityLabel("Type, currently \(selectedTab.rawValue)")
        .accessibilityIdentifier("InventoryTabButton")
    }

    private var groupByControl: some View {
        Menu {
            if selectedTab == .firearms {
                ForEach(FirearmGroupMode.allCases, id: \.self) { mode in
                    Button {
                        haptic(.light)
                        firearmGroupMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: firearmGroupMode == mode ? "checkmark" : "")
                    }
                }
            } else {
                ForEach(AmmoGroupMode.allCases, id: \.self) { mode in
                    Button {
                        haptic(.light)
                        ammoGroupMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: ammoGroupMode == mode ? "checkmark" : "")
                    }
                }
            }
        } label: {
            groupByPillLabel(text: selectedTab == .firearms ? firearmGroupMode.rawValue : ammoGroupMode.rawValue)
        }
        .accessibilityLabel("Group by, currently \(selectedTab == .firearms ? firearmGroupMode.rawValue : ammoGroupMode.rawValue)")
        .accessibilityIdentifier("GroupByButton")
    }

    /// Shared pill styling for `tabDropdown` and `groupByControl`, so the two
    /// sit side by side looking like a matched pair.
    private func groupByPillLabel(text: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(LgFontPreference.font(size: 12, weight: .semibold))
            }
            Text(text)
                .font(LgFontPreference.font(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(LgFontPreference.font(size: 9, weight: .bold))
        }
        .foregroundStyle(Color.lgTextSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.lgInput)
        .overlay(Capsule().strokeBorder(Color.lgBorderStrong, lineWidth: 1))
        .clipShape(Capsule())
    }

    private func firearmGroupKey(_ firearm: Firearm) -> String {
        switch firearmGroupMode {
        case .category: return firearm.category?.rawValue ?? FirearmCategory.other.rawValue
        case .manufacturer: return lgGroupKey(firearm.manufacturer, fallback: "Unknown Manufacturer")
        }
    }

    private var firearmGroups: [FirearmGroup] {
        let grouped = Dictionary(grouping: displayedFirearms, by: firearmGroupKey)
        return grouped.map { title, firearms in FirearmGroup(id: title, title: title, firearms: firearms) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func ammoGroupKey(_ ammo: AmmoEntry) -> String {
        switch ammoGroupMode {
        case .caliber: return lgGroupKey(ammo.caliber, fallback: "Unknown Caliber")
        case .manufacturer: return lgGroupKey(ammo.brand, fallback: "Unknown Manufacturer")
        case .category: return ammo.category?.rawValue ?? FirearmCategory.other.rawValue
        }
    }

    private var ammoGroups: [AmmoGroup] {
        let grouped = Dictionary(grouping: displayedAmmo, by: ammoGroupKey)
        return grouped.map { title, ammo in AmmoGroup(id: title, title: title, ammo: ammo) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Inventory") {
                HStack(spacing: 8) {
                    LgSearchIconButton(isActive: isSearching) { showSearch = true }
                    if selectedTab == .firearms {
                        Menu {
                            Button {
                                withAnimation { showRetired = false }
                            } label: {
                                Label("Active Firearms", systemImage: !showRetired ? "checkmark" : "")
                            }
                            Button {
                                withAnimation { showRetired = true }
                            } label: {
                                Label("Retired", systemImage: showRetired ? "checkmark" : "")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(LgFontPreference.font(size: 15, weight: .semibold))
                                .foregroundStyle(Color.lgTextSecondary)
                                .frame(width: 32, height: 32)
                                .background(Color.lgInput)
                                .overlay(Circle().strokeBorder(Color.lgBorderStrong, lineWidth: 1))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Filter firearms")
                    }
                    Button {
                        haptic(.medium)
                        if selectedTab == .firearms { showAddFirearmSheet = true } else { showAddAmmoSheet = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(LgFontPreference.font(size: 17, weight: .heavy))
                            .foregroundStyle(Color.lgOnAccent)
                            .frame(width: 32, height: 32)
                            .background(Color.lgAccent)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(selectedTab == .firearms ? "Add Firearm" : "Add Ammo")
                }
            }

            HStack(spacing: 10) {
                VStack(spacing: 6) {
                    LgFieldLabel(text: "Type")
                        .frame(maxWidth: .infinity, alignment: .center)
                    tabDropdown
                }
                VStack(spacing: 6) {
                    LgFieldLabel(text: "Group By")
                        .frame(maxWidth: .infinity, alignment: .center)
                    groupByControl
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .background(Color.lgBackground)

            Group {
                if selectedTab == .firearms {
                    firearmsContent
                } else {
                    ammoContent
                }
            }
            .background(Color.lgBackground)
        }
        .background(Color.lgBackground)
        .overlay(alignment: .top) {
            if let t = toast {
                ToastView(config: t) { self.toast = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast?.id)
        .lgSearchBox(isPresented: $showSearch, text: $searchText, prompt: searchPrompt)
        .sheet(isPresented: $showAddFirearmSheet) {
            AddEditFirearmSheet(firearm: nil, allFirearms: allFirearms, allAmmo: allAmmo) { toast = $0 }
        }
        .sheet(isPresented: $showAddAmmoSheet) {
            AddEditAmmoSheet(ammo: nil, allAmmo: allAmmo) { toast = $0 }
        }
        .sheet(item: $selectedFirearm) { firearm in
            // The confirmation dialogs for retire/delete live inside FirearmDetailSheet
            // itself (not here) — a confirmationDialog attached to this root view can't
            // reliably present while this same view is already covered by that sheet.
            FirearmDetailSheet(
                firearm: firearm, allFirearms: allFirearms, allAmmo: allAmmo,
                onToast: { toast = $0 },
                onRetireToggle: { firearm.isRetired ? unretireFirearm(firearm) : retireFirearm(firearm) },
                onDelete: { deleteFirearm(firearm) }
            )
        }
        .sheet(item: $firearmToEdit) { firearm in
            AddEditFirearmSheet(firearm: firearm, allFirearms: allFirearms, allAmmo: allAmmo) { toast = $0 }
        }
        .sheet(item: $selectedAmmo) { ammo in
            AddEditAmmoSheet(ammo: ammo, allAmmo: allAmmo) { toast = $0 }
        }
        .confirmationDialog(
            firearmsToDelete?.displayName ?? "",
            isPresented: Binding(get: { firearmsToDelete != nil }, set: { if !$0 { firearmsToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Retire Instead") {
                if let f = firearmsToDelete { firearmsToRetire = f }
                firearmsToDelete = nil
            }
            Button("Delete Permanently", role: .destructive) {
                if let f = firearmsToDelete { deleteFirearm(f) }
                firearmsToDelete = nil
            }
            Button("Cancel", role: .cancel) { firearmsToDelete = nil }
        } message: {
            Text("Permanently deletes the firearm, its service records, and its photo, and ALL of its History log entries will be deleted too. This cannot be undone. Consider retiring instead to preserve history.")
        }
        .confirmationDialog(
            "Retire Firearm?",
            isPresented: Binding(get: { firearmsToRetire != nil }, set: { if !$0 { firearmsToRetire = nil } }),
            titleVisibility: .visible
        ) {
            Button("Retire Firearm") {
                if let f = firearmsToRetire { retireFirearm(f) }
                firearmsToRetire = nil
            }
            Button("Cancel", role: .cancel) { firearmsToRetire = nil }
        } message: {
            Text("Retired firearms are hidden from active use but all history is preserved. You can restore a retired firearm at any time.")
        }
        .confirmationDialog(
            ammoToDelete?.brand ?? "",
            isPresented: Binding(get: { ammoToDelete != nil }, set: { if !$0 { ammoToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let a = ammoToDelete { deleteAmmo(a) }
                ammoToDelete = nil
            }
            Button("Cancel", role: .cancel) { ammoToDelete = nil }
        } message: {
            Text("Removes this ammo from inventory. Any firearms linked to it as primary ammo will be unlinked.")
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

    // MARK: - Firearms content

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    @ViewBuilder
    private var firearmsContent: some View {
        if displayedFirearms.isEmpty {
            ScrollView {
                LgEmptyState(
                    title: isSearching ? "No Matches" : (showRetired ? "No Retired Firearms" : "No Firearms"),
                    message: isSearching ? "No firearms match your search." : (showRetired ? nil : "Tap + to add your first firearm.")
                )
            }
        } else {
            List {
                ForEach(firearmGroups) { group in
                    Section {
                        ForEach(group.firearms) { firearm in
                            FirearmRow(
                                firearm: firearm,
                                onTap: { haptic(.light); selectedFirearm = firearm }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { requestDelete(firearm) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                                Button { requestRetireToggle(firearm) } label: {
                                    Label(firearm.isRetired ? "Restore" : "Retire",
                                          systemImage: firearm.isRetired ? "arrow.uturn.backward" : "archivebox")
                                }
                                .tint(.orange)
                                Button { haptic(.light); firearmToEdit = firearm } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        inventoryGroupHeader(group.title)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    // MARK: - Ammo content

    @ViewBuilder
    private var ammoContent: some View {
        if displayedAmmo.isEmpty {
            ScrollView {
                LgEmptyState(
                    title: isSearching ? "No Matches" : "No Ammo",
                    message: isSearching ? "No ammo matches your search." : "Tap + to track your ammo stock."
                )
            }
        } else {
            List {
                ForEach(ammoGroups) { group in
                    Section {
                        ForEach(group.ammo) { ammo in
                            AmmoRow(
                                ammo: ammo,
                                onTap: { haptic(.light); selectedAmmo = ammo }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    haptic(.medium)
                                    ammoToDelete = ammo
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                                Button {
                                    haptic(.light)
                                    ammoToRestock = ammo
                                    restockText = ""
                                } label: {
                                    Label("Add Stock", systemImage: "plus.circle")
                                }
                                .tint(.green)
                            }
                        }
                    } header: {
                        inventoryGroupHeader(group.title)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    @ViewBuilder
    private func inventoryGroupHeader(_ title: String) -> some View {
        // Bigger than a row's own title (18pt semibold) so the section
        // divider reads as more prominent than the records inside it.
        Text(title.uppercased())
            .font(LgFontPreference.font(size: 20, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(Color.lgText)
            .lineLimit(1)
            // Padding first insets just the text; the frame+background after
            // it then fill the row's full available width edge to edge —
            // padding applied *after* `.frame(maxWidth: .infinity)` would
            // instead shrink the whole filled area, leaving visible side
            // gutters (that was the bug being fixed here).
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lgCardAlt)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.lgBorder).frame(height: 1) }
            .listRowInsets(EdgeInsets())
    }

    // MARK: - Actions

    private func requestRetireToggle(_ firearm: Firearm) {
        if firearm.isRetired {
            unretireFirearm(firearm)
        } else {
            haptic(.medium)
            firearmsToRetire = firearm
        }
    }

    private func requestDelete(_ firearm: Firearm) {
        haptic(.medium)
        firearmsToDelete = firearm
    }

    private func persist(successToast: ToastConfig? = nil) {
        do {
            try modelContext.save()
            if let t = successToast { toast = t }
        } catch {
            toast = ToastConfig(title: "Error", message: "Could not save changes. Please try again.", type: .error)
        }
    }

    private func retireFirearm(_ firearm: Firearm) {
        haptic(.medium)
        firearm.isRetired = true
        persist(successToast: ToastConfig(title: "Retired", message: "\(firearm.displayName) retired.", type: .info))
    }

    private func unretireFirearm(_ firearm: Firearm) {
        haptic(.medium)
        firearm.isRetired = false
        persist(successToast: ToastConfig(title: "Restored", message: "\(firearm.displayName) restored to active.", type: .info))
    }

    private func deleteFirearm(_ firearm: Firearm) {
        haptic(.medium)
        if let path = firearm.photoPath { ImageStorage.delete(path: path) }
        modelContext.delete(firearm)
        persist(successToast: ToastConfig(title: "Deleted", message: "Firearm removed.", type: .info))
    }

    private func deleteAmmo(_ ammo: AmmoEntry) {
        haptic(.medium)
        modelContext.delete(ammo)
        persist(successToast: ToastConfig(title: "Deleted", message: "\(ammo.brand) removed from inventory.", type: .info))
    }

    private func applyRestock(to ammo: AmmoEntry) {
        guard let amount = Int(restockText.trimmingCharacters(in: .whitespaces)), amount > 0 else { return }
        ammo.quantity += amount
        persist(successToast: ToastConfig(title: "Restocked", message: "\(ammo.brand) \(ammo.caliber) now at \(ammo.quantity) rounds.", type: .success))
    }
}

// MARK: - FirearmRow

struct FirearmRow: View {
    let firearm: Firearm
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(firearm.displayName)
                    .font(LgFontPreference.font(size: 18, weight: .semibold))
                    .foregroundStyle(Color.lgText)
                    .lineLimit(1)
                Spacer()
                if firearm.isRetired {
                    LgBadge(label: "RETIRED", color: .lgTextTertiary)
                } else if firearm.isOverLimit {
                    LgBadge(label: "SERVICE DUE", color: .lgDanger)
                } else if firearm.isNearLimit {
                    LgBadge(label: "SERVICE SOON", color: .lgWarning)
                }
                // Replaces the old "..." menu spot — the count itself, e.g.
                // "326/500". Edit/Retire/Delete moved to swipe actions.
                Text("\(firearm.activeRounds)/\(firearm.roundsBeforeService)")
                    .font(.lgMono(14.5, weight: .semibold))
                    .foregroundStyle(Color.lgTextSecondary)
            }
            LgProgressBar(
                percent: firearm.progressPercent,
                color: firearm.isOverLimit ? .lgDanger : firearm.isNearLimit ? .lgWarning : .lgAccent
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.lgAccentWash)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lgAccentWashBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - AmmoRow

struct AmmoRow: View {
    let ammo: AmmoEntry
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Caliber then brand, e.g. "9mm Federal" — brand alone as its
            // own subtitle line was redundant with this.
            Text("\(ammo.caliber) \(ammo.brand)")
                .font(LgFontPreference.font(size: 16.5, weight: .semibold))
                .foregroundStyle(Color.lgText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(ammo.quantity)")
                    .font(.lgMono(22, weight: .bold))
                    .foregroundStyle(ammo.isLowStock ? Color.lgDanger : Color.lgText)
                Text("ROUNDS")
                    .font(LgFontPreference.font(size: 11))
                    .tracking(0.5)
                    .foregroundStyle(Color.lgTextTertiary)
                if ammo.isLowStock {
                    Text("LOW STOCK")
                        .font(LgFontPreference.font(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.lgDanger)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.lgAccentWash)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lgAccentWashBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - AddEditFirearmSheet

struct AddEditFirearmSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let firearm: Firearm?
    let allFirearms: [Firearm]
    let allAmmo: [AmmoEntry]
    let onComplete: (ToastConfig) -> Void
    /// Called with the newly-created firearm (create path only) — lets a
    /// caller that presented this sheet to add a firearm link back to it.
    var onCreated: ((Firearm) -> Void)? = nil

    @State private var manufacturer = ""
    @State private var model = ""
    @State private var selectedAmmo: AmmoEntry? = nil
    @State private var serialNumber = ""
    @State private var selectedCategory: FirearmCategory? = nil
    @State private var roundsBeforeServiceText = "500"
    @State private var roundsBeforeServiceIsDefault = true
    @State private var showDuplicateConfirm = false
    @State private var notes = ""
    @State private var validationError: String? = nil
    @State private var firearmImage: UIImage? = nil
    @State private var photoChanged = false
    @State private var compatibleAmmoIDs: Set<String> = []
    @State private var compatibleAmmoSnapshot: Set<String> = []
    @State private var roundsBeforeNotice: String? = nil
    @State private var showAmmoPicker = false
    @State private var showCategoryPicker = false
    @State private var showCompatAmmoPicker = false
    @State private var showPhotoSourceDialog = false
    @State private var showRemovePhotoConfirm = false
    @State private var showDiscardConfirm = false
    @State private var showCamera = false
    @State private var showLibraryPickerTrigger = false
    @FocusState private var roundsFieldFocused: Bool

    // Snapshot of the form as first loaded, to detect an unsaved-change Cancel.
    @State private var initialManufacturer = ""
    @State private var initialModel = ""
    @State private var initialAmmoID: String? = nil
    @State private var initialSerial = ""
    @State private var initialCategory: FirearmCategory? = nil
    @State private var initialRoundsBeforeService = "500"
    @State private var initialNotes = ""
    @State private var initialCompatibleAmmoIDs: Set<String> = []

    private var isEditing: Bool { firearm != nil }

    private var hasUnsavedChanges: Bool {
        manufacturer != initialManufacturer
            || model != initialModel
            || selectedAmmo?.id != initialAmmoID
            || serialNumber != initialSerial
            || selectedCategory != initialCategory
            || (roundsBeforeServiceText.isEmpty ? "500" : roundsBeforeServiceText) != initialRoundsBeforeService
            || notes != initialNotes
            || compatibleAmmoIDs != initialCompatibleAmmoIDs
            || photoChanged
    }

    /// Ammo offered as "Primary" — restricted to what's marked compatible,
    /// falling back to everything while nothing is marked (mirrors the
    /// allow-list fallback in `AmmoEntry.compatibleOptions`).
    private var primaryAmmoOptions: [AmmoEntry] {
        compatibleAmmoIDs.isEmpty ? allAmmo : allAmmo.filter { compatibleAmmoIDs.contains($0.id) }
    }

    private var compatibleAmmoSummary: String {
        if allAmmo.isEmpty { return "No ammo yet" }
        let count = compatibleAmmoIDs.count
        if count == 0 { return "All ammo" }
        if count == 1, let only = allAmmo.first(where: { compatibleAmmoIDs.contains($0.id) }) {
            return only.displayLabel
        }
        return "\(count) selected"
    }

    var body: some View {
        LgSheetScaffold(
            title: isEditing ? "Edit Firearm" : "Add Firearm",
            leftLabel: "Cancel",
            leftAction: { if hasUnsavedChanges { showDiscardConfirm = true } else { dismiss() } },
            rightLabel: "Save", rightAction: save
        ) {
            if let err = validationError {
                Text(err)
                    .font(LgFontPreference.font(size: 14.5))
                    .foregroundStyle(Color.lgDanger)
                    .padding(.top, 12)
            }

            Text("Details").lgSectionLabelStyle().padding(.top, 16)
            VStack(spacing: 10) {
                labeledField("Manufacturer", text: $manufacturer, placeholder: "e.g. Glock", maxLength: 60)
                labeledField("Model", text: $model, placeholder: "e.g. 19 Gen 5", maxLength: 60)
                labeledField("Serial Number", text: $serialNumber, placeholder: "Optional", monospace: true, maxLength: 40)
                Button { showCategoryPicker = true } label: {
                    HStack {
                        Text("Category").foregroundStyle(Color.lgText)
                        Spacer()
                        Text((selectedCategory?.rawValue ?? "None") + " ›")
                            .foregroundStyle(Color.lgTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(LgFontPreference.font(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())
                .accessibilityLabel("Category, \(selectedCategory?.rawValue ?? "None")")
            }

            Text("Ammo & Service").lgSectionLabelStyle().padding(.top, 18)
            VStack(spacing: 10) {
                Button {
                    compatibleAmmoSnapshot = compatibleAmmoIDs
                    showCompatAmmoPicker = true
                } label: {
                    HStack {
                        Text("Compatible Ammo").foregroundStyle(Color.lgText)
                        Spacer()
                        Text(compatibleAmmoSummary + " ›")
                            .foregroundStyle(Color.lgTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(LgFontPreference.font(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())
                .accessibilityLabel("Compatible Ammo, \(compatibleAmmoSummary)")

                Button { showAmmoPicker = true } label: {
                    HStack {
                        Text("Primary Ammo").foregroundStyle(Color.lgText)
                        Spacer()
                        Text((selectedAmmo?.caliber ?? "None") + " ›")
                            .foregroundStyle(Color.lgTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(LgFontPreference.font(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())
                .accessibilityLabel("Primary Ammo, \(selectedAmmo?.caliber ?? "None")")
            }

            VStack(alignment: .leading, spacing: 4) {
                LgFieldLabel(text: "Rounds Before Service")
                TextField("500", text: $roundsBeforeServiceText)
                    .keyboardType(.numberPad)
                    .font(.lgMono(16.5))
                    .lgTextFieldStyle()
                    .focused($roundsFieldFocused)
                    .onChange(of: roundsFieldFocused) { _, focused in
                        // Defaults land pre-filled; clear on first tap instead of
                        // making the user manually delete "500" before typing.
                        if focused && roundsBeforeServiceIsDefault {
                            roundsBeforeServiceText = ""
                            roundsBeforeServiceIsDefault = false
                        }
                    }
                    .onChange(of: roundsBeforeServiceText) { _, new in
                        let filtered = new.filter { $0.isNumber }
                        let digits = String(filtered.prefix(6))
                        guard digits != new else { return }
                        roundsBeforeServiceText = digits
                        if digits != filtered {
                            flashInputNotice($roundsBeforeNotice, "Up to 6 digits")
                        } else {
                            flashInputNotice($roundsBeforeNotice, "Numbers only")
                        }
                    }
                    .inputNotice(roundsBeforeNotice)
            }

            Text("Notes").lgSectionLabelStyle().padding(.top, 18)
            TextField("Optional notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .font(LgFontPreference.font(size: 15.5))
                .lgTextFieldStyle()
                .onChange(of: notes) { _, new in
                    if new.count > 500 { notes = String(new.prefix(500)) }
                }

            Text("Photo").lgSectionLabelStyle().padding(.top, 18)
            Button {
                showPhotoSourceDialog = true
            } label: {
                if let img = firearmImage {
                    LgPhotoThumbnail(image: img, height: 110, cornerRadius: 10)
                } else {
                    Text("Add Firearm Image")
                        .font(LgFontPreference.font(size: 15))
                        .foregroundStyle(Color.lgTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.lgDashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                }
            }
            // The thumbnail itself is inert (see LgPhotoThumbnail), so the
            // button needs its own shape to stay tappable once a photo is set.
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .confirmationDialog("Add Firearm Image", isPresented: $showPhotoSourceDialog, titleVisibility: .hidden) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { showLibraryPickerTrigger = true }
                if firearmImage != nil {
                    // Removal gets its own confirmation step rather than
                    // happening on this one tap.
                    Button("Remove Photo", role: .destructive) { showRemovePhotoConfirm = true }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Remove Photo?", isPresented: $showRemovePhotoConfirm, titleVisibility: .visible) {
                Button("Remove Photo", role: .destructive) {
                    firearmImage = nil
                    photoChanged = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the photo from this firearm. It's applied when you save.")
            }
            .fullScreenCover(isPresented: $showLibraryPickerTrigger) {
                PhotoLibraryPickerView { image in
                    if let image { firearmImage = image; photoChanged = true }
                    showLibraryPickerTrigger = false
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { captured in
                    if let captured { firearmImage = captured; photoChanged = true }
                    showCamera = false
                }
                .ignoresSafeArea()
            }
        }
        .lgBottomSheet(isPresented: $showAmmoPicker) {
            SelectionSheet(
                title: "Select Ammo",
                options: [PickerOption(id: "none", title: "None", subtitle: nil, isSelected: selectedAmmo == nil) {
                    selectedAmmo = nil
                }] + primaryAmmoOptions.map { ammo in
                    PickerOption(id: ammo.id, title: ammo.brand, subtitle: ammo.caliber, isSelected: selectedAmmo?.id == ammo.id) {
                        selectedAmmo = ammo
                    }
                },
                onCancel: { showAmmoPicker = false },
                onSave: { showAmmoPicker = false }
            )
        }
        .lgBottomSheet(isPresented: $showCompatAmmoPicker) {
            MultiSelectionSheet(
                title: "Compatible Ammo",
                options: allAmmo.map {
                    MultiPickerOption(id: $0.id, title: $0.brand, subtitle: $0.caliber)
                },
                selection: $compatibleAmmoIDs,
                emptyText: "Add ammo in the Ammo tab first.",
                onCancel: {
                    compatibleAmmoIDs = compatibleAmmoSnapshot
                    showCompatAmmoPicker = false
                },
                onSave: {
                    // Drop a Primary pick that's no longer on the allow-list.
                    if let picked = selectedAmmo, !compatibleAmmoIDs.isEmpty,
                       !compatibleAmmoIDs.contains(picked.id) {
                        selectedAmmo = nil
                    }
                    showCompatAmmoPicker = false
                }
            )
        }
        .lgBottomSheet(isPresented: $showCategoryPicker) {
            SelectionSheet(
                title: "Select Category",
                options: [PickerOption(id: "none", title: "None", subtitle: nil, isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }] + FirearmCategory.allCases.map { cat in
                    PickerOption(id: cat.id, title: cat.rawValue, subtitle: nil, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                },
                onCancel: { showCategoryPicker = false },
                onSave: { showCategoryPicker = false }
            )
        }
        .onAppear { populateIfEditing() }
        .confirmationDialog(
            "You Already Have This Firearm",
            isPresented: $showDuplicateConfirm,
            titleVisibility: .visible
        ) {
            Button("Add Anyway") { performSave() }
            Button("Cancel", role: .cancel) { showDuplicateConfirm = false }
        } message: {
            Text("\(manufacturer.trimmingCharacters(in: .whitespaces)) \(model.trimmingCharacters(in: .whitespaces)) is already in your inventory. If this is a second one, go ahead and add it.")
        }
        .confirmationDialog("Discard Changes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(isEditing ? "Your edits to this firearm haven't been saved." : "This firearm hasn't been saved.")
        }
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, monospace: Bool = false, maxLength: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LgFieldLabel(text: label)
            TextField(placeholder, text: text)
                .font(monospace ? .lgMono(15.5) : .system(size: 16.5))
                .lgTextFieldStyle()
                .onChange(of: text.wrappedValue) { _, new in
                    if new.count > maxLength { text.wrappedValue = String(new.prefix(maxLength)) }
                }
        }
    }

    @State private var didPopulate = false

    private func populateIfEditing() {
        // onAppear can fire again after a fullScreenCover (camera/library)
        // closes — only seed the form and its change-tracking snapshot once.
        guard !didPopulate else { return }
        didPopulate = true
        // Compatible-ammo IDs seed for both new and existing firearms.
        defer {
            initialManufacturer = manufacturer
            initialModel = model
            initialAmmoID = selectedAmmo?.id
            initialSerial = serialNumber
            initialCategory = selectedCategory
            initialRoundsBeforeService = roundsBeforeServiceText.isEmpty ? "500" : roundsBeforeServiceText
            initialNotes = notes
            initialCompatibleAmmoIDs = compatibleAmmoIDs
        }
        guard let f = firearm else { return }
        manufacturer = f.manufacturer; model = f.model
        selectedAmmo = f.primaryAmmo
        serialNumber = f.serialNumber ?? ""
        selectedCategory = f.category
        roundsBeforeServiceText = "\(f.roundsBeforeService)"
        roundsBeforeServiceIsDefault = false
        notes = f.notes ?? ""
        compatibleAmmoIDs = Set(f.compatibleAmmo.map(\.id))
        if let path = f.photoPath { firearmImage = ImageStorage.load(path: path) }
    }

    private func save() {
        let mfr = manufacturer.trimmingCharacters(in: .whitespaces)
        let mdl = model.trimmingCharacters(in: .whitespaces)
        var missing: [String] = []
        if mfr.isEmpty { missing.append("Manufacturer") }
        if mdl.isEmpty { missing.append("Model") }
        guard missing.isEmpty else {
            let list = missing.joined(separator: " and ")
            validationError = "\(list) \(missing.count > 1 ? "are" : "is") required."
            return
        }

        // Only new entries can collide — editing an existing one isn't a duplicate of itself.
        if firearm == nil, allFirearms.contains(where: {
            $0.manufacturer.caseInsensitiveCompare(mfr) == .orderedSame && $0.model.caseInsensitiveCompare(mdl) == .orderedSame
        }) {
            showDuplicateConfirm = true
            return
        }

        performSave()
    }

    private func performSave() {
        let mfr = manufacturer.trimmingCharacters(in: .whitespaces)
        let mdl = model.trimmingCharacters(in: .whitespaces)
        let rbs = Int(roundsBeforeServiceText.trimmingCharacters(in: .whitespaces)) ?? 500

        if let f = firearm {
            f.manufacturer = mfr; f.model = mdl
            f.primaryAmmo = selectedAmmo
            f.serialNumber = serialNumber.isEmpty ? nil : serialNumber
            f.category = selectedCategory
            f.roundsBeforeService = rbs
            f.notes = notes.isEmpty ? nil : notes
            applyCompatibleAmmo(to: f)
            if let img = firearmImage {
                if let oldPath = f.photoPath { ImageStorage.delete(path: oldPath) }
                do { f.photoPath = try ImageStorage.save(img, named: "firearm_\(f.id)") }
                catch { validationError = "Could not save image. Please try again."; return }
            }
            do { try modelContext.save() } catch {
                validationError = "Could not save changes. Please try again."; return
            }
            dismiss()
            onComplete(ToastConfig(title: "Updated", message: "\(f.displayName) updated.", type: .success))
        } else {
            let f = Firearm(manufacturer: mfr, model: mdl,
                            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
                            roundsBeforeService: rbs,
                            category: selectedCategory,
                            notes: notes.isEmpty ? nil : notes)
            f.primaryAmmo = selectedAmmo
            if let img = firearmImage {
                do { f.photoPath = try ImageStorage.save(img, named: "firearm_\(f.id)") }
                catch { validationError = "Could not save image. Please try again."; return }
            }
            modelContext.insert(f)
            applyCompatibleAmmo(to: f)
            do { try modelContext.save() } catch {
                validationError = "Could not save changes. Please try again."; return
            }
            onCreated?(f)
            dismiss()
            onComplete(ToastConfig(title: "Added", message: "\(f.displayName) added.", type: .success))
        }
    }

    /// Reconcile the many-to-many from the owning (`AmmoEntry.compatibleFirearms`)
    /// side — SwiftData is most reliable when the join is edited there.
    private func applyCompatibleAmmo(to f: Firearm) {
        for ammo in allAmmo {
            let shouldLink = compatibleAmmoIDs.contains(ammo.id)
            let isLinked = ammo.compatibleFirearms.contains { $0.id == f.id }
            if shouldLink && !isLinked {
                ammo.compatibleFirearms.append(f)
            } else if !shouldLink && isLinked {
                ammo.compatibleFirearms.removeAll { $0.id == f.id }
            }
        }
    }
}

// MARK: - AddEditAmmoSheet

struct AddEditAmmoSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Firearm.manufacturer) private var allFirearms: [Firearm]

    let ammo: AmmoEntry?
    let allAmmo: [AmmoEntry]
    let onComplete: (ToastConfig) -> Void

    @State private var caliber = ""
    @State private var brand = ""
    @State private var quantityText = ""
    @State private var grainsText = ""
    @State private var ammoType = ""
    @State private var selectedCategory: FirearmCategory? = nil
    @State private var thresholdText = "20"
    @State private var thresholdIsDefault = true
    @State private var validationError: String? = nil
    @State private var showCategoryPicker = false
    @State private var showCompatFirearmsPicker = false
    @State private var showNewFirearmSheet = false
    @State private var showDiscardConfirm = false
    @State private var duplicateMatch: AmmoEntry? = nil
    @State private var compatibleFirearmIDs: Set<String> = []
    @State private var compatibleFirearmsSnapshot: Set<String> = []
    @State private var quantityNotice: String? = nil
    @State private var grainsNotice: String? = nil
    @State private var thresholdNotice: String? = nil
    @FocusState private var thresholdFieldFocused: Bool

    @State private var didPopulate = false
    @State private var initialCaliber = ""
    @State private var initialBrand = ""
    @State private var initialQuantity = ""
    @State private var initialGrains = ""
    @State private var initialType = ""
    @State private var initialCategory: FirearmCategory? = nil
    @State private var initialThreshold = "20"
    @State private var initialCompatibleFirearmIDs: Set<String> = []

    private var isEditing: Bool { ammo != nil }

    private var hasUnsavedChanges: Bool {
        caliber != initialCaliber
            || brand != initialBrand
            || quantityText != initialQuantity
            || grainsText != initialGrains
            || ammoType != initialType
            || selectedCategory != initialCategory
            || (thresholdText.isEmpty ? "20" : thresholdText) != initialThreshold
            || compatibleFirearmIDs != initialCompatibleFirearmIDs
    }

    private var compatibleFirearmsSummary: String {
        if allFirearms.isEmpty { return "No firearms yet" }
        let count = compatibleFirearmIDs.count
        if count == 0 { return "All firearms" }
        if count == 1, let only = allFirearms.first(where: { compatibleFirearmIDs.contains($0.id) }) {
            return only.displayName
        }
        return "\(count) selected"
    }

    var body: some View {
        LgSheetScaffold(
            title: isEditing ? "Edit Ammo" : "Add Ammo",
            leftLabel: "Cancel",
            leftAction: { if hasUnsavedChanges { showDiscardConfirm = true } else { dismiss() } },
            rightLabel: "Save", rightAction: save
        ) {
            if let err = validationError {
                Text(err)
                    .font(LgFontPreference.font(size: 14.5))
                    .foregroundStyle(Color.lgDanger)
                    .padding(.top, 12)
            }

            Text("Details").lgSectionLabelStyle().padding(.top, 16)
            VStack(spacing: 10) {
                labeledField("Caliber", text: $caliber, placeholder: "e.g. 9mm", maxLength: 30)
                labeledField("Brand", text: $brand, placeholder: "e.g. Federal", maxLength: 60)
                numericField("Quantity", text: $quantityText, placeholder: "e.g. 200", maxDigits: 6, notice: $quantityNotice)
                numericField("Grains", text: $grainsText, placeholder: "e.g. 115", maxDigits: 4, notice: $grainsNotice)
                labeledField("Type", text: $ammoType, placeholder: "e.g. FMJ, JHP", maxLength: 30)
                Button { showCategoryPicker = true } label: {
                    HStack {
                        Text("Firearm Category").foregroundStyle(Color.lgText)
                        Spacer()
                        Text((selectedCategory?.rawValue ?? "None") + " ›")
                            .foregroundStyle(Color.lgTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(LgFontPreference.font(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())
                .accessibilityLabel("Firearm Category, \(selectedCategory?.rawValue ?? "None")")
            }

            Text("Compatibility").lgSectionLabelStyle().padding(.top, 18)
            Button {
                compatibleFirearmsSnapshot = compatibleFirearmIDs
                showCompatFirearmsPicker = true
            } label: {
                HStack {
                    Text("Compatible Firearms").foregroundStyle(Color.lgText)
                    Spacer()
                    Text(compatibleFirearmsSummary + " ›")
                        .foregroundStyle(Color.lgTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(LgFontPreference.font(size: 15.5))
            }
            .buttonStyle(LgFieldButtonStyle())
            .accessibilityLabel("Compatible Firearms, \(compatibleFirearmsSummary)")

            Text("Stock Alert").lgSectionLabelStyle().padding(.top, 18)
            numericField("Low Stock Threshold", text: $thresholdText, placeholder: "20", maxDigits: 6, isDefault: $thresholdIsDefault, focus: $thresholdFieldFocused, notice: $thresholdNotice)
        }
        .lgBottomSheet(isPresented: $showCategoryPicker) {
            SelectionSheet(
                title: "Select Category",
                options: [PickerOption(id: "none", title: "None", subtitle: nil, isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }] + FirearmCategory.allCases.map { cat in
                    PickerOption(id: cat.id, title: cat.rawValue, subtitle: nil, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                },
                onCancel: { showCategoryPicker = false },
                onSave: { showCategoryPicker = false }
            )
        }
        .lgBottomSheet(isPresented: $showCompatFirearmsPicker) {
            MultiSelectionSheet(
                title: "Compatible Firearms",
                options: allFirearms.map {
                    MultiPickerOption(id: $0.id, title: $0.displayName, subtitle: $0.category?.rawValue)
                },
                selection: $compatibleFirearmIDs,
                emptyText: "No firearms yet. Add one below.",
                addNewTitle: "+ New Firearm",
                onAddNew: {
                    // Keep whatever's been ticked so far, close this picker,
                    // and hand off to the firearm sheet on top.
                    showCompatFirearmsPicker = false
                    showNewFirearmSheet = true
                },
                onCancel: {
                    compatibleFirearmIDs = compatibleFirearmsSnapshot
                    showCompatFirearmsPicker = false
                },
                onSave: { showCompatFirearmsPicker = false }
            )
        }
        .sheet(isPresented: $showNewFirearmSheet) {
            AddEditFirearmSheet(
                firearm: nil, allFirearms: allFirearms, allAmmo: allAmmo,
                // Reopening the picker with the new firearm pre-checked is
                // feedback enough — skip the "firearm added" toast here.
                onComplete: { _ in },
                onCreated: { newFirearm in
                    // Pre-check it — linking to this ammo is the whole reason
                    // the user added it here — and reopen the picker.
                    compatibleFirearmIDs.insert(newFirearm.id)
                    showCompatFirearmsPicker = true
                }
            )
        }
        .onAppear { populateIfEditing() }
        .confirmationDialog(
            "You Already Track This Ammo",
            isPresented: Binding(get: { duplicateMatch != nil }, set: { if !$0 { duplicateMatch = nil } }),
            titleVisibility: .visible
        ) {
            Button("Add to Existing Stock") {
                if let match = duplicateMatch { restockExisting(match) }
                duplicateMatch = nil
            }
            Button("Add as a New Entry") {
                duplicateMatch = nil
                performSave()
            }
            Button("Cancel", role: .cancel) { duplicateMatch = nil }
        } message: {
            if let match = duplicateMatch {
                Text("\(match.brand) \(match.caliber) is already in inventory with \(match.quantity) rounds. Add this quantity to that entry instead of creating a duplicate?")
            }
        }
        .confirmationDialog("Discard Changes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(isEditing ? "Your edits to this ammo haven't been saved." : "This ammo hasn't been saved.")
        }
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, maxLength: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LgFieldLabel(text: label)
            TextField(placeholder, text: text)
                .font(LgFontPreference.font(size: 16.5))
                .lgTextFieldStyle()
                .onChange(of: text.wrappedValue) { _, new in
                    if new.count > maxLength { text.wrappedValue = String(new.prefix(maxLength)) }
                }
        }
    }

    @ViewBuilder
    private func numericField(
        _ label: String, text: Binding<String>, placeholder: String, maxDigits: Int,
        isDefault: Binding<Bool>? = nil, focus: FocusState<Bool>.Binding? = nil,
        notice: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LgFieldLabel(text: label)
            Group {
                if let focus {
                    TextField(placeholder, text: text).focused(focus)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .keyboardType(.numberPad)
            .font(.lgMono(16.5))
            .lgTextFieldStyle()
            .onChange(of: focus?.wrappedValue ?? false) { _, focused in
                if focused, isDefault?.wrappedValue == true {
                    text.wrappedValue = ""
                    isDefault?.wrappedValue = false
                }
            }
            .onChange(of: text.wrappedValue) { _, new in
                let filtered = new.filter { $0.isNumber }
                let digits = String(filtered.prefix(maxDigits))
                guard digits != new else { return }
                text.wrappedValue = digits
                if digits != filtered {
                    flashInputNotice(notice, "Up to \(maxDigits) digits")
                } else {
                    flashInputNotice(notice, "Numbers only")
                }
            }
            .inputNotice(notice.wrappedValue)
        }
    }

    private func populateIfEditing() {
        guard !didPopulate else { return }
        didPopulate = true
        defer {
            initialCaliber = caliber
            initialBrand = brand
            initialQuantity = quantityText
            initialGrains = grainsText
            initialType = ammoType
            initialCategory = selectedCategory
            initialThreshold = thresholdText.isEmpty ? "20" : thresholdText
            initialCompatibleFirearmIDs = compatibleFirearmIDs
        }
        guard let a = ammo else { return }
        caliber = a.caliber; brand = a.brand
        quantityText = "\(a.quantity)"
        grainsText = a.grains.map { "\($0)" } ?? ""
        ammoType = a.ammoType ?? ""
        selectedCategory = a.category
        thresholdText = "\(a.lowStockThreshold)"
        thresholdIsDefault = false
        compatibleFirearmIDs = Set(a.compatibleFirearms.map(\.id))
    }

    private func save() {
        let cal = caliber.trimmingCharacters(in: .whitespaces)
        let br = brand.trimmingCharacters(in: .whitespaces)
        var missing: [String] = []
        if cal.isEmpty { missing.append("Caliber") }
        if br.isEmpty { missing.append("Brand") }
        guard missing.isEmpty else {
            let list = missing.joined(separator: " and ")
            validationError = "\(list) \(missing.count > 1 ? "are" : "is") required."
            return
        }
        guard Int(quantityText.trimmingCharacters(in: .whitespaces)) != nil, (Int(quantityText.trimmingCharacters(in: .whitespaces)) ?? -1) >= 0 else {
            validationError = "Enter a valid quantity."
            return
        }

        // Only new entries can collide — editing an existing one isn't a duplicate of itself.
        if !isEditing, let match = allAmmo.first(where: {
            $0.caliber.caseInsensitiveCompare(cal) == .orderedSame && $0.brand.caseInsensitiveCompare(br) == .orderedSame
        }) {
            duplicateMatch = match
            return
        }

        performSave()
    }

    private func performSave() {
        let cal = caliber.trimmingCharacters(in: .whitespaces)
        let br = brand.trimmingCharacters(in: .whitespaces)
        let qty = Int(quantityText.trimmingCharacters(in: .whitespaces)) ?? 0
        let grains = Int(grainsText.trimmingCharacters(in: .whitespaces))
        let threshold = Int(thresholdText.trimmingCharacters(in: .whitespaces)) ?? 20

        let linkedFirearms = allFirearms.filter { compatibleFirearmIDs.contains($0.id) }

        if let a = ammo {
            a.caliber = cal; a.brand = br; a.quantity = qty
            a.grains = grains
            a.ammoType = ammoType.isEmpty ? nil : ammoType
            a.category = selectedCategory
            a.lowStockThreshold = threshold
            a.compatibleFirearms = linkedFirearms
            try? modelContext.save()
            dismiss()
            onComplete(ToastConfig(title: "Updated", message: "\(a.displayLabel) updated.", type: .success))
        } else {
            let a = AmmoEntry(caliber: cal, brand: br, quantity: qty)
            a.grains = grains
            a.ammoType = ammoType.isEmpty ? nil : ammoType
            a.category = selectedCategory
            a.lowStockThreshold = threshold
            modelContext.insert(a)
            a.compatibleFirearms = linkedFirearms
            try? modelContext.save()
            dismiss()
            onComplete(ToastConfig(title: "Added", message: "\(a.displayLabel) added.", type: .success))
        }
    }

    private func restockExisting(_ existing: AmmoEntry) {
        let qty = Int(quantityText.trimmingCharacters(in: .whitespaces)) ?? 0
        existing.quantity += qty
        try? modelContext.save()
        dismiss()
        onComplete(ToastConfig(title: "Restocked", message: "\(existing.displayLabel) now at \(existing.quantity) rounds.", type: .success))
    }
}

// MARK: - FirearmDetailSheet

struct FirearmDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let firearm: Firearm
    let allFirearms: [Firearm]
    let allAmmo: [AmmoEntry]
    let onToast: (ToastConfig) -> Void
    let onRetireToggle: () -> Void
    let onDelete: () -> Void

    @State private var showEditSheet = false
    @State private var showServiceConfirm = false
    @State private var showRetireConfirm = false
    @State private var showDeleteConfirm = false
    @State private var recordToUndo: ServiceRecord? = nil

    var body: some View {
        LgSheetScaffold(
            title: firearm.displayName,
            leftLabel: "Done", leftAction: { dismiss() },
            rightLabel: "Edit", rightAction: { showEditSheet = true }
        ) {
            if firearm.isRetired {
                LgBadge(label: "RETIRED", color: .lgTextTertiary).padding(.top, 14)
            }

            if let path = firearm.photoPath, let image = ImageStorage.load(path: path) {
                LgPhotoThumbnail(image: image, height: 190, cornerRadius: 12)
                    .padding(.top, 14)
            }

            Text("Stats").lgSectionLabelStyle().padding(.top, 16)
            LgCard {
                VStack(spacing: 12) {
                    if let category = firearm.category {
                        statRow("Category", category.rawValue)
                    }
                    statRow("Rounds Since Service", "\(firearm.activeRounds)", mono: true)
                    statRow("Service Interval", "\(firearm.roundsBeforeService)", mono: true)
                    statRow("Total Rounds", "\(firearm.logEntries.reduce(0) { $0 + $1.rounds })", mono: true)
                    VStack(spacing: 6) {
                        HStack {
                            Text("\(Int(firearm.progressPercent))% to service")
                                .font(.lgMono(14))
                                .foregroundStyle(Color.lgTextSecondary)
                            Spacer()
                            if firearm.isOverLimit {
                                LgBadge(label: "SERVICE DUE", color: .lgDanger)
                            } else if firearm.isNearLimit {
                                LgBadge(label: "SERVICE SOON", color: .lgWarning)
                            }
                        }
                        LgProgressBar(
                            percent: firearm.progressPercent,
                            color: firearm.isOverLimit ? .lgDanger : firearm.isNearLimit ? .lgWarning : .lgAccent,
                            trackColor: .lgProgressTrackDetail,
                            height: 6
                        )
                    }
                    if let ammo = firearm.primaryAmmo {
                        statRow("Primary Ammo", ammo.caliber)
                    }
                    if !firearm.compatibleAmmo.isEmpty {
                        statRow("Compatible Ammo", compatibleAmmoText)
                    }
                    if let ser = firearm.serialNumber, !ser.isEmpty {
                        statRow("Serial Number", ser, mono: true)
                    }
                }
            }

            if !firearm.isRetired {
                Button("Mark as Serviced") {
                    haptic(.medium)
                    showServiceConfirm = true
                }
                .buttonStyle(LgOutlineButtonStyle(color: firearm.isOverLimit ? .lgDanger : .lgAccentText))
                .padding(.top, 14)
            }

            Button(firearm.isRetired ? "Restore Firearm" : "Retire Firearm") {
                haptic(.medium)
                if firearm.isRetired {
                    onRetireToggle()
                    dismiss()
                } else {
                    showRetireConfirm = true
                }
            }
            .buttonStyle(LgOutlineButtonStyle(color: firearm.isRetired ? .lgAccentText : .lgWarning))
            .padding(.top, firearm.isRetired ? 14 : 10)
            .accessibilityIdentifier("FirearmRetireButton")

            Button("Delete Firearm") {
                haptic(.medium)
                showDeleteConfirm = true
            }
            .buttonStyle(LgOutlineButtonStyle(color: .lgDanger))
            .padding(.top, 10)
            .accessibilityIdentifier("FirearmDeleteButton")

            let history = firearm.serviceRecords.sorted(by: { $0.servicedAt > $1.servicedAt })
            if !history.isEmpty {
                Text("Service History").lgSectionLabelStyle().padding(.top, 20)
                Text("Tap a record to undo it if it was a mistake.")
                    .font(LgFontPreference.font(size: 12.5))
                    .foregroundStyle(Color.lgTextTertiary)
                    .padding(.bottom, 2)
                VStack(spacing: 0) {
                    ForEach(history) { record in
                        Button {
                            haptic(.light)
                            recordToUndo = record
                        } label: {
                            HStack {
                                Text(record.servicedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(LgFontPreference.font(size: 15))
                                    .foregroundStyle(Color.lgText)
                                Spacer()
                                Text("\(record.roundsAtService) rounds")
                                    .font(.lgMono(14))
                                    .foregroundStyle(Color.lgTextSecondary)
                                Text("›")
                                    .font(LgFontPreference.font(size: 14))
                                    .foregroundStyle(Color.lgTextTertiary)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Color.lgSeparator).frame(height: 1)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditFirearmSheet(firearm: firearm, allFirearms: allFirearms, allAmmo: allAmmo) { onToast($0) }
        }
        .confirmationDialog(
            "Undo This Service?",
            isPresented: Binding(get: { recordToUndo != nil }, set: { if !$0 { recordToUndo = nil } }),
            titleVisibility: .visible
        ) {
            Button("Undo Service", role: .destructive) {
                if let r = recordToUndo { undoService(r) }
                recordToUndo = nil
            }
            Button("Cancel", role: .cancel) { recordToUndo = nil }
        } message: {
            Text("Removes this service record and restores the rounds it cleared back to \(firearm.displayName)'s active count.")
        }
        .confirmationDialog(
            "Mark \(firearm.displayName) as serviced?",
            isPresented: $showServiceConfirm, titleVisibility: .visible
        ) {
            Button("Mark as Serviced") { markServiced() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Resets the round counter. Current rounds since service: \(firearm.activeRounds).")
        }
        .confirmationDialog(
            "Retire Firearm?",
            isPresented: $showRetireConfirm, titleVisibility: .visible
        ) {
            Button("Retire Firearm") { onRetireToggle(); dismiss() }
                .accessibilityIdentifier("ConfirmRetireFirearmButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Retired firearms are hidden from active use but all history is preserved. You can restore a retired firearm at any time.")
        }
        .confirmationDialog(
            "Delete \(firearm.displayName)?",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) { onDelete(); dismiss() }
                .accessibilityIdentifier("ConfirmDeleteFirearmButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently deletes the firearm, its service records, and its photo, and ALL of its History log entries will be deleted too. This cannot be undone.")
        }
    }

    private var compatibleAmmoText: String {
        let items = firearm.compatibleAmmo
        if items.count <= 2 {
            return items.map(\.caliber).joined(separator: ", ")
        }
        return "\(items.count) types"
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).font(LgFontPreference.font(size: 15)).foregroundStyle(Color.lgTextSecondary)
            Spacer()
            Text(value)
                .font(mono ? .lgMono(17, weight: .bold) : .system(size: 15))
                .foregroundStyle(Color.lgText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func markServiced() {
        let record = ServiceRecord(servicedAt: Date(), roundsAtService: firearm.activeRounds)
        record.firearm = firearm
        modelContext.insert(record)
        for entry in firearm.logEntries where entry.servicedAt == nil {
            entry.servicedAt = Date()
            entry.servicedBy = record
        }
        try? modelContext.save()
        haptic(.success)
        onToast(ToastConfig(title: "Serviced", message: "\(firearm.displayName) marked as serviced.", type: .success))
    }

    private func undoService(_ record: ServiceRecord) {
        for entry in record.servicedEntries {
            entry.servicedAt = nil
        }
        modelContext.delete(record)
        try? modelContext.save()
        haptic(.success)
        onToast(ToastConfig(title: "Undone", message: "Service record removed; rounds restored.", type: .info))
    }
}
