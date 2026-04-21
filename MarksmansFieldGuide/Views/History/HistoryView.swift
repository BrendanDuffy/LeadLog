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
}

// MARK: - HistoryView

struct HistoryView: View {
    @Query(sort: \LogEntry.date, order: .reverse) private var allEntries: [LogEntry]

    @State private var searchText = ""
    @State private var selectedSession: SessionSummary? = nil

    private var sessions: [SessionSummary] {
        let grouped = Dictionary(grouping: allEntries) { $0.sessionId }
        return grouped.map { id, entries in
            SessionSummary(id: id, date: entries.first?.date ?? Date(), entries: entries)
        }
        .sorted(by: { $0.date > $1.date })
    }

    private var filteredSessions: [SessionSummary] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return sessions }
        let q = searchText.lowercased()
        return sessions.filter { session in
            session.firearmNames.contains(where: { $0.lowercased().contains(q) }) ||
            session.date.formatted(date: .long, time: .omitted).lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            W.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                WesternHeader(title: "History")
                GoldDivider()

                if sessions.isEmpty {
                    emptyState
                } else {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(W.muted.opacity(0.6))
                        TextField("Search by firearm or date", text: $searchText)
                            .font(.playfairRegular(15))
                            .foregroundStyle(W.text)
                            .tint(W.brass)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(W.muted.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(W.leather.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(W.brass.opacity(0.25), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    if filteredSessions.isEmpty {
                        noResultsState
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(filteredSessions) { session in
                                    HistoryRowCard(session: session)
                                        .onTapGesture {
                                            haptic(.light)
                                            selectedSession = session
                                        }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("tabbar-icon-pocketwatch")
                .resizable().scaledToFit()
                .frame(width: 64, height: 64).opacity(0.35)
            Text("No sessions logged yet")
                .font(.rye(18)).foregroundStyle(W.muted)
            Text("Log your first session to see it here.")
                .font(.playfairRegular(14))
                .foregroundStyle(W.muted.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(); Spacer()
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No results for \"\(searchText)\"")
                .font(.rye(16)).foregroundStyle(W.muted)
            Spacer(); Spacer()
        }
    }
}

// MARK: - HistoryRowCard

struct HistoryRowCard: View {
    let session: SessionSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Date column
            VStack(alignment: .center, spacing: 2) {
                Text(session.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(W.brass.opacity(0.8))
                Text(session.date.formatted(.dateTime.day()))
                    .font(.rye(22)).foregroundStyle(W.brass)
                Text(session.date.formatted(.dateTime.year()))
                    .font(.playfairRegular(11)).foregroundStyle(W.muted.opacity(0.6))
            }
            .frame(width: 44)

            Rectangle().fill(W.brass.opacity(0.2)).frame(width: 1, height: 44)

            // Firearms
            VStack(alignment: .leading, spacing: 4) {
                ForEach(session.firearmNames.prefix(2), id: \.self) { name in
                    Text(name)
                        .font(.playfairBold(14)).foregroundStyle(W.text)
                        .lineLimit(1)
                }
                if session.firearmNames.count > 2 {
                    Text("+ \(session.firearmNames.count - 2) more")
                        .font(.playfairRegular(12)).foregroundStyle(W.muted)
                }
            }

            Spacer()

            // Rounds + chevron
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.totalRounds)")
                    .font(.rye(18)).foregroundStyle(W.brass)
                Text("rounds")
                    .font(.playfairRegular(11)).foregroundStyle(W.muted.opacity(0.6))
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
                    .strokeBorder(W.brass.opacity(0.3), lineWidth: 1))
        )
    }
}

// MARK: - SessionDetailView

struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let session: SessionSummary

    var body: some View {
        ZStack {
            W.bg.ignoresSafeArea()
            Image("texture-leather").resizable().scaledToFill().ignoresSafeArea().opacity(0.4)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Done") { dismiss() }
                        .font(.playfairRegular(16)).foregroundStyle(W.muted)
                    Spacer()
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.rye(17)).foregroundStyle(W.brass)
                    Spacer()
                    // Balance the Done button
                    Text("Done").font(.playfairRegular(16)).foregroundStyle(.clear)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)

                GoldDivider()

                ScrollView {
                    VStack(spacing: 14) {
                        // Session summary card
                        summaryCard

                        // Each firearm entry
                        sectionHeader("FIREARMS LOGGED")
                        VStack(spacing: 10) {
                            ForEach(session.entries) { entry in
                                entryCard(entry)
                            }
                        }

                        Spacer().frame(height: 32)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            statItem(value: "\(session.entries.count)", label: "Firearms\nLogged")
            Divider().background(W.brass.opacity(0.3)).frame(width: 1)
            statItem(value: "\(session.totalRounds)", label: "Total\nRounds")
            Divider().background(W.brass.opacity(0.3)).frame(width: 1)
            statItem(
                value: session.date.formatted(.dateTime.weekday(.abbreviated)).uppercased(),
                label: session.date.formatted(.dateTime.month().day().year())
            )
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(W.leather.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(W.brass.opacity(0.3), lineWidth: 1))
        )
    }

    @ViewBuilder private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.rye(20)).foregroundStyle(W.brass)
            Text(label).font(.playfairRegular(11)).foregroundStyle(W.muted.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    @ViewBuilder private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text).font(.rye(12)).tracking(1).foregroundStyle(W.brass.opacity(0.7))
            Rectangle().fill(W.brass.opacity(0.2)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func entryCard(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Firearm name
            HStack {
                Text(entry.firearmNameSnapshot ?? entry.firearm?.displayName ?? "Unknown Firearm")
                    .font(.rye(15)).foregroundStyle(W.brass)
                Spacer()
                Text("\(entry.rounds) rounds")
                    .font(.playfairBold(14)).foregroundStyle(W.brass)
            }

            if let ammo = entry.ammoSnapshot, !ammo.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5)).foregroundStyle(W.brass.opacity(0.5))
                    Text(ammo).font(.playfairRegular(13)).foregroundStyle(W.muted).lineLimit(1)
                }
            }

            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.playfairRegular(13)).foregroundStyle(W.text.opacity(0.8))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(W.bg.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let photoPath = entry.photoPath,
               let image = ImageStorage.load(path: photoPath) {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(W.leather.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(W.brass.opacity(0.25), lineWidth: 1))
        )
    }
}
