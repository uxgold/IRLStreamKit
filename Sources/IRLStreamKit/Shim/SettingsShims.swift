// Settings types the vendored engine references, extracted verbatim from
// Moblin's app-layer settings files. Kept byte-identical to upstream blocks
// so sync diffs can detect drift.
// Origin repo: https://github.com/eerimoq/moblin

import Foundation

// Origin: Moblin/Various/Settings/Settings.swift
let defaultSrtLatency: Int32 = 3000

// MARK: - Origin: Moblin/Various/Settings/SettingsStream.swift

enum SettingsStreamCodec: String, Codable, CaseIterable {
    case h265hevc = "H.265/HEVC"
    case h264avc = "H.264/AVC"

    init(from decoder: any Decoder) throws {
        self = try SettingsStreamCodec(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ??
            .h264avc
    }

    func shortString() -> String {
        switch self {
        case .h265hevc:
            "H.265"
        case .h264avc:
            "H.264"
        }
    }
}

enum SettingsStreamSrtImplementation: String, Codable, CaseIterable {
    case moblin = "Moblin"
    case official = "Official"

    func toString() -> String {
        switch self {
        case .moblin:
            String(localized: "Moblin")
        case .official:
            String(localized: "Official")
        }
    }
}

enum SettingsStreamAudioCodec: String, Codable, CaseIterable {
    case aac = "AAC"
    case opus = "OPUS"

    func toEncoder() -> AudioEncoderSettings.Format {
        switch self {
        case .aac:
            .aac
        case .opus:
            .opus
        }
    }

    func toString() -> String {
        switch self {
        case .aac:
            "AAC"
        case .opus:
            "Opus"
        }
    }
}

class SettingsStreamSrtConnectionPriority: Codable, Identifiable {
    var id: UUID = .init()
    var name: String
    var priority: Int = 1
    var enabled: Bool = true
    var relayId: UUID?

    init(name: String) {
        self.name = name
    }

    enum CodingKeys: CodingKey {
        case id
        case name
        case priority
        case enabled
        case relayId
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(.id, id)
        try container.encode(.name, name)
        try container.encode(.priority, priority)
        try container.encode(.enabled, enabled)
        try container.encode(.relayId, relayId)
    }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decode(.id, UUID.self, .init())
        name = container.decode(.name, String.self, "")
        priority = container.decode(.priority, Int.self, 1)
        enabled = container.decode(.enabled, Bool.self, true)
        relayId = container.decode(.relayId, UUID?.self, nil)
    }

    func clone() -> SettingsStreamSrtConnectionPriority {
        let new = SettingsStreamSrtConnectionPriority(name: name)
        new.priority = priority
        new.enabled = enabled
        new.relayId = relayId
        return new
    }
}

class SettingsStreamSrtConnectionPriorities: Codable, @unchecked Sendable {
    var enabled: Bool = false
    var priorities: [SettingsStreamSrtConnectionPriority] = [
        SettingsStreamSrtConnectionPriority(name: "Cellular"),
        SettingsStreamSrtConnectionPriority(name: "WiFi"),
    ]

    func clone() -> SettingsStreamSrtConnectionPriorities {
        let new = SettingsStreamSrtConnectionPriorities()
        new.enabled = enabled
        new.priorities.removeAll()
        for priority in priorities {
            new.priorities.append(priority.clone())
        }
        return new
    }
}

struct SettingsHttpHeader: Codable {
    var name: String = ""
    var value: String = ""
}

// MARK: - Origin: Moblin/Various/Settings/Settings.swift

enum SettingsDnsLookupStrategy: String, Codable, CaseIterable {
    case system = "System"
    case ipv4 = "IPv4"
    case ipv6 = "IPv6"
    case ipv4AndIpv6 = "IPv4 and IPv6"
}

class SettingsNetworkInterfaceName: Codable, Identifiable, @unchecked Sendable {
    var id: UUID = .init()
    var interfaceName: String = ""
    var name: String = ""
}

// MARK: - Origin: Moblin/Various/Settings/SettingsScene.swift

enum SettingsAlignment: String, Codable, CaseIterable {
    case topLeft = "TopLeft"
    case topRight = "TopRight"
    case bottomLeft = "BottomLeft"
    case bottomRight = "BottomRight"
    case topCenter = "TopCenter"
    case bottomCenter = "BottomCenter"
    case leftCenter = "LeftCenter"
    case rightCenter = "RightCenter"
    case center = "Center"

    func isLeft() -> Bool {
        self == .topLeft || self == .bottomLeft || self == .leftCenter
    }

    func isHorizontalCenter() -> Bool {
        self == .topCenter || self == .bottomCenter || self == .center
    }

    func isVerticalCenter() -> Bool {
        self == .leftCenter || self == .rightCenter || self == .center
    }

    func isTop() -> Bool {
        self == .topLeft || self == .topRight || self == .topCenter
    }

    func mirrorPositionHorizontally() -> Bool {
        self == .topRight || self == .bottomRight || self == .rightCenter
    }

    func mirrorPositionVertically() -> Bool {
        self == .bottomLeft || self == .bottomRight || self == .bottomCenter
    }
}

enum SettingsSceneCameraPosition: String, Codable, CaseIterable {
    case back = "Back"
    case front = "Front"
    case rtmp = "RTMP"
    case external = "External"
    case srtla = "SRT(LA)"
    case srtClient = "SRT client"
    case rist = "RIST"
    case rtsp = "RTSP"
    case whip = "WHIP"
    case whep = "WHEP"
    case mediaPlayer = "Media player"
    case screenCapture = "Screen capture"
    case backTripleLowEnergy = "Back triple"
    case backDualLowEnergy = "Back dual"
    case backWideDualLowEnergy = "Back wide dual"
    case none = "None"

    init(from decoder: any Decoder) throws {
        self = try SettingsSceneCameraPosition(rawValue: decoder.singleValueContainer()
            .decode(RawValue.self)) ?? .back
    }

    func isBuiltin() -> Bool {
        builtinCameraPositions.contains(self)
    }
}

private let builtinCameraPositions: [SettingsSceneCameraPosition] = [
    .back,
    .front,
    .backTripleLowEnergy,
    .backDualLowEnergy,
    .backWideDualLowEnergy,
]

struct SettingsWidgetLayout: Equatable {
    var x: Double = 0.0
    var xString: String = "0.0"
    var y: Double = 0.0
    var yString: String = "0.0"
    var size: Double = 100.0
    var sizeString: String = "100.0"
    var alignment: SettingsAlignment = .topLeft
    var positioningLock: Bool = false

    mutating func updateXString() {
        xString = String(x)
    }

    mutating func updateYString() {
        yString = String(y)
    }

    mutating func updateSizeString() {
        sizeString = String(size)
    }

    func extent() -> CGRect {
        .init(x: x, y: y, width: size, height: size)
    }
}

class SettingsSceneWidget: Codable, Identifiable, Equatable, ObservableObject, @unchecked Sendable {
    static func == (lhs: SettingsSceneWidget, rhs: SettingsSceneWidget) -> Bool {
        lhs.id == rhs.id
    }

    var id: UUID = .init()
    @Published var widgetId: UUID
    @Published var layout: SettingsWidgetLayout = .init()
    // To be removed.
    @Published var width2: Double = 100.0
    // To be removed.
    @Published var height2: Double = 100.0
    var migrated: Bool = true
    var migrated2: Bool = true

    init(widgetId: UUID) {
        self.widgetId = widgetId
    }

    enum CodingKeys: CodingKey {
        case widgetId
        case id
        case x
        case y
        case width
        case height
        case size
        case alignment
        case positioningLock
        case migrated
        case migrated2
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(.widgetId, widgetId)
        try container.encode(.id, id)
        try container.encode(.x, layout.x)
        try container.encode(.y, layout.y)
        try container.encode(.width, width2)
        try container.encode(.height, height2)
        try container.encode(.size, layout.size)
        try container.encode(.alignment, layout.alignment)
        try container.encode(.positioningLock, layout.positioningLock)
        try container.encode(.migrated, migrated)
        try container.encode(.migrated2, migrated2)
    }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgetId = container.decode(.widgetId, UUID.self, .init())
        id = container.decode(.id, UUID.self, .init())
        layout.x = container.decode(.x, Double.self, 0.0)
        layout.updateXString()
        layout.y = container.decode(.y, Double.self, 0.0)
        layout.updateYString()
        width2 = container.decode(.width, Double.self, 100.0)
        height2 = container.decode(.height, Double.self, 100.0)
        if let size = container.decode(.size, Double?.self, nil) {
            layout.size = size
        } else {
            layout.size = container.decode(.size, Double.self, min(width2, height2))
        }
        layout.updateSizeString()
        layout.alignment = container.decode(.alignment, SettingsAlignment.self, .topLeft)
        layout.positioningLock = container.decode(.positioningLock, Bool.self, false)
        migrated = container.decode(.migrated, Bool.self, false)
        migrated2 = container.decode(.migrated2, Bool.self, false)
    }

    func clone() -> SettingsSceneWidget {
        let new = SettingsSceneWidget(widgetId: widgetId)
        new.layout = layout
        new.migrated = migrated
        new.migrated2 = migrated2
        return new
    }
}
