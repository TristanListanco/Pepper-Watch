//
//  StaticAnalysisTests.swift
//  PepperWatchTests
//
//  Static checks over the Xcode project and the sources every app and extension target compiles:
//  SF Symbols and asset names that resolve, SwiftData models registered in the schema, privacy
//  usage descriptions, entitlements a free developer account can sign, and source hygiene. Each
//  failure points at the offending line. SwiftLint covers general Swift style in CI.
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import Pepper_Watch

@Suite("Static analysis", .tags(.staticAnalysis), .enabled(if: Project.isAvailable, "Reads the source checkout, so it runs in the Simulator"))
struct StaticAnalysisTests {
    @Test func projectIsReadable() throws {
        // Guards every other check against passing because nothing was scanned.
        let app = try #require(Project.targets.first { $0.name == "Pepper Watch" })
        #expect(Project.targets.count >= 4)
        for target in Project.targets {
            #expect(!target.sources.isEmpty, "\(target.name) compiles no Swift files")
            #expect(Set(target.configurations.keys) == ["Debug", "Release"], "\(target.name) configurations")
        }
        #expect(app.sources.contains { $0.path == "Pepper Watch/Pepper_WatchApp.swift" })
        #expect(!Project.sources.flatMap(\.symbolReferences).isEmpty)
    }

    @Test func sfSymbolsExist() {
        for reference in Project.sources.flatMap(\.symbolReferences) where UIImage(systemName: reference.value) == nil {
            Issue.record("No SF Symbol named \"\(reference.value)\"", sourceLocation: reference.location)
        }
    }

    @Test func namedColorsAndImagesExistInEveryTargetThatUsesThem() {
        for target in Project.targets {
            for reference in target.sources.flatMap({ $0.references(to: Self.assetName) }) where !target.assetNames.contains(reference.value) {
                Issue.record("\(target.name) has no color or image named \"\(reference.value)\" in its asset catalogs", sourceLocation: reference.location)
            }
        }
    }

    @Test func everySwiftDataModelIsInTheSchema() {
        let registered = Set(AppSchema.schema.entities.map(\.name))
        let models = Project.sources.flatMap { $0.references(to: Self.modelDeclaration) }
        #expect(!models.isEmpty)
        for model in models where !registered.contains(model.value) {
            Issue.record("@Model \(model.value) is missing from AppSchema.schema", sourceLocation: model.location)
        }
    }

    @Test func privacyProtectedAPIsHaveUsageDescriptions() throws {
        for rule in Self.privacyRules {
            let api = try Regex(rule.pattern)
            for target in Project.targets {
                guard let use = target.sources.lazy.compactMap({ $0.firstReference(to: api) }).first else { continue }
                for (configuration, settings) in target.configurations.sorted(by: { $0.key < $1.key })
                where !rule.keys.contains(where: { Project.declares($0, settings: settings) }) {
                    Issue.record("\(target.name) (\(configuration)) uses \(rule.feature) through \(use.value) but declares no \(rule.keys[0])", sourceLocation: use.location)
                }
            }
        }
    }

    @Test func entitlementsWorkWithAFreeDeveloperAccount() {
        for target in Project.targets {
            for (configuration, settings) in target.configurations {
                guard let path = settings["CODE_SIGN_ENTITLEMENTS"], let entitlements = Project.propertyList(at: path) else { continue }
                for key in entitlements.keys where Self.paidOnlyEntitlements.contains(key) {
                    Issue.record("\(target.name) (\(configuration)) requests \(key), which needs a paid Apple Developer Program membership", sourceLocation: Project.location(of: key, in: path))
                }
            }
        }
    }

    @Test func targetsSharingTheAppGroupAreEntitledToIt() {
        for target in Project.targets {
            guard let use = target.sources.lazy.compactMap({ $0.firstReference(to: #/appGroupID|"group\./#) }).first else { continue }
            for (configuration, settings) in target.configurations {
                let entitlements = settings["CODE_SIGN_ENTITLEMENTS"].flatMap { Project.propertyList(at: $0) }
                let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
                if !groups.contains(SharedContainer.appGroupID) {
                    Issue.record("\(target.name) (\(configuration)) shares data through the App Group but isn't entitled to \(SharedContainer.appGroupID)", sourceLocation: use.location)
                }
            }
        }
    }

    @Test("No print statements, leftover TODOs or plain-HTTP URLs in shipped code")
    func sourceHygiene() {
        for file in Project.sources {
            for (index, line) in file.lines.enumerated() {
                for (pattern, message) in Self.hygieneRules where line.contains(pattern) {
                    Issue.record(Comment(rawValue: message), sourceLocation: Reference(value: "", path: file.path, line: index + 1).location)
                }
            }
        }
    }

    @Test func fileHeadersNameTheirFile() {
        for file in Project.sources where file.lines.count > 1 && file.lines[1] != "//  \(file.name)" {
            Issue.record("The header names \(file.lines[1].dropFirst(4)) instead of \(file.name)", sourceLocation: Reference(value: "", path: file.path, line: 2).location)
        }
    }
}

// MARK: - Rules

extension StaticAnalysisTests {
    /// `Color("Name")`, `Image("Name")` and their UIKit equivalents.
    static let assetName = #/\b(?:Color|UIColor|Image|UIImage)\((?:named:\s*)?"([^"\\]+)"/#

    static let modelDeclaration = #/@Model\s+(?:\w+\s+)*?class\s+(\w+)/#

    struct PrivacyRule {
        let feature: String
        let pattern: String
        /// Any one of these Info.plist keys covers the feature; the first is the one to add.
        let keys: [String]
    }

    static let privacyRules = [
        PrivacyRule(feature: "the camera", pattern: #"\bAVCapture(Device|Session)\b|\bDataScannerViewController\b"#, keys: ["NSCameraUsageDescription"]),
        PrivacyRule(feature: "location", pattern: #"\bCL(LocationManager|LocationUpdate|ServiceSession|Monitor|BackgroundActivitySession)\b|\bLocationButton\b"#, keys: ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"]),
        PrivacyRule(feature: "saving to Photos", pattern: #"\bUIImageWriteToSavedPhotosAlbum\b|\bPHAsset(Creation|Change)Request\b"#, keys: ["NSPhotoLibraryAddUsageDescription", "NSPhotoLibraryUsageDescription"]),
        PrivacyRule(feature: "the photo library", pattern: #"\bPHPhotoLibrary\.requestAuthorization\b|\bPHAsset\.fetchAssets\b"#, keys: ["NSPhotoLibraryUsageDescription"]),
        PrivacyRule(feature: "the microphone", pattern: #"\bAVAudioRecorder\b|\brequestRecordPermission\b"#, keys: ["NSMicrophoneUsageDescription"]),
        PrivacyRule(feature: "motion data", pattern: #"\bCM(MotionActivityManager|Pedometer|Altimeter)\b"#, keys: ["NSMotionUsageDescription"]),
        PrivacyRule(feature: "Bluetooth", pattern: #"\bCB(CentralManager|PeripheralManager)\b"#, keys: ["NSBluetoothAlwaysUsageDescription"]),
        PrivacyRule(feature: "contacts", pattern: #"\bCNContactStore\b"#, keys: ["NSContactsUsageDescription"]),
        PrivacyRule(feature: "calendars", pattern: #"\bEKEventStore\b"#, keys: ["NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription"]),
        PrivacyRule(feature: "speech recognition", pattern: #"\bSFSpeechRecognizer\b"#, keys: ["NSSpeechRecognitionUsageDescription"]),
        PrivacyRule(feature: "HealthKit", pattern: #"\bHKHealthStore\b"#, keys: ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"]),
    ]

    /// Capabilities a free personal team can't sign: iCloud, push, associated domains, Sign in with
    /// Apple, Apple Pay, Wallet, network extensions, Siri and Game Center.
    static let paidOnlyEntitlements: Set<String> = [
        "com.apple.developer.icloud-container-identifiers",
        "com.apple.developer.icloud-container-environment",
        "com.apple.developer.icloud-services",
        "com.apple.developer.ubiquity-container-identifiers",
        "com.apple.developer.ubiquity-kvstore-identifier",
        "aps-environment",
        "com.apple.developer.aps-environment",
        "com.apple.developer.associated-domains",
        "com.apple.developer.applesignin",
        "com.apple.developer.in-app-payments",
        "com.apple.developer.pass-type-identifiers",
        "com.apple.developer.networking.networkextension",
        "com.apple.developer.siri",
        "com.apple.developer.game-center",
    ]

    static let hygieneRules: [(Regex<Substring>, String)] = [
        (#/(?:^|[^.\w])(?:print|debugPrint|NSLog|dump)\(/#, "Log with Logger instead of printing"),
        (#/\b(?:TODO|FIXME)\b/#, "Resolve the TODO or FIXME before shipping"),
        (#/"http:\/\//#, "Use HTTPS; App Transport Security blocks plain HTTP"),
    ]
}

extension Tag {
    @Tag static var staticAnalysis: Self
}

// MARK: - Project model

/// The Xcode project and the sources each app and extension target compiles, read from the
/// checkout this test bundle was built from.
enum Project {
    nonisolated static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    nonisolated static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: root.appending(path: "Pepper Watch.xcodeproj/project.pbxproj").path(percentEncoded: false))
    }

    struct Target {
        let name: String
        let sources: [SourceFile]
        /// Color, image and symbol set names in the asset catalogs it builds.
        let assetNames: Set<String>
        /// Build settings per configuration, with project-level settings filled in.
        let configurations: [String: [String: String]]
    }

    /// Every app and extension target; unit and UI test bundles are left out.
    static let targets = loadTargets()

    /// Every Swift file a shipped target compiles, once each.
    static let sources: [SourceFile] = {
        var seen: Set<String> = []
        return targets.flatMap(\.sources).filter { seen.insert($0.path).inserted }
    }()

    static func propertyList(at path: String) -> [String: Any]? {
        let relative = path.replacingOccurrences(of: "$(SRCROOT)/", with: "")
        guard let data = try? Data(contentsOf: root.appending(path: relative)) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Whether an Info.plist key is set, either as a generated `INFOPLIST_KEY_` setting or in the
    /// target's Info.plist file.
    static func declares(_ key: String, settings: [String: String]) -> Bool {
        if let value = settings["INFOPLIST_KEY_\(key)"], !value.isEmpty { return true }
        guard let file = settings["INFOPLIST_FILE"], let value = propertyList(at: file)?[key] else { return false }
        return (value as? String)?.isEmpty != true
    }

    /// Where a key appears in a project file, for pointing an issue at it.
    static func location(of needle: String, in path: String) -> SourceLocation {
        let text = (try? String(contentsOf: root.appending(path: path), encoding: .utf8)) ?? ""
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).firstIndex { $0.contains(needle) } ?? 0
        return Reference(value: needle, path: path, line: line + 1).location
    }

    private static func loadTargets() -> [Target] {
        guard let data = try? Data(contentsOf: root.appending(path: "Pepper Watch.xcodeproj/project.pbxproj")),
              let project = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let objects = project["objects"] as? [String: [String: Any]],
              let rootObject = (project["rootObject"] as? String).flatMap({ objects[$0] }) else { return [] }

        func settings(forList id: Any?) -> [String: [String: String]] {
            let list = (id as? String).flatMap { objects[$0] }
            let configurations = (list?["buildConfigurations"] as? [String] ?? []).compactMap { objects[$0] }
            return configurations.reduce(into: [:]) { result, configuration in
                guard let name = configuration["name"] as? String else { return }
                result[name] = (configuration["buildSettings"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            }
        }

        let projectSettings = settings(forList: rootObject["buildConfigurationList"])
        var files: [String: SourceFile] = [:]

        return objects.compactMap { id, object -> Target? in
            guard object["isa"] as? String == "PBXNativeTarget",
                  let productType = object["productType"] as? String, !productType.hasPrefix("com.apple.product-type.bundle.") else { return nil }
            var sources: [SourceFile] = []
            var assetNames: Set<String> = []
            for group in (object["fileSystemSynchronizedGroups"] as? [String] ?? []).compactMap({ objects[$0] }) {
                guard let folder = group["path"] as? String else { continue }
                // Exception sets list the folder's files this target leaves out.
                let excluded = Set((group["exceptions"] as? [String] ?? []).compactMap { objects[$0] }
                    .filter { $0["target"] as? String == id }
                    .flatMap { $0["membershipExceptions"] as? [String] ?? [] }
                    .map { "\(folder)/\($0)" })
                let contents = FileManager.default.enumerator(atPath: root.appending(path: folder).path(percentEncoded: false))?.allObjects as? [String] ?? []
                for path in contents.map({ "\(folder)/\($0)" }).sorted() where !excluded.contains(path) {
                    let name = URL(filePath: path).lastPathComponent
                    if path.hasSuffix(".swift") {
                        if files[path] == nil { files[path] = SourceFile(path: path) }
                        if let file = files[path] { sources.append(file) }
                    } else if path.contains(".xcassets/"), let set = [".colorset", ".imageset", ".symbolset"].first(where: { name.hasSuffix($0) }) {
                        assetNames.insert(String(name.dropLast(set.count)))
                    }
                }
            }
            let configurations = settings(forList: object["buildConfigurationList"]).reduce(into: [String: [String: String]]()) { result, entry in
                result[entry.key] = (projectSettings[entry.key] ?? [:]).merging(entry.value) { _, target in target }
            }
            return Target(name: object["name"] as? String ?? id, sources: sources, assetNames: assetNames, configurations: configurations)
        }
        .sorted { $0.name < $1.name }
    }
}

/// A Swift file's text, relative to the repository root.
struct SourceFile {
    let path: String
    let text: String
    let lines: [Substring]

    init(path: String) {
        self.path = path
        text = (try? String(contentsOf: Project.root.appending(path: path), encoding: .utf8)) ?? ""
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    var name: String { URL(filePath: path).lastPathComponent }

    /// Each match's first capture.
    func references(to regex: Regex<(Substring, Substring)>) -> [Reference] {
        text.matches(of: regex).map { reference(String($0.output.1), at: $0.range.lowerBound) }
    }

    func firstReference(to regex: some RegexComponent) -> Reference? {
        text.firstMatch(of: regex).map { reference(String(text[$0.range]), at: $0.range.lowerBound) }
    }

    /// SF Symbol names: literals passed as `systemName:`, `systemImage:` or `symbol:` (both sides
    /// of a ternary included) and every literal a `symbol` property returns.
    var symbolReferences: [Reference] {
        var references: [Reference] = []
        for label in text.matches(of: #/\b(?:systemName|systemImage|symbol):/#) {
            references += symbolLiterals(in: text[label.range.upperBound...].prefix { !",)\n".contains($0) })
        }
        for property in text.matches(of: #/var\s+\w*[sS]ymbol\w*\s*:\s*String\??\s*\{/#) {
            var depth = 1
            let body = text[property.range.upperBound...].prefix { character in
                if character == "{" { depth += 1 } else if character == "}" { depth -= 1 }
                return depth > 0
            }
            references += symbolLiterals(in: body)
        }
        return references
    }

    private func symbolLiterals(in fragment: Substring) -> [Reference] {
        fragment.matches(of: #/"([a-z0-9]+(?:\.[a-z0-9]+)*)"/#).map { reference(String($0.output.1), at: $0.range.lowerBound) }
    }

    private func reference(_ value: String, at index: String.Index) -> Reference {
        Reference(value: value, path: path, line: text[..<index].reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
    }
}

/// Something found in a project file, with the place to report it.
struct Reference {
    let value: String
    let path: String
    let line: Int

    var location: SourceLocation {
        SourceLocation(
            fileID: "Pepper_Watch/\(URL(filePath: path).lastPathComponent)",
            filePath: Project.root.appending(path: path).path(percentEncoded: false),
            line: line, column: 1
        )
    }
}
