package com.audiorelay

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.audiorelay.ui.MainScreen
import com.audiorelay.ui.MainViewModel
import com.audiorelay.ui.theme.AudioRelayTheme

class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "MainActivity"
    }

    private var captureService: AudioCaptureService? = null
    private var serviceBound = false
    private var viewModel: MainViewModel? = null

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val localBinder = binder as AudioCaptureService.LocalBinder
            captureService = localBinder.getService()
            serviceBound = true
            viewModel?.attachService(localBinder.getService())
            Log.i(TAG, "Service bound")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            captureService = null
            serviceBound = false
            viewModel?.detachService()
            Log.i(TAG, "Service unbound")
        }
    }

    // MediaProjection permission request
    private val mediaProjectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK && result.data != null) {
            Log.i(TAG, "MediaProjection permission granted")
            startAudioCaptureService(result.resultCode, result.data!!)
        } else {
            Log.w(TAG, "MediaProjection permission denied")
            Toast.makeText(this, "需要屏幕录制权限才能捕获音频", Toast.LENGTH_LONG).show()
        }
    }

    // Notification permission request (Android 13+)
    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            Log.i(TAG, "Notification permission granted")
        } else {
            Log.w(TAG, "Notification permission denied")
            Toast.makeText(this, "通知权限被拒绝，服务可能无法正常运行", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestNotificationPermissionIfNeeded()

        setContent {
            AudioRelayTheme {
                val vm: MainViewModel = viewModel()
                viewModel = vm

                // Bind to service if already running
                captureService?.let { vm.attachService(it) }

                vm.onStartRequested = { requestMediaProjection() }
                vm.onStopRequested = { stopAudioCaptureService() }

                MainScreen(viewModel = vm)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        // Try to bind to an already-running service
        val intent = Intent(this, AudioCaptureService::class.java)
        bindService(intent, serviceConnection, 0)
    }

    override fun onStop() {
        super.onStop()
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    private fun requestMediaProjection() {
        val projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val captureIntent = projectionManager.createScreenCaptureIntent()
        mediaProjectionLauncher.launch(captureIntent)
    }

    private fun startAudioCaptureService(resultCode: Int, resultData: Intent) {
        val serviceIntent = AudioCaptureService.createStartIntent(
            this,
            resultCode,
            resultData
        )

        ContextCompat.startForegroundService(this, serviceIntent)

        // Bind to the service
        bindService(serviceIntent, serviceConnection, BIND_AUTO_CREATE)
        Log.i(TAG, "Audio capture service started")
    }

    private fun stopAudioCaptureService() {
        captureService?.stopPipeline()

        val serviceIntent = Intent(this, AudioCaptureService::class.java)
        stopService(serviceIntent)

        Log.i(TAG, "Audio capture service stopped")
    }
}
