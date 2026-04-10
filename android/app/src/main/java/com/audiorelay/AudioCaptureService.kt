package com.audiorelay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.audiorelay.audio.AudioCaptureManager
import com.audiorelay.audio.OpusEncoder
import com.audiorelay.network.MdnsRegistrar
import com.audiorelay.network.TcpStreamServer
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AudioCaptureService : Service() {

    companion object {
        private const val TAG = "AudioCaptureService"
        private const val NOTIFICATION_CHANNEL_ID = "audio_relay_channel"
        private const val NOTIFICATION_ID = 1
        private const val SERVER_PORT = 48000

        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        fun createStartIntent(
            context: Context,
            resultCode: Int,
            resultData: Intent
        ): Intent {
            return Intent(context, AudioCaptureService::class.java).apply {
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_RESULT_DATA, resultData)
            }
        }
    }

    // Service state
    enum class ServiceState {
        IDLE, STARTING, RUNNING, ERROR
    }

    data class StreamState(
        val serviceState: ServiceState = ServiceState.IDLE,
        val clientConnected: Boolean = false,
        val clientAddress: String? = null,
        val isMuted: Boolean = false,
        val audioLevel: Float = 0f,
        val errorMessage: String? = null
    )

    private val _state = MutableStateFlow(StreamState())
    val state: StateFlow<StreamState> = _state.asStateFlow()

    // Components
    private var tcpStreamServer: TcpStreamServer? = null
    private var mdnsRegistrar: MdnsRegistrar? = null
    private var audioCaptureManager: AudioCaptureManager? = null
    private var opusEncoder: OpusEncoder? = null
    private var mediaProjection: MediaProjection? = null
    private val encoderLock = Any()

    // Volume management
    private var audioManager: AudioManager? = null
    private var savedVolume: Int = -1

    // Coroutines
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pipelineJob: Job? = null

    // Binder
    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): AudioCaptureService = this@AudioCaptureService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, createNotification())

        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, -1)
        val resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }

        if (resultData == null) {
            Log.e(TAG, "No MediaProjection result data")
            _state.value = _state.value.copy(
                serviceState = ServiceState.ERROR,
                errorMessage = "MediaProjection 数据为空"
            )
            stopSelf()
            return START_NOT_STICKY
        }

        startPipeline(resultCode, resultData)
        return START_NOT_STICKY
    }

    private fun startPipeline(resultCode: Int, resultData: Intent) {
        _state.value = _state.value.copy(serviceState = ServiceState.STARTING)

        pipelineJob = serviceScope.launch {
            try {
                // Obtain MediaProjection
                val projectionManager =
                    getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                mediaProjection = projectionManager.getMediaProjection(resultCode, resultData)

                if (mediaProjection == null) {
                    _state.value = _state.value.copy(
                        serviceState = ServiceState.ERROR,
                        errorMessage = "无法获取 MediaProjection"
                    )
                    return@launch
                }

                // Initialize Opus encoder
                synchronized(encoderLock) {
                    opusEncoder = OpusEncoder()
                }

                // Initialize TCP server with client connect/disconnect callbacks
                val server = TcpStreamServer(SERVER_PORT).apply {
                    onClientConnected = { onClientConnected() }
                    onClientDisconnected = { onClientDisconnected() }
                }
                tcpStreamServer = server

                // Initialize audio capture - feeds PCM frames to the encoder pipeline
                val capture = AudioCaptureManager()
                audioCaptureManager = capture

                // Register mDNS
                mdnsRegistrar = MdnsRegistrar(this@AudioCaptureService).apply {
                    register(SERVER_PORT)
                }

                // Start audio capture with callback that encodes and sends
                capture.start(
                    mediaProjection = mediaProjection!!,
                    onPcmData = { pcmFrame -> processAudioFrame(pcmFrame) },
                    onDiscontinuity = { requestStreamReset("capture discontinuity") }
                )

                _state.value = _state.value.copy(serviceState = ServiceState.RUNNING)
                Log.i(TAG, "Pipeline started successfully")

                // Observe TCP server state
                launch {
                    server.clientConnected.collect { connected ->
                        _state.value = _state.value.copy(clientConnected = connected)
                    }
                }

                launch {
                    server.clientAddress.collect { address ->
                        _state.value = _state.value.copy(clientAddress = address)
                    }
                }

                // Start TCP server (blocks until stopped)
                withContext(Dispatchers.IO) {
                    server.start()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Pipeline error", e)
                _state.value = _state.value.copy(
                    serviceState = ServiceState.ERROR,
                    errorMessage = e.message ?: "未知错误"
                )
            }
        }
    }

    /**
     * Process a single PCM frame: encode to Opus and send to connected client.
     */
    private fun processAudioFrame(pcmFrame: ShortArray) {
        updateAudioLevel(pcmFrame)

        val server = tcpStreamServer ?: return
        if (!server.clientConnected.value) return

        try {
            val opusData = synchronized(encoderLock) {
                opusEncoder?.encode(pcmFrame)
            } ?: return
            server.sendAudioData(opusData)
        } catch (e: Exception) {
            Log.e(TAG, "Encode/send error", e)
        }
    }

    private fun updateAudioLevel(pcmFrame: ShortArray) {
        var sumSquares = 0.0
        for (sample in pcmFrame) {
            val normalized = sample.toFloat() / Short.MAX_VALUE
            sumSquares += normalized * normalized
        }
        val rms = kotlin.math.sqrt(sumSquares / pcmFrame.size).toFloat()
        _state.value = _state.value.copy(audioLevel = rms)
    }

    private fun onClientConnected() {
        Log.i(TAG, "Client connected, muting local audio")
        muteLocalAudio()
        requestStreamReset("client connected")
        _state.value = _state.value.copy(isMuted = true)
    }

    private fun onClientDisconnected() {
        Log.i(TAG, "Client disconnected, restoring local audio")
        restoreLocalAudio()
        _state.value = _state.value.copy(isMuted = false)
    }

    private fun requestStreamReset(reason: String) {
        synchronized(encoderLock) {
            opusEncoder?.close()
            opusEncoder = OpusEncoder()
        }

        tcpStreamServer?.sendStreamReset()
        Log.i(TAG, "Stream reset requested: $reason")
    }

    private fun muteLocalAudio() {
        audioManager?.let { am ->
            savedVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            am.setStreamVolume(AudioManager.STREAM_MUSIC, 0, 0)
            Log.i(TAG, "Local audio muted (saved volume: $savedVolume)")
        }
    }

    private fun restoreLocalAudio() {
        audioManager?.let { am ->
            if (savedVolume >= 0) {
                am.setStreamVolume(AudioManager.STREAM_MUSIC, savedVolume, 0)
                Log.i(TAG, "Local audio restored (volume: $savedVolume)")
                savedVolume = -1
            }
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(R.string.notification_channel_description)
            setShowBadge(false)
        }

        val notificationManager =
            getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text_idle))
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    fun stopPipeline() {
        Log.i(TAG, "Stopping pipeline")

        restoreLocalAudio()

        mdnsRegistrar?.unregister()
        mdnsRegistrar = null

        audioCaptureManager?.stop()
        audioCaptureManager = null

        synchronized(encoderLock) {
            opusEncoder?.close()
            opusEncoder = null
        }

        tcpStreamServer?.stop()
        tcpStreamServer = null

        mediaProjection?.stop()
        mediaProjection = null

        pipelineJob?.cancel()
        pipelineJob = null

        _state.value = StreamState()
    }

    override fun onDestroy() {
        stopPipeline()
        serviceScope.cancel()
        super.onDestroy()
    }
}
