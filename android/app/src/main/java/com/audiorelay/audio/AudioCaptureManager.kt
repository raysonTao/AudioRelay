package com.audiorelay.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class AudioCaptureManager {

    companion object {
        private const val SAMPLE_RATE = 48000
        private const val CHANNELS = 2
        private const val FRAME_DURATION_MS = 20

        /** Samples per channel per frame */
        private const val FRAME_SIZE = SAMPLE_RATE * FRAME_DURATION_MS / 1000 // 960

        /** Total interleaved shorts per frame */
        private const val SAMPLES_PER_FRAME = FRAME_SIZE * CHANNELS // 1920

        /** Gaps far larger than a 20 ms frame usually mean pause/seek/reconfigure on the source. */
        private const val DISCONTINUITY_GAP_MS = 200L
    }

    private var audioRecord: AudioRecord? = null
    private var captureJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    /**
     * Start capturing system audio via AudioPlaybackCapture.
     *
     * @param mediaProjection A granted MediaProjection instance.
     * @param onPcmData Callback invoked with each PCM frame (1920 interleaved shorts at 48kHz stereo).
     */
    fun start(
        mediaProjection: MediaProjection,
        onPcmData: (ShortArray) -> Unit,
        onDiscontinuity: () -> Unit = {}
    ) {
        val captureConfig = AudioPlaybackCaptureConfiguration.Builder(mediaProjection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val audioFormat = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()

        val minBufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_STEREO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        // Use at least 2x the frame size in bytes, or the system minimum, whichever is larger
        val frameSizeBytes = SAMPLES_PER_FRAME * 2 // 2 bytes per short
        val bufferSize = maxOf(minBufferSize, frameSizeBytes * 2)

        val record = AudioRecord.Builder()
            .setAudioPlaybackCaptureConfig(captureConfig)
            .setAudioFormat(audioFormat)
            .setBufferSizeInBytes(bufferSize)
            .build()

        audioRecord = record
        record.startRecording()

        captureJob = scope.launch {
            val frameBuffer = ShortArray(SAMPLES_PER_FRAME)
            var bufferedSamples = 0
            var lastFrameCompletedAtNs = 0L
            var discontinuityPending = true

            while (isActive) {
                val remaining = SAMPLES_PER_FRAME - bufferedSamples
                val shortsRead = record.read(frameBuffer, bufferedSamples, remaining)
                val nowNs = SystemClock.elapsedRealtimeNanos()

                if (shortsRead > 0) {
                    if (bufferedSamples == 0 &&
                        lastFrameCompletedAtNs != 0L &&
                        (nowNs - lastFrameCompletedAtNs) / 1_000_000L > DISCONTINUITY_GAP_MS
                    ) {
                        discontinuityPending = true
                    }

                    bufferedSamples += shortsRead

                    if (bufferedSamples == SAMPLES_PER_FRAME) {
                        if (discontinuityPending) {
                            onDiscontinuity()
                            discontinuityPending = false
                        }
                        onPcmData(frameBuffer.copyOf())
                        bufferedSamples = 0
                        lastFrameCompletedAtNs = nowNs
                    }
                } else if (shortsRead == 0) {
                    if (lastFrameCompletedAtNs != 0L &&
                        (nowNs - lastFrameCompletedAtNs) / 1_000_000L > DISCONTINUITY_GAP_MS
                    ) {
                        discontinuityPending = true
                    }
                } else if (shortsRead < 0) {
                    // Read error; stop capture
                    break
                }
            }
        }
    }

    /**
     * Stop capturing and release resources.
     */
    fun stop() {
        captureJob?.cancel()
        captureJob = null

        audioRecord?.let { record ->
            try {
                record.stop()
            } catch (_: IllegalStateException) {
                // Already stopped
            }
            record.release()
        }
        audioRecord = null
    }
}
