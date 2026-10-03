//
//  Components.swift
//  Pepper Watch
//

import SwiftUI
import UIKit

/// Status pill: icon + label + reserved status color, never color alone.
struct SeverityBadge: View {
    let severity: Severity?
    var compact = false

    var body: some View {
        Label {
            Text(severity?.title ?? "No leaves")
        } icon: {
            Image(systemName: severity?.symbol ?? "viewfinder")
                .foregroundStyle(severity?.color ?? .secondary)
        }
            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .foregroundStyle(.primary)
            .background((severity?.color ?? .secondary).opacity(0.22), in: .capsule)
            .overlay(Capsule().strokeBorder((severity?.color ?? .secondary).opacity(0.6), lineWidth: 1))
            .accessibilityLabel("Severity: \(severity?.title ?? "no leaves detected")")
    }
}

/// Count of one class with its identity icon.
struct ClassCountLabel: View {
    let leafClass: LeafClass
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: leafClass.symbol)
                .foregroundStyle(leafClass.color)
                .accessibilityHidden(true)
            Text(count, format: .number)
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText(value: Double(count)))
            Text(leafClass.shortName)
                .font(.caption)
                .foregroundStyle(.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondaryText)
            Text(value)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(.card, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// Plain-language diagnosis and treatment steps (thesis "Actionable Output Panel").
struct RecommendationCard: View {
    let severity: Severity
    var context: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let context {
                Text(context)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondaryText)
            }
            HStack {
                SeverityBadge(severity: severity)
                Spacer()
                Text(severity.rangeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
            Text(severity.headline)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(severity.recommendations.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 20, height: 20)
                            .background(severity.color.opacity(0.25), in: .circle)
                        Text(step)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let risk = severity.riskNote {
                Label(risk, systemImage: "chart.line.downtrend.xyaxis")
                    .font(.footnote)
                    .foregroundStyle(.secondaryText)
            }

            Text("Guidance only. Follow product labels and your local agriculturist's advice.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.card, in: .rect(cornerRadius: 24))
    }
}

extension Double {
    var percentText: String { formatted(.percent.precision(.fractionLength(0))) }
    func fixed(_ digits: Int) -> String { formatted(.number.precision(.fractionLength(digits))) }
}

extension ShapeStyle where Self == Color {
    /// Card surface that stands out from grouped backgrounds in both light and dark mode.
    static var card: Color { Color(.secondarySystemGroupedBackground) }
    /// Inset surface for tiles placed inside a card.
    static var cardInset: Color { Color(.tertiarySystemGroupedBackground) }
    /// Insight detail cards: white in light mode, a lifted gray (not near-black) in dark mode.
    static var elevatedCard: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .tertiarySystemBackground : .secondarySystemGroupedBackground
        })
    }
}

// MARK: - Legible text

extension ShapeStyle where Self == AnyShapeStyle {
    /// Secondary text: the current foreground at 60%. It keeps small text at 4.5:1 or better on
    /// the app's pages and cards in both appearances, where the system's secondary gray falls
    /// short in light mode, and still follows white text over photos and dark controls.
    static var secondaryText: AnyShapeStyle { AnyShapeStyle(.primary.opacity(0.6)) }
}

/// The system's labeled-content layout with the value in `.secondaryText` instead of the
/// system gray.
struct LegibleLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            configuration.content
                .foregroundStyle(.secondaryText)
        } label: {
            configuration.label
        }
        .labeledContentStyle(.automatic)
    }
}

extension LabeledContentStyle where Self == LegibleLabeledContentStyle {
    static var legible: LegibleLabeledContentStyle { LegibleLabeledContentStyle() }
}

extension Color {
    /// This color as text: darkened in light mode, or lightened in dark mode, only as far as it
    /// takes to read at 4.5:1 on the app's pages and cards. Icons, chart marks and fills keep the
    /// color itself.
    var legible: LegibleColor { LegibleColor(base: self) }
}

/// A color nudged toward black or white until it contrasts with the lightest page or card behind
/// text in the current appearance.
struct LegibleColor: ShapeStyle {
    let base: Color

    /// Comfortably above WCAG's 4.5:1 for small text.
    private static let target = 4.6

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let isDark = environment.colorScheme == .dark
        // Grouped page gray in light mode, the raised card gray in dark mode.
        let background: Double = isDark ? Self.luminance(0.17, 0.17, 0.18) : Self.luminance(0.95, 0.95, 0.97)
        let resolved = base.resolve(in: environment)
        var (red, green, blue) = (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
        for _ in 0..<30 {
            let text = Self.luminance(red, green, blue)
            if (max(text, background) + 0.05) / (min(text, background) + 0.05) >= Self.target { break }
            if isDark {
                (red, green, blue) = (red + (1 - red) * 0.08, green + (1 - green) * 0.08, blue + (1 - blue) * 0.08)
            } else {
                (red, green, blue) = (red * 0.92, green * 0.92, blue * 0.92)
            }
        }
        return Color.Resolved(colorSpace: .sRGB, red: Float(red), green: Float(green), blue: Float(blue), opacity: resolved.opacity)
    }

    /// WCAG relative luminance of a gamma-encoded sRGB color.
    private static func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = min(max(channel, 0), 1)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

// MARK: - Summary gradient and glass cards

/// Soft green, teal and warm tones fading into the page, echoing the app's palette.
struct SummaryGradient: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                Color(.accent).opacity(0.32), .teal.opacity(0.28), .orange.opacity(0.24),
                Color(.accent).opacity(0.18), .teal.opacity(0.15), .orange.opacity(0.12),
                .clear, .clear, .clear,
            ]
        )
        .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }
}

/// A grouped page with a subtle multicolor wash across the top, like the Health summary page.
private struct SummaryGradientBackground: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.background {
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                SummaryGradient()
                    .frame(height: horizontalSizeClass == .regular ? 520 : 400)
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func summaryGradientBackground() -> some View {
        modifier(SummaryGradientBackground())
    }
}
