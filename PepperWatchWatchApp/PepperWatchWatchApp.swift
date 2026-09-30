//
//  PepperWatchWatchApp.swift
//  Pepper Watch (Apple Watch)
//
//  Fields and insights synced from the paired iPhone.
//

import SwiftUI

@main
struct PepperWatchWatchApp: App {
    @State private var phone = PhoneConnection()

    init() {
        WatchTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(phone)
                .task { phone.start() }
        }
        // New numbers from the iPhone reach the app and its widgets even while it's suspended.
        .backgroundTask(.watchConnectivity) { [phone] in
            await phone.receivePendingContent()
        }
        // Each morning, the Smart Stack's scouting and severity timing is refreshed.
        .backgroundTask(.appRefresh(DailyRefresh.taskID)) { [phone] in
            await phone.refreshForNewDay()
        }
    }
}
