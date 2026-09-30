//
//  WidgetGalleryView.swift
//  Pepper Watch
//
//  Previews every widget size with live data, using the same views as the widget extension.
//

import SwiftData
import SwiftUI
import WidgetKit

struct WidgetGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var snapshot: WidgetSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let snapshot {
                    gallerySection("Field Status") {
                        let status = snapshot.fields.first ?? snapshot.overall
                        let severity = status.window().severity
                        homeScreenWidget(width: 158, severity: severity) {
                            FieldStatusWidgetView(status: status, family: .systemSmall)
                        }
                        homeScreenWidget(width: 338, severity: severity) {
                            FieldStatusWidgetView(status: status, family: .systemMedium)
                        }
                    }

                    gallerySection("Field Actions") {
                        let options = WidgetActionsState.options(in: snapshot)
                        let index = options.isEmpty ? 0 : WidgetActionsState.selectedIndex % options.count
                        let severity = options.isEmpty ? nil : options[index].window().severity
                        homeScreenWidget(width: 158, severity: severity) {
                            FieldActionsWidgetView(options: options, index: index, family: .systemSmall)
                        }
                        homeScreenWidget(width: 338, severity: severity) {
                            FieldActionsWidgetView(options: options, index: index, family: .systemMedium)
                        }
                    }

                    gallerySection("Lock Screen") {
                        lockScreen(snapshot)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
            // Keep the preview column centered on iPad.
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task { snapshot = WidgetSync.makeSnapshot(from: modelContext) }
    }

    private func gallerySection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.bold))
            content()
        }
    }

    /// A Home Screen widget at its iPhone size, on its severity gradient.
    private func homeScreenWidget<Content: View>(width: CGFloat, severity: Severity?, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: 158)
            .background(WidgetBackground(severity: severity))
            .clipShape(.rect(cornerRadius: 22))
    }

    private func lockScreen(_ snapshot: WidgetSnapshot) -> some View {
        let status = snapshot.fields.first ?? snapshot.overall
        return VStack(spacing: 14) {
            FieldStatusWidgetView(status: status, family: .accessoryInline)
                .font(.subheadline.weight(.semibold))
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(size: 64, weight: .semibold, design: .rounded))
            HStack(spacing: 12) {
                FieldStatusWidgetView(status: status, family: .accessoryCircular)
                    .frame(width: 72, height: 72)
                FieldStatusWidgetView(status: status, family: .accessoryRectangular)
                    .frame(width: 170, height: 72)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 24)
        .frame(maxWidth: 338)
        .background(
            LinearGradient(colors: [Color(red: 0.08, green: 0.25, blue: 0.14), Color(red: 0.02, green: 0.08, blue: 0.05)], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 28)
        )
        .environment(\.colorScheme, .dark)
    }
}
