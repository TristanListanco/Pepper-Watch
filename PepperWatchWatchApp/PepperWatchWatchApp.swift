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
    @State private var briefer = WatchBriefer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(phone)
                .environment(briefer)
                .task { phone.start() }
        }
        // New numbers from the iPhone reach the app and its widgets even while it's suspended.
        .backgroundTask(.watchConnectivity) { [phone] in
            await phone.receivePendingContent()
        }
    }
}
