import XCTest
@testable import ChromaDockCore

final class AppNameFilterTests: XCTestCase {
    func testBlueQueryMatchesBlueBubblesOnly() {
        let apps = [
            fixtureApp(label: "BlueBubbles", bundle: "com.BlueBubbles.BlueBubbles-Server", group: "communication", inDock: false),
            fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        ]
        let hits = apps.filter { AppNameFilter.containsName($0.label, query: "blue") }
        XCTAssertEqual(hits.map(\.label), ["BlueBubbles"])
        XCTAssertEqual(hits.map(\.bundleIdentifier), ["com.BlueBubbles.BlueBubbles-Server"])
    }

    func testFilterIsCaseInsensitiveAndTrimmed() {
        XCTAssertTrue(AppNameFilter.containsName("BlueBubbles", query: "  BLUE "))
        XCTAssertFalse(AppNameFilter.containsName("Safari", query: "blue"))
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertFalse(AppNameFilter.containsName("BlueBubbles", query: ""))
        XCTAssertFalse(AppNameFilter.containsName("BlueBubbles", query: "   "))
    }
}

final class HueSortTests: XCTestCase {
    func testGrayThenHueOrder() {
        let gray = fixtureApp(label: "Gray", bundle: "g", group: "other", inDock: true)
        var red = fixtureApp(label: "Red", bundle: "r", group: "other", inDock: true)
        red.colorful = true
        red.hue = 0.0
        var blue = fixtureApp(label: "Blue", bundle: "b", group: "other", inDock: true)
        blue.colorful = true
        blue.hue = 0.6
        let sorted = HueSampler.hueSorted([blue, gray, red])
        XCTAssertEqual(sorted.map(\.label), ["Gray", "Red", "Blue"])
    }
}

final class HeuristicTests: XCTestCase {
    func testBlueBubblesServerIsCommunication() {
        XCTAssertEqual(
            Heuristic.suggestedGroup(bundle: "com.BlueBubbles.BlueBubbles-Server", label: "BlueBubbles"),
            "communication"
        )
    }
}

final class WillEmitTileTests: XCTestCase {
    func testDockedAppEmits() {
        let app = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        XCTAssertTrue(AppModel.willEmitTile(app, settings: .default, dockedBundles: ["com.apple.Safari"]))
    }

    func testHeuristicExtraDoesNotEmit() {
        let app = fixtureApp(label: "BlueBubbles", bundle: "com.BlueBubbles.BlueBubbles-Server", group: "communication", inDock: false)
        XCTAssertFalse(AppModel.willEmitTile(app, settings: .default, dockedBundles: []))
    }

    func testExplicitlyAssignedExtraEmits() {
        var settings = AppSettings.default
        settings.assignments["com.BlueBubbles.BlueBubbles-Server"] = "communication"
        let app = fixtureApp(label: "BlueBubbles", bundle: "com.BlueBubbles.BlueBubbles-Server", group: "communication", inDock: false)
        XCTAssertTrue(AppModel.willEmitTile(app, settings: settings, dockedBundles: []))
    }
}

final class DeleteGroupAssignmentTests: XCTestCase {
    func testHeuristicMemberDoesNotGainAssignment() {
        let next = AppModel.rewriteAssignmentsAfterDelete(
            deletedGroupID: "media",
            ungroupedID: "other",
            assignments: [:]
        )
        XCTAssertNil(next["com.BlueBubbles.BlueBubbles-Server"])
    }

    func testExplicitMemberIsRewrittenToUngrouped() {
        let next = AppModel.rewriteAssignmentsAfterDelete(
            deletedGroupID: "media",
            ungroupedID: "other",
            assignments: ["com.pais.handy": "media"]
        )
        XCTAssertEqual(next["com.pais.handy"], "other")
    }

    func testApplyingDeleteGroupRewritesAssignmentAfterMovingAppToUngrouped() {
        let extra = fixtureApp(label: "Handy", bundle: "com.pais.handy", group: "media", inDock: false)
        let result = AppModel.applyingDeleteGroup(
            deletedGroupID: "media",
            ungroupedID: "other",
            apps: [extra],
            assignments: ["com.pais.handy": "media"]
        )
        XCTAssertEqual(result.apps.map(\.groupID), ["other"])
        XCTAssertEqual(result.assignments["com.pais.handy"], "other")
    }
}

final class BuildPersistentAppsTests: XCTestCase {
    func testEmptyScanThrows() {
        let extra = fixtureApp(label: "BlueBubbles", bundle: "com.BlueBubbles.BlueBubbles-Server", group: "communication", inDock: false)
        XCTAssertThrowsError(
            try AppModel.buildPersistentApps(settings: .default, apps: [extra], current: [], helperURLs: [])
        ) { error in
            XCTAssertEqual(error as? AppModel.DockApplyError, .emptyScan)
        }
    }

    func testExtrasOnlyGroupDoesNotInsertDivider() throws {
        let safari = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        let extra = fixtureApp(label: "BlueBubbles", bundle: "com.BlueBubbles.BlueBubbles-Server", group: "communication", inDock: false)
        let current = [fileTile(bundle: "com.apple.Safari", label: "Safari")]
        var settings = AppSettings.default
        settings.insertDividers = true
        let built = try AppModel.buildPersistentApps(
            settings: settings,
            apps: [safari, extra],
            current: current,
            helperURLs: [URL(fileURLWithPath: "/tmp/Divider 1.app")]
        )
        XCTAssertEqual(built.count, 1)
        XCTAssertEqual(DockIO.bundleID(of: built[0]), "com.apple.Safari")
        XCTAssertFalse(built.contains { DockIO.isDividerTile($0) })
    }

    func testTwoDockedGroupsGetOneDivider() throws {
        let safari = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        let slack = fixtureApp(label: "Slack", bundle: "com.tinyspeck.slackmacgap", group: "communication", inDock: true)
        let current = [
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack")
        ]
        var settings = AppSettings.default
        settings.insertDividers = true
        let helper = URL(fileURLWithPath: "/tmp/Divider 1.app")
        let built = try AppModel.buildPersistentApps(
            settings: settings,
            apps: [safari, slack],
            current: current,
            helperURLs: [helper]
        )
        XCTAssertEqual(built.count, 3)
        XCTAssertEqual(DockIO.bundleID(of: built[0]), "com.apple.Safari")
        XCTAssertTrue(DockIO.isDividerTile(built[1]))
        XCTAssertEqual(DockIO.bundleID(of: built[2]), "com.tinyspeck.slackmacgap")
    }
}

final class DockIORunTests: XCTestCase {
    func testRunDrainsStdoutLargerThanPipeBuffer() throws {
        let data = try DockIO.run("/bin/sh", ["-c", "python3 -c 'import sys; sys.stdout.write(\"x\" * 120000)'"])
        XCTAssertEqual(data.count, 120000)
        XCTAssertEqual(data.first, UInt8(ascii: "x"))
        XCTAssertEqual(data.last, UInt8(ascii: "x"))
    }

    func testRunDrainsLargeStderrWithoutDeadlock() throws {
        let data = try DockIO.run("/bin/sh", ["-c", "python3 -c 'import sys; sys.stderr.write(\"y\" * 120000); sys.stdout.write(\"ok\")'"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }
}

private func fixtureApp(label: String, bundle: String, group: String, inDock: Bool) -> DockApp {
    DockApp(
        label: label,
        bundleIdentifier: bundle,
        path: "/Applications/\(label).app",
        hue: 0,
        saturation: 0,
        value: 0,
        colorful: false,
        hex: "#000000",
        groupID: group,
        inDock: inDock
    )
}

private func fileTile(bundle: String, label: String) -> [String: Any] {
    [
        "GUID": UInt32(1),
        "tile-type": "file-tile",
        "tile-data": [
            "bundle-identifier": bundle,
            "file-label": label,
            "file-type": 41,
            "file-data": [
                "_CFURLString": "file:///Applications/\(label.replacingOccurrences(of: " ", with: "%20")).app/",
                "_CFURLStringType": 15
            ]
        ]
    ]
}
