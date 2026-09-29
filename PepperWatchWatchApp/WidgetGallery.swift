//
//  WidgetGallery.swift
//  Pepper Watch (Apple Watch)
//
//  Debug-only preview of the Smart Stack widget faces with live data, for screenshots.
//  Launch with `-PWWatchWidgetGallery YES`.
//

#if DEBUG
import SwiftUI
import WidgetKit

struct WidgetGallery: View {
    @Environment(PhoneConnection.self) private var phone

    var body: some View {
        let fieldID = phone.payload?.snapshot.fields.first?.id
        ScrollView {
            VStack(spacing: 10) {
                // Smart Stack card.
                card(FieldEntry.current(fieldID: fieldID, metric: .infestation))
                // One circular complication per configurable metric.
                HStack(spacing: 10) {
                    ForEach([WidgetMetric.infestation, .leafHealth, .scans], id: \.self) { metric in
                        FieldWidgetView(entry: FieldEntry.current(fieldID: fieldID, metric: metric), previewFamily: .accessoryCircular)
                            .frame(width: 50, height: 50)
                    }
                }
                card(FieldEntry.current(fieldID: fieldID, metric: .leafHealth))
            }
            .scenePadding(.horizontal)
        }
    }

    private func card(_ entry: FieldEntry) -> some View {
        FieldWidgetView(entry: entry, previewFamily: .accessoryRectangular)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(tint(entry).gradient.opacity(0.6), in: .rect(cornerRadius: 20))
    }

    private func tint(_ entry: FieldEntry) -> Color {
        entry.status.flatMap { ScopeStats($0).current.severity?.color } ?? .brand
    }
}
#endif
