//
//  HistoryView.swift
//  Pepper Watch
//
//  Thesis "Historical Detection Log": searchable gallery of past scans.
//

import SwiftData
import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case infested = "Aphids found"
    case healthy = "Healthy only"
    case unverified = "Needs review"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .infested: "ant"
        case .healthy: "leaf"
        case .unverified: "checkmark.circle.badge.questionmark"
        }
    }

    func includes(_ event: DetectionEvent) -> Bool {
        switch self {
        case .all: true
        case .infested: event.aphidCount > 0
        case .healthy: event.aphidCount == 0 && event.healthyCount > 0
        case .unverified: event.boxes.contains { $0.verdict == nil }
        }
    }
}

struct HistoryView: View {
    @Query(sort: \DetectionEvent.timestamp, order: .reverse) private var events: [DetectionEvent]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filter: HistoryFilter = .all
    @State private var pendingDeletion: DetectionEvent?

    private var filteredEvents: [DetectionEvent] {
        events.filter { event in
            guard filter.includes(event) else { return false }
            guard !searchText.isEmpty else { return true }
            return event.fieldName.localizedCaseInsensitiveContains(searchText)
                || event.notes.localizedCaseInsensitiveContains(searchText)
                || event.source.title.localizedCaseInsensitiveContains(searchText)
                || (event.severity?.title.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var groupedByDay: [(day: Date, events: [DetectionEvent])] {
        let groups = Dictionary(grouping: filteredEvents) { Calendar.current.startOfDay(for: $0.timestamp) }
        return groups.map { (day: $0.key, events: $0.value) }.sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 6)],
                    spacing: 6,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(groupedByDay, id: \.day) { group in
                        Section {
                            ForEach(group.events) { event in
                                NavigationLink(value: event) {
                                    HistoryTile(event: event)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        pendingDeletion = event
                                    }
                                } preview: {
                                    AnnotatedImageView(imageData: event.imageData, detections: event.detections)
                                        .frame(width: 300)
                                }
                            }
                        } header: {
                            DayHeader(day: group.day, events: group.events)
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            .navigationTitle("History")
            .navigationDestination(for: DetectionEvent.self) { event in
                DetectionDetailView(event: event)
            }
            .searchable(text: $searchText, prompt: "Field, notes, severity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Filter", selection: $filter.animation()) {
                            ForEach(HistoryFilter.allCases) { filter in
                                Label(filter.rawValue, systemImage: filter.symbol).tag(filter)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Scans Yet",
                        systemImage: "photo.stack",
                        description: Text("Detections logged while scanning, snapshots and saved photos appear here.")
                    )
                } else if filteredEvents.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .confirmationDialog(
                "Delete this scan?",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Scan", role: .destructive) {
                    if let pendingDeletion {
                        withAnimation { modelContext.delete(pendingDeletion) }
                        try? modelContext.save()
                    }
                    pendingDeletion = nil
                }
            } message: {
                Text("The image and its detections will be removed from this device.")
            }
        }
    }
}

private struct DayHeader: View {
    let day: Date
    let events: [DetectionEvent]

    var body: some View {
        let aphids = events.reduce(0) { $0 + $1.aphidCount }
        let leaves = events.reduce(0) { $0 + $1.aphidCount + $1.healthyCount }
        HStack(alignment: .firstTextBaseline) {
            Text(day, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
            Spacer()
            Text("\(events.count) scans · \(leaves == 0 ? "–" : (Double(aphids) / Double(leaves)).percentText) infested")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct HistoryTile: View {
    let event: DetectionEvent

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let data = event.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ImagePlaceholder()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if let severity = event.severity {
                        Image(systemName: severity.symbol)
                            .foregroundStyle(severity.color)
                    }
                    Text("\(event.aphidCount)/\(event.aphidCount + event.healthyCount)")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: event.source.symbol)
                    .font(.caption2.weight(.semibold))
                    .padding(5)
                    .background(.ultraThinMaterial, in: .circle)
                    .padding(5)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(event.source.title) at \(event.timestamp.formatted(date: .omitted, time: .shortened)), \(event.aphidCount) of \(event.aphidCount + event.healthyCount) leaves infested, \(event.severity?.title ?? "no leaves")")
    }
}

#Preview {
    HistoryView()
        .modelContainer(PreviewSupport.container)
}
