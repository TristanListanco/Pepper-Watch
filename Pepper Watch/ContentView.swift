//
//  ContentView.swift
//  Pepper Watch
//
//  Created by Tristan Listanco on 9/29/26.
//

import SwiftData
import SwiftUI

enum AppTab: String, Hashable {
    case scan, insights, history, developer
}

struct ContentView: View {
    @Bindable private var navigator = AppNavigator.shared
    /// The tab each window was on, restored on the next launch (iOS 14 scene storage).
    @SceneStorage("selectedTab") private var restoredTab: AppTab = .scan

    var body: some View {
        TabView(selection: $navigator.selectedTab) {
            Tab("Scan", systemImage: "camera.viewfinder", value: .scan) {
                ScanTabView(isSelected: navigator.selectedTab == .scan)
            }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: .insights) {
                InsightsView()
            }
            Tab("History", systemImage: "square.grid.2x2", value: .history) {
                HistoryView()
            }
            .badge(navigator.unseenScans)
            Tab("Developer", systemImage: "hammer", value: .developer) {
                DeveloperView()
            }
        }
        // iPad shows a sidebar that can collapse into a tab bar; iPhone keeps the floating tab bar.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // MapKit resets the window tint to system blue; pin the brand green explicitly.
        .tint(Color(.accent))
        // Secondary text everywhere, including system lists and labeled values, at 60% of the
        // label color: 4.5:1 or better on pages and cards, where the system gray falls short.
        .foregroundStyle(Color.primary, Color.primary.opacity(0.6))
        // Widget taps arrive as pepperwatch:// links.
        .onOpenURL { navigator.open($0) }
        // Handoff from the watch: continue in Insights for the field it was showing.
        .onContinueUserActivity(HandoffActivity.viewField) { activity in
            guard let id = activity.userInfo?[HandoffActivity.fieldIDKey] as? String else { return }
            navigator.showInsights(fieldID: UUID(uuidString: id))
        }
        .onChange(of: navigator.selectedTab) { _, tab in
            if tab == .history { navigator.markHistorySeen() }
            restoredTab = tab
        }
        .onAppear {
            // Reopen on the last tab, unless a widget, Siri or a debug argument already chose one;
            // then that tab becomes the one to come back to.
            if navigator.hasPendingNavigation {
                restoredTab = navigator.selectedTab
            } else {
                navigator.selectedTab = restoredTab
            }
            if navigator.selectedTab == .history { navigator.markHistorySeen() }
        }
    }
}

#Preview {
    ContentView()
        .environment(PreviewSupport.engine)
        .environment(PreviewSupport.scanner)
        .environment(PreviewSupport.location)
        .environment(PreviewSupport.geofence)
        .environment(DeviceMonitor())
        .modelContainer(PreviewSupport.container)
}
