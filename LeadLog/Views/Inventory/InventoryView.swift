import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Inventory Tab Enum

private enum InventoryTab: String, CaseIterable {
    case firearms = "Firearms"
    case ammo = "Ammo"
}

// MARK: - InventoryView

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Firearm.manufacturer) private var allFirearms: [Firearm]
    @Query(sort: \AmmoEntry.brand) private var allAmmo: [AmmoEntry]

    @State private var selectedTab: InventoryTab = .firearms
    @State private var showRetired = false
    @State private var showAddFirearmSheet = false
    @State private var showAddAmmoSheet = false
    @State private var selectedFirearm: Firearm? = nil
    @State private var selectedAmmo: AmmoEntry? = nil
    @State private var toast: ToastConfig? = nil
    @State private var firearmsToDelete: Firearm? = nil
    @State private var firearmsToRetire: Firearm? = nil
    @State private var ammoToDelete: AmmoEntry? = nil

    private var displayedFirearms: [Firearm] {
        allFirearms.filter { showRetired ? $0.isRetired : !$0.isRetired }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "INVENTORY · 02", title: "Inventory") {
                HStack(spacing: 8) {
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
                                .font(.system(size: 15, weight: .semibold))
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
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Color.lgOnAccent)
                            .frame(width: 32, height: 32)
                            .background(Color.lgAccent)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(selectedTab == .firearms ? "Add Firearm" : "Add Ammo")
                }
            }

            LgSegmentedControl(options: InventoryTab.allCases, selection: $selectedTab) { $0.rawValue }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.lgBackground)

            ScrollView {
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
        .sheet(isPresented: $showAddFirearmSheet) {
            AddEditFirearmSheet(firearm: nil, allAmmo: allAmmo) { toast = $0 }
        }
        .sheet(isPresented: $showAddAmmoSheet) {
            AddEditAmmoSheet(ammo: nil) { toast = $0 }
        }
        .sheet(item: $selectedFirearm) { firearm in
            FirearmDetailSheet(firearm: firearm, allAmmo: allAmmo) { toast = $0 }
        }
        .sheet(item: $selectedAmmo) { ammo in
            AddEditAmmoSheet(ammo: ammo) { toast = $0 }
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
            Text("Permanently deletes the firearm, its service records, and its photo. Historical log entries will reference a deleted firearm. Consider retiring instead to preserve history.")
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
    }

    // MARK: - Firearms content

    @ViewBuilder
    private var firearmsContent: some View {
        if displayedFirearms.isEmpty {
            LgEmptyState(
                title: showRetired ? "No Retired Firearms" : "No Firearms",
                message: showRetired ? nil : "Tap + to add your first firearm."
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(displayedFirearms) { firearm in
                    FirearmRow(firearm: firearm) {
                        haptic(.light)
                        selectedFirearm = firearm
                    } onMenu: {
                        haptic(.medium)
                        firearmsToDelete = firearm
                    }
                    Rectangle().fill(Color.lgSeparator).frame(height: 1)
                }
            }
        }
    }

    // MARK: - Ammo content

    @ViewBuilder
    private var ammoContent: some View {
        if allAmmo.isEmpty {
            LgEmptyState(title: "No Ammo", message: "Tap + to track your ammo stock.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(allAmmo) { ammo in
                    AmmoRow(ammo: ammo) {
                        haptic(.light)
                        selectedAmmo = ammo
                    } onMenu: {
                        haptic(.medium)
                        ammoToDelete = ammo
                    }
                    Rectangle().fill(Color.lgSeparator).frame(height: 1)
                }
            }
        }
    }

    // MARK: - Actions

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
        firearm.isRetired = true; firearm.retiredAt = Date()
        persist(successToast: ToastConfig(title: "Retired", message: "\(firearm.displayName) retired.", type: .info))
    }

    private func unretireFirearm(_ firearm: Firearm) {
        haptic(.medium)
        firearm.isRetired = false; firearm.retiredAt = nil
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
}

// MARK: - FirearmRow

struct FirearmRow: View {
    let firearm: Firearm
    let onTap: () -> Void
    let onMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(firearm.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.lgText)
                    .lineLimit(1)
                Spacer()
                if firearm.isOverLimit {
                    LgBadge(label: "SERVICE DUE", color: .lgDanger)
                } else if firearm.isNearLimit {
                    LgBadge(label: "SERVICE SOON", color: .lgWarning)
                }
                Button(action: onMenu) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18.5, weight: .semibold))
                        .foregroundStyle(Color.lgTextTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(firearm.displayName) options")
            }
            let subtitle = [firearm.category?.rawValue, firearm.primaryAmmo?.displayLabel].compactMap { $0 }.joined(separator: " · ")
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.lgTextSecondary)
            }
            HStack {
                Text("\(firearm.activeRounds) rounds since service")
                    .font(.lgMono(14.5))
                    .foregroundStyle(Color.lgTextSecondary)
                Spacer()
                Text("/ \(firearm.roundsBeforeService)")
                    .font(.lgMono(13))
                    .foregroundStyle(Color.lgTextTertiary)
            }
            LgProgressBar(
                percent: firearm.progressPercent,
                color: firearm.isOverLimit ? .lgDanger : firearm.isNearLimit ? .lgWarning : .lgAccent
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - AmmoRow

struct AmmoRow: View {
    let ammo: AmmoEntry
    let onTap: () -> Void
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ammo.brand)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(Color.lgText)
                Text([ammo.displayLabel, ammo.category?.rawValue].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.lgTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(ammo.quantity)")
                    .font(.lgMono(22, weight: .bold))
                    .foregroundStyle(ammo.isLowStock ? Color.lgDanger : Color.lgText)
                Text("ROUNDS")
                    .font(.system(size: 11))
                    .tracking(0.5)
                    .foregroundStyle(Color.lgTextTertiary)
                if ammo.isLowStock {
                    Text("LOW STOCK")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.lgDanger)
                }
            }
            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18.5, weight: .semibold))
                    .foregroundStyle(Color.lgTextTertiary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(ammo.brand) options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - AddEditFirearmSheet

struct AddEditFirearmSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let firearm: Firearm?
    let allAmmo: [AmmoEntry]
    let onComplete: (ToastConfig) -> Void

    @State private var manufacturer = ""
    @State private var model = ""
    @State private var selectedAmmo: AmmoEntry? = nil
    @State private var serialNumber = ""
    @State private var selectedCategory: FirearmCategory? = nil
    @State private var roundsBeforeServiceText = "500"
    @State private var roundsBeforeServiceIsDefault = true
    @State private var notes = ""
    @State private var validationError: String? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var firearmImage: UIImage? = nil
    @State private var showAmmoPicker = false
    @State private var showCategoryPicker = false
    @State private var showPhotoSourceDialog = false
    @State private var showCamera = false
    @State private var showLibraryPickerTrigger = false
    @FocusState private var roundsFieldFocused: Bool

    private var isEditing: Bool { firearm != nil }

    var body: some View {
        LgSheetScaffold(
            title: isEditing ? "Edit Firearm" : "Add Firearm",
            leftLabel: "Cancel", leftAction: { dismiss() },
            rightLabel: "Save", rightAction: save
        ) {
            if let err = validationError {
                Text(err)
                    .font(.system(size: 14.5))
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
                        Text((selectedCategory?.rawValue ?? "None") + " ›").foregroundStyle(Color.lgTextSecondary)
                    }
                    .font(.system(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())
                .accessibilityLabel("Category, \(selectedCategory?.rawValue ?? "None")")
            }

            Text("Ammo & Service").lgSectionLabelStyle().padding(.top, 18)
            Button { showAmmoPicker = true } label: {
                HStack {
                    Text("Primary Ammo").foregroundStyle(Color.lgText)
                    Spacer()
                    Text((selectedAmmo?.displayLabel ?? "None") + " ›").foregroundStyle(Color.lgTextSecondary)
                }
                .font(.system(size: 15.5))
            }
            .buttonStyle(LgFieldButtonStyle())
            .accessibilityLabel("Primary Ammo, \(selectedAmmo?.displayLabel ?? "None")")

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
                        let digits = String(new.filter { $0.isNumber }.prefix(6))
                        if digits != new { roundsBeforeServiceText = digits }
                    }
            }
            Text("How many rounds before cleaning & oiling. 500 is a safe starting point for most handguns.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.lgTextTertiary)
                .lineSpacing(2)

            Text("Notes").lgSectionLabelStyle().padding(.top, 18)
            TextField("Optional notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .font(.system(size: 15.5))
                .lgTextFieldStyle()
                .onChange(of: notes) { _, new in
                    if new.count > 500 { notes = String(new.prefix(500)) }
                }

            Text("Photo").lgSectionLabelStyle().padding(.top, 18)
            Button {
                showPhotoSourceDialog = true
            } label: {
                if let img = firearmImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .clipped()
                } else {
                    Text("Add Firearm Image")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.lgTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Color.lgDashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                }
            }
            .buttonStyle(.plain)
            .confirmationDialog("Add Firearm Image", isPresented: $showPhotoSourceDialog, titleVisibility: .hidden) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { selectedPhotoItem = nil; showLibraryPickerTrigger = true }
                if firearmImage != nil {
                    Button("Remove Photo", role: .destructive) { firearmImage = nil }
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showLibraryPickerTrigger, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        firearmImage = img
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { captured in
                    if let captured { firearmImage = captured }
                    showCamera = false
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showAmmoPicker) {
            SelectionSheet(
                title: "Select Ammo",
                options: [PickerOption(id: "none", title: "None", subtitle: nil, isSelected: selectedAmmo == nil) {
                    selectedAmmo = nil; showAmmoPicker = false
                }] + allAmmo.map { ammo in
                    PickerOption(id: ammo.id, title: ammo.brand, subtitle: ammo.displayLabel, isSelected: selectedAmmo?.id == ammo.id) {
                        selectedAmmo = ammo; showAmmoPicker = false
                    }
                },
                onCancel: { showAmmoPicker = false }
            )
        }
        .sheet(isPresented: $showCategoryPicker) {
            SelectionSheet(
                title: "Select Category",
                options: [PickerOption(id: "none", title: "None", subtitle: nil, isSelected: selectedCategory == nil) {
                    selectedCategory = nil; showCategoryPicker = false
                }] + FirearmCategory.allCases.map { cat in
                    PickerOption(id: cat.id, title: cat.rawValue, subtitle: nil, isSelected: selectedCategory == cat) {
                        selectedCategory = cat; showCategoryPicker = false
                    }
                },
                onCancel: { showCategoryPicker = false }
            )
        }
        .onAppear { populateIfEditing() }
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

    private func populateIfEditing() {
        guard let f = firearm else { return }
        manufacturer = f.manufacturer; model = f.model
        selectedAmmo = f.primaryAmmo
        serialNumber = f.serialNumber ?? ""
        selectedCategory = f.category
        roundsBeforeServiceText = "\(f.roundsBeforeService)"
        roundsBeforeServiceIsDefault = false
        notes = f.notes ?? ""
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
        let rbs = Int(roundsBeforeServiceText.trimmingCharacters(in: .whitespaces)) ?? 500

        if let f = firearm {
            f.manufacturer = mfr; f.model = mdl
            f.primaryAmmo = selectedAmmo
            f.serialNumber = serialNumber.isEmpty ? nil : serialNumber
            f.category = selectedCategory
            f.roundsBeforeService = rbs
            f.notes = notes.isEmpty ? nil : notes
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
            do { try modelContext.save() } catch {
                validationError = "Could not save changes. Please try again."; return
            }
            dismiss()
            onComplete(ToastConfig(title: "Added", message: "\(f.displayName) added.", type: .success))
        }
    }
}

// MARK: - AddEditAmmoSheet

struct AddEditAmmoSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let ammo: AmmoEntry?
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
    @FocusState private var thresholdFieldFocused: Bool

    private var isEditing: Bool { ammo != nil }

    var body: some View {
        LgSheetScaffold(
            title: isEditing ? "Edit Ammo" : "Add Ammo",
            leftLabel: "Cancel", leftAction: { dismiss() },
            rightLabel: "Save", rightAction: save
        ) {
            if let err = validationError {
                Text(err)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.lgDanger)
                    .padding(.top, 12)
            }

            Text("Details").lgSectionLabelStyle().padding(.top, 16)
            VStack(spacing: 10) {
                labeledField("Caliber", text: $caliber, placeholder: "e.g. 9mm", maxLength: 30)
                labeledField("Brand", text: $brand, placeholder: "e.g. Federal", maxLength: 60)
                numericField("Quantity", text: $quantityText, placeholder: "e.g. 200", maxDigits: 6)
                numericField("Grains", text: $grainsText, placeholder: "e.g. 115", maxDigits: 4)
                labeledField("Type", text: $ammoType, placeholder: "e.g. FMJ, JHP", maxLength: 30)
                Button { showCategoryPicker = true } label: {
                    HStack {
                        Text("Firearm Category").foregroundStyle(Color.lgText)
                        Spacer()
                        Text((selectedCategory?.rawValue ?? "None") + " ›").foregroundStyle(Color.lgTextSecondary)
                    }
                    .font(.system(size: 15.5))
                }
                .buttonStyle(LgFieldButtonStyle())
                .accessibilityLabel("Firearm Category, \(selectedCategory?.rawValue ?? "None")")
            }

            Text("Stock Alert").lgSectionLabelStyle().padding(.top, 18)
            numericField("Low Stock Threshold", text: $thresholdText, placeholder: "20", maxDigits: 6, isDefault: $thresholdIsDefault, focus: $thresholdFieldFocused)
        }
        .sheet(isPresented: $showCategoryPicker) {
            SelectionSheet(
                title: "Select Category",
                options: [PickerOption(id: "none", title: "None", subtitle: nil, isSelected: selectedCategory == nil) {
                    selectedCategory = nil; showCategoryPicker = false
                }] + FirearmCategory.allCases.map { cat in
                    PickerOption(id: cat.id, title: cat.rawValue, subtitle: nil, isSelected: selectedCategory == cat) {
                        selectedCategory = cat; showCategoryPicker = false
                    }
                },
                onCancel: { showCategoryPicker = false }
            )
        }
        .onAppear { populateIfEditing() }
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, maxLength: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LgFieldLabel(text: label)
            TextField(placeholder, text: text)
                .font(.system(size: 16.5))
                .lgTextFieldStyle()
                .onChange(of: text.wrappedValue) { _, new in
                    if new.count > maxLength { text.wrappedValue = String(new.prefix(maxLength)) }
                }
        }
    }

    @ViewBuilder
    private func numericField(
        _ label: String, text: Binding<String>, placeholder: String, maxDigits: Int,
        isDefault: Binding<Bool>? = nil, focus: FocusState<Bool>.Binding? = nil
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
                let digits = String(new.filter { $0.isNumber }.prefix(maxDigits))
                if digits != new { text.wrappedValue = digits }
            }
        }
    }

    private func populateIfEditing() {
        guard let a = ammo else { return }
        caliber = a.caliber; brand = a.brand
        quantityText = "\(a.quantity)"
        grainsText = a.grains.map { "\($0)" } ?? ""
        ammoType = a.ammoType ?? ""
        selectedCategory = a.category
        thresholdText = "\(a.lowStockThreshold)"
        thresholdIsDefault = false
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
        guard let qty = Int(quantityText.trimmingCharacters(in: .whitespaces)), qty >= 0 else {
            validationError = "Enter a valid quantity."
            return
        }
        let grains = Int(grainsText.trimmingCharacters(in: .whitespaces))
        let threshold = Int(thresholdText.trimmingCharacters(in: .whitespaces)) ?? 20

        if let a = ammo {
            a.caliber = cal; a.brand = br; a.quantity = qty
            a.grains = grains
            a.ammoType = ammoType.isEmpty ? nil : ammoType
            a.category = selectedCategory
            a.lowStockThreshold = threshold
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
            try? modelContext.save()
            dismiss()
            onComplete(ToastConfig(title: "Added", message: "\(a.displayLabel) added.", type: .success))
        }
    }
}

// MARK: - FirearmDetailSheet

struct FirearmDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let firearm: Firearm
    let allAmmo: [AmmoEntry]
    let onToast: (ToastConfig) -> Void

    @State private var showEditSheet = false
    @State private var showServiceConfirm = false

    var body: some View {
        LgSheetScaffold(
            title: firearm.displayName,
            leftLabel: "Done", leftAction: { dismiss() },
            rightLabel: "Edit", rightAction: { showEditSheet = true }
        ) {
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
                        statRow("Primary Ammo", ammo.displayLabel)
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

            let history = firearm.serviceRecords.sorted(by: { $0.servicedAt > $1.servicedAt })
            if !history.isEmpty {
                Text("Service History").lgSectionLabelStyle().padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(history) { record in
                        HStack {
                            Text(record.servicedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 15))
                                .foregroundStyle(Color.lgText)
                            Spacer()
                            Text("\(record.roundsAtService) rounds")
                                .font(.lgMono(14))
                                .foregroundStyle(Color.lgTextSecondary)
                        }
                        .padding(.vertical, 10)
                        Rectangle().fill(Color.lgSeparator).frame(height: 1)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditFirearmSheet(firearm: firearm, allAmmo: allAmmo) { onToast($0) }
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
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Color.lgTextSecondary)
            Spacer()
            Text(value)
                .font(mono ? .lgMono(17, weight: .bold) : .system(size: 15))
                .foregroundStyle(Color.lgText)
        }
    }

    private func markServiced() {
        let record = ServiceRecord(servicedAt: Date(), roundsAtService: firearm.activeRounds)
        record.firearm = firearm
        modelContext.insert(record)
        for entry in firearm.logEntries where entry.servicedAt == nil {
            entry.servicedAt = Date()
        }
        try? modelContext.save()
        haptic(.success)
        onToast(ToastConfig(title: "Serviced", message: "\(firearm.displayName) marked as serviced.", type: .success))
    }
}
