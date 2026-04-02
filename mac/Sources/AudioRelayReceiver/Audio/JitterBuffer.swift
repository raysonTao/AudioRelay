import Foundation

/// Adaptive jitter buffer that reorders incoming audio packets and absorbs
/// network timing variations.
///
/// Packets are stored in a dictionary keyed by sequence number. The buffer
/// dynamically adjusts its target depth based on an exponential moving
/// average of observed inter-arrival jitter.
///
/// Thread-safe: all public methods are guarded by an internal lock.
final class JitterBuffer {

    // MARK: - Nested types

    /// A single audio packet ready for the jitter buffer.
    struct AudioPacket {
        /// Monotonically increasing sequence number assigned by the sender.
        let sequenceNumber: UInt32
        /// Sender-side timestamp in microseconds (used for jitter estimation).
        let timestamp: UInt64
        /// Opus-encoded audio data.
        let opusData: Data
    }

    // MARK: - Constants

    /// Duration of a single Opus frame in milliseconds.
    private static let frameDurationMs: Double = 20.0

    /// Minimum target buffer depth in milliseconds.
    private static let minDepthMs: Double = 100.0
    /// Maximum target buffer depth in milliseconds.
    private static let maxDepthMs: Double = 300.0
    /// Initial target buffer depth in milliseconds.
    private static let defaultTargetDepthMs: Double = 150.0

    /// EMA smoothing factor for jitter estimation. Smaller values react more
    /// slowly but produce a more stable estimate.
    private static let jitterAlpha: Double = 0.01

    /// Packets older than this many sequence numbers behind `nextExpectedSequence`
    /// are dropped on insertion.
    private static let lateDropThreshold: UInt32 = 50

    /// Maximum number of packets the buffer will hold. Packets beyond this
    /// count are discarded to prevent unbounded memory growth.
    private static let maxBufferCapacity: Int = 200

    // MARK: - State

    private let lock = NSLock()

    /// Packets waiting to be consumed, keyed by sequence number.
    private var packets: [UInt32: AudioPacket] = [:]

    /// The sequence number we expect to pull next.
    private(set) var nextExpectedSequence: UInt32 = 0
    private var sequenceInitialized = false

    /// Adaptive target depth in milliseconds, adjusted by jitter estimate.
    private var targetDepthMs: Double = defaultTargetDepthMs

    /// Exponential moving average of inter-arrival jitter in milliseconds.
    private var estimatedJitterMs: Double = 0

    /// Arrival time of the previous packet (monotonic, in seconds).
    private var lastArrivalTime: CFAbsoluteTime = 0
    /// Sender timestamp of the previous packet (microseconds).
    private var lastPacketTimestamp: UInt64 = 0
    /// Whether we have received at least one packet (needed for jitter calc).
    private var hasPreviousArrival = false

    // MARK: - Public interface

    /// Inserts a packet into the buffer.
    ///
    /// - Packets that are too old (behind `nextExpectedSequence` by more than
    ///   `lateDropThreshold`) are silently dropped.
    /// - Duplicate sequence numbers overwrite the previous entry.
    /// - The jitter estimate and target depth are updated on each insertion.
    func push(packet: AudioPacket) {
        lock.lock()
        defer { lock.unlock() }

        // First packet bootstraps the expected sequence.
        if !sequenceInitialized {
            nextExpectedSequence = packet.sequenceNumber
            sequenceInitialized = true
        }

        // Drop packets that arrived too late.
        if packet.sequenceNumber &+ Self.lateDropThreshold < nextExpectedSequence {
            return
        }

        // Prevent unbounded growth.
        if packets.count >= Self.maxBufferCapacity {
            if let oldest = packets.keys.min() {
                packets.removeValue(forKey: oldest)
            }
        }

        packets[packet.sequenceNumber] = packet

        // --- Jitter estimation ---
        let now = CFAbsoluteTimeGetCurrent()
        if hasPreviousArrival {
            let arrivalDeltaMs = (now - lastArrivalTime) * 1000.0
            // Timestamps are in microseconds, convert to ms.
            let sendDeltaMs = Double(packet.timestamp &- lastPacketTimestamp) / 1000.0
            let jitterSample = abs(arrivalDeltaMs - sendDeltaMs)

            // EMA update.
            estimatedJitterMs += Self.jitterAlpha * (jitterSample - estimatedJitterMs)

            // Adapt target depth: 3 * estimated jitter, clamped to [min, max].
            let desiredDepth = max(Self.minDepthMs, 3.0 * estimatedJitterMs)
            targetDepthMs = min(max(desiredDepth, Self.minDepthMs), Self.maxDepthMs)
        }
        lastArrivalTime = now
        lastPacketTimestamp = packet.timestamp
        hasPreviousArrival = true
    }

    /// Pulls the next expected packet from the buffer.
    ///
    /// Includes clock drift compensation:
    /// - Mild overflow (> target * 1.5 + 3): skip 1 extra packet per pull.
    /// - Severe overflow (> target * 3): jump to recent packets.
    ///
    /// - Returns: The packet at `nextExpectedSequence`, or `nil` if it has not
    ///   arrived yet (the caller should perform PLC in that case).
    func pull() -> AudioPacket? {
        lock.lock()
        defer { lock.unlock() }

        guard sequenceInitialized else { return nil }

        let targetFrames = Int(targetDepthMs / Self.frameDurationMs)

        // --- Severe overflow: jump to recent packets ---
        if packets.count > max(targetFrames * 3, 30) {
            if let maxSeq = packets.keys.max() {
                let jumpTo = maxSeq &- UInt32(targetFrames)
                let keysToRemove = packets.keys.filter { $0 < jumpTo }
                for key in keysToRemove {
                    packets.removeValue(forKey: key)
                }
                nextExpectedSequence = jumpTo
            }
        }
        // --- Mild overflow: skip 1 extra per pull ---
        else if packets.count > targetFrames * 3 / 2 + 3 {
            packets.removeValue(forKey: nextExpectedSequence)
            nextExpectedSequence &+= 1
        }

        let seq = nextExpectedSequence
        nextExpectedSequence &+= 1

        if let packet = packets.removeValue(forKey: seq) {
            return packet
        }
        return nil
    }

    /// Fractional fill level of the buffer relative to its current target depth.
    /// Values range from 0.0 (empty) to 1.0+ (at or above target).
    var bufferLevel: Double {
        lock.lock()
        defer { lock.unlock() }

        let targetFrames = targetDepthMs / Self.frameDurationMs
        guard targetFrames > 0 else { return 0 }
        return Double(packets.count) / targetFrames
    }

    /// Current buffer depth in milliseconds.
    var currentDepthMs: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(packets.count) * Self.frameDurationMs
    }

    /// Current adaptive target depth in milliseconds.
    var currentTargetDepthMs: Double {
        lock.lock()
        defer { lock.unlock() }
        return targetDepthMs
    }

    /// Number of packets currently in the buffer.
    var packetCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return packets.count
    }

    /// Removes all buffered packets and resets sequencing state.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        packets.removeAll()
        sequenceInitialized = false
        nextExpectedSequence = 0
        hasPreviousArrival = false
        estimatedJitterMs = 0
        targetDepthMs = Self.defaultTargetDepthMs
    }
}
