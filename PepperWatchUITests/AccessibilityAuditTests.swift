//
//  AccessibilityAuditTests.swift
//  PepperWatchUITests
//
//  Xcode's accessibility audit on each screen of the iPhone and iPad app: contrast, element
//  descriptions, hit regions, Dynamic Type, clipped text and traits. Screens open on demo data
//  through the app's DEBUG launch arguments, so the tests don't tap their way there.
//
//  Findings the app has today are recorded as expected failures, so they stay visible in the
//  test report without failing the run; anything else fails the test.
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    @MainActor func testFields() throws { try audit(tab: "scan") }

    @MainActor func testInsights() throws { try audit(tab: "insights") }

    @MainActor func testInsightDetail() throws { try audit(tab: "insights", "-PWInsightMetric", "infestation") }

    @MainActor func testHistory() throws { try audit(tab: "history") }

    @MainActor func testScanDetail() throws { try audit(tab: "history", "-PWOpenLatestScan", "YES") }

    @MainActor func testDeveloper() throws {
        try audit(tab: "developer", known: [
            KnownIssue(.elementDetection, unattributed: true, "The audit reports visible text it can't tie to an element on this screen."),
        ])
    }

    @MainActor func testPerformance() throws { try audit(tab: "developer", "-PWDeveloperPage", "performance") }

    @MainActor func testSessions() throws {
        try audit(tab: "developer", "-PWDeveloperPage", "sessions", known: [
            KnownIssue(.textClipped, unattributed: true, "The sessions table clips text the audit can't tie to an element."),
        ])
    }

    @MainActor func testModelCard() throws { try audit(tab: "developer", "-PWDeveloperPage", "model") }

    @MainActor func testWidgetGallery() throws {
        try audit(tab: "developer", "-PWDeveloperPage", "widgets", known: [
            KnownIssue(.textClipped, "Widget previews render at fixed widget sizes, where widgets truncate by design."),
        ])
    }

    // MARK: - Auditing

    /// An issue a screen is known to have, recorded as an expected failure.
    struct KnownIssue {
        let type: XCUIAccessibilityAuditType
        /// Only issues the audit couldn't attribute to an element.
        var unattributed = false
        let reason: String

        init(_ type: XCUIAccessibilityAuditType, unattributed: Bool = false, _ reason: String) {
            self.type = type
            self.unattributed = unattributed
            self.reason = reason
        }

        func matches(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
            issue.auditType == type && (!unattributed || issue.element == nil)
        }
    }

    /// Opens a tab (and optionally a page in it) on demo data, then audits what's on screen.
    @MainActor private func audit(tab: String, _ arguments: String..., known: [KnownIssue] = [], file: StaticString = #filePath, line: UInt = #line) throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-PWSeedDemo", "YES", "-PWInitialTab", tab] + arguments
        app.launch()
        allowLocationIfAsked()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20), "The \(tab) screen didn't appear", file: file, line: line)

        try app.performAccessibilityAudit(for: .all) { issue in
            // MapKit's own legal link sits on the map at the system's size.
            if issue.detailedDescription.contains("MKAttributionLabel") { return true }

            guard let reason = Self.baselineReason(for: issue) ?? known.first(where: { $0.matches(issue) })?.reason else {
                return false
            }
            XCTExpectFailure(reason) {
                XCTFail("\(issue.compactDescription): \(issue.element?.label ?? "no element"). \(issue.detailedDescription)", file: file, line: line)
            }
            return true
        }
    }

    /// App-wide findings to fix over time.
    private static func baselineReason(for issue: XCUIAccessibilityAuditIssue) -> String? {
        switch issue.auditType {
        case .contrast: "Known: secondary text on the gradient and glass backgrounds, and labels over photos, fall short of contrast minimums."
        case .dynamicType: "Known: some text keeps a fixed size instead of following Dynamic Type."
        default: nil
        }
    }

    /// A fresh install asks for location on the Fields screen; the alert would cover the app.
    @MainActor private func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }
}
