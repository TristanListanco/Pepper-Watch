//
//  InsightDetailView.swift
//  Pepper Watch
//
//  Expanded view for one metric, laid out like an Apple Health detail page:
//  range picker, headline value, the chart, then full-width Highlights,
//  About and Options sections.
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

    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var chartHeight: CGFloat { isRegular ? 340 : 240 }
    private var isPinned: Bool { PinnedMetrics.decode(pinnedRaw).contains(metric) }

    var body: some View {
        let start = range.startDate
        let scopedEvents = events.filter { $0.timestamp >= start && (fieldID == nil || $0.field?.id == fieldID) }
        let scopedSessions = sessions.filter { $0.startedAt >= start && (fieldID == nil || $0.field?.id == fieldID) }
        let stats = InsightsStats(events: scopedEvents, sessions: scopedSessions, bucket: range.bucket)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Range", selection: $range.animation(.smooth)) {
                    ForEach(InsightsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: isRegular ? 520 : .infinity)
                .frame(maxWidth: .infinity)

                headline(stats)

                if scopedEvents.isEmpty {
                    ContentUnavailableView("No Data in This Range", systemImage: metric.symbol, description: Text("Try a longer range or scan a field."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    mainChart(stats, events: scopedEvents)
                    highlightsSection(highlights(stats))
                }

                aboutSection
                optionsSection
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

    // MARK: - Chart (full width, straight on the page like Health)

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
                .background(.elevatedCard, in: .rect(cornerRadius: 20))
        case .confidence:
            ConfidenceHistogramChart(bins: stats.confidenceBins, height: chartHeight)
        case .performance:
            SessionPerformanceChart(sessions: stats.sessions, target: fpsTarget, color: metric.tint, height: chartHeight)
        }
    }

    // MARK: - Sections

    /// Full-width card: metric label, the key finding in bold, then supporting details.
    private func highlightsSection(_ lines: [String]) -> some View {
        DetailSection(title: "Highlights") {
            VStack(alignment: .leading, spacing: 10) {
                if let lead = lines.first {
                    Text(lead)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lines.dropFirst(), id: \.self) { line in
                    Text(line)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var aboutSection: some View {
        DetailSection(title: "About \(metric.title)") {
            if isRegular, metric.about.count > Self.twoColumnThreshold {
                // iPad: long text is balanced across two columns; short text stays in one.
                let (leading, trailing) = Self.balancedColumns(metric.about)
                HStack(alignment: .top, spacing: 32) {
                    aboutText(leading)
                    aboutText(trailing)
                }
            } else {
                aboutText(metric.about)
            }
        }
    }

    private func aboutText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var optionsSection: some View {
        DetailSection(title: "Options") {
            Toggle(isOn: Binding(
                get: { isPinned },
                set: { _ in withAnimation { pinnedRaw = PinnedMetrics.toggling(metric, in: pinnedRaw) } }
            )) {
                Label("Pin in Insights", systemImage: "pin.fill")
            }
        }
    }

    /// Characters beyond which About text reads better in two columns on iPad.
    private static let twoColumnThreshold = 240

    /// Flows text into two columns of similar length, breaking between words like a newspaper column.
    static func balancedColumns(_ text: String) -> (String, String) {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count > 1 else { return (text, "") }
        let half = text.count / 2
        var length = 0
        var splitIndex = words.count
        for (index, word) in words.enumerated() {
            length += word.count + 1
            if length >= half {
                splitIndex = index + 1
                break
            }
        }
        return (words[..<splitIndex].joined(separator: " "), words[splitIndex...].joined(separator: " "))
    }

    // MARK: - Highlights

    /// The first line is the key finding; the rest support it.
    private func highlights(_ stats: InsightsStats) -> [String] {
        let format = range.bucket.dateFormat
        switch metric {
        case .infestation:
            var lines: [String] = []
            let populated = stats.trend.filter { $0.total > 0 }
            if let peak = populated.max(by: { $0.rate < $1.rate }) {
                lines.append("Infestation peaked at \(peak.rate.percentText) on \(peak.date.formatted(format)).")
            }
            if let low = populated.min(by: { $0.rate < $1.rate }), populated.count > 1 {
                lines.append("It was lowest at \(low.rate.percentText) on \(low.date.formatted(format)).")
            }
            let serious = stats.severityCounts.filter { $0.severity >= .moderate }.reduce(0) { $0 + $1.count }
            lines.append("\(serious) of \(stats.scanCount) scans were moderate or severe.")
            return lines
        case .leafHealth:
            let healthyShare = stats.totalLeaves == 0 ? 0 : Double(stats.healthyLeaves) / Double(stats.totalLeaves)
            return ["\(healthyShare.percentText) of detected leaves were healthy.",
                    "\(stats.healthyLeaves) healthy and \(stats.aphidLeaves) aphid-infested leaves across \(stats.scanCount) scans."]
        case .scans:
            guard let busiest = stats.trend.max(by: { $0.scans < $1.scans }) else { return [] }
            return ["Most scans were logged on \(busiest.date.formatted(format)) (\(busiest.scans)).",
                    "\(stats.scanCount) scans across \(stats.sessions.count) scanning sessions in this range."]
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
                return ["No verified detections yet.", "Open a scan in History and mark each detection as correct or wrong."]
            }
            return ["Precision is \(precision.percentText) and recall is \(recall.percentText).",
                    "Based on \(validation.total) detections verified in the field.",
                    "\(validation.falseNegatives) infested leaves were missed and \(validation.falsePositives) healthy leaves were flagged."]
        case .confidence:
            guard let mean = stats.meanConfidence else { return [] }
            var lines = ["Average confidence was \(mean.percentText) across \(stats.totalLeaves) boxes."]
            let byClass = LeafClass.allCases.compactMap { leafClass in
                stats.meanConfidenceByClass[leafClass].map { "\(leafClass.displayName) \($0.percentText)" }
            }
            if !byClass.isEmpty { lines.append("By class: \(byClass.joined(separator: ", ")).") }
            return lines
        case .performance:
            guard let fastest = stats.sessions.max(by: { $0.fps < $1.fps }) else { return [] }
            let passing = stats.sessions.filter { $0.fps >= fpsTarget }.count
            return ["\(passing) of \(stats.sessions.count) sessions met the \(fpsTarget.fixed(0)) FPS target.",
                    "The fastest session averaged \(fastest.fps.fixed(1)) FPS in \(fastest.field).",
                    "Mean inference time was \(stats.averageInferenceMs.fixed(1)) ms per logged scan."]
        }
    }
}

/// A Health-style section: large title above a full-width card.
private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.bold))
                .padding(.horizontal, 4)
            content
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.elevatedCard, in: .rect(cornerRadius: 20))
        }
    }
}
