//
//  InsightsPager.swift
//  Pepper Watch (Apple Watch)
//
//  Fitness-style insights: turn the Digital Crown to move between full-screen pages,
//  each with its own color that blends into the next.
//

import Charts
import MapKit
import SwiftUI

/// A field's detail: a NavigationStack holding the Digital Crown pager. Each page's one action sits
/// in the bottom toolbar, and the chart pages push a day-by-day breakdown.
struct InsightsPager: View {
    let status: WidgetSnapshot.FieldStatus
    let highlight: WatchPayload.Highlight?

    @State private var page: InsightPage
    @State private var path: [InsightPage] = []
    @Namespace private var ringSpace
    @Environment(WatchBriefer.self) private var briefer

    init(status: WidgetSnapshot.FieldStatus, highlight: WatchPayload.Highlight?) {
        self.status = status
        self.highlight = highlight
        _page = State(initialValue: Self.initialPage)
        #if DEBUG
        // `-PWWatchPush YES` also opens the page's day-by-day breakdown.
        if UserDefaults.standard.bool(forKey: "PWWatchPush"), [.infestation, .leafHealth, .scans].contains(Self.initialPage) {
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
        case "location": .location
        default: .summary
        }
        #else
        .summary
        #endif
    }

    private var pages: [InsightPage] {
        var pages: [InsightPage] = [.summary, .highlights, .infestation, .leafHealth, .scans]
        if status.latitude != nil { pages.append(.location) }
        return pages
    }

    var body: some View {
        let stats = ScopeStats(status)
        NavigationStack(path: $path) {
            TabView(selection: $page) {
                ForEach(pages, id: \.self) { page in
                    content(for: page, stats: stats)
                        .containerBackground(tint(for: page, stats: stats).gradient, for: .tabView)
                        .tag(page)
                }
            }
            .tabViewStyle(.verticalPage(transitionStyle: .blur))
            .navigationTitle(status.name)
            .toolbar {
                // Like the Activity rings: turning the crown past the summary lifts the ring into the
                // corner, so the key number stays in view on every page.
                ToolbarItem(placement: .topBarTrailing) {
                    if page != .summary {
                        InfestationRing(progress: stats.current.infestationRate, animatesIn: false)
                            .matchedGeometryEffect(id: "ring", in: ringSpace)
                            .frame(width: 28, height: 28)
                            .accessibilityLabel("\(stats.current.infestationRate.percentText) infested")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    pageAction(stats: stats)
                        .tint(tint(for: page, stats: stats))
                }
            }
            .animation(.smooth, value: page)
            .navigationDestination(for: InsightPage.self) { page in
                DailyBreakdown(page: page, stats: stats)
            }
        }
        .navigationTransition(.crossFade)
    }

    @ViewBuilder
    private func content(for page: InsightPage, stats: ScopeStats) -> some View {
        switch page {
        case .summary: SummaryPage(status: status, stats: stats, showsRing: self.page == .summary, ringSpace: ringSpace)
        case .highlights: HighlightsPage(status: status, highlight: highlight)
        case .infestation: InfestationPage(stats: stats)
        case .leafHealth: LeafHealthPage(stats: stats)
        case .scans: ScansPage(stats: stats)
        case .location: LocationPage(status: status)
        }
    }

    /// Each page's color, for its background and toolbar action. The summary takes the severity
    /// color, the same status color used in the list and widgets.
    private func tint(for page: InsightPage, stats: ScopeStats) -> Color {
        page == .summary ? stats.current.severity?.color ?? .brand : page.tint
    }

    /// The current page's primary action, also triggered with Double Tap.
    @ViewBuilder
    private func pageAction(stats: ScopeStats) -> some View {
        switch page {
        case .summary:
            Button("Next Step", systemImage: "checklist") { page = .highlights }
                .handGestureShortcut(.primaryAction)
        case .highlights:
            if briefer.brief(for: status) == nil, briefer.isAvailable {
                Button("Brief Me", systemImage: "sparkles") {
                    Task { await briefer.generate(for: status) }
                }
                .disabled(briefer.phase == .generating)
                .handGestureShortcut(.primaryAction)
            }
        case .infestation, .leafHealth, .scans:
            NavigationLink(value: page) {
                Label("By Day", systemImage: "list.bullet")
            }
            .handGestureShortcut(.primaryAction)
        case .location:
            Button("Directions", systemImage: "figure.walk") { openDirections() }
                .handGestureShortcut(.primaryAction)
        }
    }

    private func openDirections() {
        guard let latitude = status.latitude, let longitude = status.longitude else { return }
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        item.name = status.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

// MARK: - Layout

/// Space kept free for the bottom toolbar's action button.
private let bottomBarClearance: CGFloat = 26

/// Pages in a vertical TabView size to their content, so charts and maps get fixed heights
/// that fit between the toolbar's top and bottom buttons.
private let chartHeight: CGFloat = 50

private extension View {
    /// Standard watch margins, so content clears the rounded display edges, the crown's page
    /// indicator and the bottom toolbar.
    func pageLayout(alignment: Alignment = .topLeading) -> some View {
        scenePadding(.horizontal)
            .padding(.bottom, bottomBarClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// Colored page title, like the metric titles in Fitness.
private struct PageHeader: View {
    let page: InsightPage

    var body: some View {
        Label(page.title, systemImage: page.symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(page.tint)
            .lineLimit(1)
    }
}

/// The page's one key number.
private struct BigNumber: View {
    let text: String
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(text)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// One short line of context under the number.
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

/// The seven days on the x-axis, even when some have no scans.
private func weekDomain(_ stats: ScopeStats) -> ClosedRange<Date> {
    let first = stats.days.first?.date ?? .now
    let last = stats.days.last?.date ?? .now
    return first...(Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last)
}

/// Single-letter weekdays only; the number above the chart carries the scale.
private func weekdayAxis(_ stats: ScopeStats) -> some AxisContent {
    AxisMarks(values: stats.days.map(\.date)) {
        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
    }
}

// MARK: - Pages

private struct SummaryPage: View {
    let status: WidgetSnapshot.FieldStatus
    let stats: ScopeStats
    let showsRing: Bool
    let ringSpace: Namespace.ID

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if showsRing {
                    InfestationRing(progress: stats.current.infestationRate)
                        .matchedGeometryEffect(id: "ring", in: ringSpace)
                }
                VStack(spacing: -2) {
                    Text(stats.hasLeaves ? stats.current.infestationRate.percentText : "—")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    Text("infested")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)
            .accessibilityElement(children: .combine)

            SeverityChip(severity: stats.current.severity)

            if let latest = status.latestScan {
                ContextLine(
                    text: "Scanned \(latest.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))",
                    symbol: "clock"
                )
            }
        }
        .pageLayout(alignment: .center)
    }
}

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
                PageHeader(page: .highlights)
                if let headline {
                    Text(headline)
                        .font(.headline)
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

                if brief != nil {
                    ContextLine(text: "Apple Intelligence", symbol: "sparkles")
                } else if highlight?.isGenerated == true {
                    ContextLine(text: "Apple Intelligence on iPhone", symbol: "sparkles")
                }
                if briefer.phase == .generating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if case .failed(let message) = briefer.phase {
                    ContextLine(text: message)
                } else if brief == nil, briefer.isAvailable {
                    // Watch models run in Private Cloud Compute; say so before anything leaves the watch.
                    Text("Brief Me sends these numbers to Private Cloud Compute.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .scenePadding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth, value: brief)
        }
        .contentMargins(.bottom, bottomBarClearance + 10, for: .scrollContent)
    }
}

private struct InfestationPage: View {
    let stats: ScopeStats

    private var context: (text: String, symbol: String?) {
        guard let change = stats.change else { return ("Past 7 days", nil) }
        let points = Int(change.rounded())
        if points == 0 { return ("Same as last week", "equal") }
        return ("\(points > 0 ? "+" : "−")\(abs(points)) pts vs last week", points > 0 ? "arrow.up.right" : "arrow.down.right")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(page: .infestation)
            BigNumber(text: stats.hasLeaves ? stats.current.infestationRate.percentText : "—")
            ContextLine(text: context.text, symbol: context.symbol)
            Chart(stats.days) { day in
                if let rate = day.rate {
                    AreaMark(x: .value("Day", day.date, unit: .day), y: .value("Infested", rate))
                        .foregroundStyle(LinearGradient(colors: [Color.aphid.opacity(0.5), Color.aphid.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", day.date, unit: .day), y: .value("Infested", rate))
                        .foregroundStyle(Color.aphid)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", day.date, unit: .day), y: .value("Infested", rate))
                        .foregroundStyle(Color.aphid)
                        .symbolSize(20)
                }
            }
            .chartXScale(domain: weekDomain(stats))
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis { weekdayAxis(stats) }
            .frame(height: chartHeight)
            .padding(.top, 6)
            .accessibilityLabel("Daily infestation rate for the past 7 days")
        }
        .pageLayout()
    }
}

private struct LeafHealthPage: View {
    let stats: ScopeStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(page: .leafHealth)
            HStack(spacing: 14) {
                ZStack {
                    if stats.hasLeaves {
                        Chart {
                            SectorMark(angle: .value("Leaves", stats.healthyLeaves), innerRadius: .ratio(0.68), angularInset: 1.5)
                                .cornerRadius(3)
                                .foregroundStyle(Color.healthy)
                            SectorMark(angle: .value("Leaves", stats.current.aphidLeaves), innerRadius: .ratio(0.68), angularInset: 1.5)
                                .cornerRadius(3)
                                .foregroundStyle(Color.aphid)
                        }
                    } else {
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 12)
                            .padding(6)
                    }
                    VStack(spacing: -2) {
                        Text(stats.current.totalLeaves, format: .number)
                            .font(.system(.headline, design: .rounded))
                        Text("leaves")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 8) {
                    LegendRow(color: .healthy, title: "Healthy", value: stats.healthyLeaves)
                    LegendRow(color: .aphid, title: "Infested", value: stats.current.aphidLeaves)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .pageLayout()
    }
}

private struct LegendRow: View {
    let color: Color
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: -2) {
                Text(value, format: .number)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ScansPage: View {
    let stats: ScopeStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(page: .scans)
            BigNumber(text: "\(stats.current.scans)", unit: stats.current.scans == 1 ? "scan" : "scans")
            ContextLine(text: "Past 7 days")
            Chart(stats.days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Scans", day.scans), width: .ratio(0.6))
                    .foregroundStyle(Color.brand.gradient)
                    .cornerRadius(3)
            }
            .chartXScale(domain: weekDomain(stats))
            .chartYAxis(.hidden)
            .chartXAxis { weekdayAxis(stats) }
            .frame(height: chartHeight)
            .padding(.top, 6)
            .accessibilityLabel("Scans per day for the past 7 days")
        }
        .pageLayout()
    }
}

private struct LocationPage: View {
    let status: WidgetSnapshot.FieldStatus

    var body: some View {
        if let latitude = status.latitude, let longitude = status.longitude {
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let radius = status.radiusMeters ?? 50
            VStack(alignment: .leading, spacing: 6) {
                PageHeader(page: .location)
                // A still map, so the Digital Crown keeps paging instead of zooming.
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
                .frame(height: 78)
                .clipShape(.rect(cornerRadius: 16))
                if !status.locationName.isEmpty {
                    ContextLine(text: status.locationName, symbol: "mappin")
                }
            }
            .pageLayout()
        }
    }
}

// MARK: - By day

/// The last seven days as a list, pushed from a chart page. A subview, so it keeps a small title.
private struct DailyBreakdown: View {
    let page: InsightPage
    let stats: ScopeStats

    var body: some View {
        List(stats.days.reversed().filter { $0.scans > 0 }) { day in
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(day.date, format: .dateTime.weekday(.wide))
                        .font(.headline)
                    Text(day.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value(for: day))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(detail(for: day))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .overlay {
            if stats.current.scans == 0 {
                ContentUnavailableView("No Scans", systemImage: page.symbol, description: Text("Nothing scanned in the past 7 days."))
            }
        }
        .navigationTitle(page.shortTitle)
        .containerBackground(page.tint.gradient, for: .navigation)
    }

    private func value(for day: ScopeStats.Day) -> String {
        switch page {
        case .scans: "\(day.scans)"
        case .leafHealth: day.total == 0 ? "—" : "\(day.total - day.aphid)"
        default: day.rate?.percentText ?? "—"
        }
    }

    private func detail(for day: ScopeStats.Day) -> String {
        guard day.total > 0 || page == .scans else { return "No leaves" }
        return switch page {
        case .scans: day.scans == 1 ? "scan" : "scans"
        case .leafHealth: "healthy, \(day.aphid) infested"
        default: "\(day.aphid) of \(day.total) leaves"
        }
    }
}

private extension InsightPage {
    /// Fits beside the back button and the time.
    var shortTitle: String {
        switch self {
        case .infestation: "Infestation"
        default: title
        }
    }
}
