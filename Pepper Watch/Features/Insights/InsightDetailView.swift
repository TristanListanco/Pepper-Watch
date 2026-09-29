//
//  InsightDetailView.swift
//  Pepper Watch
//
//  Expanded view for one metric, with Health-style D / W / M / 6M / Y ranges.
//

import SwiftData
import SwiftUI

struct InsightDetailView: View {
    let metric: InsightMetric
    let fieldID: UUID?

    @Query(sort: \DetectionEvent.timestamp) private var events: [DetectionEvent]
    @Query(sort: \ScanSession.startedAt) private var sessions: [ScanSession]
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0
    @State private var range: InsightsRange = .week
    @State private var showFullMap = false

    var body: some View {
        let start = range.startDate
        let scopedEvents = events.filter { $0.timestamp >= start && (fieldID == nil || $0.field?.id == fieldID) }
        let scopedSessions = sessions.filter { $0.startedAt >= start && (fieldID == nil || $0.field?.id == fieldID) }
        let stats = InsightsStats(events: scopedEvents, sessions: scopedSessions, bucket: range.bucket)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $range.animation(.smooth)) {
                    ForEach(InsightsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                headline(stats)

                if scopedEvents.isEmpty {
                    ContentUnavailableView("No Data in This Range", systemImage: metric.symbol, description: Text("Try a longer range or scan a field."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ChartCard(title: chartTitle) { mainChart(stats, events: scopedEvents) }
                    secondaryContent(stats)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("About \(metric.title)")
                        .font(.title3.weight(.semibold))
                    Text(metric.about)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.card, in: .rect(cornerRadius: 20))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
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
        case .fields: ("HIGHEST", stats.fieldRates.first.map { $0.rate.percentText } ?? "—", stats.fieldRates.first?.field ?? "")
        case .accuracy: ("F1-SCORE", stats.validation.f1.map(\.percentText) ?? "—", "\(stats.validation.total) verified")
        case .confidence: ("AVERAGE", stats.meanConfidence.map(\.percentText) ?? "—", "confidence")
        case .performance: ("AVERAGE", stats.averageFPS.map { $0.fixed(1) } ?? "—", "FPS")
        }
    }

    // MARK: - Charts

    private var chartTitle: String {
        switch metric {
        case .infestation: "Infestation over time"
        case .leafHealth: "Leaves by class"
        case .scans: "Scans by severity"
        case .fields: "Infestation by field"
        case .accuracy: "Confusion matrix"
        case .confidence: "Confidence distribution"
        case .performance: "Average FPS per session"
        }
    }

    @ViewBuilder
    private func mainChart(_ stats: InsightsStats, events: [DetectionEvent]) -> some View {
        switch metric {
        case .infestation:
            InfestationTrendChart(trend: stats.trend, unit: range.bucket)
        case .leafHealth:
            DailyDetectionsChart(counts: stats.classCounts, unit: range.bucket)
        case .scans:
            ScanActivityChart(buckets: ScanActivityChart.buckets(for: events, unit: range.bucket), unit: range.bucket)
                .frame(height: 240)
        case .fields:
            FieldRatesChart(fields: stats.fieldRates)
        case .accuracy:
            ValidationMatrixView(metrics: stats.validation)
        case .confidence:
            ConfidenceHistogramChart(bins: stats.confidenceBins)
        case .performance:
            SessionPerformanceChart(sessions: stats.sessions, target: fpsTarget)
        }
    }

    @ViewBuilder
    private func secondaryContent(_ stats: InsightsStats) -> some View {
        switch metric {
        case .infestation:
            ChartCard(title: "Scan severity") { SeverityBreakdownChart(counts: stats.severityCounts) }
            if let severity = stats.overallSeverity {
                RecommendationCard(severity: severity, context: "Guidance for this period")
            }
        case .leafHealth:
            ChartCard(title: "Share of leaves") { LeafHealthDonut(aphid: stats.aphidLeaves, healthy: stats.healthyLeaves) }
        case .scans:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(title: "Sessions", value: stats.sessions.count.formatted(), symbol: "timer")
                StatTile(title: "Leaves per scan", value: stats.scanCount == 0 ? "—" : (Double(stats.totalLeaves) / Double(stats.scanCount)).fixed(1), symbol: "leaf")
            }
        case .fields:
            if !stats.mapPoints.isEmpty {
                ChartCard(title: "Hotspots", subtitle: "Geotagged scans colored by severity") {
                    FieldMapView(points: stats.mapPoints, interactive: false)
                        .frame(height: 240)
                        .clipShape(.rect(cornerRadius: 16))
                        .onTapGesture { showFullMap = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens the full map")
                }
            }
        case .accuracy:
            if stats.validation.total == 0 {
                Label("Open a scan in History and mark each detection as correct or wrong to measure accuracy in the field.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.card, in: .rect(cornerRadius: 20))
            }
        case .confidence:
            EmptyView()
        case .performance:
            let passing = stats.sessions.filter { $0.fps >= fpsTarget }.count
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(title: "Met target", value: "\(passing)/\(stats.sessions.count)", detail: "≥ \(fpsTarget.fixed(0)) FPS", symbol: "checkmark.circle")
                StatTile(title: "Mean inference", value: "\(stats.averageInferenceMs.fixed(1)) ms", detail: "Per logged scan", symbol: "cpu")
            }
        }
    }
}
