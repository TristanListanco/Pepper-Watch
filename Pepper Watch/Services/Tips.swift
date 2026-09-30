//
//  Tips.swift
//  Pepper Watch
//
//  First-run tooltips (TipKit). Each tip shows once until dismissed or acted on.
//

import SwiftUI
import TipKit

enum PepperWatchTips {
    private static let resetKey = "tips.resetOnNextLaunch"

    static func configure() {
        if UserDefaults.standard.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: resetKey)
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    /// Developer option: show every tip again after the next launch.
    static func resetOnNextLaunch() {
        UserDefaults.standard.set(true, forKey: resetKey)
    }
}

struct StartDetectingTip: Tip {
    var title: Text { Text("Start detecting") }
    var message: Text? { Text("The camera opens paused. Frame a few pepper leaves, then tap to start finding aphid damage.") }
    var image: Image? { Image(systemName: "play.circle") }
}

struct SnapshotTip: Tip {
    /// Shown only after detection has started once.
    @Parameter static var hasStartedDetecting: Bool = false

    var title: Text { Text("Save a snapshot") }
    var message: Text? { Text("New leaves are logged automatically once the camera holds steady. Tap the shutter to save the current frame yourself.") }
    var image: Image? { Image(systemName: "camera.shutter.button") }

    var rules: [Rule] {
        #Rule(Self.$hasStartedDetecting) { $0 == true }
    }
}

struct PinMetricsTip: Tip {
    var title: Text { Text("Pin what matters") }
    var message: Text? { Text("Tap Edit to choose and reorder the metrics shown first.") }
    var image: Image? { Image(systemName: "pin") }
}

struct PinchGridTip: Tip {
    var title: Text { Text("Pinch to resize") }
    var message: Text? { Text("Pinch the grid to see more scans at once, or fewer and larger.") }
    var image: Image? { Image(systemName: "hand.pinch") }
}

/// Field cards have no long-press menu, so their swipe actions need a pointer.
struct FieldSwipeTip: Tip {
    /// Donated each time the Fields list appears; the tip waits for a second visit.
    static let fieldsViewed = Tips.Event(id: "fieldsViewed")

    var title: Text { Text("Swipe a field") }
    var message: Text? { Text("Swipe left to edit or delete a field, or right for walking directions.") }
    var image: Image? { Image(systemName: "hand.draw") }

    var rules: [Rule] {
        #Rule(Self.fieldsViewed) { $0.donations.count >= 2 }
    }
}

struct VerifyDetectionsTip: Tip {
    var title: Text { Text("Check the model") }
    var message: Text? { Text("Mark each detection as correct or wrong. Insights uses your answers to measure accuracy in the field.") }
    var image: Image? { Image(systemName: "checkmark.circle") }
}
