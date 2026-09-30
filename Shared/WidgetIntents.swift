//
//  WidgetIntents.swift
//  Pepper Watch (shared with the widget extension)
//
//  Interactive widget buttons and the deep links widgets open.
//

import AppIntents
import Foundation

/// Which field the Field Actions widget is showing. Only real fields are offered;
/// "All Fields" appears only before any field exists.
nonisolated enum WidgetActionsState {
    private static let indexKey = "widget.actions.index"

    static func options(in snapshot: WidgetSnapshot?) -> [WidgetSnapshot.FieldStatus] {
        guard let snapshot else { return [] }
        return snapshot.fields.isEmpty ? [snapshot.overall] : snapshot.fields
    }

    static var selectedIndex: Int {
        get { SharedContainer.defaults.integer(forKey: indexKey) }
        set { SharedContainer.defaults.set(newValue, forKey: indexKey) }
    }
}

/// The ‹ › buttons on the Field Actions widget. Runs in the widget without opening the app.
struct CycleFieldIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Next Field"
    static let isDiscoverable = false

    @Parameter(title: "Forward", default: true)
    var forward: Bool

    init() {}

    init(forward: Bool) {
        self.forward = forward
    }

    func perform() async throws -> some IntentResult {
        let count = max(WidgetActionsState.options(in: WidgetSnapshot.load()).count, 1)
        let current = WidgetActionsState.selectedIndex
        WidgetActionsState.selectedIndex = ((current + (forward ? 1 : -1)) % count + count) % count
        return .result()
    }
}

/// Opens the scanner from Control Center, the Lock Screen or the Action button (iOS 18 controls).
/// Shared with the widget extension, which shows the control; it runs in the app, which provides
/// the launcher.
struct OpenScannerIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Leaves"
    static let description = IntentDescription("Opens the Pepper Watch scanner.")
    static let supportedModes: IntentModes = .foreground
    // Siri and Shortcuts already offer Start Scanning, which can also pick a field.
    static let isDiscoverable = false

    @AppDependency private var launcher: ScannerLauncher

    func perform() async throws -> some IntentResult {
        await launcher.open()
        return .result()
    }
}

/// How the app opens its scanner, registered with App Intents at launch.
nonisolated final class ScannerLauncher: Sendable {
    let open: @MainActor @Sendable () -> Void

    init(open: @escaping @MainActor @Sendable () -> Void) {
        self.open = open
    }
}

extension URL {
    /// `pepperwatch://scan?field=<id>` or `pepperwatch://insights?field=<id>`, handled by the app's navigator.
    static func pepperWatch(_ destination: String, fieldID: String?) -> URL {
        var components = URLComponents()
        components.scheme = "pepperwatch"
        components.host = destination
        if let fieldID { components.queryItems = [URLQueryItem(name: "field", value: fieldID)] }
        return components.url!
    }
}
