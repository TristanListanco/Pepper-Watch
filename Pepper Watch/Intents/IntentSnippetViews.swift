//
//  IntentSnippetViews.swift
//  Pepper Watch
//
//  Cards Siri shows alongside its spoken answer.
//

import SwiftUI

struct FieldStatusSnippet: View {
    let report: FieldReport

    var body: some View {
        let stats = report.stats
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(report.scopeName.capitalized, systemImage: "leaf.fill")
                    .font(.headline)
                    .foregroundStyle(Color("AccentColor"))
                Spacer()
                SeverityBadge(severity: stats.overallSeverity, compact: true)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(stats.totalLeaves == 0 ? "—" : stats.infestationRate.percentText)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text("infested · \(stats.scanCount) scans · 7 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                SparklineChart(
                    points: stats.trend.map { MiniPoint(date: $0.date, value: $0.rate) },
                    color: LeafClass.aphidInfested.color,
                    domain: 0...1
                )
                .frame(width: 120, height: 50)
            }
        }
        .padding()
    }
}

struct SummarySnippet: View {
    let content: HighlightContent
    let isGenerated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let headline = content.headline {
                Text(headline)
                    .font(.headline)
            }
            ForEach(Array(content.observations.enumerated()), id: \.offset) { _, observation in
                Text(observation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let recommendation = content.recommendation {
                Label {
                    Text(recommendation)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                }
                .font(.subheadline)
            }
            Text(isGenerated ? "Summarized with Apple Intelligence on this device." : "Standard highlights from your scans.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
