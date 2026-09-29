//
//  InsightDetailView.swift
//  Pepper Watch
//
//  Expanded view for one metric, laid out like an Apple Health detail page:
//  range picker, headline value, full-width chart, then Highlights, related
//  charts, About and Options. Sections flow into columns on iPad.
//

import SwiftData
import SwiftUI

struct InsightDetailView: View {
    let metric: InsightMetric
    let fieldID: UUID?

    @Query(sort: \DetectionEvent.timestamp) private var events: [DetectionEvent]
    @Query(sort: \ScanSession.startedAt) private var sessions: [ScanSession]
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0
    @AppStorage(PinnedMetrics.key) private var pinnedRaw = PinnedMetrics.defaultValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var range: InsightsRange = .week
    @State private var showFullMap = false

    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var chartHeight: CGFloat { isRegular ? 340 : 240 }
    private var isPinned: Bool { PinnedMetrics.decode(pinnedRaw).contains(metric) }

    var body: some View {
        let start = range.startDate
        let scopedEvents = events.filter { $0.timestamp >= start && (fieldID == nil || $0.field?.id == fieldID) }
        let scopedSessions = sessions.filter { $0.startedAt >= start && (fieldID == nil || $0.field?.id == fieldID) }
        let stats = InsightsStats(events: scopedEvents, sessions: scopedSessions, bucket: range.bucket)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Range", selection: $range.animation(.smooth)) {
                    ForEach(InsightsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: isRegular ? 480 : .infinity)

                headline(stats)

                if scopedEvents.isEmpty {
                    ContentUnavailableView("No Data in This Range", systemImage: metric.symbol, description: Text("Try a longer range or scan a field."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    mainChart(stats, events: scopedEvents)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: isRegular ? 360 : 300), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    if !scopedEvents.isEmpty {
                        DetailSection(title: "Highlights") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(highlights(stats), id: \.self) { line in
                                    Label {
                                        Text(line).fixedSize(horizontal: false, vertical: true)
                                    } icon: {
                                        Image(systemName: metric.symbol).foregroundStyle(metric.tint)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        secondaryContent(stats)
                    }

                    DetailSection(title: "About \(metric.title)") {
                        Text(metric.about)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DetailSection(title: "Options") {
                        Toggle(isOn: Binding(
                            get: { isPinned },
                            set: { _ in withAnimation { pinnedRaw = PinnedMetrics.toggling(metric, in: pinnedRaw) } }
                        )) {
                            Label("Pin in Insights", systemImage: "pin.fill")
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.fill" : "pin") {
                    withAnimation { pinnedRaw = PinnedMetrics.toggling(metric, in: pinnedRaw) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: isPinned)
        .sheet(isPresented: $showFullMap) {
            NavigationStack {
                FieldMapView(points: stats.mapPoints)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Field Hotspots")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { showFullMap = false }
                        }
                    }
            }
        }
    }

    // MARK: - Headline

    private func headline(_ stats: InsightsStats) -> some View {
        let (label, value, unit) = headlineParts(stats)
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(range.intervalText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func headlineParts(_ stats: InsightsStats) -> (String, String, String) {
        switch metric {
        case .infestation: ("AVERAGE", stats.infestationRate.percentText, "infested")
        case .leafHealth: ("TOTAL", stats.totalLeaves.formatted(), "leaves")
        case .scans: ("TOTAL", stats.scanCount.formatted(), "scans")
        case .fields: ("HIGHEST", stats.fieldRates.first.map { $0.rate.percentText } ?? "—", "infested")
        case .accuracy: ("F1-SCORE", stats.validation.f1.map(\.percentText) ?? "—", "")
        case .confidence: ("AVERAGE", stats.meanConfidence.map(\.percentText) ?? "—", "confidence")
        case .performance: ("AVERAGE", stats.averageFPS.map { $0.fixed(1) } ?? "—", "FPS")
        }
    }

    // MARK: - Main chart (full width, straight on the page like Health)

    @ViewBuilder
    private func mainChart(_ stats: InsightsStats, events: [DetectionEvent]) -> some View {
        switch metric {
        case .infestation:
            InfestationTrendChart(trend: stats.trend, unit: range.bucket, height: chartHeight)
        case .leafHealth:
            DailyDetectionsChart(counts: stats.classCounts, unit: range.bucket, height: chartHeight)
        case .scans:
            ScanActivityChart(buckets: ScanActivityChart.buckets(for: events, unit: range.bucket), unit: range.bucket)
                .frame(height: chartHeight)
        case .fields:
            FieldRatesChart(fields: stats.fieldRates, color: metric.tint)
        case .accuracy:
            ValidationMatrixView(metrics: stats.validation)
                .padding()
                .background(.card, in: .rect(cornerRadius: 20))
        case .confidence:
            ConfidenceHistogramChart(bins: stats.confidenceBins, height: chartHeight)
        case .performance:
            SessionPerformanceChart(sessions: stats.sessions, target: fpsTarget, color: metric.tint, height: chartHeight)
        }
    }

    // MARK: - Related charts

    @ViewBuilder
    private func secondaryContent(_ stats: InsightsStats) -> some View {
        switch metric {
        case .infestation:
            DetailSection(title: "Scan Severity") { SeverityBreakdownChart(counts: stats.severityCounts) }
            if let severity = stats.overallSeverity {
                RecommendationCard(severity: severity, context: "Guidance for this period")
            }
        case .leafHealth:
            DetailSection(title: "Share of Leaves") { LeafHealthDonut(aphid: stats.aphidLeaves, healthy: stats.healthyLeaves) }
        case .scans:
            DetailSection(title: "Scan Severity") { SeverityBreakdownChart(counts: stats.severityCounts) }
        case .fields:
            if !stats.mapPoints.isEmpty {
                DetailSection(title: "Hotspots") {
                    FieldMapView(points: stats.mapPoints, interactive: false)
                        .frame(height: isRegular ? 300 : 220)
                        .clipShape(.rect(cornerRadius: 16))
                        .onTapGesture { showFullMap = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens the full map")
                }
            }
        case .accuracy:
            EmptyView()
        case .confidence:
            DetailSection(title: "By Class") {
                HStack(spacing: 12) {
                    ForEach(LeafClass.allCases) { leafClass in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(leafClass.displayName, systemImage: leafClass.symbol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(stats.meanConfidenceByClass[leafClass].map(\.percentText) ?? "—")
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .performance:
            let passing = stats.sessions.filter { $0.fps >= fpsTarget }.count
            DetailSection(title: "Summary") {
                HStack(spacing: 12) {
                    detailStat("Met target", "\(passing)/\(stats.sessions.count)", caption: "≥ \(fpsTarget.fixed(0)) FPS")
                    detailStat("Mean inference", "\(stats.averageInferenceMs.fixed(1)) ms", caption: "Per logged scan")
                }
            }
        }
    }

    private func detailStat(_ title: String, _ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Highlights

    private func highlights(_ stats: InsightsStats) -> [String] {
        let format = range.bucket.dateFormat
        switch metric {
        case .infestation:
            var lines: [String] = []
            let populated = stats.trend.filter { $0.total > 0 }
            if let peak = populated.max(by: { $0.rate < $1.rate }) {
                lines.append("Highest was \(peak.rate.percentText) on \(peak.date.formatted(format)).")
            }
            if let low = populated.min(by: { $0.rate < $1.rate }), populated.count > 1 {
                lines.append("Lowest was \(low.rate.percentText) on \(low.date.formatted(format)).")
            }
            return lines
        case .leafHealth:
            let healthyShare = stats.totalLeaves == 0 ? 0 : Double(stats.healthyLeaves) / Double(stats.totalLeaves)
            return ["\(healthyShare.percentText) of \(stats.totalLeaves) detected leaves were healthy.",
                    "\(stats.aphidLeaves) leaves showed aphid damage."]
        case .scans:
            guard let busiest = stats.trend.max(by: { $0.scans < $1.scans }) else { return [] }
            return ["Most scans were logged on \(busiest.date.formatted(format)) (\(busiest.scans)).",
                    "\(stats.sessions.count) scanning sessions in this range."]
        case .fields:
            guard let worst = stats.fieldRates.first else { return [] }
            var lines = ["\(worst.field) has the highest infestation at \(worst.rate.percentText)."]
            if let best = stats.fieldRates.last, stats.fieldRates.count > 1 {
                lines.append("\(best.field) is lowest at \(best.rate.percentText).")
            }
            return lines
        case .accuracy:
            let validation = stats.validation
            guard validation.total > 0, let precision = validation.precision, let recall = validation.recall else {
                return ["No verified detections yet. Open a scan in History and mark each detection correct or wrong."]
            }
            return ["Precision is \(precision.percentText) and recall is \(recall.percentText) across \(validation.total) verified detections.",
                    "\(validation.falseNegatives) infested leaves were missed and \(validation.falsePositives) healthy leaves were flagged."]
        case .confidence:
            guard let mean = stats.meanConfidence else { return [] }
            return ["Average confidence was \(mean.percentText) across \(stats.totalLeaves) boxes."]
        case .performance:
            guard let fastest = stats.sessions.max(by: { $0.fps < $1.fps }) else { return [] }
            let passing = stats.sessions.filter { $0.fps >= fpsTarget }.count
            return ["\(passing) of \(stats.sessions.count) sessions met the \(fpsTarget.fixed(0)) FPS target.",
                    "Fastest session averaged \(fastest.fps.fixed(1)) FPS in \(fastest.field)."]
        }
    }
}

/// A titled card in the Health-style detail layout.
private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.card, in: .rect(cornerRadius: 20))
    }
}
