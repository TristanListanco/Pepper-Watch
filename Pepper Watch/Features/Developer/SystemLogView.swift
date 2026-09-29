//
//  SystemLogView.swift
//  Pepper Watch
//

import SwiftData
import SwiftUI

struct SystemLogView: View {
    @Query(sort: \SystemLog.timestamp, order: .reverse) private var logs: [SystemLog]
    @Environment(\.modelContext) private var modelContext
    @State private var level: LogLevel?
    @State private var searchText = ""
    @State private var isConfirmingClear = false

    private var filteredLogs: [SystemLog] {
        logs.filter { log in
            (level == nil || log.level == level)
                && (searchText.isEmpty
                    || log.message.localizedCaseInsensitiveContains(searchText)
                    || log.category.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Level", selection: $level) {
                    Text("All").tag(LogLevel?.none)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(LogLevel?.some(level))
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            ForEach(filteredLogs) { log in
                LogRow(log: log)
            }
        }
        .navigationTitle("System Log")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Message or category")
        .overlay {
            if logs.isEmpty {
                ContentUnavailableView("No Log Entries", systemImage: "list.bullet.rectangle", description: Text("Model loads, scanning sessions, health checks and thermal events are recorded here."))
            } else if filteredLogs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: CSVExporter.systemLogs(logs), preview: SharePreview("System log CSV")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(logs.isEmpty)
                Button("Clear", systemImage: "trash", role: .destructive) { isConfirmingClear = true }
                    .disabled(logs.isEmpty)
            }
        }
        .confirmationDialog("Clear the system log?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) {
                for log in logs { modelContext.delete(log) }
                try? modelContext.save()
            }
        }
    }
}

private struct LogRow: View {
    let log: SystemLog

    private var levelColor: Color {
        switch log.level {
        case .info: .secondary
        case .warning: Severity.low.color
        case .error: Severity.severe.color
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: log.level.symbol)
                .foregroundStyle(levelColor)
                .accessibilityLabel(log.level.rawValue)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(log.category.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                    Spacer()
                    Text(log.timestamp, format: .dateTime.month().day().hour().minute().second())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(log.message)
                    .font(.subheadline)
                Text(metricsLine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var metricsLine: String {
        var parts = ["Thermal \(log.thermalState)", "\(log.memoryMB.fixed(0)) MB"]
        if log.batteryPercent >= 0 { parts.append("Battery \(log.batteryPercent.fixed(0))%") }
        if log.fps > 0 { parts.append("\(log.fps.fixed(1)) FPS") }
        return parts.joined(separator: " · ")
    }
}
