//
//  InsightsCharts.swift
//  Pepper Watch
//

import Charts
import MapKit
import SwiftUI

private extension View {
    /// Both classes keep a fixed color so filtering never repaints a series.
    func leafClassColorScale() -> some View {
        chartForegroundStyleScale(
            domain: LeafClass.allCases.map(\.displayName),
            range: LeafClass.allCases.map(\.color)
        )
    }
}

private struct ChartTooltip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) { content }
            .font(.caption)
            .padding(8)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

// MARK: - Leaf health distribution

struct LeafHealthDonut: View {
    let aphid: Int
    let healthy: Int

    private var slices: [(leafClass: LeafClass, count: Int)] {
        [(.aphidInfested, aphid), (.healthy, healthy)]
    }

    private var rate: Double {
        aphid + healthy == 0 ? 0 : Double(aphid) / Double(aphid + healthy)
    }

    var body: some View {
        VStack(spacing: 16) {
            Chart(slices, id: \.leafClass) { slice in
                SectorMark(
                    angle: .value("Leaves", slice.count),
                    innerRadius: .ratio(0.64),
                    angularInset: 2
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Class", slice.leafClass.displayName))
            }
            .leafClassColorScale()
            .chartLegend(.hidden)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        VStack(spacing: 0) {
                            Text(rate.percentText)
                                .font(.title.weight(.bold))
                            Text("infested")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 200)

            // Legend doubles as direct labels: icon + name + count + share.
            HStack(spacing: 24) {
                ForEach(slices, id: \.leafClass) { slice in
                    HStack(spacing: 8) {
                        Image(systemName: slice.leafClass.symbol)
                            .foregroundStyle(slice.leafClass.color)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(slice.leafClass.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(slice.count) · \((aphid + healthy == 0 ? 0 : Double(slice.count) / Double(aphid + healthy)).percentText)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Infestation trend

struct InfestationTrendChart: View {
    let daily: [InsightsStats.DailyPoint]
    @State private var selectedDay: Date?

    private var selectedPoint: InsightsStats.DailyPoint? {
        guard let selectedDay else { return nil }
        return daily.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    var body: some View {
        let lineColor = LeafClass.aphidInfested.color
        Chart {
            ForEach([(Severity.moderate, Severity.moderateThreshold), (Severity.severe, Severity.severeThreshold)], id: \.0) { severity, threshold in
                RuleMark(y: .value("Threshold", threshold))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Label(severity.title, systemImage: severity.symbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            ForEach(daily) { point in
                AreaMark(x: .value("Day", point.day, unit: .day), y: .value("Infested", point.rate))
                    .foregroundStyle(LinearGradient(colors: [lineColor.opacity(0.25), lineColor.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.day, unit: .day), y: .value("Infested", point.rate))
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", point.day, unit: .day), y: .value("Infested", point.rate))
                    .foregroundStyle(lineColor)
                    .symbolSize(selectedPoint?.day == point.day ? 90 : 30)
            }

            if let selectedPoint {
                RuleMark(x: .value("Day", selectedPoint.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip {
                            Text(selectedPoint.day, format: .dateTime.month().day())
                                .foregroundStyle(.secondary)
                            Text("\(selectedPoint.rate.percentText) infested")
                                .font(.caption.weight(.semibold))
                            Text("\(selectedPoint.aphid) of \(selectedPoint.total) leaves · \(selectedPoint.scans) scans")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) { Text(rate.percentText) }
                }
            }
        }
        .chartXSelection(value: $selectedDay)
        .frame(height: 220)
    }
}

// MARK: - Daily detections by class

struct DailyDetectionsChart: View {
    let counts: [InsightsStats.DailyClassCount]
    @State private var selectedDay: Date?

    var body: some View {
        Chart {
            ForEach(counts) { item in
                BarMark(x: .value("Day", item.day, unit: .day), y: .value("Leaves", item.count))
                    .foregroundStyle(by: .value("Class", item.leafClass.displayName))
                    .cornerRadius(3)
            }
            if let selectedDay {
                let dayCounts = counts.filter { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
                if let first = dayCounts.first {
                    RuleMark(x: .value("Day", first.day, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.15))
                        .lineStyle(StrokeStyle(lineWidth: 16))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip {
                                Text(first.day, format: .dateTime.month().day())
                                    .foregroundStyle(.secondary)
                                ForEach(dayCounts) { item in
                                    Label("\(item.leafClass.displayName): \(item.count)", systemImage: item.leafClass.symbol)
                                }
                            }
                        }
                }
            }
        }
        .leafClassColorScale()
        .chartLegend(position: .top, alignment: .leading)
        .chartXSelection(value: $selectedDay)
        .frame(height: 220)
    }
}

// MARK: - Severity of logged scans

struct SeverityBreakdownChart: View {
    let counts: [InsightsStats.SeverityCount]

    var body: some View {
        Chart(counts) { item in
            BarMark(x: .value("Scans", item.count), y: .value("Severity", item.severity.title))
                .foregroundStyle(item.severity.color)
                .cornerRadius(4)
                .annotation(position: .trailing, spacing: 6) {
                    Text(item.count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let title = value.as(String.self), let severity = Severity.allCases.first(where: { $0.title == title }) {
                        Label(title, systemImage: severity.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 170)
    }
}

// MARK: - Infestation by field

struct FieldRatesChart: View {
    let fields: [InsightsStats.FieldRate]

    var body: some View {
        Chart(fields) { field in
            BarMark(x: .value("Infested", field.rate), y: .value("Field", field.field))
                .foregroundStyle(LeafClass.aphidInfested.color)
                .cornerRadius(4)
                .annotation(position: .trailing, spacing: 6) {
                    Text("\(field.rate.percentText) · \(field.total) leaves")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: 0...1.35)
        .chartXAxis(.hidden)
        .frame(height: CGFloat(max(fields.count, 1)) * 44 + 12)
    }
}

// MARK: - Confidence distribution

struct ConfidenceHistogramChart: View {
    let bins: [InsightsStats.ConfidenceBin]

    var body: some View {
        Chart(bins) { bin in
            BarMark(x: .value("Confidence", bin.label), y: .value("Detections", bin.count))
                .foregroundStyle(by: .value("Class", bin.leafClass.displayName))
                .position(by: .value("Class", bin.leafClass.displayName))
                .cornerRadius(3)
        }
        .leafClassColorScale()
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(orientation: .verticalReversed)
            }
        }
        .frame(height: 220)
    }
}

// MARK: - Field validation (confusion matrix)

struct ValidationMatrixView: View {
    let metrics: ValidationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("Actual\ninfested").gridColumnHeader()
                    Text("Actual\nhealthy").gridColumnHeader()
                }
                GridRow {
                    Text("Predicted\ninfested").gridRowHeader()
                    cell("TP", metrics.truePositives, note: "Correct")
                    cell("FP", metrics.falsePositives, note: "False alarm")
                }
                GridRow {
                    Text("Predicted\nhealthy").gridRowHeader()
                    cell("FN", metrics.falseNegatives, note: "Missed")
                    cell("TN", metrics.trueNegatives, note: "Correct")
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricTile("Precision", metrics.precision, formula: "TP / (TP + FP)")
                metricTile("Recall", metrics.recall, formula: "TP / (TP + FN)")
                metricTile("Accuracy", metrics.accuracy, formula: "(TP + TN) / all")
                metricTile("F1-score", metrics.f1, formula: "2PR / (P + R)")
            }
        }
    }

    private func cell(_ title: String, _ count: Int, note: String) -> some View {
        let maxCount = max(metrics.truePositives, metrics.falsePositives, metrics.trueNegatives, metrics.falseNegatives, 1)
        let intensity = Double(count) / Double(maxCount)
        // One-hue sequential ramp: darker means more boxes.
        return VStack(spacing: 2) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(count, format: .number).font(.title2.weight(.semibold).monospacedDigit())
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(Color(red: 0.165, green: 0.471, blue: 0.839).opacity(0.1 + intensity * 0.5), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func metricTile(_ title: String, _ value: Double?, formula: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map(\.percentText) ?? "—").font(.title3.weight(.semibold).monospacedDigit())
            Text(formula).font(.caption2.monospaced()).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.cardInset, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private extension Text {
    func gridColumnHeader() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }

    func gridRowHeader() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
    }
}

// MARK: - Session performance vs. thesis target

struct SessionPerformanceChart: View {
    let sessions: [InsightsStats.SessionPerformance]
    let target: Double
    @State private var selectedDate: Date?

    private var selected: InsightsStats.SessionPerformance? {
        guard let selectedDate else { return nil }
        return sessions.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        let passColor = Color.accentColor
        let failColor = Severity.severe.color
        Chart {
            RuleMark(y: .value("Target", target))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text("Target ≥ \(target.fixed(0)) FPS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            ForEach(sessions) { session in
                LineMark(x: .value("Session", session.date), y: .value("FPS", session.fps))
                    .foregroundStyle(passColor.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Session", session.date), y: .value("FPS", session.fps))
                    .foregroundStyle(session.fps >= target ? passColor : failColor)
                    .symbol(session.fps >= target ? .circle : .triangle)
                    .symbolSize(selected?.id == session.id ? 100 : 40)
            }

            if let selected {
                RuleMark(x: .value("Session", selected.date))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip {
                            Text(selected.date, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(.secondary)
                            Text("\(selected.fps.fixed(1)) FPS · \(selected.latencyMs.fixed(0)) ms")
                                .font(.caption.weight(.semibold))
                            Text("\(selected.field) · \(selected.computeUnits)")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .chartYScale(domain: 0...max(target * 2, (sessions.map(\.fps).max() ?? 0) * 1.1))
        .chartXSelection(value: $selectedDate)
        .frame(height: 200)
    }
}

// MARK: - Field map

struct FieldMapView: View {
    let points: [InsightsStats.MapPoint]
    var interactive = true

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
            ForEach(points) { point in
                Annotation(point.field, coordinate: point.coordinate, anchor: .center) {
                    let severity = point.severity ?? .clear
                    Image(systemName: severity.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(severity.color, in: .circle)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .accessibilityLabel("\(point.field): \(severity.title), \(point.summary.aphidCount) infested leaves")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
    }
}
