package com.audiorelay.audio

import org.concentus.OpusEncoder as ConcentusEncoder
import org.concentus.OpusApplication
import org.concentus.OpusSignal

class OpusEncoder {

    companion object {
        private const val SAMPLE_RATE = 48000
        private const val CHANNELS = 2
        private const val BITRATE = 96000
        private const val FRAME_DURATION_MS = 20

        /** Samples per channel per frame: 48000 * 20 / 1000 = 960 */
        const val FRAME_SIZE = SAMPLE_RATE * FRAME_DURATION_MS / 1000

        /** Total interleaved samples per frame: 960 * 2 = 1920 */
        const val SAMPLES_PER_FRAME = FRAME_SIZE * CHANNELS

        /** Maximum Opus packet size in bytes */
        private const val MAX_PACKET_SIZE = 4000
    }

    private var encoder: ConcentusEncoder? = null

    init {
        val enc = ConcentusEncoder(SAMPLE_RATE, CHANNELS, OpusApplication.OPUS_APPLICATION_AUDIO)
        enc.setBitrate(BITRATE)
        enc.setSignalType(OpusSignal.OPUS_SIGNAL_AUTO)
        encoder = enc
    }

    /**
     * Encode a single frame of interleaved 16-bit PCM audio.
     *
     * @param pcm Interleaved PCM samples. Must contain exactly [SAMPLES_PER_FRAME] (1920) shorts.
     * @return Opus-encoded frame as a ByteArray.
     * @throws IllegalStateException if the encoder has been closed.
     * @throws IllegalArgumentException if the input size is wrong.
     */
    fun encode(pcm: ShortArray): ByteArray {
        val enc = encoder ?: throw IllegalStateException("Encoder has been closed")
        require(pcm.size == SAMPLES_PER_FRAME) {
            "Expected $SAMPLES_PER_FRAME samples, got ${pcm.size}"
        }

        val outputBuffer = ByteArray(MAX_PACKET_SIZE)
        val encodedLength = enc.encode(pcm, 0, FRAME_SIZE, outputBuffer, 0, outputBuffer.size)

        return outputBuffer.copyOf(encodedLength)
    }

    /**
     * Release encoder resources.
     */
    fun close() {
        encoder = null
    }
}
