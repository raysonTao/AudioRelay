import Foundation

// MARK: - Packet Type

enum PacketType: UInt8 {
    case audio     = 0x01
    case handshake = 0x02
    case heartbeat = 0x03
    case config    = 0x04
}

// MARK: - Audio Packet

struct AudioPacket {
    let packetType: PacketType
    let sequenceNumber: UInt32
    let timestamp: UInt64
    let payload: Data

    /// Total size of the packet header (type + sequence + timestamp + payloadLength).
    static let headerSize = 1 + 4 + 8 + 2  // 15 bytes
}

// MARK: - Handshake Payload

extension AudioPacket {

    struct HandshakePayload {
        let protocolVersion: UInt32
        let sampleRate: UInt32
        let channels: UInt8
        let bitrate: UInt32
        let frameDurationMs: UInt8

        /// Expected byte size of a serialized handshake payload.
        static let size = 4 + 4 + 1 + 4 + 1  // 14 bytes

        // MARK: Deserialization

        init?(data: Data) {
            guard data.count >= HandshakePayload.size else { return nil }

            var offset = data.startIndex
            protocolVersion = data.readUInt32(at: &offset)
            sampleRate = data.readUInt32(at: &offset)
            channels = data[offset]; offset += 1
            bitrate = data.readUInt32(at: &offset)
            frameDurationMs = data[offset]; offset += 1
        }

        init(protocolVersion: UInt32, sampleRate: UInt32, channels: UInt8, bitrate: UInt32, frameDurationMs: UInt8) {
            self.protocolVersion = protocolVersion
            self.sampleRate = sampleRate
            self.channels = channels
            self.bitrate = bitrate
            self.frameDurationMs = frameDurationMs
        }

        // MARK: Serialization

        func serialize() -> Data {
            var data = Data(capacity: HandshakePayload.size)
            data.appendUInt32(protocolVersion)
            data.appendUInt32(sampleRate)
            data.append(channels)
            data.appendUInt32(bitrate)
            data.append(frameDurationMs)
            return data
        }
    }

    /// Convenience accessor that parses the payload as a handshake.
    /// Returns nil if the packet type is not `.handshake` or the payload is malformed.
    var handshakePayload: HandshakePayload? {
        guard packetType == .handshake else { return nil }
        return HandshakePayload(data: payload)
    }
}

// MARK: - Data Helpers (Big-Endian)

extension Data {

    /// Reads a big-endian UInt32 starting at `offset` and advances the offset by 4.
    func readUInt32(at offset: inout Data.Index) -> UInt32 {
        let value = UInt32(self[offset]) << 24
            | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8
            | UInt32(self[offset + 3])
        offset += 4
        return value
    }

    /// Reads a big-endian UInt16 starting at `offset` and advances the offset by 2.
    func readUInt16(at offset: inout Data.Index) -> UInt16 {
        let value = UInt16(self[offset]) << 8
            | UInt16(self[offset + 1])
        offset += 2
        return value
    }

    /// Reads a big-endian UInt64 starting at `offset` and advances the offset by 8.
    func readUInt64(at offset: inout Data.Index) -> UInt64 {
        let value = UInt64(self[offset]) << 56
            | UInt64(self[offset + 1]) << 48
            | UInt64(self[offset + 2]) << 40
            | UInt64(self[offset + 3]) << 32
            | UInt64(self[offset + 4]) << 24
            | UInt64(self[offset + 5]) << 16
            | UInt64(self[offset + 6]) << 8
            | UInt64(self[offset + 7])
        offset += 8
        return value
    }

    /// Appends a UInt32 in big-endian byte order.
    mutating func appendUInt32(_ value: UInt32) {
        var big = value.bigEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &big) { Array($0) })
    }

    /// Appends a UInt16 in big-endian byte order.
    mutating func appendUInt16(_ value: UInt16) {
        var big = value.bigEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &big) { Array($0) })
    }

    /// Appends a UInt64 in big-endian byte order.
    mutating func appendUInt64(_ value: UInt64) {
        var big = value.bigEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &big) { Array($0) })
    }
}
