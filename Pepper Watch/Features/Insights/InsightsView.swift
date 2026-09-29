//
//  InsightsView.swift
//  Pepper Watch
//

import SwiftData
import SwiftUI

enum InsightsRange: String, CaseIterable, Identifiable {
    case day = "24H"
    case week = "7D"
    case month = "30D"
    case all = "All"

    var id: String { rawValue }

    var startDate: Date {
        switch self {
        case .day: Date.now.addingTimeInterval(-86_400)
        case .week: Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        case .month: Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        case .all: .distantPast
        }
    }
}

struct InsightsView: View {
    @State private var range: InsightsRange = .week

    var body: some View {
        NavigationStack {
            InsightsContent(range: $range)
                .navigationTitle("Insights")
        }
    }
}

private struct InsightsContent: View {
    @Binding var range: InsightsRange
    @Query private var events: [DetectionEvent]
    @Query private var sessions: [ScanSession]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0
    @State private var showFullMap = false

    init(range: Binding<InsightsRange>) {
        _range = range
        let start = range.wrappedValue.startDate
        _events = Query(filter: #Predicate<DetectionEvent> { $0.timestamp >= start }, sort: \.timestamp)
        _sessions = Query(filter: #Predicate<ScanSession> { $0.startedAt >= start }, sort: \.startedAt)
    }

    var body: some View {
        let stats = InsightsStats(events: events, sessions: sessions)
        ScrollView {
            VStack(spacing: 16) {
                Picker("Time range", selection: $range.animation()) {
                    ForEach(InsightsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if events.isEmpty {
                    emptyState
                } else {
                    dashboard(stats)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if !events.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: CSVExporter.detections(events), preview: SharePreview("Pepper Watch detections")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Detections Yet", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Scan a pepper field or analyze a photo to build your dashboard. You can also load demo data to explore the charts.")
        } actions: {
            Button("Load Demo Data", systemImage: "wand.and.stars") {
                withAnimation { DemoDataGenerator.generate(in: modelContext) }
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func dashboard(_ stats: InsightsStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(title: "Scans logged", value: stats.scanCount.formatted(), detail: "\(stats.sessions.count) sessions", symbol: "camera.viewfinder")
            StatTile(title: "Leaves analyzed", value: stats.totalLeaves.formatted(), detail: "\(stats.aphidLeaves) infested", symbol: "leaf")
            StatTile(title: "Infestation rate", value: stats.infestationRate.percentText, detail: "Share of infested leaves", symbol: "ant")
            VStack(alignment: .leading, spacing: 8) {
                Label("Latest scan", systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                SeverityBadge(severity: stats.latestSeverity)
                Text(stats.latestSeverity?.rangeDescription ?? "No leaves detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .background(.card, in: .rect(cornerRadius: 20))
            .accessibilityElement(children: .combine)
        }

        if let severity = stats.overallSeverity {
            RecommendationCard(severity: severity, context: "Overall status for this period")
        }

        ChartCard(title: "Leaf Health", subtitle: "All leaves detected in logged scans") {
            LeafHealthDonut(aphid: stats.aphidLeaves, healthy: stats.healthyLeaves)
        }

        ChartCard(title: "Infestation Trend", subtitle: "Daily share of aphid-infested leaves. Tap to inspect a day.") {
            InfestationTrendChart(daily: stats.daily)
        }

        ChartCard(title: "Leaves per Day", subtitle: "Detections by class") {
            DailyDetectionsChart(counts: stats.dailyClassCounts)
        }

        ChartCard(title: "Scan Severity", subtitle: "How many logged scans fell into each level") {
            SeverityBreakdownChart(counts: stats.severityCounts)
        }

        if stats.fieldRates.count > 1 {
            ChartCard(title: "Infestation by Field", subtitle: "Where to act first") {
                FieldRatesChart(fields: stats.fieldRates)
            }
        }

        if !stats.mapPoints.isEmpty {
            ChartCard(title: "Field Hotspots", subtitle: "Geotagged scans colored by severity") {
                FieldMapView(points: stats.mapPoints, interactive: false)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 16))
                    .onTapGesture { showFullMap = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens the full map")
            }
        }

        ChartCard(title: "Field Validation", subtitle: validationSubtitle(stats.validation)) {
            ValidationMatrixView(metrics: stats.validation)
        }

        ChartCard(title: "Detection Confidence", subtitle: "Model probability scores per class") {
            ConfidenceHistogramChart(bins: stats.confidenceBins)
        }

        if !stats.sessions.isEmpty {
            ChartCard(title: "Real-time Performance", subtitle: "Average FPS per scanning session vs. the thesis target") {
                SessionPerformanceChart(sessions: stats.sessions, target: fpsTarget)
                let passing = stats.sessions.filter { $0.fps >= fpsTarget }.count
                Text("\(passing) of \(stats.sessions.count) sessions met ≥ \(fpsTarget.fixed(0)) FPS · \(stats.averageInferenceMs.fixed(1)) ms mean inference")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func validationSubtitle(_ metrics: ValidationMetrics) -> String {
        metrics.total == 0
            ? "Confirm or reject detections in History to measure field accuracy."
            : "\(metrics.total) detections verified in the field"
    }
}

#Preview {
    InsightsView()
        .modelContainer(PreviewSupport.container)
}
