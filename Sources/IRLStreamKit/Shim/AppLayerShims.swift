// Shims for symbols the vendored engine expects from Moblin's app layer.
// Each block notes its upstream origin so sync diffs can detect drift.
// Origin repo: https://github.com/eerimoq/moblin

import CoreMedia
import Foundation
#if !targetEnvironment(macCatalyst)
import WiFiAware

// Origin: Moblin/View/Settings/WiFiAware/WiFiAwareSettingsView.swift
// Service name is declared in the consuming app's Info.plist (upstream: Moblin's).
private let wiFiAwareServiceName = "_moblin._tcp"

@available(iOS 26, *)
func wiFiAwarePublishableService() -> WAPublishableService {
    WAPublishableService.allServices[wiFiAwareServiceName]!
}

@available(iOS 26, *)
func wiFiAwareSubscribableService() -> WASubscribableService {
    WASubscribableService.allServices[wiFiAwareServiceName]!
}
#endif

// Origin: Moblin/Various/Utils/Utils.swift
func currentPresentationTimeStamp() -> CMTime {
    CMClockGetTime(CMClockGetHostTimeClock())
}

// Origin: Moblin/Various/Utils/Utils.swift
extension CMTime {
    init(seconds: Double) {
        self = CMTime(seconds: seconds, preferredTimescale: 1000)
    }
}

// Origin: Moblin/Various/Utils/Utils.swift
extension Data {
    static func random(length: Int) -> Data {
        Data((0 ..< length).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
    }
}

// Origin: Moblin/Various/Utils/Utils.swift
extension String {
    init(cArray: [CChar]) {
        self = cArray.withUnsafeBufferPointer {
            String(cString: $0.baseAddress!)
        }
    }
}

// Origin: Moblin/Various/Utils/Utils.swift
extension [String] {
    func withCPointers<T>(_ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>) -> T) -> T {
        let pointersArray = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: count)
        defer {
            pointersArray.deallocate()
        }
        func addAt(index: Int) -> T {
            if index == count {
                return body(pointersArray)
            }
            return self[index].withCString { cstr in
                pointersArray[index] = cstr
                return addAt(index: index + 1)
            }
        }
        return addAt(index: 0)
    }
}

// Origin: Moblin/Various/Utils/FileSystemUtils.swift
extension URL {
    var attributes: [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            logger.info("file-system: Failed to get attributes for file \(self)")
        }
        return nil
    }

    var fileSize: UInt64 {
        attributes?[.size] as? UInt64 ?? UInt64(0)
    }

    func remove() {
        try? FileManager.default.removeItem(at: self)
    }

    func exists() -> Bool {
        FileManager.default.fileExists(atPath: path())
    }
}

// Origin: Moblin/Various/Model/ModelCamera.swift
typealias CameraId = String

// Origin: Moblin/Various/Utils/UiUtils.swift
func isMac() -> Bool {
    ProcessInfo().isMacCatalystApp
}

// Origin: Moblin/VideoEffects/Dewarp360/Dewarp360Filter.swift
let graphicsEpsilon = 0.00001

// Origin: Moblin/Various/Utils/Utils.swift
extension CGSize {
    func minimum() -> CGFloat {
        min(height, width)
    }

    func maximum() -> CGFloat {
        max(height, width)
    }
}

// Origin: Moblin/Various/Utils/Utils.swift
struct TimeStampRebaser {
    private var firstPresentationTimeStamp: Double = .nan

    mutating func rebase(_ presentationTimeStamp: Double) -> Double? {
        if firstPresentationTimeStamp.isNaN {
            firstPresentationTimeStamp = presentationTimeStamp
        }
        let presentationTimeStamp = presentationTimeStamp - firstPresentationTimeStamp
        guard presentationTimeStamp > 0 else {
            return nil
        }
        return presentationTimeStamp
    }
}

// Origin: Moblin/Various/Utils/Utils.swift
protocol Named {
    var name: String { get }
}

// Origin: Moblin/Various/BondingStatisticsFormatter.swift (struct only; the
// formatter itself depends on app-layer settings/UI types and is not vendored)
struct BondingConnection {
    let name: String
    var usage: UInt64
    var rtt: Int?
}

// Origin: Moblin/Various/Utils/Utils.swift
extension UnsafeMutableRawBufferPointer {
    func writeUInt16(_ value: UInt16, offset: Int) {
        self[offset + 0] = UInt8((value >> 8) & 0xFF)
        self[offset + 1] = UInt8(value & 0xFF)
    }

    func writeUInt32(_ value: UInt32, offset: Int) {
        self[offset + 0] = UInt8(value >> 24)
        self[offset + 1] = UInt8((value >> 16) & 0xFF)
        self[offset + 2] = UInt8((value >> 8) & 0xFF)
        self[offset + 3] = UInt8(value & 0xFF)
    }
}

// Origin: Moblin/Various/Utils/Utils.swift
extension UnsafeRawBufferPointer {
    func readUInt16(offset: Int) -> UInt16 {
        var value: UInt16 = 0
        value |= UInt16(self[offset + 0]) << 8
        value |= UInt16(self[offset + 1]) << 0
        return value
    }

    func readUInt32(offset: Int) -> UInt32 {
        var value: UInt32 = 0
        value |= UInt32(self[offset + 0]) << 24
        value |= UInt32(self[offset + 1]) << 16
        value |= UInt32(self[offset + 2]) << 8
        value |= UInt32(self[offset + 3]) << 0
        return value
    }
}
