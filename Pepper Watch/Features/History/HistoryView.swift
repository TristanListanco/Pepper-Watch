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
    @Query(sort: \Field.name) private var fields: [Field]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.systemLogger) private var logger
    @AppStorage("history.columns") private var columnCount = 3
    @State private var searchText = ""
    @State private var filter: HistoryFilter = .all
    @State private var fieldFilterID = ""
    @State private var selectedDay: Date?
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var pendingDeletion: [DetectionEvent] = []
    @State private var pinchBaseline: CGFloat = 1

    private static let columnRange = 1...6

    /// Events matching the filter menu and search, before the chart's day selection.
    private var matchingEvents: [DetectionEvent] {
        events.filter { event in
            guard filter.includes(event) else { return false }
            if !fieldFilterID.isEmpty, event.field?.id.uuidString != fieldFilterID { return false }
            guard !searchText.isEmpty else { return true }
            return event.fieldName.localizedCaseInsensitiveContains(searchText)
                || event.notes.localizedCaseInsensitiveContains(searchText)
                || event.source.title.localizedCaseInsensitiveContains(searchText)
                || (event.severity?.title.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var visibleEvents: [DetectionEvent] {
        guard let selectedDay else { return matchingEvents }
        return matchingEvents.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: selectedDay) }
    }

    private var groupedByDay: [(day: Date, events: [DetectionEvent])] {
        let groups = Dictionary(grouping: visibleEvents) { Calendar.current.startOfDay(for: $0.timestamp) }
        return groups.map { (day: $0.key, events: $0.value) }.sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !events.isEmpty, !isSelecting {
                        activityCard
                            .padding(.horizontal)
                    }
                    grid
                }
            }
            .simultaneousGesture(pinchToResize)
            .sensoryFeedback(.selection, trigger: columnCount)
            .navigationTitle(isSelecting ? (selection.isEmpty ? "Select Items" : "\(selection.count) Selected") : "History")
            .navigationBarTitleDisplayMode(isSelecting ? .inline : .automatic)
            .navigationDestination(for: DetectionEvent.self) { event in
                DetectionDetailView(event: event)
            }
            .searchable(text: $searchText, prompt: "Field, notes, severity")
            .toolbar { toolbarContent }
            .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Scans Yet",
                        systemImage: "photo.stack",
                        description: Text("Detections logged while scanning, snapshots and saved photos appear here.")
                    )
                } else if visibleEvents.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .confirmationDialog(
                pendingDeletion.count == 1 ? "Delete this scan?" : "Delete \(pendingDeletion.count) scans?",
                isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
                titleVisibility: .visible
            ) {
                Button(pendingDeletion.count == 1 ? "Delete Scan" : "Delete \(pendingDeletion.count) Scans", role: .destructive) {
                    delete(pendingDeletion)
                }
            } message: {
                Text("Images and detections will be removed from this device. This can't be undone.")
            }
        }
    }

    // MARK: - Activity chart

    private var activityCard: some View {
        let monthStart = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        let recent = matchingEvents.filter { $0.timestamp >= monthStart }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity")
                        .font(.headline)
                    Text("Scans per day, last 30 days. Tap a day to filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let selectedDay {
                    Button {
                        withAnimation(.snappy) { self.selectedDay = nil }
                    } label: {
                        Label(selectedDay.formatted(.dateTime.month(.abbreviated).day()), systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Clear day filter")
                }
            }
            if recent.isEmpty {
                Text("No scans in the last 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 60)
            } else {
                ScanActivityChart(
                    buckets: ScanActivityChart.buckets(for: recent, unit: .day),
                    unit: .day,
                    selection: $selectedDay
                )
                .frame(height: 150)
            }
        }
        .padding()
        .background(.card, in: .rect(cornerRadius: 20))
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: columnCount),
            spacing: 3,
            pinnedViews: [.sectionHeaders]
        ) {
            ForEach(groupedByDay, id: \.day) { group in
                Section {
                    ForEach(group.events) { event in
                        tile(for: event)
                    }
                } header: {
                    DayHeader(day: group.day, events: group.events)
                }
            }
        }
        .padding(.horizontal, 3)
        .animation(.snappy, value: columnCount)
    }

    @ViewBuilder
    private func tile(for event: DetectionEvent) -> some View {
        if isSelecting {
            Button {
                toggleSelection(event)
            } label: {
                HistoryTile(event: event, compact: columnCount >= 5, isSelected: selection.contains(event.id))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(event.id) ? .isSelected : [])
        } else {
            NavigationLink(value: event) {
                HistoryTile(event: event, compact: columnCount >= 5, isSelected: nil)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Select", systemImage: "checkmark.circle") {
                    withAnimation { isSelecting = true }
                    selection = [event.id]
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    pendingDeletion = [event]
                }
            } preview: {
                AnnotatedImageView(imageData: event.imageData, detections: event.detections)
                    .frame(width: 300)
            }
        }
    }

    /// Pinch in to see more thumbnails, pinch out to see them larger (like Photos).
    private var pinchToResize: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let ratio = value.magnification / pinchBaseline
                if ratio > 1.3, columnCount > Self.columnRange.lowerBound {
                    columnCount -= 1
                    pinchBaseline = value.magnification
                } else if ratio < 0.77, columnCount < Self.columnRange.upperBound {
                    columnCount += 1
                    pinchBaseline = value.magnification
                }
            }
            .onEnded { _ in pinchBaseline = 1 }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    withAnimation {
                        isSelecting = false
                        selection = []
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                let allSelected = !visibleEvents.isEmpty && selection.count == visibleEvents.count
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(visibleEvents.map(\.id))
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    pendingDeletion = visibleEvents.filter { selection.contains($0.id) }
                }
                .disabled(selection.isEmpty)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button("Select") {
                    withAnimation { isSelecting = true }
                }
                .disabled(events.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Show", selection: $filter.animation()) {
                        ForEach(HistoryFilter.allCases) { filter in
                            Label(filter.rawValue, systemImage: filter.symbol).tag(filter)
                        }
                    }
                    if !fields.isEmpty {
                        Picker("Field", selection: $fieldFilterID.animation()) {
                            Text("All Fields").tag("")
                            ForEach(fields) { field in
                                Text(field.name).tag(field.id.uuidString)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Section("Thumbnail Size") {
                        Button("Larger", systemImage: "plus.magnifyingglass") {
                            columnCount = max(Self.columnRange.lowerBound, columnCount - 1)
                        }
                        .disabled(columnCount == Self.columnRange.lowerBound)
                        Button("Smaller", systemImage: "minus.magnifyingglass") {
                            columnCount = min(Self.columnRange.upperBound, columnCount + 1)
                        }
                        .disabled(columnCount == Self.columnRange.upperBound)
                    }
                } label: {
                    Label("Filter", systemImage: filter == .all && fieldFilterID.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ event: DetectionEvent) {
        if selection.contains(event.id) {
            selection.remove(event.id)
        } else {
            selection.insert(event.id)
        }
    }

    private func delete(_ events: [DetectionEvent]) {
        let count = events.count
        withAnimation {
            for event in events { modelContext.delete(event) }
        }
        try? modelContext.save()
        logger?.log(category: "history", "Deleted \(count) scan\(count == 1 ? "" : "s")")
        selection.subtract(events.map(\.id))
        pendingDeletion = []
        if isSelecting, selection.isEmpty { isSelecting = false }
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
    var compact = false
    /// `nil` outside selection mode.
    var isSelected: Bool?

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
                if !compact {
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
                } else if let severity = event.severity {
                    // Tiny thumbnails keep only the severity color strip.
                    Rectangle()
                        .fill(severity.color)
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !compact, isSelected == nil {
                    Image(systemName: event.source.symbol)
                        .font(.caption2.weight(.semibold))
                        .padding(5)
                        .background(.ultraThinMaterial, in: .circle)
                        .padding(5)
                }
            }
            .overlay {
                if isSelected == true {
                    Color.white.opacity(0.25)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let isSelected {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : .black.opacity(0.25))
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .clipShape(.rect(cornerRadius: compact ? 4 : 10))
            .contentShape(.rect(cornerRadius: compact ? 4 : 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(event.source.title) at \(event.timestamp.formatted(date: .omitted, time: .shortened)), \(event.aphidCount) of \(event.aphidCount + event.healthyCount) leaves infested, \(event.severity?.title ?? "no leaves")")
    }
}

#Preview {
    HistoryView()
        .modelContainer(PreviewSupport.container)
}
