//
//  HistoryView.swift
//  Pepper Watch
//
//  Thesis "Historical Detection Log": filterable gallery of past scans.
//

import SwiftData
import SwiftUI
import TipKit

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
    /// Sectioned by day (iOS 27), so the grid gets its day groups straight from the query.
    /// Sections come back oldest first, so the view reverses them for a newest-first gallery.
    @Query(
        sort: [SortDescriptor(\DetectionEvent.dayKey), SortDescriptor(\DetectionEvent.timestamp)],
        sectionBy: \DetectionEvent.dayKey
    )
    private var days: SectionedResults<DetectionEvent, String>
    @Query(sort: \Field.name) private var fields: [Field]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.widgetSync) private var widgetSync
    @Environment(\.systemLogger) private var logger
    @AppStorage("history.thumbnailLevel") private var thumbnailLevel = 2
    @State private var filter: HistoryFilter = .all
    @State private var fieldFilterID = ""
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var pendingDeletion: [DetectionEvent] = []
    @State private var path: [DetectionEvent] = []
    /// The live pinch. Gesture state resets on its own, springing back, even when the system
    /// cancels the pinch midway, so the grid never stays stuck at a scale.
    @GestureState(resetTransaction: Transaction(animation: HistoryView.resizeAnimation))
    private var pinch: Pinch?

    /// One spring for the grid settling after a pinch or a size change from the menu.
    static let resizeAnimation = Animation.spring(duration: 0.42, bounce: 0.12)
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    /// Thumbnails on screen, in order, and the visible part of the grid, to keep the pinched
    /// photos in view when the thumbnail size changes.
    @State private var visibleIDs: [UUID] = []
    @State private var visibleRect: CGRect = .zero
    @Namespace private var zoomSpace
    /// Each thumbnail's geometry, matched across thumbnail sizes so tiles glide to their new
    /// place and size instead of the grid reflowing.
    @Namespace private var gridSpace

    private struct Pinch: Equatable {
        var magnification: CGFloat
        var anchor: UnitPoint
    }

    /// Minimum thumbnail widths; the grid fits as many columns as the width allows (3 on iPhone at the default).
    private static let thumbnailSizes: [CGFloat] = [64, 84, 110, 150, 210, 300]

    private var thumbnailSize: CGFloat {
        Self.thumbnailSizes[min(max(thumbnailLevel, 0), Self.thumbnailSizes.count - 1)]
    }

    private func matchesFilter(_ event: DetectionEvent) -> Bool {
        guard filter.includes(event) else { return false }
        if !fieldFilterID.isEmpty, event.field?.id.uuidString != fieldFilterID { return false }
        return true
    }

    /// Every scan, newest first.
    private var events: [DetectionEvent] {
        days.reversed().flatMap { $0.reversed() }
    }

    /// The query's day sections, newest first, keeping only scans that match the filter menu.
    private var groupedByDay: [(day: Date, events: [DetectionEvent])] {
        days.reversed().compactMap { section in
            let matching = section.reversed().filter(matchesFilter)
            guard let first = matching.first else { return nil }
            return (day: Calendar.current.startOfDay(for: first.timestamp), events: matching)
        }
    }

    /// Events matching the filter menu.
    private var visibleEvents: [DetectionEvent] {
        groupedByDay.flatMap(\.events)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                grid
                // Photos-style pinch: the content follows the fingers, then settles at the new size.
                // Scaling inside the scroll view keeps the large title and anchors the zoom in the content.
                .scaleEffect(liveScale, anchor: pinch?.anchor ?? .center)
                .simultaneousGesture(pinchToResize)
            }
            .scrollPosition($scrollPosition)
            .onScrollTargetVisibilityChange(idType: UUID.self, threshold: 0.5) { visibleIDs = $0 }
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in visibleRect = rect }
            .refreshable { await refresh() }
            .background(Color(.systemGroupedBackground))
            .sensoryFeedback(.selection, trigger: thumbnailLevel)
            .navigationTitle(isSelecting ? (selection.isEmpty ? "Select Items" : "\(selection.count) Selected") : "History")
            .navigationSubtitle(isSelecting || visibleEvents.isEmpty ? "" : "\(visibleEvents.count) \(visibleEvents.count == 1 ? "scan" : "scans")")
            .navigationBarTitleDisplayMode(isSelecting ? .inline : .automatic)
            .navigationDestination(for: DetectionEvent.self) { event in
                DetectionDetailView(event: event)
                    .navigationTransition(.zoom(sourceID: event.id, in: zoomSpace))
            }
            .toolbar { toolbarContent }
            #if DEBUG
            // `-PWOpenLatestScan YES` opens the newest scan for screenshots.
            .task {
                if UserDefaults.standard.bool(forKey: "PWOpenLatestScan"), path.isEmpty, let latest = events.first {
                    path = [latest]
                }
            }
            #endif
            .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Scans Yet",
                        systemImage: "photo.stack",
                        description: Text("Detections logged while scanning, snapshots and saved photos appear here.")
                    )
                } else if visibleEvents.isEmpty {
                    ContentUnavailableView(
                        "No Matching Scans",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try a different filter or field.")
                    )
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

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: 3)],
            spacing: 3,
            pinnedViews: [.sectionHeaders]
        ) {
            ForEach(groupedByDay, id: \.day) { group in
                Section {
                    ForEach(group.events) { event in
                        tile(for: event)
                    }
                } header: {
                    DayHeader(day: group.day)
                }
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 3)
    }

    private func tile(for event: DetectionEvent) -> some View {
        tileContent(for: event)
            .matchedGeometryEffect(id: event.id, in: gridSpace)
    }

    @ViewBuilder
    private func tileContent(for event: DetectionEvent) -> some View {
        if isSelecting {
            Button {
                toggleSelection(event)
            } label: {
                HistoryTile(event: event, compact: thumbnailSize < 90, isSelected: selection.contains(event.id))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(event.id) ? .isSelected : [])
        } else {
            NavigationLink(value: event) {
                HistoryTile(event: event, compact: thumbnailSize < 90, isSelected: nil)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .matchedTransitionSource(id: event.id, in: zoomSpace)
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
            // Drag a scan's photo into Photos, Files, Mail or another app (iOS 16 Transferable).
            // The full image is loaded only when a drag starts.
            .draggable(ScanPhoto(
                data: event.imageData ?? event.thumbnailData ?? Data(),
                filename: "pepper-watch-\(event.timestamp.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))).jpg"
            ))
        }
    }

    /// How much the grid follows the fingers: freely between sizes, with a rubber band at either end.
    private var liveScale: CGFloat {
        guard let magnification = pinch?.magnification else { return 1 }
        let largest = Self.thumbnailSizes.count - 1
        if magnification > 1 {
            return thumbnailLevel < largest ? min(magnification, 2) : 1 + (magnification - 1) * 0.12
        } else {
            return thumbnailLevel > 0 ? max(magnification, 0.5) : 1 - (1 - magnification) * 0.12
        }
    }

    /// Pinch in to see more thumbnails, pinch out to see them larger. Like Photos, the grid scales
    /// live around the pinch point, then springs into the new size with the pinched photos still
    /// under your fingers.
    private var pinchToResize: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, pinch, _ in
                pinch = Pinch(magnification: value.magnification, anchor: value.startAnchor)
            }
            .onEnded { value in
                PinchGridTip().invalidate(reason: .actionPerformed)
                let magnification = value.magnification
                var level = thumbnailLevel
                if magnification > 1.15 {
                    level += magnification > 1.7 ? 2 : 1
                } else if magnification < 0.87 {
                    level -= magnification < 0.6 ? 2 : 1
                }
                level = min(max(level, 0), Self.thumbnailSizes.count - 1)
                guard level != thumbnailLevel else { return }

                // The photo near the pinch, and how far down the screen it was.
                let fraction = visibleRect.height > 0 ? min(max((value.startLocation.y - visibleRect.minY) / visibleRect.height, 0), 1) : 0.5
                let anchorID = visibleIDs.isEmpty ? nil : visibleIDs[min(Int(fraction * CGFloat(visibleIDs.count)), visibleIDs.count - 1)]
                withAnimation(Self.resizeAnimation) {
                    thumbnailLevel = level
                    if let anchorID {
                        scrollPosition.scrollTo(id: anchorID, anchor: UnitPoint(x: 0.5, y: fraction))
                    }
                }
            }
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
            .visibilityPriority(.low)
            ToolbarSpacer(.fixed, placement: .primaryAction)
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
                            withAnimation(Self.resizeAnimation) {
                                thumbnailLevel = min(thumbnailLevel + 1, Self.thumbnailSizes.count - 1)
                            }
                        }
                        .disabled(thumbnailLevel == Self.thumbnailSizes.count - 1)
                        Button("Smaller", systemImage: "minus.magnifyingglass") {
                            withAnimation(Self.resizeAnimation) {
                                thumbnailLevel = max(thumbnailLevel - 1, 0)
                            }
                        }
                        .disabled(thumbnailLevel == 0)
                    }
                } label: {
                    Label("Filter", systemImage: filter == .all && fieldFilterID.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .help("Filter and Thumbnail Size")
                .popoverTip(events.isEmpty ? nil : PinchGridTip())
            }
            .visibilityPriority(.high)
        }
    }

    // MARK: - Actions

    /// Pull to refresh: rebuilds thumbnails that are missing from the full image and updates widgets.
    private func refresh() async {
        for event in events where event.thumbnailData == nil {
            guard let data = event.imageData, let image = await ImageEncoder.uprightImage(from: data) else { continue }
            event.thumbnailData = await ImageEncoder.encode(image).thumbnail
        }
        try? modelContext.save()
        widgetSync?.update()
    }

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

    var body: some View {
        Text(day, format: .dateTime.weekday(.wide).month().day())
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // Same as the page, so pinned dates blend in (black in Dark Mode).
            .background(Color(.systemGroupedBackground))
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
                        .accessibilityHidden(true)
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
                                .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
                }
            }
            .clipShape(.rect(cornerRadius: compact ? 4 : 10))
            .contentShape(.rect(cornerRadius: compact ? 4 : 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(event.source.title) at \(event.timestamp.formatted(date: .omitted, time: .shortened)), \(event.aphidCount) of \(event.aphidCount + event.healthyCount) leaves infested, \(event.severity?.title ?? "no leaves")")
            .accessibilityAddTraits(isSelected == true ? .isSelected : [])
    }
}

#Preview {
    HistoryView()
        .modelContainer(PreviewSupport.container)
}
