package com.audiorelay.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.audiorelay.AudioCaptureService
import com.audiorelay.AudioCaptureService.ServiceState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.net.Inet4Address
import java.net.NetworkInterface

class MainViewModel : ViewModel() {

    data class UiState(
        val serviceState: ServiceState = ServiceState.IDLE,
        val clientConnected: Boolean = false,
        val clientAddress: String? = null,
        val isMuted: Boolean = false,
        val audioLevel: Float = 0f,
        val errorMessage: String? = null,
        val serverAddress: String = ""
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private var service: AudioCaptureService? = null

    // Callbacks set by Activity
    var onStartRequested: (() -> Unit)? = null
    var onStopRequested: (() -> Unit)? = null

    fun attachService(captureService: AudioCaptureService) {
        service = captureService
        viewModelScope.launch {
            captureService.state.collect { serviceState ->
                _uiState.value = UiState(
                    serviceState = serviceState.serviceState,
                    clientConnected = serviceState.clientConnected,
                    clientAddress = serviceState.clientAddress,
                    isMuted = serviceState.isMuted,
                    audioLevel = serviceState.audioLevel,
                    errorMessage = serviceState.errorMessage,
                    serverAddress = getLocalIpAddress() + ":48000"
                )
            }
        }
    }

    fun detachService() {
        service = null
        _uiState.value = UiState()
    }

    fun onStartClicked() {
        onStartRequested?.invoke()
    }

    fun onStopClicked() {
        onStopRequested?.invoke()
    }

    private fun getLocalIpAddress(): String {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                if (networkInterface.isLoopback || !networkInterface.isUp) continue

                val addresses = networkInterface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()
                    if (address is Inet4Address && !address.isLoopbackAddress) {
                        return address.hostAddress ?: "0.0.0.0"
                    }
                }
            }
        } catch (_: Exception) {}
        return "0.0.0.0"
    }
}
