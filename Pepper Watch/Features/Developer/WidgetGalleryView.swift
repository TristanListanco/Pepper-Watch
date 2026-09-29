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
                    gallerySection("Home Screen") {
                        HStack(alignment: .top, spacing: 16) {
                            homeTile(.systemSmall, snapshot: snapshot, size: CGSize(width: 158, height: 158))
                            homeTile(.systemSmall, status: snapshot.fields.first ?? snapshot.overall, snapshot: snapshot, size: CGSize(width: 158, height: 158))
                        }
                        homeTile(.systemMedium, snapshot: snapshot, size: CGSize(width: 338, height: 158))
                        homeTile(.systemLarge, snapshot: snapshot, size: CGSize(width: 338, height: 354))
                    }

                    gallerySection("Field Actions") {
                        let options = WidgetActionsState.options(in: snapshot)
                        let index = options.isEmpty ? 0 : WidgetActionsState.selectedIndex % options.count
                        let severity = options.isEmpty ? nil : options[index].window().severity
                        HStack(alignment: .top, spacing: 16) {
                            FieldActionsWidgetView(options: options, index: index, family: .systemSmall)
                                .padding(16)
                                .frame(width: 158, height: 158)
                                .background(WidgetBackground(severity: severity))
                .clipShape(.rect(cornerRadius: 22))
                        }
                        FieldActionsWidgetView(options: options, index: index, family: .systemMedium)
                            .padding(16)
                            .frame(width: 338, height: 158)
                            .background(WidgetBackground(severity: severity))
                .clipShape(.rect(cornerRadius: 22))
                    }

                    gallerySection("Lock Screen") {
                        lockScreen(snapshot)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                Text("To add a widget, touch and hold the Home Screen or Lock Screen, tap Edit, then Add Widget, and search for Pepper Watch. Tap a widget to choose which field it shows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

    private func homeTile(_ family: WidgetFamily, status: WidgetSnapshot.FieldStatus? = nil, snapshot: WidgetSnapshot, size: CGSize) -> some View {
        let shown = status ?? snapshot.overall
        return FieldStatusWidgetView(status: shown, fields: snapshot.fields, family: family, onColor: true)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetBackground(severity: shown.window().severity))
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
                FieldStatusWidgetView(status: snapshot.overall, family: .accessoryCircular)
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
