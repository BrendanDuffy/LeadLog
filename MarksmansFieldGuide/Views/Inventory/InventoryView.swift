import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Inventory Tab Enum

private enum InventoryTab { case firearms, ammo }

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

    private var displayedFirearms: [Firearm] {
        allFirearms.filter { showRetired ? $0.isRetired : !$0.isRetired }
    }

    var body: some View {
        ZStack(alignment: .top) {
            W.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                WesternHeader(title: "Inventory")
                GoldDivider()

                // FIREARMS / AMMO segment
                HStack(spacing: 0) {
                    segmentButton(label: "FIREARMS", tab: .firearms)
                    segmentButton(label: "AMMO", tab: .ammo)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

                // Content area
                Group {
                    if selectedTab == .firearms {
                        firearmsContent
                    } else {
                        ammoContent
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }

            // Toast
            if let t = toast {
                WesternToastView(config: t) { self.toast = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast?.id)
        .sheet(isPresented: $showAddFirearmSheet) {
            AddEditFirearmSheet(firearm: nil) { toast = $0 }
        }
        .sheet(isPresented: $showAddAmmoSheet) {
            AddEditAmmoSheet(ammo: nil) { toast = $0 }
        }
        .sheet(item: $selectedFirearm) { firearm in
            FirearmDetailView(firearm: firearm) { toast = $0 }
        }
        .sheet(item: $selectedAmmo) { ammo in
            AddEditAmmoSheet(ammo: ammo) { toast = $0 }
        }
    }

    // MARK: - Firearms content

    @ViewBuilder
    private var firearmsContent: some View {
        if displayedFirearms.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image("tabbar-icon-revolver")
                    .resizable().scaledToFit()
                    .frame(width: 64, height: 64).opacity(0.35)
                Text(showRetired ? "No retired firearms" : "No firearms yet")
                    .font(.rye(18)).foregroundStyle(W.muted)
                if !showRetired {
                    Text("Tap + ADD FIREARM to get started.")
                        .font(.playfairRegular(14))
                        .foregroundStyle(W.muted.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer(); Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(displayedFirearms) { firearm in
                        FirearmRowCard(firearm: firearm)
                            .onTapGesture { haptic(.light); selectedFirearm = firearm }
                            .contextMenu {
                                if !firearm.isRetired {
                                    Button { retireFirearm(firearm) } label: {
                                        Label("Retire Firearm", systemImage: "archivebox")
                                    }
                                } else {
                                    Button { unretireFirearm(firearm) } label: {
                                        Label("Restore to Active", systemImage: "arrow.uturn.backward")
                                    }
                                }
                                Button(role: .destructive) { deleteFirearm(firearm) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(16)
                .padding(.bottom, 72)
            }
        }
    }

    // MARK: - Ammo content

    @ViewBuilder
    private var ammoContent: some View {
        if allAmmo.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Text("No ammo in inventory")
                    .font(.rye(18)).foregroundStyle(W.muted)
                Text("Tap + ADD AMMO to track your stock.")
                    .font(.playfairRegular(14))
                    .foregroundStyle(W.muted.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer(); Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(allAmmo) { ammo in
                        AmmoRowCard(ammo: ammo)
                            .onTapGesture { haptic(.light); selectedAmmo = ammo }
                            .contextMenu {
                                Button(role: .destructive) { deleteAmmo(ammo) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(16)
                .padding(.bottom, 72)
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
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
                        Label("Retired Firearms", systemImage: showRetired ? "checkmark" : "")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 14))
                        Text(showRetired ? "Retired" : "Active")
                            .font(.rye(12))
                    }
                    .foregroundStyle(W.brass)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(W.leather.opacity(0.9))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(W.brass.opacity(0.4), lineWidth: 1))
                    )
                }
            }

            Button {
                haptic(.medium)
                selectedTab == .firearms ? (showAddFirearmSheet = true) : (showAddAmmoSheet = true)
            } label: {
                Text(selectedTab == .firearms ? "+ ADD FIREARM" : "+ ADD AMMO")
                    .font(.rye(14))
                    .tracking(1)
                    .foregroundStyle(W.brass)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(W.brass)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .background(W.bg)
    }

    // MARK: - Segment button

    @ViewBuilder
    private func segmentButton(label: String, tab: InventoryTab) -> some View {
        let selected = selectedTab == tab
        Button {
            haptic(.light)
            withAnimation { selectedTab = tab }
        } label: {
            Text(label)
                .font(.rye(13)).tracking(1)
                .foregroundStyle(selected ? W.brass : W.muted.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? W.leather.opacity(0.8) : Color.clear)
                .overlay(Rectangle().fill(selected ? W.brass : Color.clear).frame(height: 2),
                         alignment: .bottom)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func retireFirearm(_ firearm: Firearm) {
        haptic(.medium)
        firearm.isRetired = true; firearm.retiredAt = Date()
        try? modelContext.save()
        toast = ToastConfig(title: "Retired", message: "\(firearm.displayName) retired.", type: .info)
    }

    private func unretireFirearm(_ firearm: Firearm) {
        haptic(.medium)
        firearm.isRetired = false; firearm.retiredAt = nil
        try? modelContext.save()
        toast = ToastConfig(title: "Restored", message: "\(firearm.displayName) restored to active.", type: .info)
    }

    private func deleteFirearm(_ firearm: Firearm) {
        haptic(.medium)
        modelContext.delete(firearm)
        try? modelContext.save()
    }

    private func deleteAmmo(_ ammo: AmmoEntry) {
        haptic(.medium)
        modelContext.delete(ammo)
        try? modelContext.save()
    }
}

// MARK: - FirearmRowCard

struct FirearmRowCard: View {
    let firearm: Firearm

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(firearm.displayName)
                        .font(.rye(16)).foregroundStyle(W.brass)
                    if let caliber = firearm.caliber {
                        Text(caliber)
                            .font(.playfairRegular(13)).foregroundStyle(W.muted)
                    }
                }
                Spacer()
                if firearm.isOverLimit {
                    StatusBadge(label: "SERVICE DUE", color: W.error)
                } else if firearm.isNearLimit {
                    StatusBadge(label: "SERVICE SOON", color: Color(rgb: 0xB8860B))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(W.muted.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(firearm.activeRounds) rounds since service")
                        .font(.playfairRegular(12)).foregroundStyle(W.muted.opacity(0.7))
                    Spacer()
                    Text("/ \(firearm.roundsBeforeService)")
                        .font(.playfairRegular(12)).foregroundStyle(W.muted.opacity(0.5))
                }
                ServiceProgressBar(
                    percent: firearm.progressPercent,
                    isOver: firearm.isOverLimit,
                    isNear: firearm.isNearLimit
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(W.leather.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(W.brass.opacity(0.3), lineWidth: 1))
        )
    }
}

// MARK: - AmmoRowCard

struct AmmoRowCard: View {
    let ammo: AmmoEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ammo.brand)
                    .font(.rye(15)).foregroundStyle(W.brass)
                HStack(spacing: 6) {
                    Text(ammo.caliber)
                        .font(.playfairBold(13)).foregroundStyle(W.text)
                    if let grains = ammo.grains {
                        Text("·").foregroundStyle(W.muted.opacity(0.4))
                        Text("\(grains)gr").font(.playfairRegular(12)).foregroundStyle(W.muted)
                    }
                    if let type = ammo.ammoType {
                        Text("·").foregroundStyle(W.muted.opacity(0.4))
                        Text(type).font(.playfairRegular(12)).foregroundStyle(W.muted)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(ammo.quantity)")
                    .font(.rye(18)).foregroundStyle(ammo.isLowStock ? W.error : W.brass)
                Text("rounds")
                    .font(.playfairRegular(11)).foregroundStyle(W.muted.opacity(0.6))
                if ammo.isLowStock {
                    StatusBadge(label: "LOW STOCK", color: W.error)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(W.muted.opacity(0.5))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(W.leather.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(ammo.isLowStock ? W.error.opacity(0.4) : W.brass.opacity(0.3), lineWidth: 1))
        )
    }
}

// MARK: - ServiceProgressBar

struct ServiceProgressBar: View {
    let percent: Double
    let isOver: Bool
    let isNear: Bool

    private var barColor: Color {
        if isOver { return W.error }
        if isNear { return Color(rgb: 0xB8860B) }
        return W.brass.opacity(0.8)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(W.muted.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(percent / 100.0))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(0.6), lineWidth: 1)
                    .background(color.opacity(0.1).clipShape(RoundedRectangle(cornerRadius: 4)))
            )
    }
}

// MARK: - AddEditFirearmSheet

struct AddEditFirearmSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let firearm: Firearm?
    let onComplete: (ToastConfig) -> Void

    @State private var manufacturer = ""
    @State private var model = ""
    @State private var caliber = ""
    @State private var serialNumber = ""
    @State private var roundsBeforeServiceText = "500"
    @State private var notes = ""
    @State private var validationError: String? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var firearmsImage: UIImage? = nil

    private var isEditing: Bool { firearm != nil }

    var body: some View {
        VStack(spacing: 0) {
            westernSheetHeader(title: isEditing ? "EDIT FIREARM" : "ADD FIREARM", onSave: save, onDismiss: { dismiss() })
            GoldDivider()

            ScrollView {
                VStack(spacing: 14) {
                    if let err = validationError { errorBanner(err) }

                    ParchmentInputField(label: "Manufacturer", text: $manufacturer, placeholder: "e.g. Glock")
                    ParchmentInputField(label: "Model", text: $model, placeholder: "e.g. 19 Gen 5")
                    ParchmentInputField(label: "Caliber", text: $caliber, placeholder: "e.g. 9mm")
                    ParchmentInputField(label: "Serial Number", text: $serialNumber, placeholder: "Optional")
                    ParchmentInputField(label: "Rounds Before Service", text: $roundsBeforeServiceText,
                                        placeholder: "500", keyboardType: .numberPad)
                    ParchmentInputField(label: "Notes", text: $notes, placeholder: "Optional notes", isMultiline: true)

                    // Photo picker
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        if let img = firearmsImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(W.brass.opacity(0.5), lineWidth: 1))
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "camera")
                                    .font(.system(size: 16))
                                Text("+ ADD FIREARM IMAGE")
                                    .font(.rye(13))
                                    .tracking(1)
                            }
                            .foregroundStyle(W.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                    .foregroundStyle(W.muted)
                            )
                        }
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                firearmsImage = img
                            }
                        }
                    }

                    Spacer().frame(height: 24)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("card-leather-v2").resizable().scaledToFill().ignoresSafeArea()
        )
        .onAppear { populateIfEditing() }
    }

    private func populateIfEditing() {
        guard let f = firearm else { return }
        manufacturer = f.manufacturer; model = f.model
        caliber = f.caliber ?? ""; serialNumber = f.serialNumber ?? ""
        roundsBeforeServiceText = "\(f.roundsBeforeService)"
        notes = f.notes ?? ""
        if let path = f.photoPath { firearmsImage = ImageStorage.load(path: path) }
    }

    private func save() {
        let mfr = manufacturer.trimmingCharacters(in: .whitespaces)
        let mdl = model.trimmingCharacters(in: .whitespaces)
        guard !mfr.isEmpty else { validationError = "Manufacturer is required."; return }
        guard !mdl.isEmpty else { validationError = "Model is required."; return }
        let rbs = Int(roundsBeforeServiceText.trimmingCharacters(in: .whitespaces)) ?? 500

        if let f = firearm {
            f.manufacturer = mfr; f.model = mdl
            f.caliber = caliber.isEmpty ? nil : caliber
            f.serialNumber = serialNumber.isEmpty ? nil : serialNumber
            f.roundsBeforeService = rbs
            f.notes = notes.isEmpty ? nil : notes
            if let img = firearmsImage {
                if let oldPath = f.photoPath { ImageStorage.delete(path: oldPath) }
                f.photoPath = ImageStorage.save(img, named: "firearm_\(f.id)")
            }
            try? modelContext.save()
            dismiss()
            onComplete(ToastConfig(title: "Updated", message: "\(f.displayName) updated.", type: .success))
        } else {
            let f = Firearm(manufacturer: mfr, model: mdl,
                            caliber: caliber.isEmpty ? nil : caliber,
                            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
                            roundsBeforeService: rbs,
                            notes: notes.isEmpty ? nil : notes)
            if let img = firearmsImage {
                f.photoPath = ImageStorage.save(img, named: "firearm_\(f.id)")
            }
            modelContext.insert(f)
            try? modelContext.save()
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
    @State private var thresholdText = "50"
    @State private var validationError: String? = nil

    private var isEditing: Bool { ammo != nil }

    var body: some View {
        VStack(spacing: 0) {
            westernSheetHeader(title: isEditing ? "EDIT AMMO" : "ADD AMMO", onSave: save, onDismiss: { dismiss() })
            GoldDivider()

            ScrollView {
                VStack(spacing: 14) {
                    if let err = validationError { errorBanner(err) }

                    ParchmentInputField(label: "Caliber", text: $caliber, placeholder: "e.g. 9mm")
                    ParchmentInputField(label: "Brand", text: $brand, placeholder: "e.g. Federal")
                    ParchmentInputField(label: "Quantity", text: $quantityText,
                                        placeholder: "e.g. 200", keyboardType: .numberPad)
                    ParchmentInputField(label: "Grains", text: $grainsText,
                                        placeholder: "e.g. 115", keyboardType: .numberPad)
                    ParchmentInputField(label: "Type", text: $ammoType, placeholder: "e.g. FMJ, JHP")
                    ParchmentInputField(label: "Low Stock Alert", text: $thresholdText,
                                        placeholder: "50", keyboardType: .numberPad)

                    Spacer().frame(height: 24)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("card-leather-v2").resizable().scaledToFill().ignoresSafeArea()
        )
        .onAppear { populateIfEditing() }
    }

    private func populateIfEditing() {
        guard let a = ammo else { return }
        caliber = a.caliber; brand = a.brand
        quantityText = "\(a.quantity)"
        grainsText = a.grains.map { "\($0)" } ?? ""
        ammoType = a.ammoType ?? ""
        thresholdText = "\(a.lowStockThreshold)"
    }

    private func save() {
        let cal = caliber.trimmingCharacters(in: .whitespaces)
        let br = brand.trimmingCharacters(in: .whitespaces)
        guard !cal.isEmpty else { validationError = "Caliber is required."; return }
        guard !br.isEmpty else { validationError = "Brand is required."; return }
        guard let qty = Int(quantityText.trimmingCharacters(in: .whitespaces)), qty >= 0 else {
            validationError = "Enter a valid quantity."
            return
        }
        let grains = Int(grainsText.trimmingCharacters(in: .whitespaces))
        let threshold = Int(thresholdText.trimmingCharacters(in: .whitespaces)) ?? 50

        if let a = ammo {
            a.caliber = cal; a.brand = br; a.quantity = qty
            a.grains = grains
            a.ammoType = ammoType.isEmpty ? nil : ammoType
            a.lowStockThreshold = threshold
            try? modelContext.save()
            dismiss()
            onComplete(ToastConfig(title: "Updated", message: "\(a.displayLabel) updated.", type: .success))
        } else {
            let a = AmmoEntry(caliber: cal, brand: br, quantity: qty)
            a.grains = grains
            a.ammoType = ammoType.isEmpty ? nil : ammoType
            a.lowStockThreshold = threshold
            modelContext.insert(a)
            try? modelContext.save()
            dismiss()
            onComplete(ToastConfig(title: "Added", message: "\(a.displayLabel) added.", type: .success))
        }
    }
}

// MARK: - FirearmDetailView

struct FirearmDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let firearm: Firearm
    let onToast: (ToastConfig) -> Void

    @State private var showEditSheet = false
    @State private var showServiceConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                W.leather
                Text(firearm.displayName)
                    .font(.rye(18)).foregroundStyle(W.brass)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Button("Done") { dismiss() }
                        .font(.rye(14)).foregroundStyle(W.muted)
                    Spacer()
                    Button("Edit") { showEditSheet = true }
                        .font(.rye(14)).foregroundStyle(W.brass)
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 56)

            GoldDivider()

            ScrollView {
                VStack(spacing: 14) {
                    statsCard

                    if !firearm.isRetired {
                        Button {
                            haptic(.medium)
                            showServiceConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                Text("MARK AS SERVICED").tracking(1)
                            }
                            .font(.rye(14))
                            .foregroundStyle(firearm.isOverLimit ? W.error : W.brass)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(firearm.isOverLimit ? W.error : W.brass.opacity(0.5), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }

                    if !firearm.serviceRecords.isEmpty {
                        sectionHeader("SERVICE HISTORY")
                        VStack(spacing: 8) {
                            ForEach(firearm.serviceRecords.sorted(by: { $0.servicedAt > $1.servicedAt })) { record in
                                serviceRecordRow(record)
                            }
                        }
                    }

                    let recent = Array(firearm.logEntries.sorted(by: { $0.date > $1.date }).prefix(10))
                    if !recent.isEmpty {
                        sectionHeader("RECENT SESSIONS")
                        VStack(spacing: 8) {
                            ForEach(recent) { entry in sessionEntryRow(entry) }
                        }
                    }

                    Spacer().frame(height: 32)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("card-leather-v2").resizable().scaledToFill().ignoresSafeArea()
        )
        .sheet(isPresented: $showEditSheet) {
            AddEditFirearmSheet(firearm: firearm) { onToast($0) }
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

    private var statsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                statItem(value: "\(firearm.activeRounds)", label: "Since\nService")
                Divider().background(W.brass.opacity(0.3)).frame(width: 1)
                statItem(value: "\(firearm.roundsBeforeService)", label: "Service\nInterval")
                Divider().background(W.brass.opacity(0.3)).frame(width: 1)
                statItem(value: "\(firearm.logEntries.reduce(0) { $0 + $1.rounds })", label: "Total\nRounds")
            }

            VStack(spacing: 4) {
                HStack {
                    Text("\(Int(firearm.progressPercent))% to service")
                        .font(.playfairRegular(12)).foregroundStyle(W.muted.opacity(0.7))
                    Spacer()
                    if firearm.isOverLimit {
                        StatusBadge(label: "SERVICE DUE", color: W.error)
                    } else if firearm.isNearLimit {
                        StatusBadge(label: "SERVICE SOON", color: Color(rgb: 0xB8860B))
                    }
                }
                ServiceProgressBar(percent: firearm.progressPercent,
                                   isOver: firearm.isOverLimit, isNear: firearm.isNearLimit)
            }

            if let cal = firearm.caliber {
                detailRow(label: "Caliber", value: cal)
            }
            if let ser = firearm.serialNumber {
                detailRow(label: "Serial", value: ser)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(W.leather.opacity(0.7))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(W.brass.opacity(0.3), lineWidth: 1)))
    }

    @ViewBuilder private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.rye(20)).foregroundStyle(W.brass)
            Text(label).font(.playfairRegular(11)).foregroundStyle(W.muted.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    @ViewBuilder private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.playfairBold(13)).foregroundStyle(W.muted)
            Spacer()
            Text(value).font(.playfairRegular(14)).foregroundStyle(W.text)
        }
    }

    @ViewBuilder private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text).font(.rye(12)).tracking(1).foregroundStyle(W.brass.opacity(0.7))
            Rectangle().fill(W.brass.opacity(0.2)).frame(height: 1)
        }
    }

    @ViewBuilder private func serviceRecordRow(_ record: ServiceRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.servicedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.playfairBold(14)).foregroundStyle(W.text)
                if let note = record.note, !note.isEmpty {
                    Text(note).font(.playfairRegular(12)).foregroundStyle(W.muted)
                }
            }
            Spacer()
            Text("\(record.roundsAtService) rounds")
                .font(.playfairRegular(13)).foregroundStyle(W.muted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(W.leather.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(W.brass.opacity(0.2), lineWidth: 1)))
    }

    @ViewBuilder private func sessionEntryRow(_ entry: LogEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.playfairBold(14)).foregroundStyle(W.text)
                if let ammo = entry.ammoSnapshot {
                    Text(ammo).font(.playfairRegular(12)).foregroundStyle(W.muted).lineLimit(1)
                }
            }
            Spacer()
            Text("\(entry.rounds) rds").font(.playfairBold(13)).foregroundStyle(W.brass)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(W.leather.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(W.brass.opacity(0.2), lineWidth: 1)))
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

// MARK: - Shared sheet helpers (private to this file)

private func westernSheetHeader(title: String, onSave: @escaping () -> Void, onDismiss: @escaping () -> Void) -> some View {
    ZStack {
        W.leather
        Text(title)
            .font(.rye(20))
            .foregroundStyle(W.brass)
            .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack {
            Button("Cancel", action: onDismiss)
                .font(.rye(14))
                .foregroundStyle(W.muted)
            Spacer()
            Button("Save", action: onSave)
                .font(.rye(14))
                .foregroundStyle(W.brass)
        }
        .padding(.horizontal, 20)
    }
    .frame(height: 56)
}

private func errorBanner(_ message: String) -> some View {
    Text(message)
        .font(.playfairRegular(13)).foregroundStyle(W.error)
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(W.error.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(W.error.opacity(0.4), lineWidth: 1))
}
