//
//  InsightsPager.swift
//  Pepper Watch (Apple Watch)
//
//  A field's detail: a NavigationStack holding the Digital Crown pager. Metric pages put an
//  animated chart across the top, then the metric's name, then what it found. The range button
//  steps the charts through D, W, M, 6M and Y; tapping a chart pushes its breakdown.
//

import Charts
import MapKit
import SwiftUI

typealias TrendRange = WatchPayload.TrendRange

struct InsightsPager: View {
    let status: WidgetSnapshot.FieldStatus
    let highlight: WatchPayload.Highlight?
    let validation: WatchPayload.Validation?
    let trends: [String: WatchPayload.Trend]?

    @State private var page: InsightPage
    @State private var path: [InsightPage] = []
    @AppStorage("watch.range") private var rangeRaw = TrendRange.week.rawValue
    @Environment(WatchBriefer.self) private var briefer

    init(status: WidgetSnapshot.FieldStatus, highlight: WatchPayload.Highlight?, validation: WatchPayload.Validation?, trends: [String: WatchPayload.Trend]?) {
        self.status = status
        self.highlight = highlight
        self.validation = validation
        self.trends = trends
        _page = State(initialValue: Self.initialPage)
        #if DEBUG
        // `-PWWatchPush YES` also opens the page's breakdown.
        if UserDefaults.standard.bool(forKey: "PWWatchPush"), Self.initialPage.usesRange {
            _path = State(initialValue: [Self.initialPage])
        }
        #endif
    }

    /// Debug builds accept `-PWWatchPage infestation` to open a page for screenshots.
    private static var initialPage: InsightPage {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "PWWatchPage") {
        case "highlights": .highlights
        case "infestation": .infestation
        case "leafHealth": .leafHealth
        case "scans": .scans
        case "accuracy": .accuracy
        case "location": .location
        default: .summary
        }
        #else
        .summary
        #endif
    }

    private var range: TrendRange { TrendRange(rawValue: rangeRaw) ?? .week }

    private var pages: [InsightPage] {
        var pages: [InsightPage] = [.summary, .highlights, .infestation, .leafHealth, .scans, .accuracy]
        if status.latitude != nil { pages.append(.location) }
        return pages
    }

    /// The iPhone's buckets for a range; older payloads fall back to the daily counts for W and M.
    private func trend(for range: TrendRange) -> WatchPayload.Trend? {
        if let trend = trends?[range.rawValue] { return trend }
        let days = range == .week ? 7 : range == .month ? 30 : 0
        guard days > 0 else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let buckets = (0..<days).reversed().map { back -> WatchPayload.TrendBucket in
            let date = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            let day = status.daily.first { calendar.isDate($0.date, inSameDayAs: date) }
            return WatchPayload.TrendBucket(start: date, aphid: day?.aphid ?? 0, total: day?.total ?? 0, scans: day?.scans ?? 0)
        }
        let previous = status.window(days: days, offset: days)
        return WatchPayload.Trend(
            buckets: buckets,
            previous: WatchPayload.TrendBucket(start: buckets.first?.start ?? today, aphid: previous.aphidLeaves, total: previous.totalLeaves, scans: previous.scans)
        )
    }

    var body: some View {
        let stats = ScopeStats(status)
        let trend = trend(for: range)
        NavigationStack(path: $path) {
            TabView(selection: $page) {
                ForEach(pages, id: \.self) { page in
                    content(for: page, stats: stats, trend: trend)
                        .containerBackground(pageGradient(tint(for: page, stats: stats)), for: .tabView)
                        .tag(page)
                }
            }
            .tabViewStyle(.verticalPage(transitionStyle: .blur))
            .navigationTitle(status.name)
            .toolbar {
                if page.usesRange {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.smooth) { rangeRaw = range.next.rawValue }
                        } label: {
                            Text(range.rawValue)
                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                .contentTransition(.numericText())
                        }
                        .tint(page.tint)
                        .handGestureShortcut(.primaryAction)
                        .accessibilityLabel("Range")
                        .accessibilityValue(range.periodTitle)
                    }
                }
                if page == .highlights, briefer.brief(for: status) == nil, briefer.isAvailable {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        Button("Brief Me", systemImage: "sparkles") {
                            Task { await briefer.generate(for: status) }
                        }
                        .disabled(briefer.phase == .generating)
                        .tint(page.tint)
                        .handGestureShortcut(.primaryAction)
                    }
                }
            }
            .navigationDestination(for: InsightPage.self) { page in
                Breakdown(page: page, range: range, trend: trend)
            }
        }
        .navigationTransition(.crossFade)
    }

    @ViewBuilder
    private func content(for page: InsightPage, stats: ScopeStats, trend: WatchPayload.Trend?) -> some View {
        switch page {
        case .summary: SummaryPage(status: status, stats: stats)
        case .highlights: HighlightsPage(status: status, highlight: highlight)
        case .infestation: InfestationPage(trend: trend, range: range)
        case .leafHealth: LeafHealthPage(trend: trend, range: range)
        case .scans: ScansPage(trend: trend, range: range)
        case .accuracy: AccuracyPage(validation: validation)
        case .location: LocationPage(status: status)
        }
    }

    /// Each page's color. The summary takes the severity color, as in the list and widgets.
    private func tint(for page: InsightPage, stats: ScopeStats) -> Color {
        page == .summary ? stats.current.severity?.color ?? .brand : page.tint
    }
}

// MARK: - Ranges and trends

extension InsightPage {
    /// Pages whose charts follow the range button.
    var usesRange: Bool {
        switch self {
        case .infestation, .leafHealth, .scans: true
        default: false
        }
    }

    /// Fits beside the back button and the time.
    var shortTitle: String {
        self == .infestation ? "Infestation" : title
    }
}

extension TrendRange {
    var periodTitle: String {
        switch self {
        case .day: "Past 24 hours"
        case .week: "Past 7 days"
        case .month: "Past 30 days"
        case .sixMonths: "Past 6 months"
        case .year: "Past year"
        }
    }

    /// "last week" in "+12 pts vs last week".
    var previousTitle: String {
        switch self {
        case .day: "yesterday"
        case .week: "last week"
        case .month: "last month"
        case .sixMonths: "prior 6 months"
        case .year: "last year"
        }
    }

    /// Where the x-axis gets labels, and how they read.
    fileprivate var axis: (component: Calendar.Component, count: Int, format: Date.FormatStyle) {
        switch self {
        case .day: (.hour, 6, .dateTime.hour(.defaultDigits(amPM: .narrow)))
        case .week: (.day, 1, .dateTime.weekday(.narrow))
        case .month: (.day, 7, .dateTime.day())
        case .sixMonths: (.month, 1, .dateTime.month(.narrow))
        case .year: (.month, 1, .dateTime.month(.narrow))
        }
    }

    /// A bucket's name in findings, like "Thu" or "Sep".
    fileprivate func name(of date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.hour())
        case .week: date.formatted(.dateTime.weekday(.abbreviated))
        case .month: date.formatted(.dateTime.month(.abbreviated).day())
        case .sixMonths: "week of \(date.formatted(.dateTime.month(.abbreviated).day()))"
        case .year: date.formatted(.dateTime.month(.abbreviated))
        }
    }
}

extension WatchPayload.Trend {
    var aphid: Int { buckets.reduce(0) { $0 + $1.aphid } }
    var total: Int { buckets.reduce(0) { $0 + $1.total } }
    var scans: Int { buckets.reduce(0) { $0 + $1.scans } }
    var rate: Double? { total == 0 ? nil : Double(aphid) / Double(total) }

    /// Percentage points against the period before, when both have leaves.
    var change: Double? {
        guard let rate, let previousRate = previous.rate else { return nil }
        return (rate - previousRate) * 100
    }
}

/// A full-screen background with more color at the top than `Color.gradient`, fading to black
/// so text below stays readable.
func pageGradient(_ tint: Color) -> LinearGradient {
    LinearGradient(
        stops: [
            .init(color: tint.mix(with: .black, by: 0.15), location: 0),
            .init(color: tint.mix(with: .black, by: 0.62), location: 0.55),
            .init(color: tint.mix(with: .black, by: 0.9), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Axis labels in a pale version of the page's color, so they blend with it instead of taking
/// the system tint.
private func axisLabelColor(_ tint: Color) -> Color {
    tint.mix(with: .white, by: 0.6).opacity(0.75)
}

/// The chart's x-axis, from the first bucket to the end of the last.
private func domain(_ trend: WatchPayload.Trend, _ range: TrendRange) -> ClosedRange<Date> {
    let first = trend.buckets.first?.start ?? .now
    let last = trend.buckets.last?.start ?? .now
    return first...(Calendar.current.date(byAdding: range.bucket.component, value: 1, to: last) ?? last)
}

private func timeAxis(_ range: TrendRange, tint: Color) -> some AxisContent {
    AxisMarks(values: .stride(by: range.axis.component, count: range.axis.count)) {
        AxisValueLabel(format: range.axis.format, centered: true)
            .foregroundStyle(axisLabelColor(tint))
    }
}

// MARK: - Layout

/// Pages in a vertical TabView size to their content, so charts get a fixed height.
private let chartHeight: CGFloat = 80

/// Grows chart marks from zero when a page first appears.
private struct GrowIn: ViewModifier {
    @Binding var progress: Double

    func body(content: Content) -> some View {
        content.onAppear {
            guard progress == 0 else { return }
            withAnimation(.smooth(duration: 0.9).delay(0.1)) { progress = 1 }
        }
    }
}

/// The metric page layout: a tall chart across the top, then, toward the bottom, the name (no
/// icon), the value and the key finding.
private struct MetricPage<ChartContent: View>: View {
    let page: InsightPage
    let value: String
    var unit: String?
    /// The most important finding is shown; later ones are for VoiceOver.
    let findings: [String]
    var opensBreakdown = true
    @ViewBuilder var chart: ChartContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if opensBreakdown {
                    NavigationLink(value: page) { chart }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the breakdown")
                } else {
                    chart
                }
            }
            .frame(height: chartHeight)
            // Nearly the full screen width; text below keeps the standard margins.
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                Text(page.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(page.tint)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let finding = findings.first {
                    Text(finding)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .scenePadding(.horizontal)
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityHint(findings.dropFirst().joined(separator: ". "))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One short line of context.
private struct ContextLine: View {
    let text: String
    var symbol: String?

    var body: some View {
        Group {
            if let symbol {
                Label(text, systemImage: symbol)
            } else {
                Text(text)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Severity as an icon and label on a Liquid Glass capsule tinted with the status color.
private struct SeverityChip: View {
    let severity: Severity?

    var body: some View {
        Label {
            Text(severity?.title ?? "No scans")
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: severity?.symbol ?? "camera.viewfinder")
                .foregroundStyle(severity?.color ?? .secondary)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint((severity?.color ?? .gray).opacity(0.3)), in: .capsule)
    }
}

// MARK: - Summary

/// The main page: a donut as large as the screen allows within the system margins, the severity
/// and when the field was last scanned. Always the past 7 days, so it reads as "right now".
private struct SummaryPage: View {
    let status: WidgetSnapshot.FieldStatus
    let stats: ScopeStats

    /// Room for the severity chip and the last-scan line under the donut.
    private let captionHeight: CGFloat = 60
    /// Like native full-screen layouts, the content also uses the band the page keeps free at the
    /// bottom. It's drawn past the page's frame rather than resizing the page, so paging stays put.
    private let bottomBand: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height + bottomBand
            let side = max(min(proxy.size.width, height - captionHeight), 60)
            VStack(spacing: 8) {
                InfestationDonut(aphid: stats.current.aphidLeaves, total: stats.current.totalLeaves)
                    .frame(width: side, height: side)
                SeverityChip(severity: stats.current.severity)
                if let latest = status.latestScan {
                    ContextLine(text: latest.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)), symbol: "clock")
                }
            }
            .frame(width: proxy.size.width, height: height)
        }
        .scenePadding(.horizontal)
    }
}

// MARK: - Highlights

/// The headline and the one thing to do next. A brief made on the watch takes over from the
/// iPhone's summary while its numbers are current; the full briefing stays on iPhone.
private struct HighlightsPage: View {
    let status: WidgetSnapshot.FieldStatus
    let highlight: WatchPayload.Highlight?
    @Environment(WatchBriefer.self) private var briefer

    var body: some View {
        let brief = briefer.brief(for: status)
        let headline = brief?.headline ?? highlight?.headline ?? highlight?.observations.first
        let nextStep = brief?.action ?? highlight?.recommendation
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(InsightPage.highlights.title)
                    .font(.headline)
                    .foregroundStyle(InsightPage.highlights.tint)
                if let headline {
                    Text(headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                if let nextStep {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next Step")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(nextStep)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
                if headline == nil {
                    Text("Open Insights on iPhone to create highlights.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Group {
                    if brief != nil {
                        Label("Apple Intelligence", systemImage: "sparkles")
                    } else if highlight?.isGenerated == true {
                        Label("Apple Intelligence on iPhone", systemImage: "sparkles")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if briefer.phase == .generating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if case .failed(let message) = briefer.phase {
                    ContextLine(text: message)
                } else if brief == nil, briefer.isAvailable {
                    // Watch models run in Private Cloud Compute; say so before anything leaves the watch.
                    Text("Brief Me sends these numbers to Private Cloud Compute.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .scenePadding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth, value: brief)
        }
        .contentMargins(.bottom, 40, for: .scrollContent)
    }
}

// MARK: - Metric pages

private let emptyTrend = WatchPayload.Trend(buckets: [], previous: .init(start: .now, aphid: 0, total: 0, scans: 0))

private struct InfestationPage: View {
    let trend: WatchPayload.Trend?
    let range: TrendRange
    @State private var progress = 0.0

    var body: some View {
        let trend = trend ?? emptyTrend
        MetricPage(page: .infestation, value: trend.rate?.percentText ?? "—", unit: "infested", findings: findings(trend)) {
            Chart(trend.buckets) { bucket in
                if let rate = bucket.rate {
                    AreaMark(x: .value("Time", bucket.start, unit: range.bucket.component), y: .value("Infested", rate * progress))
                        .foregroundStyle(LinearGradient(colors: [Color.aphid.opacity(0.5), Color.aphid.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", bucket.start, unit: range.bucket.component), y: .value("Infested", rate * progress))
                        .foregroundStyle(Color.aphid)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXScale(domain: domain(trend, range))
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0.5]) { _ in AxisGridLine().foregroundStyle(.quaternary) }
            }
            .chartXAxis { timeAxis(range, tint: InsightPage.infestation.tint) }
            .animation(.smooth, value: range)
            .accessibilityLabel("Infestation rate, \(range.periodTitle.lowercased())")
        }
        .modifier(GrowIn(progress: $progress))
    }

    private func findings(_ trend: WatchPayload.Trend) -> [String] {
        guard trend.rate != nil else { return [range.periodTitle, "No leaves scanned"] }
        var lines: [String] = []
        if let change = trend.change {
            let points = Int(change.rounded())
            lines.append(points == 0 ? "Same as \(range.previousTitle)" : "\(points > 0 ? "+" : "−")\(abs(points)) pts vs \(range.previousTitle)")
        } else {
            lines.append(range.periodTitle)
        }
        if let peak = trend.buckets.filter({ $0.rate != nil }).max(by: { ($0.rate ?? 0) < ($1.rate ?? 0) }), let rate = peak.rate {
            lines.append("Peak \(rate.percentText), \(range.name(of: peak.start))")
        }
        return lines
    }
}

private struct LeafHealthPage: View {
    let trend: WatchPayload.Trend?
    let range: TrendRange
    @State private var progress = 0.0

    var body: some View {
        let trend = trend ?? emptyTrend
        let healthy = trend.total - trend.aphid
        let share = trend.total == 0 ? nil : Double(healthy) / Double(trend.total)
        MetricPage(
            page: .leafHealth,
            value: share?.percentText ?? "—",
            unit: "healthy",
            findings: trend.total == 0
                ? [range.periodTitle, "No leaves scanned"]
                : ["\(healthy) healthy, \(trend.aphid) infested", "\(trend.total) leaves, \(range.periodTitle.lowercased())"]
        ) {
            Chart(trend.buckets) { bucket in
                BarMark(x: .value("Time", bucket.start, unit: range.bucket.component), y: .value("Leaves", Double(bucket.total - bucket.aphid) * progress))
                    .foregroundStyle(by: .value("Leaf", "Healthy"))
                BarMark(x: .value("Time", bucket.start, unit: range.bucket.component), y: .value("Leaves", Double(bucket.aphid) * progress))
                    .foregroundStyle(by: .value("Leaf", "Infested"))
            }
            .chartForegroundStyleScale(["Healthy": Color.healthy, "Infested": Color.aphid])
            .chartLegend(.hidden)
            .chartXScale(domain: domain(trend, range))
            .chartYAxis(.hidden)
            .chartXAxis { timeAxis(range, tint: InsightPage.leafHealth.tint) }
            .animation(.smooth, value: range)
            .accessibilityLabel("Healthy and infested leaves, \(range.periodTitle.lowercased())")
        }
        .modifier(GrowIn(progress: $progress))
    }
}

private struct ScansPage: View {
    let trend: WatchPayload.Trend?
    let range: TrendRange
    @State private var progress = 0.0

    var body: some View {
        let trend = trend ?? emptyTrend
        let busiest = trend.buckets.max { $0.scans < $1.scans }
        MetricPage(
            page: .scans,
            value: "\(trend.scans)",
            unit: trend.scans == 1 ? "scan" : "scans",
            findings: [range.periodTitle] + (busiest.flatMap { $0.scans > 0 ? ["Most \(range.name(of: $0.start)): \($0.scans)"] : nil } ?? [])
        ) {
            Chart(trend.buckets) { bucket in
                BarMark(x: .value("Time", bucket.start, unit: range.bucket.component), y: .value("Scans", Double(bucket.scans) * progress))
                    .foregroundStyle(Color.brand.gradient)
                    .cornerRadius(2)
            }
            .chartXScale(domain: domain(trend, range))
            .chartYAxis(.hidden)
            .chartXAxis { timeAxis(range, tint: InsightPage.scans.tint) }
            .animation(.smooth, value: range)
            .accessibilityLabel("Scans, \(range.periodTitle.lowercased())")
        }
        .modifier(GrowIn(progress: $progress))
    }
}

/// How often the model agreed with the leaves you checked in History, with the thesis metrics.
private struct AccuracyPage: View {
    let validation: WatchPayload.Validation?
    @State private var progress = 0.0

    private struct Metric: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    var body: some View {
        let metrics = [
            ("Acc", validation?.accuracy), ("Prec", validation?.precision), ("Rec", validation?.recall), ("F1", validation?.f1),
        ].compactMap { name, value in value.map { Metric(name: name, value: $0) } }
        MetricPage(
            page: .accuracy,
            value: validation?.accuracy?.percentText ?? "—",
            unit: "accurate",
            findings: validation.map { v in
                ["From \(v.total) leaves you checked", "Precision \(v.precision?.percentText ?? "—") · Recall \(v.recall?.percentText ?? "—")"]
            } ?? ["Confirm or reject detections", "in History on iPhone"],
            opensBreakdown: false
        ) {
            Chart(metrics) { metric in
                // The unfilled part of each bar, like the Noise app's chart. Ranged bars, so the
                // track and the value overlap instead of stacking.
                BarMark(x: .value("Metric", metric.name), yStart: .value("Value", 0), yEnd: .value("Value", 1), width: .ratio(0.55))
                    .foregroundStyle(.quaternary)
                    .cornerRadius(3)
                BarMark(x: .value("Metric", metric.name), yStart: .value("Value", 0), yEnd: .value("Value", metric.value * progress), width: .ratio(0.55))
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(3)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { AxisValueLabel().foregroundStyle(axisLabelColor(InsightPage.accuracy.tint)) }
            }
            .accessibilityLabel("Accuracy, precision, recall and F1")
        }
        .modifier(GrowIn(progress: $progress))
    }
}

// MARK: - Location

/// The field on a map card. Keep turning the Digital Crown on this last page and the card grows
/// into a full-screen map; turn back and it settles into the card again.
private struct LocationPage: View {
    let status: WidgetSnapshot.FieldStatus
    @State private var isExpanded: Bool
    /// Where the scroll view rests before the crown moves it, measured on first layout.
    @State private var restingOffset: CGFloat?
    @Namespace private var mapSpace
    /// Debug screenshots keep the map open regardless of the scroll position.
    private let holdsExpanded: Bool

    /// How far the crown needs to scroll past the top of the page to open the map.
    private let expandThreshold: CGFloat = 24

    init(status: WidgetSnapshot.FieldStatus) {
        self.status = status
        #if DEBUG
        // `-PWWatchExpandMap YES` shows the map full screen, for screenshots.
        holdsExpanded = UserDefaults.standard.bool(forKey: "PWWatchExpandMap")
        #else
        holdsExpanded = false
        #endif
        _isExpanded = State(initialValue: holdsExpanded)
    }

    var body: some View {
        if let latitude = status.latitude, let longitude = status.longitude {
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let radius = status.radiusMeters ?? 50
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(InsightPage.location.title)
                            .font(.headline)
                            .foregroundStyle(InsightPage.location.tint)
                        Group {
                            if isExpanded {
                                Color.clear
                            } else {
                                map(center: center, radius: radius)
                                    .matchedGeometryEffect(id: "map", in: mapSpace)
                                    .clipShape(.rect(cornerRadius: 16))
                            }
                        }
                        .frame(height: 96)
                        if !status.locationName.isEmpty {
                            ContextLine(text: status.locationName, symbol: "mappin")
                        }
                        // Room to keep scrolling.
                        Color.clear.frame(height: 140)
                    }
                    .scenePadding(.horizontal)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    // Measure from where the page rests, not from zero: watchOS insets scroll content.
                    let rest = min(restingOffset ?? offset, offset)
                    restingOffset = rest
                    let expanded = holdsExpanded || offset - rest > expandThreshold
                    guard expanded != isExpanded else { return }
                    withAnimation(.smooth(duration: 0.45)) { isExpanded = expanded }
                }

                if isExpanded {
                    map(center: center, radius: radius)
                        .matchedGeometryEffect(id: "map", in: mapSpace)
                        .ignoresSafeArea()
                        // The crown keeps driving the scroll view underneath, so turning back closes it.
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// A still map, so the Digital Crown keeps scrolling instead of zooming.
    private func map(center: CLLocationCoordinate2D, radius: Double) -> some View {
        Map(
            initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: radius * 5, longitudinalMeters: radius * 5)),
            interactionModes: []
        ) {
            MapCircle(center: center, radius: radius)
                .foregroundStyle(Color.teal.opacity(0.25))
                .stroke(Color.teal, lineWidth: 2)
            Marker(status.name, systemImage: "leaf.fill", coordinate: center)
                .tint(Color.brand)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

// MARK: - Breakdown

/// The selected range bucket by bucket, pushed from a chart. A subview, so it keeps a small title.
private struct Breakdown: View {
    let page: InsightPage
    let range: TrendRange
    let trend: WatchPayload.Trend?

    var body: some View {
        let buckets = Array((trend?.buckets ?? []).filter { $0.scans > 0 }.reversed())
        List(buckets) { bucket in
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title(for: bucket.start))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle = subtitle(for: bucket.start) {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value(for: bucket))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail(for: bucket))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .overlay {
            if buckets.isEmpty {
                ContentUnavailableView("No Scans", systemImage: page.symbol, description: Text("Nothing scanned in the \(range.periodTitle.lowercased())."))
            }
        }
        .navigationTitle("\(page.shortTitle) · \(range.rawValue)")
        .containerBackground(pageGradient(page.tint), for: .navigation)
    }

    private func title(for date: Date) -> String {
        switch range {
        case .day: date.formatted(.dateTime.hour())
        case .week: date.formatted(.dateTime.weekday(.wide))
        case .month: date.formatted(.dateTime.month(.abbreviated).day())
        case .sixMonths: "Week of \(date.formatted(.dateTime.month(.abbreviated).day()))"
        case .year: date.formatted(.dateTime.month(.wide))
        }
    }

    private func subtitle(for date: Date) -> String? {
        switch range {
        case .week: date.formatted(.dateTime.month(.abbreviated).day())
        case .month: date.formatted(.dateTime.weekday(.wide))
        case .year: date.formatted(.dateTime.year())
        default: nil
        }
    }

    private func value(for bucket: WatchPayload.TrendBucket) -> String {
        switch page {
        case .scans: "\(bucket.scans)"
        case .leafHealth: bucket.total == 0 ? "—" : "\(bucket.total - bucket.aphid)"
        default: bucket.rate?.percentText ?? "—"
        }
    }

    private func detail(for bucket: WatchPayload.TrendBucket) -> String {
        guard bucket.total > 0 || page == .scans else { return "No leaves" }
        return switch page {
        case .scans: bucket.scans == 1 ? "scan" : "scans"
        case .leafHealth: "healthy, \(bucket.aphid) infested"
        default: "\(bucket.aphid) of \(bucket.total) leaves"
        }
    }
}
