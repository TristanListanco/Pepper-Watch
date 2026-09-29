//
//  InsightsView.swift
//  Pepper Watch
//
//  Health-style summary: compact metric cards that open a full chart view.
//

import SwiftData
import SwiftUI

enum InsightsRange: String, CaseIterable, Identifiable {
    case day = "D"
    case week = "W"
    case month = "M"
    case sixMonths = "6M"
    case year = "Y"

    var id: String { rawValue }

    var startDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return switch self {
        case .day: Date.now.addingTimeInterval(-86_400)
        case .week: calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .sixMonths: calendar.date(byAdding: .month, value: -6, to: today) ?? today
        case .year: calendar.date(byAdding: .year, value: -1, to: today) ?? today
        }
    }

    /// Chart bucket size for the range.
    var bucket: Calendar.Component {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .sixMonths: .weekOfYear
        case .year: .month
        }
    }

    var intervalText: String {
        (startDate..<Date.now).formatted(.interval.month(.abbreviated).day().year())
    }
}

enum InsightMetric: String, CaseIterable, Identifiable, Hashable {
    case infestation, leafHealth, scans, fields, accuracy, confidence, performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .infestation: "Infestation Rate"
        case .leafHealth: "Leaf Health"
        case .scans: "Scans"
        case .fields: "Fields"
        case .accuracy: "Detection Accuracy"
        case .confidence: "Model Confidence"
        case .performance: "Real-time Performance"
        }
    }

    var symbol: String {
        switch self {
        case .infestation: "ant.fill"
        case .leafHealth: "leaf.fill"
        case .scans: "camera.viewfinder"
        case .fields: "map.fill"
        case .accuracy: "checkmark.seal.fill"
        case .confidence: "gauge.with.dots.needle.67percent"
        case .performance: "speedometer"
        }
    }

    @MainActor var tint: Color {
        switch self {
        case .infestation: LeafClass.aphidInfested.color
        case .leafHealth: LeafClass.healthy.color
        case .scans: .accentColor
        case .fields: .teal
        case .accuracy: .blue
        case .confidence: .purple
        case .performance: .indigo
        }
    }

    var about: String {
        switch self {
        case .infestation:
            "The share of detected leaves the model classified as aphid-infested. Above 25% counts as moderate and above 50% as severe. Aphid feeding causes 20–30% yield loss, and more when viruses spread."
        case .leafHealth:
            "Every leaf the model boxed in logged scans, split into healthy and aphid-infested. Look for infested leaves early, while they show yellowing, downward curling or honeydew."
        case .scans:
            "Scans saved from the camera, snapshots and photo imports, colored by the severity of each scan."
        case .fields:
            "Infestation by field, so you know where to act first. Map points come from geotagged scans inside each field's geofence."
        case .accuracy:
            "Built from detections you confirmed or rejected in History, using the thesis definitions: precision = TP / (TP + FP), recall = TP / (TP + FN), accuracy = (TP + TN) / all, and F1 is their harmonic mean. mAP needs labeled test data, so it comes from training."
        case .confidence:
            "How sure the model was about each box. A cluster of low scores means you should lower the threshold carefully or collect more training images."
        case .performance:
            "Average analyzed frames per second in each scanning session. The thesis requires at least 17 FPS for real-time detection."
        }
    }
}

struct InsightsView: View {
    @Query(sort: \DetectionEvent.timestamp) private var events: [DetectionEvent]
    @Query(sort: \ScanSession.startedAt) private var sessions: [ScanSession]
    @Query(sort: \Field.name) private var fields: [Field]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("insights.fieldID") private var selectedFieldID = ""
    @AppStorage("insights.showAllMetrics") private var showAllMetrics = false
    @State private var narrator = InsightNarrator()
    @State private var path: [InsightMetric] = Self.initialPath

    /// Debug builds accept `-PWInsightMetric infestation` to open a detail page for screenshots.
    private static var initialPath: [InsightMetric] {
        #if DEBUG
        UserDefaults.standard.string(forKey: "PWInsightMetric").flatMap(InsightMetric.init(rawValue:)).map { [$0] } ?? []
        #else
        []
        #endif
    }

    private var selectedField: Field? { fields.first { $0.id.uuidString == selectedFieldID } }

    private var scopedEvents: [DetectionEvent] {
        guard let selectedField else { return events }
        return events.filter { $0.field?.id == selectedField.id }
    }

    private var scopedSessions: [ScanSession] {
        guard let selectedField else { return sessions }
        return sessions.filter { $0.field?.id == selectedField.id }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if events.isEmpty {
                    emptyState
                } else {
                    summary
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
            .navigationSubtitle(selectedField?.name ?? "All Fields")
            .navigationDestination(for: InsightMetric.self) { metric in
                InsightDetailView(metric: metric, fieldID: selectedField?.id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Field", selection: $selectedFieldID) {
                            Label("All Fields", systemImage: "square.grid.2x2").tag("")
                            ForEach(fields) { field in
                                Label(field.name, systemImage: "leaf").tag(field.id.uuidString)
                            }
                        }
                    } label: {
                        Label("Field", systemImage: selectedField == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                if !scopedEvents.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: CSVExporter.detections(scopedEvents), preview: SharePreview("Pepper Watch detections")) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Detections Yet", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Scan a field or analyze a photo to build your insights. You can also load demo data to explore.")
        } actions: {
            Button("Load Demo Data", systemImage: "wand.and.stars") {
                withAnimation { DemoDataGenerator.generate(in: modelContext) }
            }
            .buttonStyle(.glassProminent)
        }
    }

    private var summary: some View {
        let weekStart = InsightsRange.week.startDate
        let previousStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let current = InsightsStats(
            events: scopedEvents.filter { $0.timestamp >= weekStart },
            sessions: scopedSessions.filter { $0.startedAt >= weekStart }
        )
        let previous = InsightsStats(
            events: scopedEvents.filter { $0.timestamp >= previousStart && $0.timestamp < weekStart },
            sessions: scopedSessions.filter { $0.startedAt >= previousStart && $0.startedAt < weekStart }
        )
        let latest = scopedEvents.last
        let facts = InsightDigest.facts(current: current, previous: previous, scope: selectedField?.name ?? "all fields", latest: latest)
        let fallback = InsightDigest.fallback(current: current, previous: previous, latest: latest)
        let visibleMetrics = showAllMetrics ? InsightMetric.allCases : Array(InsightMetric.allCases.prefix(4))

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Highlights")
                HighlightsCard(narrator: narrator, fallback: fallback) {
                    narrator.refresh(facts: facts, force: true)
                }

                SectionHeader(title: "Summary", detail: "Past 7 days")
                    .padding(.top, 8)
                ForEach(visibleMetrics) { metric in
                    NavigationLink(value: metric) {
                        InsightSummaryCard(metric: metric, current: current, previous: previous)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    withAnimation(.smooth) { showAllMetrics.toggle() }
                } label: {
                    HStack {
                        Text(showAllMetrics ? "Show Less" : "Show All Metrics")
                        Spacer()
                        Image(systemName: showAllMetrics ? "chevron.up" : "chevron.down")
                    }
                    .font(.body.weight(.medium))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.card, in: .rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .padding()
        }
        .task(id: facts) { narrator.refresh(facts: facts) }
    }
}

private struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.bold))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Highlights

private struct HighlightsCard: View {
    let narrator: InsightNarrator
    let fallback: HighlightContent
    let onRegenerate: () -> Void

    private var isAI: Bool {
        switch narrator.phase {
        case .generating, .generated: true
        default: false
        }
    }

    private var content: HighlightContent { isAI ? narrator.content : fallback }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(isAI ? "Apple Intelligence" : "Highlights", systemImage: isAI ? "apple.intelligence" : "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .leading, endPoint: .trailing)
                    )
                Spacer()
                if narrator.phase == .generating {
                    ProgressView()
                        .controlSize(.small)
                } else if isAI || narrator.phase.isFailure {
                    Button("Regenerate", systemImage: "arrow.clockwise", action: onRegenerate)
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                }
            }

            Text(content.headline ?? " ")
                .font(.title3.weight(.semibold))
                .redacted(reason: content.headline == nil ? .placeholder : [])
                .contentTransition(.opacity)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(content.observations.enumerated()), id: \.offset) { _, observation in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 5, height: 5)
                            .offset(y: -3)
                        Text(observation)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let recommendation = content.recommendation {
                Label {
                    Text(recommendation)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.cardInset, in: .rect(cornerRadius: 14))
            }

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.card, in: .rect(cornerRadius: 20))
        .animation(.smooth, value: content)
    }

    private var footnote: String {
        switch narrator.phase {
        case .generating, .generated:
            "Generated on device from your scan statistics. Check guidance with your local agriculturist."
        case .unavailable(let reason):
            "\(reason) Showing standard highlights."
        case .failed:
            "Couldn't generate a summary. Showing standard highlights."
        case .idle:
            "Standard highlights from your scan statistics."
        }
    }
}

private extension InsightNarrator.Phase {
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}

// MARK: - Summary card

struct InsightSummaryCard: View {
    let metric: InsightMetric
    let current: InsightsStats
    let previous: InsightsStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(metric.title, systemImage: metric.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Spacer()
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .contentTransition(.numericText())
                        Text(unit)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                miniChart
                    .frame(width: 112, height: 50)
            }
        }
        .padding()
        .background(.card, in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the \(metric.title) chart")
    }

    private var caption: String {
        switch metric {
        case .scans, .leafHealth, .infestation:
            current.trend.last.map { $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? "No data"
        default:
            "7 days"
        }
    }

    private var value: String {
        switch metric {
        case .infestation: current.infestationRate.percentText
        case .leafHealth: current.healthyLeaves.formatted()
        case .scans: current.scanCount.formatted()
        case .fields: current.fieldRates.first.map { $0.rate.percentText } ?? "—"
        case .accuracy: current.validation.f1.map(\.percentText) ?? "—"
        case .confidence: current.meanConfidence.map(\.percentText) ?? "—"
        case .performance: current.averageFPS.map { $0.fixed(1) } ?? "—"
        }
    }

    private var unit: String {
        switch metric {
        case .infestation: "infested"
        case .leafHealth: "healthy leaves"
        case .scans: current.scanCount == 1 ? "scan" : "scans"
        case .fields: current.fieldRates.first?.field ?? ""
        case .accuracy: "F1-score"
        case .confidence: "average"
        case .performance: "FPS"
        }
    }

    /// Change from the previous 7 days, like Health's trend line.
    private var detail: String? {
        switch metric {
        case .infestation:
            guard previous.totalLeaves > 0 else { return nil }
            let change = (current.infestationRate - previous.infestationRate) * 100
            if abs(change) < 1 { return "Same as last week" }
            return "\(change > 0 ? "▲" : "▼") \(abs(change).fixed(0)) pts vs last week"
        case .leafHealth:
            return "\(current.aphidLeaves) infested"
        case .scans:
            guard previous.scanCount > 0 else { return nil }
            return "\(previous.scanCount) the week before"
        case .fields:
            return current.fieldRates.isEmpty ? nil : "Highest infestation"
        case .accuracy:
            return current.validation.total == 0 ? "Verify detections in History" : "\(current.validation.total) verified"
        case .confidence:
            return "\(current.totalLeaves) boxes"
        case .performance:
            return "Target ≥ 17 FPS"
        }
    }

    @ViewBuilder
    private var miniChart: some View {
        switch metric {
        case .infestation:
            SparklineChart(points: current.trend.map { MiniPoint(date: $0.date, value: $0.rate) }, color: metric.tint, domain: 0...1)
        case .leafHealth:
            HStack {
                Spacer()
                MiniDonut(aphid: current.aphidLeaves, healthy: current.healthyLeaves)
                    .frame(width: 50)
            }
        case .scans:
            MiniBarChart(points: current.trend.map { MiniPoint(date: $0.date, value: Double($0.scans)) }, color: metric.tint)
        case .fields:
            MiniRankBars(fields: current.fieldRates)
        case .accuracy:
            HStack {
                Spacer()
                MiniMatrix(metrics: current.validation)
                    .frame(width: 50)
            }
        case .confidence:
            MiniHistogram(bins: current.confidenceBins)
        case .performance:
            SparklineChart(
                points: current.sessions.map { MiniPoint(date: $0.date, value: $0.fps) },
                color: metric.tint,
                domain: 0...max(40, current.sessions.map(\.fps).max() ?? 0),
                reference: 17
            )
        }
    }
}

#Preview {
    InsightsView()
        .modelContainer(PreviewSupport.container)
}
