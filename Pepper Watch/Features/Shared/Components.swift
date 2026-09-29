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
            Text(count, format: .number)
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText(value: Double(count)))
            Text(leafClass.shortName)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
            HStack {
                SeverityBadge(severity: severity)
                Spacer()
                Text(severity.rangeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
