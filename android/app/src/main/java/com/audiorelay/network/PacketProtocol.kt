package com.audiorelay.network

import java.nio.ByteBuffer
import java.nio.ByteOrder

enum class PacketType(val value: Byte) {
    AUDIO(0x01),
    HANDSHAKE(0x02),
    HEARTBEAT(0x03),
    CONFIG(0x04);

    companion object {
        fun fromByte(b: Byte): PacketType =
            entries.firstOrNull { it.value == b }
                ?: throw IllegalArgumentException("Unknown packet type: $b")
    }
}

data class AudioPacket(
    val packetType: PacketType,
    val sequenceNumber: UInt,
    val timestamp: ULong,
    val payload: ByteArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AudioPacket) return false
        return packetType == other.packetType &&
            sequenceNumber == other.sequenceNumber &&
            timestamp == other.timestamp &&
            payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = packetType.hashCode()
        result = 31 * result + sequenceNumber.hashCode()
        result = 31 * result + timestamp.hashCode()
        result = 31 * result + payload.contentHashCode()
        return result
    }
}

data class HandshakePayload(
    val protocolVersion: UInt,
    val sampleRate: UInt,
    val channels: Byte,
    val bitrate: UInt,
    val frameDurationMs: Byte
) {
    fun toByteArray(): ByteArray {
        val buffer = ByteBuffer.allocate(14).order(ByteOrder.BIG_ENDIAN)
        buffer.putInt(protocolVersion.toInt())
        buffer.putInt(sampleRate.toInt())
        buffer.put(channels)
        buffer.putInt(bitrate.toInt())
        buffer.put(frameDurationMs)
        return buffer.array()
    }

    companion object {
        fun fromByteArray(data: ByteArray): HandshakePayload {
            val buffer = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
            return HandshakePayload(
                protocolVersion = buffer.getInt().toUInt(),
                sampleRate = buffer.getInt().toUInt(),
                channels = buffer.get(),
                bitrate = buffer.getInt().toUInt(),
                frameDurationMs = buffer.get()
            )
        }
    }
}

/**
 * Header layout within packet data (after length prefix):
 * Offset  Size  Field
 * 0       1     packetType
 * 1       4     sequenceNumber (uint32)
 * 5       8     timestamp (uint64, microseconds)
 * 13      2     payloadLength (uint16)
 * 15      N     payload
 */
private const val HEADER_SIZE = 15
private const val LENGTH_PREFIX_SIZE = 4

fun serialize(packet: AudioPacket): ByteArray {
    val packetDataSize = HEADER_SIZE + packet.payload.size
    val totalSize = LENGTH_PREFIX_SIZE + packetDataSize

    val buffer = ByteBuffer.allocate(totalSize).order(ByteOrder.BIG_ENDIAN)

    // Length prefix: total length of packet data (excluding the 4-byte prefix itself)
    buffer.putInt(packetDataSize)

    // Packet data
    buffer.put(packet.packetType.value)
    buffer.putInt(packet.sequenceNumber.toInt())
    buffer.putLong(packet.timestamp.toLong())
    buffer.putShort(packet.payload.size.toShort())
    buffer.put(packet.payload)

    return buffer.array()
}

fun deserialize(packetData: ByteArray): AudioPacket {
    val buffer = ByteBuffer.wrap(packetData).order(ByteOrder.BIG_ENDIAN)

    val packetType = PacketType.fromByte(buffer.get())
    val sequenceNumber = buffer.getInt().toUInt()
    val timestamp = buffer.getLong().toULong()
    val payloadLength = buffer.getShort().toInt() and 0xFFFF
    val payload = ByteArray(payloadLength)
    buffer.get(payload)

    return AudioPacket(
        packetType = packetType,
        sequenceNumber = sequenceNumber,
        timestamp = timestamp,
        payload = payload
    )
}

class PacketFramer {
    private var accumulator = ByteArray(0)

    /**
     * Feed raw TCP data into the framer and extract any complete packets.
     */
    fun feed(data: ByteArray): List<AudioPacket> {
        accumulator = accumulator + data
        val packets = mutableListOf<AudioPacket>()

        while (true) {
            if (accumulator.size < LENGTH_PREFIX_SIZE) break

            val lengthBuffer = ByteBuffer.wrap(accumulator, 0, LENGTH_PREFIX_SIZE)
                .order(ByteOrder.BIG_ENDIAN)
            val packetDataLength = lengthBuffer.getInt()

            if (packetDataLength <= 0 || packetDataLength > 1_000_000) {
                // Invalid frame; reset accumulator to avoid stuck state
                accumulator = ByteArray(0)
                break
            }

            val totalFrameSize = LENGTH_PREFIX_SIZE + packetDataLength
            if (accumulator.size < totalFrameSize) break

            val packetData = accumulator.copyOfRange(LENGTH_PREFIX_SIZE, totalFrameSize)
            accumulator = accumulator.copyOfRange(totalFrameSize, accumulator.size)

            try {
                packets.add(deserialize(packetData))
            } catch (e: Exception) {
                // Skip malformed packet
            }
        }

        return packets
    }

    fun reset() {
        accumulator = ByteArray(0)
    }
}

private var sequenceCounter: UInt = 0u

private fun nextSequence(): UInt = sequenceCounter++

private fun currentTimestampMicros(): ULong =
    (System.currentTimeMillis() * 1000).toULong()

fun createHandshake(): AudioPacket {
    val payload = HandshakePayload(
        protocolVersion = 1u,
        sampleRate = 48000u,
        channels = 2,
        bitrate = 96000u,
        frameDurationMs = 20
    )
    return AudioPacket(
        packetType = PacketType.HANDSHAKE,
        sequenceNumber = nextSequence(),
        timestamp = currentTimestampMicros(),
        payload = payload.toByteArray()
    )
}

fun createHeartbeat(): AudioPacket {
    return AudioPacket(
        packetType = PacketType.HEARTBEAT,
        sequenceNumber = nextSequence(),
        timestamp = currentTimestampMicros(),
        payload = ByteArray(0)
    )
}

fun createAudioPacket(opusData: ByteArray): AudioPacket {
    return AudioPacket(
        packetType = PacketType.AUDIO,
        sequenceNumber = nextSequence(),
        timestamp = currentTimestampMicros(),
        payload = opusData
    )
}
