//
//  ImageEncoder.swift
//  Pepper Watch
//

import CoreImage
import ImageIO

/// JPEG encoding for stored detection images, off the main actor.
nonisolated enum ImageEncoder {
    struct Encoded: Sendable {
        var image: Data?
        var thumbnail: Data?
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    @concurrent static func encode(_ frame: PixelBufferBox) async -> Encoded {
        encode(CIImage(cvPixelBuffer: frame.buffer))
    }

    @concurrent static func encode(_ image: CGImage) async -> Encoded {
        encode(CIImage(cgImage: image))
    }

    private static func encode(_ image: CIImage) -> Encoded {
        Encoded(
            image: jpeg(image, maxDimension: 1280, quality: 0.75),
            thumbnail: jpeg(image, maxDimension: 360, quality: 0.6)
        )
    }

    /// Decodes photo-library data into an upright image no larger than `maxDimension`.
    @concurrent static func uprightImage(from data: Data, maxDimension: CGFloat = 2048) async -> CGImage? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let scaled = scale(image, maxDimension: maxDimension)
        return context.createCGImage(scaled, from: scaled.extent, format: .RGBA8, colorSpace: colorSpace)
    }

    private static func jpeg(_ image: CIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let key = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(of: scale(image, maxDimension: maxDimension), colorSpace: colorSpace, options: [key: quality])
    }

    private static func scale(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > maxDimension else { return image }
        let factor = maxDimension / longest
        let scaled = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: factor, kCIInputAspectRatioKey: 1])
        return scaled.cropped(to: scaled.extent.integral)
    }
}
