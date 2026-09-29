//
//  ScanActivityChart.swift
//  Pepper Watch
//

import Charts
import SwiftUI

/// Logged scans per time bucket, stacked by severity (reserved status colors, labeled legend).
struct ScanActivityChart: View {
    struct Bucket: Identifiable {
        var id: String { "\(date.timeIntervalSince1970)-\(severity.rawValue)" }
        let date: Date
        let severity: Severity
        let count: Int
    }

    let buckets: [Bucket]
    var unit: Calendar.Component = .day
    /// When bound, tapping a bar selects that bucket (and tapping it again clears it).
    var selection: Binding<Date?>?

    static func buckets(for events: [DetectionEvent], unit: Calendar.Component, calendar: Calendar = .current) -> [Bucket] {
        var counts: [Date: [Severity: Int]] = [:]
        for event in events {
            guard let severity = event.severity else { continue }
            let start = calendar.dateInterval(of: unit, for: event.timestamp)?.start ?? calendar.startOfDay(for: event.timestamp)
            counts[start, default: [:]][severity, default: 0] += 1
        }
        return counts.keys.sorted().flatMap { date in
            Severity.allCases.compactMap { severity in
                counts[date]?[severity].map { Bucket(date: date, severity: severity, count: $0) }
            }
        }
    }

    private var selectedDate: Date? { selection?.wrappedValue }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value("Date", bucket.date, unit: unit), y: .value("Scans", bucket.count))
                    .foregroundStyle(by: .value("Severity", bucket.severity.title))
                    .opacity(selectedDate == nil || Calendar.current.isDate(bucket.date, equalTo: selectedDate!, toGranularity: unit) ? 1 : 0.3)
                    .cornerRadius(2)
            }
        }
        .chartForegroundStyleScale(domain: Severity.allCases.map(\.title), range: Severity.allCases.map(\.color))
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let selection, let plotFrame = proxy.plotFrame {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(.rect)
                        .onTapGesture { location in
                            let x = location.x - geometry[plotFrame].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            let start = Calendar.current.dateInterval(of: unit, for: date)?.start ?? date
                            withAnimation(.snappy) {
                                if let current = selection.wrappedValue, Calendar.current.isDate(current, equalTo: start, toGranularity: unit) {
                                    selection.wrappedValue = nil
                                } else if buckets.contains(where: { Calendar.current.isDate($0.date, equalTo: start, toGranularity: unit) }) {
                                    selection.wrappedValue = start
                                }
                            }
                        }
                }
            }
        }
        .accessibilityLabel("Scans per \(unit == .hour ? "hour" : "day") by severity")
    }
}
