package com.audiorelay.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.audiorelay.AudioCaptureService.ServiceState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: MainViewModel) {
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text("Audio Relay", fontWeight = FontWeight.Bold)
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            // Connection status card
            ConnectionStatusCard(
                serviceState = state.serviceState,
                clientConnected = state.clientConnected,
                clientAddress = state.clientAddress
            )

            // Server address display
            if (state.serviceState == ServiceState.RUNNING) {
                ServerInfoCard(serverAddress = state.serverAddress)
            }

            // Audio level indicator
            if (state.serviceState == ServiceState.RUNNING) {
                AudioLevelCard(level = state.audioLevel)
            }

            // Mute status
            if (state.isMuted) {
                MuteStatusCard()
            }

            // Error message
            state.errorMessage?.let { error ->
                ErrorCard(message = error)
            }

            Spacer(modifier = Modifier.weight(1f))

            // Start/Stop button
            StartStopButton(
                isRunning = state.serviceState == ServiceState.RUNNING ||
                        state.serviceState == ServiceState.STARTING,
                isLoading = state.serviceState == ServiceState.STARTING,
                onStart = { viewModel.onStartClicked() },
                onStop = { viewModel.onStopClicked() }
            )
        }
    }
}

@Composable
private fun ConnectionStatusCard(
    serviceState: ServiceState,
    clientConnected: Boolean,
    clientAddress: String?
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Status indicator dot
            val indicatorColor by animateColorAsState(
                targetValue = when {
                    clientConnected -> Color(0xFF4CAF50) // Green
                    serviceState == ServiceState.RUNNING -> Color(0xFFFFC107) // Amber
                    serviceState == ServiceState.STARTING -> Color(0xFFFFC107)
                    serviceState == ServiceState.ERROR -> Color(0xFFF44336) // Red
                    else -> Color(0xFF9E9E9E) // Grey
                },
                label = "statusColor"
            )

            Box(
                modifier = Modifier
                    .size(16.dp)
                    .clip(CircleShape)
                    .background(indicatorColor)
            )

            Column {
                Text(
                    text = when {
                        clientConnected -> "已连接"
                        serviceState == ServiceState.RUNNING -> "等待连接..."
                        serviceState == ServiceState.STARTING -> "正在启动..."
                        serviceState == ServiceState.ERROR -> "错误"
                        else -> "已停止"
                    },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )

                if (clientConnected && clientAddress != null) {
                    Text(
                        text = "客户端: $clientAddress",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun ServerInfoCard(serverAddress: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Text(
                text = "服务器地址",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f)
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = serverAddress,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSecondaryContainer
            )
        }
    }
}

@Composable
private fun AudioLevelCard(level: Float) {
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Text(
                text = "音频电平",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
            )
            Spacer(modifier = Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = level.coerceIn(0f, 1f),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .clip(RoundedCornerShape(4.dp)),
                color = when {
                    level > 0.8f -> Color(0xFFF44336)
                    level > 0.5f -> Color(0xFFFFC107)
                    else -> Color(0xFF4CAF50)
                },
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
            )
        }
    }
}

@Composable
private fun MuteStatusCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.tertiaryContainer
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "音频已转发到 Mac，本地已静音",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onTertiaryContainer
            )
        }
    }
}

@Composable
private fun ErrorCard(message: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer
        )
    ) {
        Text(
            text = message,
            modifier = Modifier.padding(20.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onErrorContainer
        )
    }
}

@Composable
private fun StartStopButton(
    isRunning: Boolean,
    isLoading: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit
) {
    Button(
        onClick = if (isRunning) onStop else onStart,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (isRunning)
                MaterialTheme.colorScheme.error
            else
                MaterialTheme.colorScheme.primary
        ),
        shape = RoundedCornerShape(16.dp),
        enabled = !isLoading
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                color = MaterialTheme.colorScheme.onPrimary,
                strokeWidth = 2.dp
            )
            Spacer(modifier = Modifier.width(12.dp))
        }
        Text(
            text = when {
                isLoading -> "正在启动..."
                isRunning -> "停止转发"
                else -> "开始转发"
            },
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold
        )
    }
}
