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
    @State private var selection: AppTab = Self.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Scan", systemImage: "camera.viewfinder", value: .scan) {
                ScanView(isSelected: selection == .scan)
            }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: .insights) {
                InsightsView()
            }
            Tab("History", systemImage: "square.grid.2x2", value: .history) {
                HistoryView()
            }
            Tab("Developer", systemImage: "hammer", value: .developer) {
                DeveloperView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
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

#Preview {
    ContentView()
        .environment(PreviewSupport.engine)
        .environment(PreviewSupport.scanner)
        .environment(PreviewSupport.location)
        .environment(DeviceMonitor())
        .modelContainer(PreviewSupport.container)
}
