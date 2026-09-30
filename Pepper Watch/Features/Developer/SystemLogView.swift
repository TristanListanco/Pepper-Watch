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
    /// Categories picked as search tokens, like "session" or "health".
    @State private var categoryTokens: [CategoryToken] = []
    @State private var isConfirmingClear = false
    @State private var isExporting = false
    @State private var exportFrame: CGRect?

    private var filteredLogs: [SystemLog] {
        let categories = Set(categoryTokens.map(\.category))
        return logs.filter { log in
            (level == nil || log.level == level)
                && (categories.isEmpty || categories.contains(log.category))
                && (searchText.isEmpty
                    || log.message.localizedCaseInsensitiveContains(searchText)
                    || log.category.localizedCaseInsensitiveContains(searchText))
        }
    }

    /// Categories to offer as tokens: those in the log that match what's typed and aren't picked yet.
    private var suggestedTokens: [CategoryToken] {
        let picked = Set(categoryTokens.map(\.category))
        return Set(logs.map(\.category))
            .filter { !picked.contains($0) && (searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText)) }
            .sorted()
            .map(CategoryToken.init)
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
        // Search tokens and suggestions (iOS 16): pick categories, then type to search messages.
        .searchable(text: $searchText, tokens: $categoryTokens, prompt: "Message or category") { token in
            Label(token.category.capitalized, systemImage: "tag")
        }
        .searchSuggestions {
            ForEach(suggestedTokens) { token in
                Label(token.category.capitalized, systemImage: "tag")
                    .searchCompletion(token)
            }
        }
        .overlay {
            if logs.isEmpty {
                ContentUnavailableView("No Log Entries", systemImage: "list.bullet.rectangle", description: Text("Model loads, scanning sessions, health checks and thermal events are recorded here."))
            } else if filteredLogs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    export()
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(logs.isEmpty || isExporting)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { exportFrame = $0 }
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

    /// Builds the CSV with a spinner in place of the button, then opens the share sheet.
    private func export() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            // Let the spinner appear before the rows are read.
            try? await Task.sleep(for: .milliseconds(120))
            let url = try? await CSVExporter.systemLogs(logs).writeToTemporaryFile()
            isExporting = false
            if let url {
                SharePresenter.present(file: url, title: "System Log · \(logs.count) entries", symbol: "doc.text", from: exportFrame)
            }
        }
    }
}

private struct CategoryToken: Identifiable, Hashable {
    let category: String
    var id: String { category }
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
                    .textSelection(.enabled)
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
