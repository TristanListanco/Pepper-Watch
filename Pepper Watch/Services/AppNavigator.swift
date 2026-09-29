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
