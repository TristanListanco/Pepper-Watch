//
//  InfestationRing.swift
//  Pepper Watch (Apple Watch)
//

import SwiftUI

/// An Activity-style ring that fills to the infestation rate when the page appears.
struct InfestationRing: View {
    let progress: Double
    @State private var shown: Double

    init(progress: Double, animatesIn: Bool = true) {
        self.progress = progress
        _shown = State(initialValue: animatesIn ? 0 : min(max(progress, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            // Same proportions at every size, from the summary dial to the toolbar corner.
            let lineWidth = min(proxy.size.width, proxy.size.height) * 0.13
            ZStack {
                Circle()
                    .stroke(Color.aphid.opacity(0.22), lineWidth: lineWidth)
                if shown > 0 {
                    Circle()
                        .trim(from: 0, to: shown)
                        .stroke(
                            AngularGradient(
                                colors: [Color.aphid.mix(with: .black, by: 0.2), .aphid, Color.aphid.mix(with: .white, by: 0.25)],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360 * shown)
                            ),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .padding(lineWidth / 2)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.9).delay(0.1)) { shown = min(max(progress, 0), 1) }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.smooth) { shown = min(max(newValue, 0), 1) }
        }
        .accessibilityHidden(true)
    }
}
