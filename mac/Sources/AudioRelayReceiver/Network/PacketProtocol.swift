import Foundation

enum ConfigCommand: UInt8 {
    case streamReset = 0x01
}

// MARK: - Packet Serialization

enum PacketProtocol {

    /// Length-prefix size (UInt32, 4 bytes).
    static let lengthPrefixSize = 4

    // MARK: Serialize

    /// Serializes an `AudioPacket` into wire format with a 4-byte length prefix.
    ///
    /// Wire layout:
    /// ```
    /// [totalLength: 4B] [packetType: 1B] [sequenceNumber: 4B] [timestamp: 8B] [payloadLength: 2B] [payload: NB]
    /// ```
    static func serialize(packet: AudioPacket) -> Data {
        let packetDataSize = AudioPacket.headerSize + packet.payload.count
        var data = Data(capacity: lengthPrefixSize + packetDataSize)

        // Length prefix (total bytes after this field).
        data.appendUInt32(UInt32(packetDataSize))

        // Packet header.
        data.append(packet.packetType.rawValue)
        data.appendUInt32(packet.sequenceNumber)
        data.appendUInt64(packet.timestamp)
        data.appendUInt16(UInt16(packet.payload.count))

        // Payload.
        data.append(packet.payload)
        return data
    }

    // MARK: Deserialize

    /// Attempts to deserialize a single packet from raw packet data (without length prefix).
    /// Returns nil if the data is malformed or too short.
    static func deserialize(packetData: Data) -> AudioPacket? {
        guard packetData.count >= AudioPacket.headerSize else { return nil }

        var offset = packetData.startIndex

        // Packet type.
        guard let packetType = PacketType(rawValue: packetData[offset]) else { return nil }
        offset += 1

        // Sequence number.
        let sequenceNumber = packetData.readUInt32(at: &offset)

        // Timestamp.
        let timestamp = packetData.readUInt64(at: &offset)

        // Payload length.
        let payloadLength = Int(packetData.readUInt16(at: &offset))

        // Payload.
        guard packetData.count - (offset - packetData.startIndex) >= payloadLength else { return nil }
        let payload = packetData[offset..<offset + payloadLength]

        return AudioPacket(
            packetType: packetType,
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            payload: Data(payload)
        )
    }

    // MARK: Helpers

    /// Creates a handshake response packet (type 0x02) with an empty payload.
    /// The sender can include version info in the payload if needed.
    static func createHandshakeResponse(sequenceNumber: UInt32 = 0) -> AudioPacket {
        AudioPacket(
            packetType: .handshake,
            sequenceNumber: sequenceNumber,
            timestamp: currentTimestamp(),
            payload: Data()
        )
    }

    /// Creates a heartbeat response packet (type 0x03) with an empty payload.
    static func createHeartbeatResponse(sequenceNumber: UInt32 = 0) -> AudioPacket {
        AudioPacket(
            packetType: .heartbeat,
            sequenceNumber: sequenceNumber,
            timestamp: currentTimestamp(),
            payload: Data()
        )
    }

    /// Returns the current time as microseconds since epoch.
    private static func currentTimestamp() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000_000)
    }
}

// MARK: - Packet Framer

/// Accumulates raw TCP stream data and extracts complete length-prefixed packets.
///
/// TCP is a stream protocol, so a single `recv` call may contain partial packets,
/// exactly one packet, or multiple packets. This class handles all three cases.
final class PacketFramer {

    private var buffer = Data()

    /// Appends newly received TCP data to the internal buffer.
    func append(data: Data) {
        buffer.append(data)
    }

    /// Attempts to extract the next complete `AudioPacket` from the buffer.
    /// Returns `nil` if there is not yet enough data for a full packet.
    /// Call repeatedly until it returns `nil` to drain all available packets.
    func nextPacket() -> AudioPacket? {
        let prefixSize = PacketProtocol.lengthPrefixSize

        // Need at least the length prefix to know the packet size.
        guard buffer.count >= prefixSize else { return nil }

        // Read the total packet-data length (does not include the prefix itself).
        var offset = buffer.startIndex
        let totalLength = Int(buffer.readUInt32(at: &offset))

        // Wait until the full packet data is available.
        guard buffer.count >= prefixSize + totalLength else { return nil }

        // Slice out the packet data (after the 4-byte prefix).
        let packetData = buffer[buffer.startIndex + prefixSize ..< buffer.startIndex + prefixSize + totalLength]

        // Attempt deserialization.
        guard let packet = PacketProtocol.deserialize(packetData: Data(packetData)) else {
            // Malformed packet: skip past it to avoid getting stuck.
            buffer.removeSubrange(buffer.startIndex..<buffer.startIndex + prefixSize + totalLength)
            return nil
        }

        // Consume the processed bytes from the buffer.
        buffer.removeSubrange(buffer.startIndex..<buffer.startIndex + prefixSize + totalLength)
        return packet
    }

    /// Number of bytes currently buffered.
    var bufferedByteCount: Int {
        buffer.count
    }

    /// Discards all buffered data.
    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}

extension AudioPacket {

    var configCommand: ConfigCommand? {
        guard packetType == .config, let rawValue = payload.first else { return nil }
        return ConfigCommand(rawValue: rawValue)
    }
}
