//
//  InsightsPager.swift
//  Pepper Watch (Apple Watch)
//
//  A field's detail: a NavigationStack holding the Digital Crown pager. Metric pages read like
//  infographics: a chart across the full width and most of the height, then a compact name, value
//  and finding. The range button steps the charts through D, W, M, 6M and Y; tapping a chart
//  pushes its breakdown. The last page is the field's map, full screen.
//

import Charts
import MapKit
import SwiftUI

typealias TrendRange = WatchPayload.TrendRange

struct InsightsPager: View {
    let status: WidgetSnapshot.FieldStatus
    let trends: [String: WatchPayload.Trend]?

    @State private var page: InsightPage
    @State private var path: [InsightPage] = []
    /// Held in state so a range change animates every page's values; saved for next time.
    @State private var range: TrendRange
    @AppStorage("watch.range") private var savedRange = TrendRange.week.rawValue

    init(status: WidgetSnapshot.FieldStatus, trends: [String: WatchPayload.Trend]?) {
        self.status = status
        self.trends = trends
        _page = State(initialValue: Self.initialPage)
        _range = State(initialValue: TrendRange(rawValue: UserDefaults.standard.string(forKey: "watch.range") ?? "") ?? .week)
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
        case "infestation": .infestation
        case "leafHealth": .leafHealth
        case "scans": .scans
        case "location": .location
        default: .summary
        }
        #else
        .summary
        #endif
    }

    private var pages: [InsightPage] {
        var pages: [InsightPage] = [.summary, .infestation, .leafHealth, .scans]
        if status.latitude != nil { pages.append(.location) }
        return pages
    }

    /// The iPhone's buckets for a range; older payloads fall back to the daily counts for W and M.
    private func trend(for range: TrendRange) -> WatchPayload.Trend? {
        if let trend = trends?[range.rawValue] { return trend.startingWithData(for: range) }
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
                        .containerBackground(for: .tabView) {
                            if page == .location {
                                LocationMap(status: status)
                            } else {
                                pageGradient(tint(for: page, stats: stats))
                            }
                        }
                        .tag(page)
                }
            }
            .tabViewStyle(.verticalPage(transitionStyle: .blur))
            .navigationTitle(status.name)
            .toolbar {
                if page.usesRange {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.smooth) { range = range.next }
                            savedRange = range.rawValue
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
        case .infestation: InfestationPage(trend: trend, range: range)
        case .leafHealth: LeafHealthPage(trend: trend, range: range)
        case .scans: ScansPage(trend: trend, range: range)
        case .location: LocationPage(status: status, severity: stats.current.severity)
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
    /// Month-long views start at the first period with scans, so a history that began in
    /// September starts in September instead of at empty months.
    func startingWithData(for range: TrendRange) -> WatchPayload.Trend {
        guard range == .sixMonths || range == .year,
              let first = buckets.firstIndex(where: { $0.scans > 0 || $0.total > 0 })
        else { return self }
        return WatchPayload.Trend(buckets: Array(buckets[first...]), previous: previous)
    }

    /// Few buckets get slim fixed bars instead of bars as wide as a whole period.
    var barWidth: MarkDimension { buckets.count < 6 ? .fixed(14) : .automatic }

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

/// The chart's x-axis, from the first bucket to the end of the last. Weekly 6M buckets span whole
/// months, so the first month gets its label and the axis doesn't run into next month.
private func domain(_ trend: WatchPayload.Trend, _ range: TrendRange) -> ClosedRange<Date> {
    let calendar = Calendar.current
    let first = trend.buckets.first?.start ?? .now
    let last = trend.buckets.last?.start ?? .now
    let end = calendar.date(byAdding: range.bucket.component, value: 1, to: last) ?? last
    guard range == .sixMonths,
          let firstMonth = calendar.dateInterval(of: .month, for: first),
          let lastMonth = calendar.dateInterval(of: .month, for: last)
    else { return first...end }
    return firstMonth.start...lastMonth.end
}

private func timeAxis(_ range: TrendRange, tint: Color) -> some AxisContent {
    AxisMarks(values: .stride(by: range.axis.component, count: range.axis.count)) {
        AxisValueLabel(format: range.axis.format, centered: true)
            .foregroundStyle(axisLabelColor(tint))
    }
}

// MARK: - Layout

/// Like native full-screen layouts, pages also use the band the pager keeps free at the bottom.
/// It's drawn past the page's frame rather than resizing the page, so paging stays put.
private let bottomBand: CGFloat = 26

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

/// A metric page laid out like an infographic: the chart spans the full width of the display and
/// takes all the height the compact name, value and finding below leave free.
private struct MetricPage<ChartContent: View>: View {
    let page: InsightPage
    let value: String
    var unit: String?
    /// The most important finding is shown; later ones are for VoiceOver.
    let findings: [String]
    @ViewBuilder var chart: ChartContent

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 6) {
                NavigationLink(value: page) {
                    chart
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the breakdown")

                caption
                    .scenePadding(.horizontal)
                    .padding(.bottom, 4)
            }
            .frame(width: proxy.size.width, height: proxy.size.height + bottomBand, alignment: .top)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(page.tint)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if let finding = findings.first {
                Text(finding)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            }
        }
        // Values roll to their new numbers when the range changes.
        .animation(.smooth, value: value)
        .animation(.smooth, value: findings)
        .accessibilityElement(children: .combine)
        .accessibilityHint(findings.dropFirst().joined(separator: ". "))
    }
}

/// The value of a chart's standout mark, set small in the chart like an infographic label.
private func markLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
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

// MARK: - Metric pages

private let emptyTrend = WatchPayload.Trend(buckets: [], previous: .init(start: .now, aphid: 0, total: 0, scans: 0))

private struct InfestationPage: View {
    let trend: WatchPayload.Trend?
    let range: TrendRange
    @State private var progress = 0.0

    var body: some View {
        let trend = trend ?? emptyTrend
        let peak = trend.buckets.filter { $0.rate != nil }.max { ($0.rate ?? 0) < ($1.rate ?? 0) }
        // Scaled to the peak so the line uses the chart's height, with room for its label.
        let top = min(1, max(0.2, (peak?.rate ?? 0) * 1.35))
        MetricPage(page: .infestation, value: trend.rate?.percentText ?? "—", unit: "infested", findings: findings(trend)) {
            Chart {
                ForEach(trend.buckets) { bucket in
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
                // The peak as a dot with its value; also what shows when there's a single point.
                if let peak, let rate = peak.rate {
                    PointMark(x: .value("Time", peak.start, unit: range.bucket.component), y: .value("Infested", rate * progress))
                        .symbolSize(36)
                        .foregroundStyle(.white)
                        .annotation(position: .top, spacing: 3, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            markLabel(rate.percentText)
                        }
                }
            }
            .chartXScale(domain: domain(trend, range))
            .chartYScale(domain: 0...top)
            .chartYAxis(.hidden)
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
                BarMark(x: .value("Time", bucket.start, unit: range.bucket.component), y: .value("Leaves", Double(bucket.total - bucket.aphid) * progress), width: trend.barWidth)
                    .foregroundStyle(by: .value("Leaf", "Healthy"))
                    .cornerRadius(2)
                BarMark(x: .value("Time", bucket.start, unit: range.bucket.component), y: .value("Leaves", Double(bucket.aphid) * progress), width: trend.barWidth)
                    .foregroundStyle(by: .value("Leaf", "Infested"))
                    .cornerRadius(2)
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
                // The busiest period stands out with its count; the rest step back.
                let isBusiest = bucket.scans > 0 && bucket.id == busiest?.id
                BarMark(x: .value("Time", bucket.start, unit: range.bucket.component), y: .value("Scans", Double(bucket.scans) * progress), width: trend.barWidth)
                    .foregroundStyle(isBusiest ? AnyShapeStyle(Color.brand.gradient) : AnyShapeStyle(Color.brand.opacity(0.45)))
                    .cornerRadius(2)
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        if isBusiest { markLabel("\(bucket.scans)") }
                    }
            }
            .chartXScale(domain: domain(trend, range))
            // Headroom for the busiest bar's count.
            .chartYScale(domain: 0...Double(max(busiest?.scans ?? 0, 1)) * 1.25)
            .chartYAxis(.hidden)
            .chartXAxis { timeAxis(range, tint: InsightPage.scans.tint) }
            .animation(.smooth, value: range)
            .accessibilityLabel("Scans, \(range.periodTitle.lowercased())")
        }
        .modifier(GrowIn(progress: $progress))
    }
}

// MARK: - Location

/// The field's map behind the whole page, so the Location page is the map itself.
private struct LocationMap: View {
    let status: WidgetSnapshot.FieldStatus

    var body: some View {
        if let latitude = status.latitude, let longitude = status.longitude {
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let radius = status.radiusMeters ?? 50
            let span = radius * 6
            // Sit the field a little above center, clear of the caption at the bottom.
            let shifted = CLLocationCoordinate2D(latitude: latitude - span / 111_000 * 0.12, longitude: longitude)
            ZStack {
                // A still map, so the Digital Crown keeps paging instead of zooming.
                Map(
                    initialPosition: .region(MKCoordinateRegion(center: shifted, latitudinalMeters: span, longitudinalMeters: span)),
                    interactionModes: []
                ) {
                    MapCircle(center: center, radius: radius)
                        .foregroundStyle(Color.teal.opacity(0.25))
                        .stroke(Color.teal, lineWidth: 2)
                    Marker(status.name, systemImage: "leaf.fill", coordinate: center)
                        .tint(Color.brand)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))

                VStack(spacing: 0) {
                    // Keeps the time and title legible over the map.
                    LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 56)
                    Spacer(minLength: 0)
                    // A blur under the caption that fades out toward the map.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.5)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 104)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// The field's place and a short status, on the blur at the bottom of the map.
private struct LocationPage: View {
    let status: WidgetSnapshot.FieldStatus
    let severity: Severity?

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 2) {
                Label(status.locationName.isEmpty ? "Field location" : status.locationName, systemImage: "mappin.and.ellipse")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Label {
                    Text(statusLine)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: severity?.symbol ?? "camera.viewfinder")
                        .foregroundStyle(severity?.color ?? .secondary)
                }
                .font(.caption2.weight(.medium))
                .lineLimit(1)
            }
            .scenePadding(.horizontal)
            .padding(.bottom, 8)
            .frame(width: proxy.size.width, height: proxy.size.height + bottomBand, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        let severityText = severity?.title ?? "No scans this week"
        guard let latest = status.latestScan else { return severityText }
        return "\(severityText) · \(latest.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))"
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
