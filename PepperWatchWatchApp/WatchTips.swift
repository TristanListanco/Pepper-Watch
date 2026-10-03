//
//  WatchTips.swift
//  Pepper Watch (Apple Watch)
//
//  First-run tips (TipKit). watchOS shows tips inline rather than as popovers.
//

import SwiftUI
import TipKit

enum WatchTips {
    static func configure() {
        #if DEBUG
        // `-PWHideTips YES` hides every tip, for screenshots.
        if UserDefaults.standard.bool(forKey: "PWHideTips") { Tips.hideAllTipsForTesting() }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// Reordering is a touch-and-hold gesture, so it needs pointing out once there's something to order.
struct ReorderFieldsTip: Tip {
    @Parameter static var fieldCount: Int = 0

    // watchOS shows a tip's title inline, so the title carries the gesture.
    var title: Text { Text("Touch and hold to reorder") }
    var message: Text? { Text("Drag a field into place. Pepper Watch opens on the first one.") }
    var image: Image? { Image(systemName: "hand.draw") }

    var rules: [Rule] {
        #Rule(Self.$fieldCount) { $0 >= 2 }
    }
}

/// Shown in a chart's breakdown, once you've shown interest in the numbers over time.
struct RangeShortcutTip: Tip {
    var title: Text { Text("Double tap changes the range") }
    var message: Text? { Text("On a chart, double tap or tap the range button to step through D, W, M, 6M and Y.") }
    var image: Image? { Image(systemName: "hand.tap") }
}
