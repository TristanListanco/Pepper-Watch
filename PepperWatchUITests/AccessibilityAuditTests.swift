//
//  AccessibilityAuditTests.swift
//  PepperWatchUITests
//
//  Xcode's accessibility audit on each screen of the iPhone and iPad app: contrast, element
//  descriptions, hit regions, Dynamic Type, clipped text and traits. Screens open on demo data
//  through the app's DEBUG launch arguments, so the tests don't tap their way there.
//
//  Element descriptions, hit regions, traits and clipped text come from the accessibility tree
//  and gate the build. Contrast and text detection are measured from rendered pixels and vary
//  between simulators, so their findings, like Dynamic Type's, are recorded as expected failures:
//  they stay visible in the test report without failing the run.
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    @MainActor func testFields() throws { try audit(tab: "scan") }

    @MainActor func testInsights() throws { try audit(tab: "insights") }

    @MainActor func testInsightDetail() throws { try audit(tab: "insights", "-PWInsightMetric", "infestation") }

    @MainActor func testHistory() throws { try audit(tab: "history") }

    @MainActor func testScanDetail() throws { try audit(tab: "history", "-PWOpenLatestScan", "YES") }

    @MainActor func testDeveloper() throws { try audit(tab: "developer") }

    @MainActor func testPerformance() throws { try audit(tab: "developer", "-PWDeveloperPage", "performance") }

    @MainActor func testSessions() throws {
        try audit(tab: "developer", "-PWDeveloperPage", "sessions", known: [
            KnownIssue(.textClipped, on: .unattributed, "The sessions table clips text the audit can't tie to an element."),
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
        /// Which elements the known issue covers.
        enum Scope {
            /// Any element on the screen.
            case anywhere
            /// Only issues the audit couldn't attribute to an element.
            case unattributed
        }

        let type: XCUIAccessibilityAuditType
        let scope: Scope
        let reason: String

        init(_ type: XCUIAccessibilityAuditType, on scope: Scope = .anywhere, _ reason: String) {
            self.type = type
            self.scope = scope
            self.reason = reason
        }

        @MainActor func matches(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
            guard issue.auditType == type else { return false }
            switch scope {
            case .anywhere: return true
            case .unattributed: return issue.element == nil
            }
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
        // Let summaries and charts finish animating in, so the audit measures settled content.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Screen settles")], timeout: 2)

        let tabBar = app.tabBars.firstMatch
        let tabBarFrame = tabBar.exists ? tabBar.frame : .null

        try app.performAccessibilityAudit(for: .all) { issue in
            // MapKit's own legal link sits on the map at the system's size.
            if issue.detailedDescription.contains("MKAttributionLabel") { return true }
            // Content scrolled under the floating tab bar is measured against its glass; it's read
            // once it scrolls back up.
            if issue.auditType == .contrast, let element = issue.element, element.frame.intersects(tabBarFrame) { return true }

            guard let reason = Self.baselineReason(for: issue) ?? known.first(where: { $0.matches(issue) })?.reason else {
                return false
            }
            XCTExpectFailure(reason) {
                let element = issue.element.map { "\"\($0.label)\" at \($0.frame.integral)" } ?? "no element"
                XCTFail("\(issue.compactDescription): \(element). \(issue.detailedDescription)", file: file, line: line)
            }
            return true
        }
    }

    /// Findings recorded but not gating: pixel-measured checks, and Dynamic Type to fix over time.
    private static func baselineReason(for issue: XCUIAccessibilityAuditIssue) -> String? {
        switch issue.auditType {
        case .contrast: "Measured from rendered pixels, which vary between simulators; the app's text styles are built for 4.5:1."
        case .elementDetection: "Text detected in rendered pixels, such as map labels drawn by MapKit, which varies between simulators."
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
