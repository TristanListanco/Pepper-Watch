//
//  PhotoTransfer.swift
//  Pepper Watch
//
//  Drag and drop for photos (Transferable): scans drag out of History into other apps, and
//  photos from other apps drop onto the scanner to be analyzed.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A scan's photo, as a JPEG file named for when it was taken.
nonisolated struct ScanPhoto: Transferable, Sendable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

/// Any image dropped from Photos, Files or another app.
nonisolated struct DroppedPhoto: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedPhoto(data: $0) }
    }
}
