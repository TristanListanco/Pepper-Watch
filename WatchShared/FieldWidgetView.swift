//
//  FieldWidgetView.swift
//  Pepper Watch (shared by the Apple Watch app and its widgets)
//

import SwiftUI
import WidgetKit

/// One layout per watch widget family: the Smart Stack card, and the circular, corner and inline
/// complications. Each shows the metric chosen when configuring the widget.
struct FieldWidgetView: View {
    let entry: FieldEntry
    /// Set by the app's debug gallery; widgets use the family WidgetKit provides.
    var previewFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var widgetFamily

    private var family: WidgetFamily { previewFamily ?? widgetFamily }

    var body: some View {
        Group {
            if let status = entry.status {
                content(status, stats: ScopeStats(status, now: entry.date))
            } else {
                Label("Open Pepper Watch", systemImage: "leaf.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(tint.gradient.opacity(0.6), for: .widget)
        .widgetURL(entry.status.map { URL.watchField($0.id) })
    }

    /// Smart Stack background in the field's severity color.
    private var tint: Color {
        entry.status.flatMap { ScopeStats($0, now: entry.date).current.severity?.color } ?? .brand
    }

    /// The configured number, ready for any family.
    private struct Reading {
        let value: String
        let unit: String
        /// Fill for gauges; `nil` for counts, which have no natural maximum.
        let fraction: Double?
        let gradient: Gradient
        let symbol: String
    }

    private func reading(_ stats: ScopeStats) -> Reading {
        let total = stats.current.totalLeaves
        switch entry.metric {
        case .infestation:
            let rate = stats.current.infestationRate
            return Reading(value: stats.hasLeaves ? rate.percentText : "—", unit: "infested", fraction: rate,
                           gradient: Gradient(colors: [.healthy, .aphid]), symbol: "ant.fill")
        case .leafHealth:
            let share = total == 0 ? 0 : Double(stats.healthyLeaves) / Double(total)
            return Reading(value: stats.hasLeaves ? share.percentText : "—", unit: "healthy", fraction: share,
                           gradient: Gradient(colors: [.aphid, .healthy]), symbol: "leaf.fill")
        case .scans:
            let scans = stats.current.scans
            return Reading(value: "\(scans)", unit: scans == 1 ? "scan" : "scans", fraction: nil,
                           gradient: Gradient(colors: [.brand]), symbol: "camera.viewfinder")
        }
    }

    @ViewBuilder
    private func content(_ status: WidgetSnapshot.FieldStatus, stats: ScopeStats) -> some View {
        let reading = reading(stats)
        switch family {
        case .accessoryCircular:
            Group {
                if let fraction = reading.fraction {
                    Gauge(value: fraction) {
                        Image(systemName: reading.symbol)
                    } currentValueLabel: {
                        Text(stats.hasLeaves ? "\(Int((fraction * 100).rounded()))" : "—")
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(reading.gradient)
                } else {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 0) {
                            Image(systemName: reading.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(reading.value)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .accessibilityLabel("\(status.name): \(reading.value) \(reading.unit)")
        case .accessoryCorner:
            Text(reading.value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .widgetCurvesContent()
                .widgetLabel {
                    if let fraction = reading.fraction {
                        Gauge(value: fraction) {
                            Text(status.name)
                        }
                        .tint(reading.gradient)
                    } else {
                        Text("\(status.name) \(reading.unit)")
                    }
                }
        case .accessoryInline:
            Label {
                Text(stats.hasLeaves || entry.metric == .scans ? "\(status.name) \(reading.value) \(reading.unit)" : "\(status.name): no scans")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: reading.symbol)
            }
        default:
            rectangular(status, stats: stats, reading: reading)
        }
    }

    /// The Smart Stack card: field, the number, and one line from Apple Intelligence.
    private func rectangular(_ status: WidgetSnapshot.FieldStatus, stats: ScopeStats, reading: Reading) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: reading.symbol)
                    .foregroundStyle(.secondary)
                Text(status.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let severity = stats.current.severity {
                    Image(systemName: severity.symbol)
                        .foregroundStyle(severity.color)
                }
            }
            .font(.headline)
            .widgetAccentable()

            Group {
                if stats.hasLeaves || entry.metric == .scans {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(reading.value)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(reading.unit)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No scans this week")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Group {
                if let headline = entry.headline {
                    Text(headline)
                } else if let severity = stats.current.severity {
                    Text(severity.title)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
