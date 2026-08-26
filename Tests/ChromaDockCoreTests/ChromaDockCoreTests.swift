import CoreGraphics
import ImageIO
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

final class NeighborHueTests: XCTestCase {
    func testGrayDoesNotShiftAndDoesNotPull() {
        var gray = fixtureApp(label: "Notes", bundle: "notes", group: "system", inDock: true)
        gray.colorful = false
        gray.hue = 0.1
        var red = fixtureApp(label: "Red", bundle: "r", group: "system", inDock: true)
        red.colorful = true
        red.hue = 0.0
        red.saturation = 0.8
        red.value = 0.8
        let nudges = HueSampler.neighborAligned([gray, red])
        XCTAssertFalse(nudges[0].applied)
        XCTAssertFalse(nudges[1].applied)
    }

    func testMiddleShiftsTowardNeighborMeanAndStaysCapped() {
        var left = fixtureApp(label: "Left", bundle: "l", group: "browsers", inDock: true)
        left.colorful = true
        left.hue = 0.0
        left.saturation = 0.9
        left.value = 0.9
        var mid = fixtureApp(label: "Mid", bundle: "m", group: "browsers", inDock: true)
        mid.colorful = true
        mid.hue = 0.40
        mid.saturation = 0.9
        mid.value = 0.9
        var right = fixtureApp(label: "Right", bundle: "r", group: "browsers", inDock: true)
        right.colorful = true
        right.hue = 0.20
        right.saturation = 0.9
        right.value = 0.9
        let nudges = HueSampler.neighborAligned([left, mid, right], maxShiftTurns: 12.0 / 360.0)
        XCTAssertTrue(nudges[1].applied)
        XCTAssertEqual(abs(nudges[1].deltaDegrees), 12, accuracy: 0.01)
        XCTAssertLessThan(nudges[1].shiftedHue, mid.hue)
    }

    func testHueWrapsAcrossRed() {
        XCTAssertEqual(HueSampler.shortestHueDelta(from: 0.95, to: 0.05), 0.10, accuracy: 1e-9)
        XCTAssertEqual(HueSampler.shortestHueDelta(from: 0.05, to: 0.95), -0.10, accuracy: 1e-9)
        var a = fixtureApp(label: "A", bundle: "a", group: "other", inDock: true)
        a.colorful = true
        a.hue = 0.98
        a.saturation = 0.8
        a.value = 0.8
        var b = fixtureApp(label: "B", bundle: "b", group: "other", inDock: true)
        b.colorful = true
        b.hue = 0.02
        b.saturation = 0.8
        b.value = 0.8
        let nudges = HueSampler.neighborAligned([a, b], maxShiftTurns: 12.0 / 360.0)
        XCTAssertGreaterThan(nudges[0].deltaTurns, 0)
        XCTAssertLessThan(nudges[1].deltaTurns, 0)
    }

    func testOrderUnchanged() {
        var a = fixtureApp(label: "Edge", bundle: "edge", group: "browsers", inDock: true)
        a.colorful = true
        a.hue = 0.6
        a.saturation = 0.7
        a.value = 0.7
        var b = fixtureApp(label: "Safari", bundle: "safari", group: "browsers", inDock: true)
        b.colorful = true
        b.hue = 0.55
        b.saturation = 0.7
        b.value = 0.7
        let apps = [a, b]
        _ = HueSampler.neighborAligned(apps)
        XCTAssertEqual(apps.map(\.label), ["Edge", "Safari"])
    }
}

final class HueSortTests: XCTestCase {
    func testDarkestIconsComeFirst() {
        var light = fixtureApp(label: "Calendar", bundle: "c", group: "system", inDock: true)
        light.luminance = 0.92
        light.colorful = true
        light.hue = 0.08
        var dark = fixtureApp(label: "Terminal", bundle: "t", group: "system", inDock: true)
        dark.luminance = 0.08
        var mid = fixtureApp(label: "Settings", bundle: "s", group: "system", inDock: true)
        mid.luminance = 0.45
        let sorted = HueSampler.hueSorted([light, dark, mid])
        XCTAssertEqual(sorted.map(\.label), ["Terminal", "Settings", "Calendar"])
    }

    func testColorfulDoesNotJumpAheadOfDarkerGray() {
        var gray = fixtureApp(label: "Passwords", bundle: "p", group: "system", inDock: true)
        gray.luminance = 0.12
        var colorful = fixtureApp(label: "Photos", bundle: "ph", group: "system", inDock: true)
        colorful.colorful = true
        colorful.hue = 0.0
        colorful.luminance = 0.72
        let sorted = HueSampler.hueSorted([colorful, gray])
        XCTAssertEqual(sorted.map(\.label), ["Passwords", "Photos"])
    }

    func testEqualLuminanceUsesLabel() {
        var a = fixtureApp(label: "B-app", bundle: "b", group: "other", inDock: true)
        a.luminance = 0.4
        var b = fixtureApp(label: "A-app", bundle: "a", group: "other", inDock: true)
        b.luminance = 0.4
        XCTAssertEqual(HueSampler.hueSorted([a, b]).map(\.label), ["A-app", "B-app"])
    }
}

final class IconLuminanceTests: XCTestCase {
    func testSolidBlackIsDarkerThanSolidWhite() {
        let black = HueSampler.analyze(solidRaster(r: 8, g: 8, b: 8))
        let white = HueSampler.analyze(solidRaster(r: 245, g: 245, b: 245))
        XCTAssertNotNil(black)
        XCTAssertNotNil(white)
        XCTAssertLessThan(black!.luminance, 0.08)
        XCTAssertGreaterThan(white!.luminance, 0.90)
        XCTAssertLessThan(black!.luminance, white!.luminance)
    }

    func testDarkBlueIsDarkerThanBrightYellow() {
        let blue = HueSampler.analyze(solidRaster(r: 0, g: 0, b: 90))
        let yellow = HueSampler.analyze(solidRaster(r: 255, g: 220, b: 0))
        XCTAssertNotNil(blue)
        XCTAssertNotNil(yellow)
        XCTAssertLessThan(blue!.luminance, yellow!.luminance)
    }

    func testMostlyBlackIconStaysDark() {
        var raster = solidRaster(r: 6, g: 6, b: 6, size: 16)
        // One saturated pixel must not make the icon sort as light.
        let o = 4 * (8 * 16 + 8)
        raster = HueSampler.Raster(size: raster.size, bytesPerRow: raster.bytesPerRow, bytes: {
            var bytes = raster.bytes
            bytes[o] = 255
            bytes[o + 1] = 40
            bytes[o + 2] = 40
            bytes[o + 3] = 255
            return bytes
        }())
        let sample = HueSampler.analyze(raster)
        XCTAssertNotNil(sample)
        XCTAssertLessThan(sample!.luminance, 0.12)
    }
}

final class DockSnapshotTests: XCTestCase {
    func testAssignmentsFromDockFollowDividerSections() {
        let tiles = [
            fileTile(bundle: "com.apple.Terminal", label: "Terminal"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.line.1", label: "│"),
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.line.2", label: "│"),
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack")
        ]
        let map = AppModel.assignmentsFromDock(tiles: tiles, groups: AppSettings.default.groups)
        XCTAssertEqual(map["com.apple.Terminal"], "system")
        XCTAssertEqual(map["com.apple.Safari"], "development")
        XCTAssertEqual(map["com.tinyspeck.slackmacgap"], "browsers")
    }

    func testAssignmentsFromDockEmptyWithoutDividers() {
        let tiles = [
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack")
        ]
        XCTAssertEqual(AppModel.assignmentsFromDock(tiles: tiles, groups: AppSettings.default.groups), [:])
    }

    func testNativeSpacerDoesNotStartANewSection() {
        let spacer: [String: Any] = ["GUID": UInt32(2), "tile-type": "small-spacer-tile", "tile-data": [:]]
        let tiles = [
            fileTile(bundle: "com.apple.Terminal", label: "Terminal"),
            spacer,
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.line.1", label: "│"),
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack")
        ]
        let map = AppModel.assignmentsFromDock(tiles: tiles, groups: AppSettings.default.groups)
        XCTAssertEqual(map["com.apple.Terminal"], "system")
        XCTAssertEqual(map["com.apple.Safari"], "system")
        XCTAssertEqual(map["com.tinyspeck.slackmacgap"], "development")
    }

    func testAdoptKeepsInAppGroupPick() {
        var settings = AppSettings.default
        settings.assignments["com.apple.Safari"] = "media"
        settings.dockSnapshot["com.apple.Safari"] = "browsers"
        var safari = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "media", inDock: true)
        safari.groupID = "media"
        let tiles = [
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.line.1", label: "│"),
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack")
        ]
        let adopted = AppModel.adoptDockMembership(settings: settings, apps: [safari], tiles: tiles)
        XCTAssertEqual(adopted.apps[0].groupID, "media")
        XCTAssertEqual(adopted.settings.assignments["com.apple.Safari"], "media")
    }

    func testAdoptTakesLiveDockMoveWhenNoNewerInAppPick() {
        var settings = AppSettings.default
        settings.assignments["com.apple.Safari"] = "browsers"
        settings.dockSnapshot["com.apple.Safari"] = "browsers"
        let safari = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        let tiles = [
            fileTile(bundle: "com.apple.Terminal", label: "Terminal"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.line.1", label: "│"),
            fileTile(bundle: "com.apple.Safari", label: "Safari")
        ]
        let adopted = AppModel.adoptDockMembership(settings: settings, apps: [safari], tiles: tiles)
        XCTAssertEqual(adopted.apps[0].groupID, "development")
        XCTAssertEqual(adopted.settings.assignments["com.apple.Safari"], "development")
    }

    func testMissingDockSnapshotDecodesEmpty() throws {
        let encoded = try JSONEncoder().encode(AppSettings.default)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        obj.removeValue(forKey: "dockSnapshot")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.dockSnapshot, [:])
    }

    func testMissingHueNudgePreviewDecodesOn() throws {
        let encoded = try JSONEncoder().encode(AppSettings.default)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        obj.removeValue(forKey: "previewHueNudge")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.previewHueNudge)
    }
}

final class HeuristicTests: XCTestCase {
    func testBlueBubblesServerIsCommunication() {
        XCTAssertEqual(
            Heuristic.suggestedGroup(bundle: "com.BlueBubbles.BlueBubbles-Server", label: "BlueBubbles"),
            "communication"
        )
    }

    func testResolvedGroupFallsBackWhenHeuristicGroupWasDeleted() {
        var settings = AppSettings.default
        settings.groups.removeAll { $0.id == "media" }
        XCTAssertEqual(
            AppModel.resolvedGroup(bundle: "com.spotify.client", label: "Spotify", settings: settings),
            settings.ungroupedID
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

    func testLeadingNativeSpacerIsKept() throws {
        let safari = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        let spacer: [String: Any] = ["GUID": UInt32(9), "tile-type": "small-spacer-tile", "tile-data": [:]]
        let current = [
            spacer,
            fileTile(bundle: "com.apple.Safari", label: "Safari")
        ]
        var settings = AppSettings.default
        settings.insertDividers = false
        let built = try AppModel.buildPersistentApps(
            settings: settings,
            apps: [safari],
            current: current,
            helperURLs: []
        )
        XCTAssertEqual(built.count, 2)
        XCTAssertTrue(DockIO.isNativeSpacer(built[0]))
        XCTAssertEqual(DockIO.bundleID(of: built[1]), "com.apple.Safari")
    }

    func testSpacerAfterSkippedDividerIsKept() throws {
        let safari = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        let spacer: [String: Any] = ["GUID": UInt32(8), "tile-type": "small-spacer-tile", "tile-data": [:]]
        let current = [
            fileTile(bundle: "com.nextcz.dockdivider.1", label: "│"),
            spacer,
            fileTile(bundle: "com.apple.Safari", label: "Safari")
        ]
        var settings = AppSettings.default
        settings.insertDividers = false
        let built = try AppModel.buildPersistentApps(
            settings: settings,
            apps: [safari],
            current: current,
            helperURLs: []
        )
        XCTAssertTrue(DockIO.isNativeSpacer(built[0]))
        XCTAssertEqual(DockIO.bundleID(of: built[1]), "com.apple.Safari")
        XCTAssertFalse(built.contains { DockIO.isDividerTile($0) })
    }

    func testNativeSpacerAfterAppIsKept() throws {
        let safari = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        let slack = fixtureApp(label: "Slack", bundle: "com.tinyspeck.slackmacgap", group: "communication", inDock: true)
        let spacer: [String: Any] = ["GUID": UInt32(2), "tile-type": "small-spacer-tile", "tile-data": [:]]
        let current = [
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            spacer,
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack")
        ]
        var settings = AppSettings.default
        settings.insertDividers = true
        let built = try AppModel.buildPersistentApps(
            settings: settings,
            apps: [safari, slack],
            current: current,
            helperURLs: [URL(fileURLWithPath: "/tmp/Divider 1.app")]
        )
        XCTAssertFalse(DockIO.isDividerTile(spacer))
        XCTAssertTrue(DockIO.isNativeSpacer(spacer))
        XCTAssertEqual(built.count, 4)
        XCTAssertEqual(DockIO.bundleID(of: built[0]), "com.apple.Safari")
        XCTAssertTrue(DockIO.isNativeSpacer(built[1]))
        XCTAssertTrue(DockIO.isDividerTile(built[2]))
        XCTAssertEqual(DockIO.bundleID(of: built[3]), "com.tinyspeck.slackmacgap")
    }

    func testLegacyAndCurrentDividerTilesAreNotLeftovers() throws {
        let safari = fixtureApp(label: "Safari", bundle: "com.apple.Safari", group: "browsers", inDock: true)
        let slack = fixtureApp(label: "Slack", bundle: "com.tinyspeck.slackmacgap", group: "communication", inDock: true)
        let current = [
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.divider.1", label: "│"),
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.line.1", label: "│"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.line.2", label: "│")
        ]
        var settings = AppSettings.default
        settings.insertDividers = true
        let helper = URL(fileURLWithPath: "/tmp/Line 1.app")
        let built = try AppModel.buildPersistentApps(
            settings: settings,
            apps: [safari, slack],
            current: current,
            helperURLs: [helper]
        )
        XCTAssertEqual(built.count, 3)
        XCTAssertEqual(DockIO.bundleID(of: built[0]), "com.apple.Safari")
        XCTAssertTrue(DockIO.isDividerTile(built[1]))
        XCTAssertEqual(DockIO.bundleID(of: built[1]), "llc.nextcitizen.ChromaDock.line.1")
        XCTAssertEqual(DockIO.bundleID(of: built[2]), "com.tinyspeck.slackmacgap")
        XCTAssertFalse(built.contains { DockIO.bundleID(of: $0) == "llc.nextcitizen.ChromaDock.divider.1" })
        XCTAssertFalse(built.contains { DockIO.bundleID(of: $0) == "llc.nextcitizen.ChromaDock.line.2" })
    }

    func testUnscannedDockedAppIsKept() throws {
        let slack = fixtureApp(label: "Slack", bundle: "com.tinyspeck.slackmacgap", group: "communication", inDock: true)
        let current = [
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack")
        ]
        var settings = AppSettings.default
        settings.insertDividers = false
        let built = try AppModel.buildPersistentApps(
            settings: settings,
            apps: [slack],
            current: current,
            helperURLs: []
        )
        XCTAssertEqual(DockIO.bundleID(of: built[0]), "com.tinyspeck.slackmacgap")
        XCTAssertEqual(DockIO.bundleID(of: built[1]), "com.apple.Safari")
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

final class RestoreDividerCountTests: XCTestCase {
    func testDividerCountUsesHighestIndex() {
        let tiles = [
            fileTile(bundle: "com.apple.Safari", label: "Safari"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.divider.1", label: "│"),
            fileTile(bundle: "com.tinyspeck.slackmacgap", label: "Slack"),
            fileTile(bundle: "llc.nextcitizen.ChromaDock.divider.4", label: "│")
        ]
        XCTAssertEqual(DividerManager.dividerCount(in: tiles), 4)
        XCTAssertEqual(DividerManager.dividerIndex(fromBundleID: "com.nextcz.dockdivider.2"), 2)
        XCTAssertNil(DividerManager.dividerIndex(fromBundleID: "com.apple.Safari"))
    }

    func testEmptyTilesNeedNoHelpers() {
        XCTAssertEqual(DividerManager.dividerCount(in: []), 0)
        XCTAssertEqual(
            DividerManager.dividerCount(in: [fileTile(bundle: "com.apple.Safari", label: "Safari")]),
            0
        )
    }
}

final class HelperLaunchIdentityTests: XCTestCase {
    func testAllDividerPrefixesAndInstallPaths() {
        XCTAssertTrue(Paths.isDividerBundle("llc.nextcitizen.ChromaDock.line.1"))
        XCTAssertTrue(Paths.isDividerBundle("llc.nextcitizen.ChromaDock.divider.2"))
        XCTAssertTrue(Paths.isDividerInstallPath("/Users/me/Library/Application Support/ChromaDock/Lines/Line 1.app"))
        XCTAssertTrue(Paths.isDividerInstallPath("/Users/me/Library/Application Support/ChromaDock/Dividers/Divider 1.app"))
        XCTAssertFalse(Paths.isDividerInstallPath("/Applications/Safari.app"))
        XCTAssertFalse(Paths.isDividerBundle("com.apple.Safari"))
    }

    func testOldAndNewDividerPrefixesAreRecognized() {
        XCTAssertTrue(DockIO.isDividerTile(fileTile(bundle: "llc.nextcitizen.ChromaDock.line.1", label: "│")))
        XCTAssertTrue(DockIO.isDividerTile(fileTile(bundle: "llc.nextcitizen.ChromaDock.divider.2", label: "│")))
        XCTAssertTrue(DockIO.isDividerTile(fileTile(bundle: "com.nextcz.dockdivider.3", label: "│")))
        XCTAssertFalse(DockIO.isDividerTile(fileTile(bundle: "com.apple.Safari", label: "Safari")))
    }

    func testBundleIDFromHelperAppName() {
        XCTAssertEqual(
            DividerManager.bundleID(forHelperApp: URL(fileURLWithPath: "/tmp/Line 3.app")),
            "llc.nextcitizen.ChromaDock.line.3"
        )
        XCTAssertEqual(
            DividerManager.bundleID(forHelperApp: URL(fileURLWithPath: "/tmp/Divider 3.app")),
            "llc.nextcitizen.ChromaDock.line.3"
        )
        XCTAssertNil(DividerManager.bundleID(forHelperApp: URL(fileURLWithPath: "/tmp/Safari.app")))
        XCTAssertNil(DividerManager.bundleID(forHelperApp: URL(fileURLWithPath: "/tmp/Divider.app")))
    }
}

final class DividerStyleTests: XCTestCase {
    func testMissingDividerStyleDecodesAsLines() throws {
        let encoded = try JSONEncoder().encode(AppSettings.default)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        obj.removeValue(forKey: "dividerStyle")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.dividerStyle, .line)
    }

    func testStoredDotsDecodesAsDash() throws {
        XCTAssertEqual(DividerStyle.fromStored("dots"), .dash)
        XCTAssertEqual(DividerStyle.fromStored("dash"), .dash)
        XCTAssertEqual(DividerStyle.fromStored("line"), .line)
        XCTAssertEqual(DividerStyle.catalog, [.line, .dash])
    }

    func testDashHasFewerThanFiveSegments() {
        let rects = DividerMark.dashRects(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(rects.count, DividerStyle.dashCount)
        XCTAssertLessThan(rects.count, 5)
        XCTAssertEqual(rects.count, 4)
        for i in 1..<rects.count {
            XCTAssertGreaterThan(rects[i].minY, rects[i - 1].maxY)
        }
    }

    func testDashPNGIsNotEmpty() throws {
        let data = try DividerManager.markPNG(pixelSize: 128, style: .dash)
        XCTAssertGreaterThan(data.count, 32)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}

final class LineStyleTests: XCTestCase {
    func testDarkWallpaperGetsLightHairline() {
        XCTAssertEqual(LineStyle.paint(luminance: 0.12, darkAppearance: true), .light)
        XCTAssertEqual(LineStyle.paint(luminance: 0.20, darkAppearance: false), .light)
    }

    func testLightWallpaperGetsDarkHairline() {
        XCTAssertEqual(LineStyle.paint(luminance: 0.80, darkAppearance: true), .dark)
        XCTAssertEqual(LineStyle.paint(luminance: 0.70, darkAppearance: false), .dark)
    }

    func testNightModeRaisesTheDarknessThreshold() {
        XCTAssertEqual(LineStyle.paint(luminance: 0.46, darkAppearance: true), .light)
        XCTAssertEqual(LineStyle.paint(luminance: 0.46, darkAppearance: false), .dark)
    }

    func testTileCenterIsScreenCentered() {
        let x = LineStyle.tileCenterX(
            visualIndex: 1,
            tileCount: 3,
            tileSize: 10,
            spacing: 0,
            screenWidth: 100
        )
        // tiles occupy 30pt starting at 35; index 1 center is 35+10+5=50
        XCTAssertEqual(x, 50, accuracy: 0.01)
    }
}

final class WallpaperSamplerTests: XCTestCase {
    func testSamplesLeftDarkAndRightLight() throws {
        let image = try XCTUnwrap(makeSplitImage(width: 100, height: 40))
        let screen = CGSize(width: 100, height: 40)
        let left = WallpaperSampler.meanLuminance(
            of: image,
            screenSize: screen,
            sampleInScreen: CGRect(x: 5, y: 0, width: 20, height: 20)
        )
        let right = WallpaperSampler.meanLuminance(
            of: image,
            screenSize: screen,
            sampleInScreen: CGRect(x: 75, y: 0, width: 20, height: 20)
        )
        XCTAssertNotNil(left)
        XCTAssertNotNil(right)
        XCTAssertLessThan(left ?? 1, 0.08)
        XCTAssertGreaterThan(right ?? 0, 0.90)
    }

    func testAspectFillCentersAWideImage() {
        let frame = WallpaperSampler.aspectFillFrame(
            imageSize: CGSize(width: 200, height: 50),
            canvas: CGSize(width: 100, height: 50)
        )
        XCTAssertEqual(frame.origin.x, -50, accuracy: 0.01)
        XCTAssertEqual(frame.width, 200, accuracy: 0.01)
        XCTAssertEqual(frame.height, 50, accuracy: 0.01)
    }
}

final class DividerIconTests: XCTestCase {
    func testHairlinePNGIsPNG() throws {
        let data = try DividerManager.hairlinePNG(pixelSize: 128)
        XCTAssertGreaterThan(data.count, 32)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testInstallHelperReplacesStaleBrandIconWithHairline() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("chromadock-helper-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let exe = dir.appendingPathComponent("dummy-exe")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let stale = dir.appendingPathComponent("Line 1.app/Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: stale.appendingPathComponent("AppIcon.icns"))

        let app = try DividerManager.installHelper(index: 1, executable: exe, into: dir)
        let resources = app.appendingPathComponent("Contents/Resources")
        XCTAssertFalse(fm.fileExists(atPath: resources.appendingPathComponent("AppIcon.icns").path))
        XCTAssertFalse(fm.fileExists(atPath: resources.appendingPathComponent("DividerLine.icns").path))
        XCTAssertFalse(fm.fileExists(atPath: resources.appendingPathComponent("Hairline.icns").path))
        XCTAssertTrue(fm.fileExists(atPath: resources.appendingPathComponent("Line.icns").path))

        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        let obj = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil)
        let info = try XCTUnwrap(obj as? [String: Any])
        XCTAssertEqual(info["CFBundleIconFile"] as? String, "Line")
        XCTAssertNil(info["LSUIElement"])
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "llc.nextcitizen.ChromaDock.line.1")
    }

    func testMainAppInfoPlistHidesDockIcon() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plist)
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let info = try XCTUnwrap(obj as? [String: Any])
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "llc.nextcitizen.ChromaDock")
    }
}

final class WallpaperPathTests: XCTestCase {
    func testWallpaperStoreIndexLivesInApplicationSupport() {
        let path = Paths.wallpaperStoreIndex.path
        XCTAssertTrue(path.contains("/Application Support/com.apple.wallpaper/Store/Index.plist"))
    }
}

final class LegacyDividerCleanupTests: XCTestCase {
    func testLegacyArtifactPaths() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        XCTAssertEqual(DividerManager.linesLaunchAgentLabel, "llc.nextcitizen.ChromaDock.lines")
        XCTAssertEqual(DividerManager.appLaunchAgentLabel, "llc.nextcitizen.ChromaDock")
        XCTAssertEqual(
            DividerManager.linesLaunchAgentPlist(home: home).path,
            "/Users/example/Library/LaunchAgents/llc.nextcitizen.ChromaDock.lines.plist"
        )
        XCTAssertEqual(
            DividerManager.appLaunchAgentPlist(home: home).path,
            "/Users/example/Library/LaunchAgents/llc.nextcitizen.ChromaDock.plist"
        )
        XCTAssertEqual(
            DividerManager.linesKeepScript(home: home).path,
            "/Users/example/Library/Application Support/ChromaDock/keep-lines.sh"
        )
        XCTAssertEqual(DividerManager.legacyLaunchAgentLabel, "com.nextcz.dock-dividers")
        XCTAssertEqual(
            DividerManager.legacyLaunchAgentPlist(home: home).path,
            "/Users/example/Library/LaunchAgents/com.nextcz.dock-dividers.plist"
        )
        XCTAssertEqual(
            DividerManager.legacyStartScript(home: home).path,
            "/Users/example/Library/Application Support/dock-group-hue/start-dividers.sh"
        )
        XCTAssertEqual(
            DividerManager.legacyApplicationsDir(home: home).path,
            "/Users/example/Applications/Dock Dividers"
        )
        XCTAssertEqual(
            DividerManager.legacySupportDir(home: home).path,
            "/Users/example/Library/Application Support/dock-group-hue"
        )
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

final class ContactInterestTests: XCTestCase {
    func testSubjectAndDefaultBody() {
        XCTAssertEqual(ContactInterest.subject, "ChromaDock Interest")
        XCTAssertFalse(ContactInterest.defaultBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testPageURLIsNextczContactWidget() {
        XCTAssertEqual(ContactInterest.pageURL.host, "nextcz.com")
        XCTAssertEqual(ContactInterest.pageURL.scheme, "https")
        XCTAssertEqual(ContactInterest.pageURL.fragment, ContactInterest.widgetID)
    }

    func testMessagePrependsSubject() {
        XCTAssertEqual(
            ContactInterest.message(body: "Please keep me posted."),
            "ChromaDock Interest\n\nPlease keep me posted."
        )
    }

    func testBlankBodyFallsBackToDefault() {
        XCTAssertEqual(
            ContactInterest.message(body: "  \n"),
            "ChromaDock Interest\n\n\(ContactInterest.defaultBody)"
        )
    }

    func testMessageDoesNotDuplicateSubject() {
        let already = "ChromaDock Interest\n\nEdited note."
        XCTAssertEqual(ContactInterest.message(body: already), already)
        XCTAssertEqual(ContactInterest.message(body: "ChromaDock Interest"), "ChromaDock Interest")
    }

    func testPrefillJavaScriptTargetsLiveFormAndEscapes() {
        let js = ContactInterest.prefillJavaScript(message: "ChromaDock Interest\n\nLine \"quoted\" & <tag>")
        XCTAssertTrue(js.contains("CONTACT_FORM_MESSAGE"))
        XCTAssertTrue(js.contains("CONTACT_FORM_EMAIL"))
        XCTAssertTrue(js.contains("_valueTracker"))
        XCTAssertTrue(js.contains("setInterval"))
        XCTAssertFalse(js.contains("if (fill()) return"))
        XCTAssertTrue(js.contains(ContactInterest.widgetID))
        XCTAssertTrue(js.contains("\\n"))
        XCTAssertTrue(js.contains("\\\"quoted\\\""))
        XCTAssertFalse(js.contains("Line \"quoted\""))
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
        luminance: 0,
        hex: "#000000",
        groupID: group,
        inDock: inDock
    )
}

private func solidRaster(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255, size: Int = 8) -> HueSampler.Raster {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    for i in 0..<(size * size) {
        let o = i * 4
        bytes[o] = r
        bytes[o + 1] = g
        bytes[o + 2] = b
        bytes[o + 3] = a
    }
    return HueSampler.Raster(size: size, bytesPerRow: size * 4, bytes: bytes)
}

private func makeSplitImage(width: Int, height: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let light = x >= width / 2
            let v: UInt8 = light ? 255 : 0
            pixels[i] = v
            pixels[i + 1] = v
            pixels[i + 2] = v
            pixels[i + 3] = 255
        }
    }
    let data = Data(pixels) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
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
