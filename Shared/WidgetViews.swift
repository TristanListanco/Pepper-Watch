//
//  WidgetViews.swift
//  Pepper Watch (shared with the widget extension)
//
//  Home Screen and Lock Screen widget layouts. Shared so the app can preview them.
//

import AppIntents
import SwiftUI
import WidgetKit

nonisolated enum WidgetPalette {
    /// Brand green (#2F8A3B) and the aphid-infested class orange (#EB6834).
    static let brand = Color(red: 0.184, green: 0.541, blue: 0.231)
    static let aphid = Color(red: 0.922, green: 0.408, blue: 0.204)

    /// Background gradient for colorful Home Screen widgets, following the severity status colors
    /// but deep enough for white text. Dark mode keeps only a deep tint of the same hue.
    static func gradient(for severity: Severity?, dark: Bool = false) -> [Color] {
        switch (severity, dark) {
        case (.clear?, false): [Color(red: 0.14, green: 0.65, blue: 0.35), Color(red: 0.05, green: 0.42, blue: 0.22)]
        case (.low?, false): [Color(red: 0.80, green: 0.56, blue: 0.05), Color(red: 0.53, green: 0.34, blue: 0.0)]
        case (.moderate?, false): [Color(red: 0.89, green: 0.41, blue: 0.18), Color(red: 0.60, green: 0.21, blue: 0.06)]
        case (.severe?, false): [Color(red: 0.84, green: 0.21, blue: 0.24), Color(red: 0.52, green: 0.07, blue: 0.12)]
        case (nil, false): [Color(red: 0.18, green: 0.54, blue: 0.23), Color(red: 0.08, green: 0.33, blue: 0.13)]
        case (.clear?, true): [Color(red: 0.06, green: 0.24, blue: 0.14), Color(red: 0.02, green: 0.08, blue: 0.05)]
        case (.low?, true): [Color(red: 0.27, green: 0.19, blue: 0.03), Color(red: 0.09, green: 0.06, blue: 0.01)]
        case (.moderate?, true): [Color(red: 0.30, green: 0.13, blue: 0.05), Color(red: 0.10, green: 0.04, blue: 0.02)]
        case (.severe?, true): [Color(red: 0.30, green: 0.07, blue: 0.09), Color(red: 0.10, green: 0.02, blue: 0.03)]
        case (nil, true): [Color(red: 0.07, green: 0.20, blue: 0.10), Color(red: 0.02, green: 0.07, blue: 0.04)]
        }
    }

    /// Bright severity color for the rate and status icon on the dark background.
    static func accent(for severity: Severity?) -> Color {
        switch severity {
        case .clear?: Color(red: 0.30, green: 0.82, blue: 0.50)
        case .low?: Color(red: 0.98, green: 0.74, blue: 0.20)
        case .moderate?: Color(red: 1.0, green: 0.56, blue: 0.33)
        case .severe?: Color(red: 1.0, green: 0.42, blue: 0.42)
        case nil: Color(red: 0.40, green: 0.80, blue: 0.48)
        }
    }
}

/// Severity-tinted gradient behind colorful widgets; a deep tint in dark mode.
struct WidgetBackground: View {
    let severity: Severity?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: WidgetPalette.gradient(for: severity, dark: colorScheme == .dark),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Field Status widget (Lock Screen)

struct FieldStatusWidgetView: View {
    let status: WidgetSnapshot.FieldStatus
    let family: WidgetFamily
    var now: Date = .now

    var body: some View {
        let window = status.window(now: now)
        switch family {
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
        default:
            Label(
                window.totalLeaves == 0 ? "\(status.name): no scans" : "\(status.name) \(window.infestationRate.widgetPercent) · \(window.severity?.title ?? "")",
                systemImage: "ant.fill"
            )
        }
    }
}

private struct SeverityTag: View {
    let severity: Severity?
    let iconColor: Color

    var body: some View {
        Label {
            Text(severity?.title ?? "No scans")
        } icon: {
            Image(systemName: severity?.symbol ?? "camera.viewfinder")
                .foregroundStyle(iconColor)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
}

// MARK: - Field Actions widget (interactive)

/// Flip between fields with the ‹ › buttons, then jump into scanning or insights.
struct FieldActionsWidgetView: View {
    let options: [WidgetSnapshot.FieldStatus]
    let index: Int
    let family: WidgetFamily
    var now: Date = .now

    @Environment(\.colorScheme) private var colorScheme

    /// White text on the colorful gradient; bright severity accents on the dark background.
    private var isDark: Bool { colorScheme == .dark }
    private var controlFill: Color { .white.opacity(isDark ? 0.14 : 0.22) }

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
                .foregroundStyle(isDark ? WidgetPalette.accent(for: window.severity) : .white)
            SeverityTag(severity: window.severity, iconColor: isDark ? WidgetPalette.accent(for: window.severity) : .white)
        }
    }

    private var pager: some View {
        HStack(spacing: 6) {
            Button(intent: CycleFieldIntent(forward: false)) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(controlFill, in: .circle)
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
                    .background(controlFill, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next field")
        }
    }

    private func actionPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(controlFill, in: .rect(cornerRadius: 14))
    }
}

extension Double {
    var widgetPercent: String { formatted(.percent.precision(.fractionLength(0))) }
}
