//
//  CloudSyncOnboardingView.swift
//  Pepper Watch
//
//  First launch: choose whether fields and scans sync through the user's iCloud account.
//

import CloudKit
import SwiftUI

struct CloudSyncOnboardingView: View {
    @AppStorage(SyncSettings.enabledKey) private var syncEnabled = false
    @AppStorage(SyncSettings.choiceMadeKey) private var hasChosenSync = false
    @Environment(\.openURL) private var openURL
    @State private var status: ICloudAccount.Status = .checking

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                        .symbolEffect(.pulse, isActive: status == .checking)
                    Text("Sync with iCloud")
                        .font(.largeTitle.weight(.bold))
                    Text("Sign in with your iCloud account to keep your fields, scans and photos up to date on your iPhone and iPad.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 22) {
                    FeatureRow(symbol: "ipad.and.iphone", title: "On all your devices", detail: "Scan on your phone and review on your iPad.")
                    FeatureRow(symbol: "lock.icloud", title: "Private to you", detail: "Data is stored in your private iCloud database. Only you can see it.")
                    FeatureRow(symbol: "wifi.slash", title: "Still works offline", detail: "Detection runs on device. Changes sync when you're back online.")
                }

                accountCard
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    choose(sync: true)
                } label: {
                    Text(status == .available ? "Continue with iCloud" : "Turn On iCloud Sync")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)

                Button("Keep Data on This Device") {
                    choose(sync: false)
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .tint(Color("AccentColor"))
        .task { status = await ICloudAccount.status() }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { status = await ICloudAccount.status() }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if status == .checking {
                    ProgressView()
                } else {
                    Image(systemName: status.symbol)
                        .font(.title2)
                        .foregroundStyle(status == .available ? Severity.clear.color : Severity.low.color)
                }
                Text(status.title)
                    .font(.headline)
            }
            switch status {
            case .noAccount:
                Text("To sign in, open Settings, tap Sign in at the top, and use your Apple Account. Syncing starts automatically once you're signed in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Settings", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.glass)
                    Button("Check Again", systemImage: "arrow.clockwise") {
                        Task {
                            status = .checking
                            status = await ICloudAccount.status()
                        }
                    }
                    .buttonStyle(.glass)
                }
            case .restricted:
                Text("iCloud is turned off by Screen Time or device management. You can keep data on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .unavailable(let detail):
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .available, .checking:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.card, in: .rect(cornerRadius: 20))
        .animation(.smooth, value: status)
    }

    private func choose(sync: Bool) {
        syncEnabled = sync
        withAnimation { hasChosenSync = true }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
