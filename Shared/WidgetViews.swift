//
//  WidgetViews.swift
//  Pepper Watch (shared with the widget extension)
//
//  Home Screen and Lock Screen widget layouts. Shared so the app can preview them.
//

import AppIntents
import Charts
import SwiftUI
import WidgetKit

nonisolated enum WidgetPalette {
    /// Brand green (#2F8A3B) and the aphid-infested class orange (#EB6834).
    static let brand = Color(red: 0.184, green: 0.541, blue: 0.231)
    static let aphid = Color(red: 0.922, green: 0.408, blue: 0.204)

    /// Background gradient for colorful Home Screen widgets, following the severity status colors
    /// but deep enough for white text.
    static func gradient(for severity: Severity?) -> [Color] {
        switch severity {
        case .clear?: [Color(red: 0.14, green: 0.65, blue: 0.35), Color(red: 0.05, green: 0.42, blue: 0.22)]
        case .low?: [Color(red: 0.80, green: 0.56, blue: 0.05), Color(red: 0.53, green: 0.34, blue: 0.0)]
        case .moderate?: [Color(red: 0.89, green: 0.41, blue: 0.18), Color(red: 0.60, green: 0.21, blue: 0.06)]
        case .severe?: [Color(red: 0.84, green: 0.21, blue: 0.24), Color(red: 0.52, green: 0.07, blue: 0.12)]
        case nil: [Color(red: 0.18, green: 0.54, blue: 0.23), Color(red: 0.08, green: 0.33, blue: 0.13)]
        }
    }
}

/// Severity-tinted gradient behind colorful widgets.
struct WidgetBackground: View {
    let severity: Severity?

    var body: some View {
        LinearGradient(colors: WidgetPalette.gradient(for: severity), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Field Status widget

struct FieldStatusWidgetView: View {
    let status: WidgetSnapshot.FieldStatus
    var fields: [WidgetSnapshot.FieldStatus] = []
    let family: WidgetFamily
    var now: Date = .now
    /// White content for the severity gradient background.
    var onColor = false

    var body: some View {
        let window = status.window(now: now)
        Group {
            switch family {
            case .systemMedium:
                HStack(spacing: 16) {
                    StatusSummary(status: status, window: window, onColor: onColor)
                        .frame(width: 124, alignment: .leading)
                    WeeklyTrendChart(daily: window.daily, now: now, onColor: onColor)
                }
            case .systemLarge:
                LargeFieldStatus(status: status, window: window, fields: fields, now: now, onColor: onColor)
            case .accessoryCircular:
                Gauge(value: window.infestationRate, in: 0...1) {
                    Image(systemName: "ant.fill")
                } currentValueLabel: {
                    Text(window.totalLeaves == 0 ? "–" : "\(Int((window.infestationRate * 100).rounded()))")
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel("\(status.name): \(window.infestationRate.widgetPercent) infested")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label(status.name, systemImage: window.severity?.symbol ?? "leaf")
                        .font(.headline)
                        .widgetAccentable()
                    Text(window.totalLeaves == 0 ? "No scans this week" : "\(window.infestationRate.widgetPercent) infested")
                    Text("\(window.severity?.title ?? "—") · \(window.scans) scans")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                Label(
                    window.totalLeaves == 0 ? "\(status.name): no scans" : "\(status.name) \(window.infestationRate.widgetPercent) · \(window.severity?.title ?? "")",
                    systemImage: "ant.fill"
                )
            default:
                StatusSummary(status: status, window: window, onColor: onColor)
            }
        }
        .foregroundStyle(onColor ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

/// Field name, 7-day infestation rate and severity.
private struct StatusSummary: View {
    let status: WidgetSnapshot.FieldStatus
    let window: WidgetSnapshot.WindowSummary
    let onColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(onColor ? .white : WidgetPalette.brand)
                Text(status.name)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))

            Spacer(minLength: 4)

            Text(window.totalLeaves == 0 ? "—" : window.infestationRate.widgetPercent)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text("infested · 7 days")
                .font(.caption2)
                .opacity(0.8)

            Spacer(minLength: 4)

            SeverityTag(severity: window.severity, onColor: onColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SeverityTag: View {
    let severity: Severity?
    var onColor = false

    var body: some View {
        Label {
            Text(severity?.title ?? "No scans")
        } icon: {
            Image(systemName: severity?.symbol ?? "camera.viewfinder")
                .foregroundStyle(onColor ? AnyShapeStyle(.white) : AnyShapeStyle(severity?.color ?? .secondary))
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
}

private struct WeeklyTrendChart: View {
    let daily: [WidgetSnapshot.DailyCount]
    let now: Date
    var onColor = false

    var body: some View {
        let line = onColor ? Color.white : WidgetPalette.aphid
        if daily.isEmpty {
            Text("No scans this week")
                .font(.caption)
                .opacity(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(daily) { day in
                AreaMark(x: .value("Day", day.date, unit: .day), y: .value("Infested", day.rate))
                    .foregroundStyle(LinearGradient(colors: [line.opacity(0.35), line.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", day.date, unit: .day), y: .value("Infested", day.rate))
                    .foregroundStyle(line)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", day.date, unit: .day), y: .value("Infested", day.rate))
                    .foregroundStyle(line)
                    .symbolSize(18)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXScale(domain: weekDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .foregroundStyle(onColor ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }
            .accessibilityLabel("Daily infestation over the past week")
        }
    }

    private var weekDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return start...end
    }
}

private struct LargeFieldStatus: View {
    let status: WidgetSnapshot.FieldStatus
    let window: WidgetSnapshot.WindowSummary
    let fields: [WidgetSnapshot.FieldStatus]
    let now: Date
    let onColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(status.name, systemImage: "leaf.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(onColor ? .white : WidgetPalette.brand)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(window.totalLeaves == 0 ? "—" : window.infestationRate.widgetPercent)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text("infested · 7 days")
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
                Spacer()
                SeverityTag(severity: window.severity, onColor: onColor)
            }

            WeeklyTrendChart(daily: window.daily, now: now, onColor: onColor)
                .frame(height: 110)

            Divider()
                .overlay(onColor ? Color.white.opacity(0.4) : Color.clear)

            ForEach(fields.prefix(4)) { field in
                let fieldWindow = field.window(now: now)
                HStack {
                    Image(systemName: fieldWindow.severity?.symbol ?? "leaf")
                        .foregroundStyle(onColor ? AnyShapeStyle(.white) : AnyShapeStyle(fieldWindow.severity?.color ?? .secondary))
                    Text(field.name)
                        .lineLimit(1)
                    Spacer()
                    Text(fieldWindow.totalLeaves == 0 ? "—" : fieldWindow.infestationRate.widgetPercent)
                        .monospacedDigit()
                        .opacity(0.85)
                }
                .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Field Actions widget (interactive)

/// Flip between fields with the ‹ › buttons, then jump into scanning or insights.
struct FieldActionsWidgetView: View {
    let options: [WidgetSnapshot.FieldStatus]
    let index: Int
    let family: WidgetFamily
    var now: Date = .now

    var body: some View {
        let status = options.isEmpty ? nil : options[min(max(index, 0), options.count - 1)]
        let window = status?.window(now: now)
        Group {
            if let status, let window {
                if family == .systemMedium {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            header(status)
                            Spacer(minLength: 2)
                            rate(window)
                            Spacer(minLength: 2)
                            pager
                        }
                        VStack(spacing: 8) {
                            Link(destination: .pepperWatch("scan", fieldID: status.id)) {
                                actionPill("Scan", systemImage: "camera.viewfinder")
                            }
                            Link(destination: .pepperWatch("insights", fieldID: status.id)) {
                                actionPill("Insights", systemImage: "chart.bar.xaxis")
                            }
                        }
                        .frame(width: 118)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        header(status)
                        Spacer(minLength: 2)
                        rate(window)
                        Spacer(minLength: 2)
                        pager
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.largeTitle)
                    Text("Open Pepper Watch to set up a field.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ status: WidgetSnapshot.FieldStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "leaf.fill")
            Text(status.name)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
    }

    private func rate(_ window: WidgetSnapshot.WindowSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(window.totalLeaves == 0 ? "—" : window.infestationRate.widgetPercent)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            SeverityTag(severity: window.severity, onColor: true)
        }
    }

    private var pager: some View {
        HStack(spacing: 6) {
            Button(intent: CycleFieldIntent(forward: false)) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.22), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous field")

            Text("\(min(index, options.count - 1) + 1) of \(options.count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)

            Button(intent: CycleFieldIntent(forward: true)) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.22), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next field")
        }
    }

    private func actionPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.22), in: .rect(cornerRadius: 14))
    }
}

extension Double {
    var widgetPercent: String { formatted(.percent.precision(.fractionLength(0))) }
}
