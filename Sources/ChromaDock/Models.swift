import AppKit
import Foundation

struct DockApp: Identifiable, Hashable, Codable, Sendable {
    var id: String { bundleIdentifier }
    var label: String
    var bundleIdentifier: String
    var path: String
    var hue: Double
    var saturation: Double
    var value: Double
    var colorful: Bool
    var luminance: Double
    var hex: String
    var groupID: String
    var inDock: Bool

    var hueDegrees: Double { hue * 360 }
}

struct DockGroup: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var sortByHue: Bool
}

struct AppSettings: Codable, Sendable {
    var groups: [DockGroup]
    var assignments: [String: String] // bundle id -> group id
    var sortByHue: Bool
    var insertDividers: Bool
    var keepDividersRunning: Bool
    var openAtLogin: Bool
    var ungroupedID: String
    var dividerStyle: DividerStyle
    /// Group each docked app sat in at the last Scan, keyed by bundle id.
    /// Used so Apply can tell a live Dock drag from an in-app group pick.
    var dockSnapshot: [String: String]

    static let ungroupedID = "other"

    enum CodingKeys: String, CodingKey {
        case groups, assignments, sortByHue, insertDividers, keepDividersRunning, openAtLogin, ungroupedID, dividerStyle, dockSnapshot
    }

    init(
        groups: [DockGroup],
        assignments: [String: String],
        sortByHue: Bool,
        insertDividers: Bool,
        keepDividersRunning: Bool,
        openAtLogin: Bool,
        ungroupedID: String,
        dividerStyle: DividerStyle = .line,
        dockSnapshot: [String: String] = [:]
    ) {
        self.groups = groups
        self.assignments = assignments
        self.sortByHue = sortByHue
        self.insertDividers = insertDividers
        self.keepDividersRunning = keepDividersRunning
        self.openAtLogin = openAtLogin
        self.ungroupedID = ungroupedID
        self.dividerStyle = dividerStyle
        self.dockSnapshot = dockSnapshot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = try c.decode([DockGroup].self, forKey: .groups)
        assignments = try c.decode([String: String].self, forKey: .assignments)
        sortByHue = try c.decode(Bool.self, forKey: .sortByHue)
        insertDividers = try c.decode(Bool.self, forKey: .insertDividers)
        keepDividersRunning = try c.decode(Bool.self, forKey: .keepDividersRunning)
        openAtLogin = try c.decode(Bool.self, forKey: .openAtLogin)
        ungroupedID = try c.decode(String.self, forKey: .ungroupedID)
        dividerStyle = DividerStyle.fromStored(try c.decodeIfPresent(String.self, forKey: .dividerStyle))
        dockSnapshot = try c.decodeIfPresent([String: String].self, forKey: .dockSnapshot) ?? [:]
    }

    static var `default`: AppSettings {
        AppSettings(
            groups: [
                DockGroup(id: "system", title: "System", sortByHue: true),
                DockGroup(id: "development", title: "Development", sortByHue: true),
                DockGroup(id: "browsers", title: "Browsers", sortByHue: true),
                DockGroup(id: "communication", title: "Communication", sortByHue: true),
                DockGroup(id: "media", title: "Media", sortByHue: true),
                DockGroup(id: "other", title: "Other", sortByHue: true)
            ],
            assignments: [:],
            sortByHue: true,
            insertDividers: true,
            keepDividersRunning: true,
            openAtLogin: false,
            ungroupedID: ungroupedID,
            dividerStyle: .line
        )
    }
}

enum Heuristic {
    static func suggestedGroup(bundle: String, label: String) -> String {
        let b = bundle.lowercased()
        let l = label.lowercased()

        if b.hasPrefix("com.apple.safari")
            || b.contains("chrome")
            || b.contains("firefox")
            || b.contains("edgemac") && !b.contains("edgemac.app.")
            || l == "safari" || l == "google chrome" || l == "microsoft edge" || l == "firefox" {
            return "browsers"
        }

        let commBits = [
            "slack", "teams", "zoom", "whatsapp", "telegram", "discord", "signal",
            "messages", "facetime", "mail", "outlook", "phone", "ichat", "bluebubbles"
        ]
        if commBits.contains(where: { b.contains($0) || l.contains($0) }) {
            return "communication"
        }

        let mediaBits = ["spotify", "music", "photos", "tv", "vlc", "iina", "voicememos", "podcast"]
        if mediaBits.contains(where: { b.contains($0) || l.contains($0) }) {
            return "media"
        }

        let devBits = [
            "vscode", "visual studio code", "xcode", "linear", "github", "iterm",
            "terminal", "warp", "docker", "jetbrains", "sublime", "textmate"
        ]
        if devBits.contains(where: { b.contains($0) || l.contains($0) }) {
            return "development"
        }

        if b.hasPrefix("com.apple.") {
            return "system"
        }
        return "other"
    }
}
