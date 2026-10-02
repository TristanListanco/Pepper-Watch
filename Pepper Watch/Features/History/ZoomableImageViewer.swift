//
//  ZoomableImageViewer.swift
//  Pepper Watch
//

import SwiftUI
import UIKit

/// Full-screen photo viewer with the system's zooming, as in Photos: pinch zooms around your
/// fingers, double-tap zooms in where you tap, and pulling down at full size closes the viewer.
struct ZoomableImageViewer: View {
    let imageData: Data?
    let detections: [Detection]

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    /// The photo with its boxes drawn in at full resolution, so they stay sharp when zoomed.
    @State private var annotated: UIImage?
    @State private var showsBoxes = true
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ZoomingImageView(
                image: showsBoxes ? annotated ?? image : image,
                zoomScale: $zoomScale,
                onPullDown: { dismiss() }
            )
            .task(id: proxy.size) {
                if image == nil, let imageData { image = UIImage(data: imageData) }
                if let image { annotated = annotatedImage(image, fitting: proxy.size) }
            }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
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
        .overlay(alignment: .bottom) {
            if zoomScale > 1.05 {
                Text("\(Double(zoomScale).fixed(1))×")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: zoomScale > 1.05)
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo")
    }

    /// Draws the boxes at the size the photo appears on screen, so labels and lines look as they do
    /// elsewhere, but renders at the photo's own resolution.
    private func annotatedImage(_ image: UIImage, fitting container: CGSize) -> UIImage? {
        guard !detections.isEmpty, image.size.width > 0, container.width > 0 else { return nil }
        let fit = min(container.width / image.size.width, container.height / image.size.height)
        let displayed = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        let renderer = ImageRenderer(
            // Rendered offscreen into a bitmap; the viewer itself is labeled.
            // swiftlint:disable:next accessibility_label_for_image
            content: Image(uiImage: image)
                .resizable()
                .overlay { DetectionOverlay(detections: detections, imageSize: image.size, contentMode: .fit) }
                .frame(width: displayed.width, height: displayed.height)
        )
        renderer.scale = max(image.size.width * image.scale / displayed.width, 1)
        return renderer.uiImage
    }
}

/// A `UIScrollView` zooming an image view.
private struct ZoomingImageView: UIViewRepresentable {
    let image: UIImage?
    @Binding var zoomScale: CGFloat
    let onPullDown: () -> Void

    func makeUIView(context: Context) -> ImageZoomView {
        let view = ImageZoomView()
        view.onZoom = { scale in zoomScale = scale }
        view.onPullDown = onPullDown
        return view
    }

    func updateUIView(_ view: ImageZoomView, context: Context) {
        view.image = image
    }
}

private final class ImageZoomView: UIScrollView, UIScrollViewDelegate {
    var onZoom: ((CGFloat) -> Void)?
    var onPullDown: (() -> Void)?

    private let imageView = UIImageView()
    private var laidOutSize: CGSize = .zero

    var image: UIImage? {
        get { imageView.image }
        set {
            let previousAspect = imageView.image.map { Self.aspect($0) }
            imageView.image = newValue
            // Showing or hiding boxes swaps in an image of the same shape; keep the zoom.
            let newAspect = newValue.map { Self.aspect($0) }
            if previousAspect == nil || newAspect == nil || previousAspect != newAspect {
                layoutImage()
            }
        }
    }

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        // Lets a pull at full size bounce, so it can close the viewer.
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutSize {
            laidOutSize = bounds.size
            layoutImage()
        }
    }

    private static func aspect(_ image: UIImage) -> CGFloat {
        image.size.height > 0 ? (image.size.width / image.size.height * 1000).rounded() : 0
    }

    /// Fits the image to the screen at 1×.
    private func layoutImage() {
        setZoomScale(minimumZoomScale, animated: false)
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0 else { return }
        let fit = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * fit, height: size.height * fit)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        centerImage()
        // Layout can run inside a SwiftUI update; report the reset zoom after it.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onZoom?(self.zoomScale)
        }
    }

    /// Keeps the image centered while it's smaller than the screen.
    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let scale = min(2.5, maximumZoomScale)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        onZoom?(zoomScale)
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // A firm pull down at full size closes the viewer, like Photos.
        let pulled = -(contentOffset.y + contentInset.top)
        if zoomScale <= minimumZoomScale + 0.01, pulled > 90 || (pulled > 30 && velocity.y < -1) {
            onPullDown?()
        }
    }
}
