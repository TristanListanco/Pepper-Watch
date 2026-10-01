//
//  AppDataStore.swift
//  Pepper Watch
//

import SwiftData

/// The app's single SwiftData container, shared by the UI and App Intents (Siri, Shortcuts, Spotlight).
/// Data stays on this device.
enum AppDataStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: AppSchema.schema)
        } catch {
            // Keep the app usable for a demo even if the on-disk store can't open. An in-memory
            // store with the app's own schema can't fail to open.
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }()
}
