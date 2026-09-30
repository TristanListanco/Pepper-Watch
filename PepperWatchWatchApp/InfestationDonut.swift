//
//  InfestationDonut.swift
//  Pepper Watch (Apple Watch)
//

import Charts
import SwiftUI

/// A minimal donut: infested and healthy leaves as two sectors, with the infested share in the
/// middle. Used on the summary, in the toolbar corner and in the field list, so they read the same.
struct InfestationDonut: View {
    let aphid: Int
    let total: Int
    var showsValue = true
    @State private var revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(aphid: Int, total: Int, showsValue: Bool = true, animatesIn: Bool = true) {
        self.aphid = aphid
        self.total = total
        self.showsValue = showsValue
        _revealed = State(initialValue: !animatesIn)
    }

    private var rate: Double { total == 0 ? 0 : Double(aphid) / Double(total) }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Chart {
                    if total == 0 {
                        SectorMark(angle: .value("Leaves", 1), innerRadius: .ratio(0.74))
                            .foregroundStyle(.quaternary)
                    } else {
                        // Infested sweeps in from the top when the donut first appears.
                        SectorMark(angle: .value("Leaves", revealed ? aphid : 0), innerRadius: .ratio(0.74), angularInset: size * 0.012)
                            .cornerRadius(size * 0.03)
                            .foregroundStyle(Color.aphid)
                        SectorMark(angle: .value("Leaves", revealed ? total - aphid : total), innerRadius: .ratio(0.74), angularInset: size * 0.012)
                            .cornerRadius(size * 0.03)
                            .foregroundStyle(Color.healthy)
                    }
                }
                .chartLegend(.hidden)

                if showsValue {
                    Text(total == 0 ? "—" : rate.percentText)
                        .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                        .foregroundStyle(total == 0 ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(size * 0.2)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            guard !revealed else { return }
            // Reduce Motion shows the finished donut instead of sweeping it in.
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.smooth(duration: 0.9).delay(0.1)) { revealed = true }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(total == 0 ? "No leaves scanned" : "\(rate.percentText) of leaves infested")
    }
}
