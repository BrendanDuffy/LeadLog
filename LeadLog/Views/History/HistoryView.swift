import SwiftUI
import SwiftData

// MARK: - Grouping

enum HistoryGroupMode: String, CaseIterable {
    case date = "Date"
    case firearm = "Firearm"
    case ammo = "Ammo"
}

struct HistoryEntryGroup: Identifiable {
    let id: String
    let title: String
    let entries: [LogEntry]

    var latestDate: Date { entries.first?.date ?? Date() }
    var totalRounds: Int { entries.reduce(0) { $0 + $1.rounds } }
}

// MARK: - HistoryView

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LogEntry.date, order: .reverse) private var allEntries: [LogEntry]

    @State private var searchText = ""
    @State private var showSearch = false
    @State private var groupMode: HistoryGroupMode = .date
    @State private var showRetired = false
    @State private var toast: ToastConfig? = nil
    @State private var entryToView: LogEntry? = nil
    @State private var entryToEdit: LogEntry? = nil
    @State private var entryToDelete: LogEntry? = nil

    /// Entries scoped to the Active/Retired filter — mirrors Inventory's
    /// Active Firearms / Retired split so History stays in sync with it.
    /// An entry whose firearm has since been deleted (nil `firearm`, only
    /// possible for legacy data predating cascade delete) is treated as
    /// active so it still surfaces somewhere rather than vanishing.
    private var scopedEntries: [LogEntry] {
        allEntries.filter { showRetired ? ($0.firearm?.isRetired ?? false) : !($0.firearm?.isRetired ?? false) }
    }

    private func buildGroups(keyedBy key: (LogEntry) -> String?, fallback: String) -> [HistoryEntryGroup] {
        let grouped = Dictionary(grouping: scopedEntries) { entry -> String in
            let k = key(entry)?.trimmingCharacters(in: .whitespaces) ?? ""
            return k.isEmpty ? fallback : k
        }
        return grouped.map { title, entries in
            HistoryEntryGroup(id: title, title: title, entries: entries.sorted(by: { $0.date > $1.date }))
        }
        .sorted(by: { $0.latestDate > $1.latestDate })
    }

    private var firearmGroups: [HistoryEntryGroup] {
        buildGroups(keyedBy: { $0.firearmNameSnapshot ?? $0.firearm?.displayName }, fallback: "Unknown Firearm")
    }

    private var ammoGroups: [HistoryEntryGroup] {
        buildGroups(keyedBy: { $0.ammoCaliberSnapshot }, fallback: "No Ammo Recorded")
    }

    private var dateGroups: [HistoryEntryGroup] {
        buildGroups(keyedBy: { $0.date.formatted(date: .long, time: .omitted) }, fallback: "Unknown Date")
    }

    private var currentGroups: [HistoryEntryGroup] {
        switch groupMode {
        case .firearm: return firearmGroups
        case .ammo: return ammoGroups
        case .date: return dateGroups
        }
    }

    private func filteredGroups(_ groups: [HistoryEntryGroup]) -> [HistoryEntryGroup] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return groups }
        let q = searchText.lowercased()
        return groups.compactMap { group -> HistoryEntryGroup? in
            if group.title.lowercased().contains(q) { return group }
            let matches = group.entries.filter { entry in
                (entry.firearmNameSnapshot ?? entry.firearm?.displayName ?? "").lowercased().contains(q) ||
                (entry.ammoSnapshot ?? "").lowercased().contains(q) ||
                entry.date.formatted(date: .long, time: .omitted).lowercased().contains(q)
            }
            guard !matches.isEmpty else { return nil }
            return HistoryEntryGroup(id: group.id, title: group.title, entries: matches)
        }
    }

    private func crossReference(for entry: LogEntry) -> String? {
        switch groupMode {
        case .firearm:
            guard let ammo = entry.ammoCaliberSnapshot, !ammo.isEmpty else { return nil }
            return ammo
        case .ammo, .date:
            return entry.firearmNameSnapshot ?? entry.firearm?.displayName
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if allEntries.isEmpty {
                ScrollView {
                    LgEmptyState(title: "No Sessions Yet", message: "Log your first session to see it here.")
                }
                .background(Color.lgBackground)
            } else {
                let groups = filteredGroups(currentGroups)
                if groups.isEmpty {
                    ScrollView {
                        LgEmptyState(
                            title: isSearching ? "No Results" : (showRetired ? "No Retired Sessions" : "No Active Sessions"),
                            message: isSearching
                                ? "No sessions match your search."
                                : (showRetired ? "No sessions found for retired firearms." : "No sessions found for active firearms.")
                        )
                    }
                    .background(Color.lgBackground)
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    Button {
                                        haptic(.light)
                                        entryToView = entry
                                    } label: {
                                        HistoryEntryRow(entry: entry, crossReference: crossReference(for: entry))
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                haptic(.medium)
                                                entryToDelete = entry
                                            } label: {
                                                Label("Delete History Record", systemImage: "trash")
                                            }
                                            .labelStyle(.iconOnly)
                                            .tint(.red)

                                            Button {
                                                haptic(.light)
                                                entryToEdit = entry
                                            } label: {
                                                Label("Edit History Record", systemImage: "pencil")
                                            }
                                            .labelStyle(.iconOnly)
                                            .tint(.yellow)
                                        }
                                }
                            } header: {
                                groupHeader(group)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 0)
                }
            }
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
        .lgSearchBox(isPresented: $showSearch, text: $searchText, prompt: "Search by firearm, ammo, or date")
        .sheet(item: $entryToView) { entry in
            ViewLogEntrySheet(entry: entry) {
                entryToView = nil
                entryToEdit = entry
            }
        }
        .sheet(item: $entryToEdit) { entry in
            EditLogEntrySheet(entry: entry) { toast = $0 }
        }
        .confirmationDialog(
            "Delete This Log Entry?",
            isPresented: Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let e = entryToDelete { deleteEntry(e) }
                entryToDelete = nil
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("Permanently removes this entry from your history. Any ammo counted against it will be restored to inventory.")
        }
    }

    private func deleteEntry(_ entry: LogEntry) {
        haptic(.medium)
        if let ammo = entry.ammo {
            ammo.quantity += entry.rounds
        }
        if let path = entry.photoPath { ImageStorage.delete(path: path) }
        modelContext.delete(entry)
        do {
            try modelContext.save()
            toast = ToastConfig(title: "Deleted", message: "Log entry removed.", type: .info)
        } catch {
            toast = ToastConfig(title: "Error", message: "Could not delete entry. Please try again.", type: .error)
        }
    }

    @ViewBuilder
    private func groupHeader(_ group: HistoryEntryGroup) -> some View {
        // Bigger than a row's own title, matching Inventory's dividers —
        // and padding comes before `.frame(maxWidth: .infinity)` so the
        // background fills the row edge to edge instead of leaving gutters.
        HStack {
            Text(group.title.uppercased())
                .font(LgFontPreference.font(size: 20, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.lgText)
                .lineLimit(1)
            Spacer()
            Text("\(group.totalRounds) rds")
                .font(LgFontPreference.font(size: 11.5))
                .foregroundStyle(Color.lgTextTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.lgCardAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.lgBorder).frame(height: 1) }
        .listRowInsets(EdgeInsets())
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("History")
                    .font(LgFontPreference.font(size: 31, weight: .bold))
                    .foregroundStyle(Color.lgText)
                Spacer()
                HStack(spacing: 8) {
                    LgSearchIconButton(isActive: isSearching) { showSearch = true }
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
                    .accessibilityLabel("Filter history, currently \(showRetired ? "Retired" : "Active Firearms")")
                    .accessibilityIdentifier("HistoryRetiredFilterButton")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("GROUP BY").lgEyebrowStyle()
                LgSegmentedControl(options: HistoryGroupMode.allCases, selection: $groupMode) { $0.rawValue }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Color.lgBackground)
    }
}

// MARK: - HistoryEntryRow

struct HistoryEntryRow: View {
    let entry: LogEntry
    let crossReference: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 0) {
                Text(entry.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.lgMono(10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.lgTextSecondary)
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.lgMono(19, weight: .bold))
                    .foregroundStyle(Color.lgText)
            }
            .frame(width: 38)

            Rectangle().fill(Color.lgBorder).frame(width: 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(crossReference ?? entry.date.formatted(date: .long, time: .omitted))
                    .font(LgFontPreference.font(size: 14.5))
                    .foregroundStyle(Color.lgText)
                    .lineLimit(1)
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(LgFontPreference.font(size: 12.5))
                        .foregroundStyle(Color.lgTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.rounds)")
                    .font(.lgMono(17, weight: .bold))
                    .foregroundStyle(Color.lgText)
                HStack(spacing: 3) {
                    if let photoPath = entry.photoPath, !photoPath.isEmpty {
                        Image(systemName: "camera.fill")
                            .font(LgFontPreference.font(size: 9))
                            .foregroundStyle(Color.lgTextSecondary)
                    }
                    Text("ROUNDS")
                        .font(LgFontPreference.font(size: 9.5))
                        .tracking(0.3)
                        .foregroundStyle(Color.lgTextTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.lgAccentWash)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lgAccentWashBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - ViewLogEntrySheet

struct ViewLogEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: LogEntry
    let onEdit: () -> Void

    @State private var photoImage: UIImage? = nil
    @State private var showPhotoViewer = false

    var body: some View {
        LgSheetScaffold(
            title: entry.date.formatted(date: .abbreviated, time: .omitted),
            leftLabel: "Close", leftAction: { dismiss() },
            rightLabel: "Edit", rightAction: onEdit
        ) {
            VStack(spacing: 10) {
                detailRow(label: "Firearm", value: entry.firearmNameSnapshot ?? entry.firearm?.displayName ?? "Unknown Firearm")
                detailRow(label: "Rounds Fired", value: "\(entry.rounds)")
                if let ammo = entry.ammoSnapshot ?? entry.ammo?.displayLabel {
                    detailRow(label: "Ammo", value: ammo)
                }
            }
            .padding(.top, 14)

            if let notes = entry.notes, !notes.isEmpty {
                Text("Notes").lgSectionLabelStyle().padding(.top, 18)
                Text(notes)
                    .font(LgFontPreference.font(size: 15))
                    .foregroundStyle(Color.lgText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.lgInput)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.lgBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("Target Photo").lgSectionLabelStyle().padding(.top, 18)
            if let image = photoImage {
                Button {
                    haptic(.light)
                    showPhotoViewer = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        LgPhotoThumbnail(image: image, height: 220, cornerRadius: 12)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(LgFontPreference.font(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                            .padding(10)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ViewTargetPhoto")
            } else {
                Text("No target photo attached.")
                    .font(LgFontPreference.font(size: 14.5))
                    .foregroundStyle(Color.lgTextTertiary)
                    .padding(.vertical, 4)
            }
        }
        .onAppear {
            photoImage = entry.photoPath.flatMap { ImageStorage.load(path: $0) }
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            if let image = photoImage {
                PhotoViewerSheet(image: image) { showPhotoViewer = false }
            }
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(LgFontPreference.font(size: 14.5))
                .foregroundStyle(Color.lgTextSecondary)
            Spacer()
            Text(value)
                .font(LgFontPreference.font(size: 15.5, weight: .semibold))
                .foregroundStyle(Color.lgText)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.lgInput)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.lgBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - PhotoViewerSheet
// Full-screen, pinch-to-zoom photo viewer — target photos are meant to be
// inspected closely, so a small inline thumbnail isn't enough on its own.

struct PhotoViewerSheet: View {
    let image: UIImage
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale == 1 {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1 {
                            scale = 1
                            lastScale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        haptic(.light)
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(LgFontPreference.font(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("ClosePhotoViewer")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer()
            }
        }
    }
}

// MARK: - EditLogEntrySheet

struct EditLogEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Firearm.manufacturer) private var allFirearms: [Firearm]
    @Query(sort: \AmmoEntry.brand) private var allAmmo: [AmmoEntry]

    let entry: LogEntry
    let onComplete: (ToastConfig) -> Void

    @State private var selectedFirearm: Firearm? = nil
    @State private var entryDate = Date()
    @State private var roundsText = ""
    @State private var selectedAmmo: AmmoEntry? = nil
    @State private var notes = ""
    @State private var photoImage: UIImage? = nil
    @State private var photoChanged = false
    @State private var validationError: String? = nil
    @State private var roundsNotice: String? = nil

    @State private var showFirearmPicker = false
    @State private var showAmmoPicker = false
    @State private var showPhotoSourceDialog = false
    @State private var showCamera = false
    @State private var showLibraryPickerTrigger = false
    @State private var showPhotoViewer = false
    @State private var showRemovePhotoConfirm = false
    @State private var showDiscardConfirm = false
    @FocusState private var roundsFieldFocused: Bool

    // Snapshot of the entry as loaded, to tell whether Cancel would drop edits.
    @State private var initialFirearmID: String? = nil
    @State private var initialDate = Date()
    @State private var initialRounds = ""
    @State private var initialAmmoID: String? = nil
    @State private var initialNotes = ""

    private var compatibleAmmo: [AmmoEntry] {
        AmmoEntry.compatibleOptions(for: selectedFirearm, from: allAmmo)
    }

    private var hasUnsavedChanges: Bool {
        selectedFirearm?.id != initialFirearmID
            || !Calendar.current.isDate(entryDate, inSameDayAs: initialDate)
            || roundsText != initialRounds
            || selectedAmmo?.id != initialAmmoID
            || notes != initialNotes
            || photoChanged
    }

    private var ammoButtonValue: String {
        selectedAmmo?.caliber ?? "Select"
    }

    var body: some View {
        LgSheetScaffold(
            title: "Edit Entry",
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
                HStack {
                    Text("Date")
                        .font(LgFontPreference.font(size: 15.5))
                        .foregroundStyle(Color.lgText)
                    Spacer()
                    DatePicker("", selection: $entryDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Color.lgAccentText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.lgInput)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.lgBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button { showFirearmPicker = true } label: {
                    HStack {
                        Text("Firearm").foregroundStyle(Color.lgText)
                        Spacer()
                        Text((selectedFirearm?.displayName ?? "Select Firearm") + " ›")
                            .foregroundStyle(Color.lgTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(LgFontPreference.font(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())

                VStack(alignment: .leading, spacing: 4) {
                    LgFieldLabel(text: "Rounds Fired")
                    TextField("e.g. 50", text: $roundsText)
                        .keyboardType(.numberPad)
                        .font(.lgMono(16.5))
                        .lgTextFieldStyle()
                        .focused($roundsFieldFocused)
                        .onChange(of: roundsText) { _, new in
                            let digitsOnly = new.filter { $0.isNumber }
                            let capped = RoundsFired.clamp(digitsOnly)
                            guard capped != new else { return }
                            roundsText = capped
                            if capped != digitsOnly {
                                flashInputNotice($roundsNotice, "Capped at \(RoundsFired.maxValue.formatted())")
                            } else if digitsOnly != new {
                                flashInputNotice($roundsNotice, "Numbers only")
                            }
                        }
                        .inputNotice(roundsNotice)
                }

                // Which ammo is offered depends on the firearm's compatibility
                // list; disabled until a firearm is set (mirrors Log Session).
                Button { showAmmoPicker = true } label: {
                    HStack {
                        Text("Ammo").foregroundStyle(Color.lgText)
                        Spacer()
                        Text(ammoButtonValue + " ›")
                            .foregroundStyle(Color.lgTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(LgFontPreference.font(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle(disabled: selectedFirearm == nil))
                .disabled(selectedFirearm == nil)
            }

            Text("Notes").lgSectionLabelStyle().padding(.top, 18)
            TextField("Optional notes", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .font(LgFontPreference.font(size: 15))
                .lgTextFieldStyle()
                .onChange(of: notes) { _, new in
                    if new.count > 500 { notes = String(new.prefix(500)) }
                }

            Text("Photo").lgSectionLabelStyle().padding(.top, 18)
            if let image = photoImage {
                VStack(spacing: 6) {
                    Button {
                        haptic(.light)
                        showPhotoViewer = true
                    } label: {
                        LgPhotoThumbnail(image: image, height: 110, cornerRadius: 10)
                    }
                    .buttonStyle(.plain)

                    Button("Remove Photo") {
                        haptic(.light)
                        showRemovePhotoConfirm = true
                    }
                    .buttonStyle(LgOutlineButtonStyle(color: .lgDanger))
                }
            } else {
                Button("Attach Target Photo") { showPhotoSourceDialog = true }
                    .buttonStyle(LgDashedButtonStyle())
            }
        }
        .confirmationDialog("Attach Target Photo", isPresented: $showPhotoSourceDialog, titleVisibility: .hidden) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showLibraryPickerTrigger = true }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove Photo?", isPresented: $showRemovePhotoConfirm, titleVisibility: .visible) {
            Button("Remove Photo", role: .destructive) {
                photoImage = nil
                photoChanged = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the target photo from this entry. It's applied when you save.")
        }
        .confirmationDialog("Discard Changes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your edits to this entry haven't been saved.")
        }
        .fullScreenCover(isPresented: $showLibraryPickerTrigger) {
            PhotoLibraryPickerView { image in
                if let image {
                    photoImage = image
                    photoChanged = true
                }
                showLibraryPickerTrigger = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { captured in
                if let captured {
                    photoImage = captured
                    photoChanged = true
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            if let image = photoImage {
                PhotoViewerSheet(image: image) { showPhotoViewer = false }
            }
        }
        .lgBottomSheet(isPresented: $showFirearmPicker) {
            SelectionSheet(
                title: "Select Firearm",
                options: allFirearms.map { f in
                    PickerOption(id: f.id, title: f.displayName, subtitle: f.category?.rawValue, isSelected: selectedFirearm?.id == f.id) {
                        selectedFirearm = f
                        // Drop an ammo pick that isn't compatible with the new firearm.
                        if let a = selectedAmmo,
                           !AmmoEntry.compatibleOptions(for: f, from: allAmmo).contains(where: { $0.id == a.id }) {
                            selectedAmmo = nil
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
                    PickerOption(id: ammo.id, title: ammo.brand, subtitle: ammo.caliber, isSelected: selectedAmmo?.id == ammo.id) {
                        selectedAmmo = ammo
                    }
                },
                emptyText: "Add ammo in the Inventory tab first.",
                onCancel: { showAmmoPicker = false },
                onSave: { showAmmoPicker = false }
            )
        }
        .onAppear {
            selectedFirearm = entry.firearm
            entryDate = entry.date
            roundsText = "\(entry.rounds)"
            selectedAmmo = entry.ammo
            notes = entry.notes ?? ""
            photoImage = entry.photoPath.flatMap { ImageStorage.load(path: $0) }

            initialFirearmID = entry.firearm?.id
            initialDate = entry.date
            initialRounds = "\(entry.rounds)"
            initialAmmoID = entry.ammo?.id
            initialNotes = entry.notes ?? ""
        }
    }

    private func save() {
        guard let firearm = selectedFirearm else {
            validationError = "Please select a firearm."
            return
        }
        guard let rounds = Int(roundsText.trimmingCharacters(in: .whitespaces)), rounds > 0 else {
            validationError = "Please enter a valid number of rounds (greater than 0)."
            return
        }
        // Ammo is required whenever the firearm has compatible ammo to pick
        // (matches Log Session); only optional when nothing is compatible.
        if selectedAmmo == nil && !compatibleAmmo.isEmpty {
            validationError = "Please select ammo for this entry."
            return
        }

        if photoChanged {
            if let oldPath = entry.photoPath { ImageStorage.delete(path: oldPath) }
            if let img = photoImage {
                do { entry.photoPath = try ImageStorage.save(img, named: UUID().uuidString) }
                catch { validationError = "Could not save image. Please try again."; return }
            } else {
                entry.photoPath = nil
            }
        }

        // Reconcile ammo inventory: undo the old deduction, apply the new one.
        if let oldAmmo = entry.ammo {
            oldAmmo.quantity += entry.rounds
        }
        if let newAmmo = selectedAmmo {
            newAmmo.quantity = max(0, newAmmo.quantity - rounds)
        }

        entry.firearm = firearm
        entry.firearmNameSnapshot = firearm.displayName
        entry.date = entryDate
        entry.rounds = rounds
        entry.ammo = selectedAmmo
        entry.ammoSnapshot = selectedAmmo?.displayLabel
        entry.notes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes

        do {
            try modelContext.save()
        } catch {
            validationError = "Could not save changes. Please try again."
            return
        }
        dismiss()
        onComplete(ToastConfig(title: "Updated", message: "Log entry updated.", type: .success))
    }
}
