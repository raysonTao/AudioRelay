import Foundation

// MARK: - Connection State

/// Holds connection lifecycle state and audio pipeline metrics.
/// Used by ContentViewModel (ObservableObject) which triggers SwiftUI updates.
final class ConnectionState {

    // MARK: State Enum

    enum State: String, Sendable {
        case disconnected
        case discovering
        case connecting
        case connected
        case reconnecting
    }

    // MARK: Properties

    /// Current connection lifecycle state.
    var currentState: State = .disconnected

    /// Display name of the connected server.
    var serverName: String?

    /// IP address (or host) of the connected server.
    var serverAddress: String?

    /// Jitter buffer fill level, 0.0 (empty) to 1.0 (full).
    var bufferLevel: Double = 0.0

    /// Current audio output level, 0.0 (silence) to 1.0 (peak).
    var audioLevel: Double = 0.0

    /// Estimated one-way latency in milliseconds.
    var latencyMs: Double = 0.0

    /// Total number of packets successfully received.
    var packetsReceived: UInt64 = 0

    /// Total number of packets detected as lost (sequence gaps).
    var packetsLost: UInt64 = 0

    // MARK: Computed

    /// Packet loss ratio, 0.0 to 1.0.
    var lossRate: Double {
        let total = Double(packetsReceived + packetsLost)
        guard total > 0 else { return 0 }
        return Double(packetsLost) / total
    }

    /// Whether the connection is in an active (non-idle) state.
    var isActive: Bool {
        switch currentState {
        case .connected, .reconnecting:
            return true
        case .disconnected, .discovering, .connecting:
            return false
        }
    }

    // MARK: Actions

    /// Resets all statistics to their default values.
    func reset() {
        currentState = .disconnected
        serverName = nil
        serverAddress = nil
        bufferLevel = 0.0
        audioLevel = 0.0
        latencyMs = 0.0
        packetsReceived = 0
        packetsLost = 0
    }

    /// Records a successful packet reception and updates latency.
    func recordPacketReceived(latency: Double) {
        packetsReceived += 1
        let alpha = 0.1
        latencyMs = latencyMs == 0 ? latency : latencyMs * (1 - alpha) + latency * alpha
    }

    /// Records detected lost packets (sequence number gaps).
    func recordPacketsLost(count: UInt64) {
        packetsLost += count
    }
}
