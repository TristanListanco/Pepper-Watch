//
//  Handoff.swift
//  Pepper Watch (shared by the iPhone app and the watch app)
//
//  Handoff (NSUserActivity): looking at a field on the watch offers to continue on the iPhone
//  in that field's Insights.
//

import Foundation

nonisolated enum HandoffActivity {
    /// Declared under NSUserActivityTypes in both apps' Info.plist files.
    static let viewField = "com.tristanlistanco.Pepper-Watch.viewField"
    /// The field's UUID string, as in `WidgetSnapshot.FieldStatus.id`.
    static let fieldIDKey = "fieldID"
}
