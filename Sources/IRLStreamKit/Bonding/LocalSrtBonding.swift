import Foundation
import Network

/// The surface `Media` drives on its bonding transport. Extracting it as a
/// protocol lets `Media` hold either the vendored `SrtlaClient` (default) or the
/// IRLTP-backed ``IRLTPBondingAdapter`` interchangeably.
///
/// The empty conformance below also compile-checks that this protocol exactly
/// matches `SrtlaClient`'s method surface — if Moblin's API drifts on a sync,
/// this stops building, which is the signal to update the adapter.
protocol LocalSrtBonding: AnyObject {
    func start(uri: String, timeout: Double, dnsLookupStrategy: SettingsDnsLookupStrategy)
    func stop()
    func handleLocalPacket(packet: Data)
    func connectionStatistics() -> [BondingConnection]
    func logStatistics()
    func getTotalByteCount() -> Int64
    func setConnectionPriorities(connectionPriorities: SettingsStreamSrtConnectionPriorities)
    func setNetworkInterfaceNames(networkInterfaceNames: [SettingsNetworkInterfaceName])
    func addMoblink(endpoint: NWEndpoint, id: UUID, name: String)
    func removeMoblink(endpoint: NWEndpoint)
}

extension SrtlaClient: LocalSrtBonding {}

/// Opt-in side channel for bonding transports that inject inbound SRT directly
/// into libsrt's socket (the IRLTP adapter) rather than via a loopback listener
/// that libsrt connects to. Media hands over libsrt's bound local UDP port right
/// after opening the official SRT engine; transports that don't need it (the
/// vendored `SrtlaClient`) simply don't conform, so the `LocalSrtBonding` surface
/// stays byte-identical to upstream.
protocol LocalSrtPortReceiving: AnyObject {
    func setLocalSrtPort(_ port: UInt16)
}
