//
//  AppDataStore.swift
//  Pepper Watch
//

import CloudKit
import SwiftData

nonisolated enum SyncSettings {
    static let containerID = "iCloud.com.tristanlistanco.Pepper-Watch"
    static let enabledKey = "sync.iCloudEnabled"
    static let choiceMadeKey = "sync.choiceMade"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

/// The app's single SwiftData container, shared by the UI and App Intents (Siri, Shortcuts, Spotlight).
enum AppDataStore {
    /// Created on first use with the user's iCloud choice; changing it applies on the next launch.
    static let container: ModelContainer = makeContainer(syncWithICloud: SyncSettings.isEnabled)
    private(set) static var isSyncingWithICloud = false

    private static func makeContainer(syncWithICloud: Bool) -> ModelContainer {
        let schema = AppSchema.schema
        if syncWithICloud,
           let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .private(SyncSettings.containerID))) {
            isSyncingWithICloud = true
            return container
        }
        // CloudKit must be disabled explicitly, because the app has the iCloud entitlement.
        if let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)) {
            return container
        }
        // Keep the app usable for a demo even if the on-disk store can't open.
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

/// The device's iCloud account state, for onboarding and Settings.
enum ICloudAccount {
    enum Status: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case unavailable(String)

        var title: String {
            switch self {
            case .checking: "Checking iCloud…"
            case .available: "Signed in to iCloud"
            case .noAccount: "Not signed in to iCloud"
            case .restricted: "iCloud is restricted on this device"
            case .unavailable: "iCloud is unavailable right now"
            }
        }

        var symbol: String {
            switch self {
            case .checking: "icloud"
            case .available: "checkmark.icloud.fill"
            case .noAccount, .restricted, .unavailable: "exclamationmark.icloud.fill"
            }
        }
    }

    static func status() async -> Status {
        do {
            switch try await CKContainer(identifier: SyncSettings.containerID).accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine, .temporarilyUnavailable: return .unavailable("Try again in a moment.")
            @unknown default: return .unavailable("Unknown account status.")
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }
}
