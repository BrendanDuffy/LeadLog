import SwiftUI
import SwiftData

// MARK: - Session Summary

struct SessionSummary: Identifiable {
    let id: String
    let date: Date
    let entries: [LogEntry]

    var totalRounds: Int { entries.reduce(0) { $0 + $1.rounds } }

    var firearmNames: [String] {
        var seen = Set<String>()
        return entries.compactMap { entry -> String? in
            let name = entry.firearmNameSnapshot ?? entry.firearm?.displayName ?? "Unknown"
            return seen.insert(name).inserted ? name : nil
        }
    }

    var hasPhotos: Bool {
        entries.contains { $0.photoPath != nil && !($0.photoPath?.isEmpty ?? true) }
    }
}

// MARK: - Grouping

enum HistoryGroupMode: String, CaseIterable {
    case firearm = "Firearm"
    case ammo = "Ammo"
    case date = "Date"
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
    @Query(sort: \LogEntry.date, order: .reverse) private var allEntries: [LogEntry]

    @State private var searchText = ""
    @State private var groupMode: HistoryGroupMode = .firearm
    @State private var selectedSession: SessionSummary? = nil
    @State private var sessions: [SessionSummary] = []

    private var filteredSessions: [SessionSummary] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return sessions }
        let q = searchText.lowercased()
        return sessions.filter { session in
            session.firearmNames.contains(where: { $0.lowercased().contains(q) }) ||
            session.date.formatted(date: .long, time: .omitted).lowercased().contains(q)
        }
    }

    private func rebuildSessions() {
        let grouped = Dictionary(grouping: allEntries) { $0.sessionId }
        sessions = grouped.map { id, entries in
            SessionSummary(id: id, date: entries.first?.date ?? Date(), entries: entries)
        }
        .sorted(by: { $0.date > $1.date })
    }

    private func buildGroups(keyedBy key: (LogEntry) -> String?, fallback: String) -> [HistoryEntryGroup] {
        let grouped = Dictionary(grouping: allEntries) { entry -> String in
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
        buildGroups(keyedBy: { $0.ammoSnapshot }, fallback: "No Ammo Recorded")
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

    private func session(for entry: LogEntry) -> SessionSummary? {
        sessions.first(where: { $0.id == entry.sessionId })
    }

    private func crossReference(for entry: LogEntry) -> String? {
        switch groupMode {
        case .firearm:
            guard let ammo = entry.ammoSnapshot, !ammo.isEmpty else { return nil }
            return ammo
        case .ammo:
            return entry.firearmNameSnapshot ?? entry.firearm?.displayName
        case .date:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                if sessions.isEmpty {
                    LgEmptyState(title: "No Sessions Yet", message: "Log your first session to see it here.")
                } else {
                    switch groupMode {
                    case .date:
                        if filteredSessions.isEmpty {
                            LgEmptyState(title: "No Results", message: "No sessions match your search.")
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredSessions) { session in
                                    SessionRow(session: session) {
                                        haptic(.light)
                                        selectedSession = session
                                    }
                                    Rectangle().fill(Color.lgSeparator).frame(height: 1)
                                }
                            }
                        }
                    case .firearm, .ammo:
                        let groups = filteredGroups(groupMode == .firearm ? firearmGroups : ammoGroups)
                        if groups.isEmpty {
                            LgEmptyState(title: "No Results", message: "No sessions match your search.")
                        } else {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                ForEach(groups) { group in
                                    Section {
                                        ForEach(group.entries) { entry in
                                            HistoryEntryRow(entry: entry, crossReference: crossReference(for: entry)) {
                                                haptic(.light)
                                                selectedSession = session(for: entry)
                                            }
                                            Rectangle().fill(Color.lgSeparator).frame(height: 1)
                                        }
                                    } header: {
                                        groupHeader(group)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(Color.lgBackground)
        }
        .background(Color.lgBackground)
        .sheet(item: $selectedSession) { session in
            SessionDetailSheet(session: session)
        }
        .onChange(of: allEntries, initial: true) { _, _ in rebuildSessions() }
    }

    @ViewBuilder
    private func groupHeader(_ group: HistoryEntryGroup) -> some View {
        HStack {
            Text(group.title.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.lgText)
                .lineLimit(1)
            Spacer()
            Text("\(group.totalRounds) rds · \(group.entries.count) \(group.entries.count == 1 ? "session" : "sessions")")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.lgTextTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.lgCardAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.lgBorder).frame(height: 1) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HISTORY · 03").lgEyebrowStyle()
                Text("History")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(Color.lgText)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.lgTextTertiary)
                TextField("Search by firearm, ammo, or date", text: $searchText)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Color.lgText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.lgCardAlt)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.lgBorderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 6) {
                Text("GROUP BY").lgEyebrowStyle()
                LgSegmentedControl(options: HistoryGroupMode.allCases, selection: $groupMode) { $0.rawValue }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Color.lgBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.lgBorder).frame(height: 1) }
    }
}

// MARK: - SessionRow

struct SessionRow: View {
    let session: SessionSummary
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 0) {
                Text(session.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.lgMono(11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.lgTextSecondary)
                Text(session.date.formatted(.dateTime.day()))
                    .font(.lgMono(22, weight: .bold))
                    .foregroundStyle(Color.lgText)
                Text(session.date.formatted(.dateTime.year()))
                    .font(.lgMono(10))
                    .foregroundStyle(Color.lgTextTertiary)
            }
            .frame(width: 42)

            Rectangle().fill(Color.lgBorder).frame(width: 1)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(session.firearmNames.prefix(2), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Color.lgText)
                        .lineLimit(1)
                }
                if session.firearmNames.count > 2 {
                    Text("+ \(session.firearmNames.count - 2) more")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.lgTextSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.totalRounds)")
                    .font(.lgMono(19.5, weight: .bold))
                    .foregroundStyle(Color.lgText)
                HStack(spacing: 3) {
                    if session.hasPhotos {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.lgTextSecondary)
                    }
                    Text("ROUNDS")
                        .font(.system(size: 11))
                        .tracking(0.3)
                        .foregroundStyle(Color.lgTextTertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - HistoryEntryRow

struct HistoryEntryRow: View {
    let entry: LogEntry
    let crossReference: String?
    let onTap: () -> Void

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
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.lgText)
                    .lineLimit(1)
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12.5))
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
                            .font(.system(size: 9))
                            .foregroundStyle(Color.lgTextSecondary)
                    }
                    Text("ROUNDS")
                        .font(.system(size: 9.5))
                        .tracking(0.3)
                        .foregroundStyle(Color.lgTextTertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - SessionDetailSheet

struct SessionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: SessionSummary

    var body: some View {
        LgSheetScaffold(
            title: session.date.formatted(date: .abbreviated, time: .omitted),
            leftLabel: "Done", leftAction: { dismiss() }
        ) {
            Text("Summary").lgSectionLabelStyle().padding(.top, 16)
            LgCard {
                VStack(spacing: 10) {
                    statRow("Date", session.date.formatted(date: .long, time: .omitted))
                    statRow("Day", session.date.formatted(.dateTime.weekday(.wide)))
                    statRow("Firearms Logged", "\(session.entries.count)", mono: true)
                    statRow("Total Rounds", "\(session.totalRounds)", mono: true, bold: true)
                }
            }

            Text("Firearms Logged").lgSectionLabelStyle().padding(.top, 20)
            VStack(spacing: 0) {
                ForEach(session.entries) { entry in
                    entryRow(entry)
                    Rectangle().fill(Color.lgSeparator).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String, mono: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Color.lgTextSecondary)
            Spacer()
            Text(value)
                .font(mono ? .lgMono(15, weight: bold ? .bold : .regular) : .system(size: 15))
                .foregroundStyle(Color.lgText)
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.firearmNameSnapshot ?? entry.firearm?.displayName ?? "Unknown Firearm")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.lgText)
                Spacer()
                Text("\(entry.rounds) rounds")
                    .font(.lgMono(15, weight: .bold))
                    .foregroundStyle(Color.lgText)
            }
            if let ammo = entry.ammoSnapshot, !ammo.isEmpty {
                Text(ammo)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.lgTextSecondary)
            }
            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.lgTextSecondary)
            }
            if let photoPath = entry.photoPath,
               let image = ImageStorage.load(path: photoPath) {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 12)
    }
}
