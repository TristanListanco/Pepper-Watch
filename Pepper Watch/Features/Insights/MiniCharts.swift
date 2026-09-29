//
//  MiniCharts.swift
//  Pepper Watch
//
//  Small, axis-free Swift Charts for the Health-style summary cards.
//

import Charts
import SwiftUI

struct MiniPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

struct SparklineChart: View {
    let points: [MiniPoint]
    let color: Color
    var domain: ClosedRange<Double>?
    var reference: Double?

    var body: some View {
        Chart {
            if let reference {
                RuleMark(y: .value("Reference", reference))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                    .foregroundStyle(color)
                    .symbolSize(36)
            }
        }
        .chartYScale(domain: domain ?? 0...max(points.map(\.value).max() ?? 1, 0.0001))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

struct MiniBarChart: View {
    let points: [MiniPoint]
    let color: Color

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Date", point.date, unit: .day), y: .value("Value", point.value))
                .foregroundStyle(point.id == points.last?.id ? color : color.opacity(0.45))
                .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

struct MiniDonut: View {
    let aphid: Int
    let healthy: Int

    var body: some View {
        Chart {
            SectorMark(angle: .value("Leaves", max(aphid, 0)), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(LeafClass.aphidInfested.color)
            SectorMark(angle: .value("Leaves", max(healthy, aphid + healthy == 0 ? 1 : 0)), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(aphid + healthy == 0 ? Color.secondary.opacity(0.3) : LeafClass.healthy.color)
        }
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

struct MiniHistogram: View {
    let bins: [InsightsStats.ConfidenceBin]

    var body: some View {
        let totals = Dictionary(grouping: bins, by: \.lowerBound).map { (lower: $0.key, count: $0.value.reduce(0) { $0 + $1.count }) }
            .sorted { $0.lower < $1.lower }
        Chart(totals, id: \.lower) { bin in
            BarMark(x: .value("Confidence", bin.lower), y: .value("Count", bin.count), width: .ratio(0.8))
                .foregroundStyle(.purple.gradient)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

struct MiniRankBars: View {
    let fields: [InsightsStats.FieldRate]

    var body: some View {
        Chart(fields.prefix(3)) { field in
            BarMark(x: .value("Infested", field.rate), y: .value("Field", field.field))
                .foregroundStyle(LeafClass.aphidInfested.color)
                .cornerRadius(2)
        }
        .chartXScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

struct MiniMatrix: View {
    let metrics: ValidationMetrics

    var body: some View {
        let values = [metrics.truePositives, metrics.falsePositives, metrics.falseNegatives, metrics.trueNegatives]
        let maxValue = Double(max(values.max() ?? 1, 1))
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                cell(values[0], maxValue)
                cell(values[1], maxValue)
            }
            GridRow {
                cell(values[2], maxValue)
                cell(values[3], maxValue)
            }
        }
        .accessibilityHidden(true)
    }

    private func cell(_ value: Int, _ maxValue: Double) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(red: 0.165, green: 0.471, blue: 0.839).opacity(0.12 + 0.6 * Double(value) / maxValue))
    }
}
