//
//  PhotoViewer.swift
//  Pepper Watch
//

import SwiftUI
import UIKit

/// Full-screen view of a scan's photo with its detection boxes on or off. It opens with the zoom
/// transition, so pulling down closes it.
struct PhotoViewer: View {
    let imageData: Data?
    let detections: [Detection]

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var showsBoxes = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityIgnoresInvertColors()
                    .accessibilityLabel("Scan photo")
                    .overlay {
                        if showsBoxes {
                            DetectionOverlay(detections: detections, imageSize: image.size, contentMode: .fit)
                        }
                    }
                    .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .task {
            if image == nil, let imageData { image = UIImage(data: imageData) }
        }
        .overlay(alignment: .top) {
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                Spacer()
                Button(showsBoxes ? "Hide Boxes" : "Show Boxes", systemImage: showsBoxes ? "square.dashed" : "square.dashed.inset.filled") {
                    showsBoxes.toggle()
                }
                .buttonStyle(.glass)
            }
            // White controls over the photo, as in Photos.
            .tint(.white)
            .environment(\.colorScheme, .dark)
            .padding()
        }
        .statusBarHidden()
    }
}
