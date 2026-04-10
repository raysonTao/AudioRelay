package com.audiorelay.network

import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.IOException
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

class TcpStreamServer(private val port: Int = 48000) {

    companion object {
        private const val TAG = "TcpStreamServer"
        private const val HEARTBEAT_INTERVAL_MS = 2000L
        private const val HEARTBEAT_TIMEOUT_MS = 6000L
    }

    var onClientConnected: (() -> Unit)? = null
    var onClientDisconnected: (() -> Unit)? = null

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    private val _clientConnected = MutableStateFlow(false)
    val clientConnected: StateFlow<Boolean> = _clientConnected.asStateFlow()

    private val _clientAddress = MutableStateFlow<String?>(null)
    val clientAddress: StateFlow<String?> = _clientAddress.asStateFlow()

    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var clientOutput: OutputStream? = null

    private val sendLock = Any()
    private val running = AtomicBoolean(false)
    private val framer = PacketFramer()

    private var heartbeatJob: Job? = null
    private var readJob: Job? = null

    @Volatile
    private var lastHeartbeatResponse: Long = 0L

    /**
     * Start the TCP server. Blocks until stopped.
     */
    suspend fun start() = withContext(Dispatchers.IO) {
        if (running.getAndSet(true)) return@withContext

        try {
            serverSocket = ServerSocket(port).apply { reuseAddress = true }
            _isRunning.value = true
            Log.i(TAG, "TCP server started on port $port")

            while (running.get()) {
                try {
                    val socket = serverSocket?.accept() ?: break
                    handleClient(socket)
                } catch (e: IOException) {
                    if (running.get()) {
                        Log.e(TAG, "Error accepting client", e)
                    }
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "Failed to start server", e)
        } finally {
            _isRunning.value = false
            running.set(false)
        }
    }

    private suspend fun handleClient(socket: Socket) = coroutineScope {
        disconnectClient()

        clientSocket = socket
        val address = socket.remoteSocketAddress.toString()
        _clientAddress.value = address
        Log.i(TAG, "Client connected: $address")

        try {
            clientOutput = socket.getOutputStream().buffered()
            _clientConnected.value = true

            // Send handshake using our protocol
            val handshakePacket = createHandshake()
            sendPacket(handshakePacket)
            Log.i(TAG, "Handshake sent")

            lastHeartbeatResponse = System.currentTimeMillis()

            // Start heartbeat sender
            heartbeatJob = launch(Dispatchers.IO) {
                runHeartbeatSender()
            }

            onClientConnected?.invoke()

            // Read loop for client responses
            readJob = launch(Dispatchers.IO) {
                readLoop(socket)
            }
            readJob?.join()
        } catch (e: IOException) {
            Log.e(TAG, "Client error", e)
        } finally {
            disconnectClient()
        }
    }

    private suspend fun runHeartbeatSender() {
        try {
            while (running.get() && clientSocket?.isConnected == true) {
                delay(HEARTBEAT_INTERVAL_MS)
                sendPacket(createHeartbeat())

                // Check for timeout
                val elapsed = System.currentTimeMillis() - lastHeartbeatResponse
                if (elapsed > HEARTBEAT_TIMEOUT_MS) {
                    Log.w(TAG, "Heartbeat timeout, disconnecting client")
                    disconnectClient()
                    break
                }
            }
        } catch (e: IOException) {
            Log.d(TAG, "Heartbeat sender stopped")
        }
    }

    private fun readLoop(socket: Socket) {
        try {
            val input = socket.getInputStream()
            val readBuffer = ByteArray(65536)
            framer.reset()

            while (running.get() && !socket.isClosed) {
                val bytesRead = input.read(readBuffer)
                if (bytesRead == -1) break

                val data = readBuffer.copyOf(bytesRead)
                val packets = framer.feed(data)

                for (packet in packets) {
                    when (packet.packetType) {
                        PacketType.HEARTBEAT -> {
                            lastHeartbeatResponse = System.currentTimeMillis()
                        }
                        PacketType.HANDSHAKE -> {
                            Log.i(TAG, "Received handshake response from client")
                            lastHeartbeatResponse = System.currentTimeMillis()
                        }
                        else -> {
                            // Ignore other packet types from client
                        }
                    }
                }
            }
        } catch (e: IOException) {
            if (running.get()) {
                Log.d(TAG, "Read loop ended: ${e.message}")
            }
        }
    }

    /**
     * Send an audio packet to the connected client using the protocol framing.
     */
    fun sendAudioData(opusData: ByteArray) {
        val packet = createAudioPacket(opusData)
        sendPacket(packet)
    }

    fun sendStreamReset() {
        sendPacket(createStreamResetPacket())
    }

    /**
     * Send any packet using the protocol framing.
     */
    fun sendPacket(packet: AudioPacket) {
        synchronized(sendLock) {
            try {
                val out = clientOutput ?: return
                val data = serialize(packet)
                out.write(data)
                out.flush()
            } catch (e: IOException) {
                Log.e(TAG, "Failed to send packet", e)
            }
        }
    }

    private fun disconnectClient() {
        heartbeatJob?.cancel()
        readJob?.cancel()
        heartbeatJob = null
        readJob = null

        try { clientOutput?.close() } catch (_: IOException) {}
        try { clientSocket?.close() } catch (_: IOException) {}

        clientOutput = null
        clientSocket = null
        framer.reset()

        val wasConnected = _clientConnected.value
        _clientConnected.value = false
        _clientAddress.value = null

        if (wasConnected) {
            Log.i(TAG, "Client disconnected")
            onClientDisconnected?.invoke()
        }
    }

    fun stop() {
        running.set(false)
        disconnectClient()

        try { serverSocket?.close() } catch (_: IOException) {}
        serverSocket = null

        _isRunning.value = false
        Log.i(TAG, "TCP server stopped")
    }
}
