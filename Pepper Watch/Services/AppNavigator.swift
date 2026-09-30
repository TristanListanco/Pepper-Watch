//
//  AppNavigator.swift
//  Pepper Watch
//

import Foundation
import Observation

/// App-wide navigation requests from widgets (deep links) and Siri / Shortcuts intents.
@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    var selectedTab: AppTab = AppNavigator.initialTab
    /// A field the Scan tab should open the scanner for.
    var pendingScanFieldID: UUID?
    /// A field Insights should filter to.
    var pendingInsightsFieldID: String?
    /// Counts "New Field" requests from the menu bar; the Scan tab opens the editor on each.
    private(set) var newFieldRequests = 0
    /// Scans logged since History was last opened, shown as its tab badge.
    private(set) var unseenScans = 0

    /// Handles `pepperwatch://scan?field=<id>` and `pepperwatch://insights?field=<id>`.
    func open(_ url: URL) {
        let fieldID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "field" }?.value
        switch url.host() {
        case "scan":
            selectedTab = .scan
            pendingScanFieldID = fieldID.flatMap(UUID.init(uuidString:))
        case "insights":
            selectedTab = .insights
            pendingInsightsFieldID = fieldID == WidgetSnapshot.allFieldsID ? "" : fieldID
        default:
            break
        }
    }

    func startScanning(fieldID: UUID?) {
        selectedTab = .scan
        pendingScanFieldID = fieldID
    }

    /// Whether launch arguments or a deep link already picked where to open.
    var hasPendingNavigation: Bool {
        pendingScanFieldID != nil || pendingInsightsFieldID != nil || Self.hasDebugInitialTab
    }

    private static var hasDebugInitialTab: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "PWInitialTab") != nil
        #else
        false
        #endif
    }

    func noteNewScan() {
        unseenScans += 1
    }

    func markHistorySeen() {
        unseenScans = 0
    }

    func requestNewField() {
        selectedTab = .scan
        newFieldRequests += 1
    }

    func showInsights(fieldID: UUID?) {
        selectedTab = .insights
        pendingInsightsFieldID = fieldID?.uuidString ?? ""
    }

    /// Debug builds accept `-PWInitialTab insights` for demos and screenshots.
    private static var initialTab: AppTab {
        #if DEBUG
        UserDefaults.standard.string(forKey: "PWInitialTab").flatMap(AppTab.init(rawValue:)) ?? .scan
        #else
        .scan
        #endif
    }
}
