# Audio Relay

将 Android 设备的系统音频实时中继到 Mac 播放。适用于将平板上的网课、视频、会议音频转发到 Mac 端耳机收听。

## 工作原理

```
Android (发送端)                         Mac (接收端)
┌──────────────────┐    TCP/48000    ┌──────────────────┐
│ AudioPlaybackCapture │──────────────▶│  JitterBuffer    │
│ → Opus 编码 (96kbps) │   长度前缀帧    │  → Opus 解码     │
│ → TCP 发送          │              │  → AVAudioEngine  │
└──────────────────┘              └──────────────────┘
         ▲ mDNS 服务发现 (_audiorelay._tcp.)  ▲
```

- **Android** 通过 AudioPlaybackCapture API 捕获系统音频（媒体、游戏），Opus 编码后通过 TCP 发送
- **Mac** 通过 mDNS/Bonjour 自动发现 Android 端，接收并解码播放
- 自适应 Jitter Buffer（100-300ms）吸收网络抖动
- Android 端连接时自动静音本地扬声器，断开后恢复

## 协议格式

每个 TCP 帧：4 字节大端长度前缀 + 数据包

数据包头（15 字节）：类型(1B) + 序列号(4B) + 时间戳(8B, 微秒) + 负载长度(2B)

| 类型 | 值 | 说明 |
|------|------|------|
| Audio | 0x01 | Opus 编码的音频帧 |
| Handshake | 0x02 | 连接握手 |
| Heartbeat | 0x03 | 心跳保活 |
| Config | 0x04 | 配置同步 |

## 音频参数

| 参数 | 值 |
|------|------|
| 采样率 | 48 kHz |
| 声道 | 立体声 |
| 编码 | Opus, 96 kbps |
| 帧长 | 20 ms (960 samples/channel) |
| 信号类型 | Auto（自动适配语音/音乐） |

## 环境要求

**Android 发送端：**
- Android 10+ (API 29)
- 需授权屏幕录制（用于 AudioPlaybackCapture）

**Mac 接收端：**
- macOS 13+
- Homebrew 安装 libopus：`brew install opus`

## 构建

### Android

用 Android Studio 打开 `android/` 目录，或命令行：

```bash
cd android
./gradlew installDebug
```

### Mac

```bash
cd mac
swift build
```

构建产物为 `.build/debug/AudioRelayReceiver`，可复制到 `/Applications/AudioRelay.app/Contents/MacOS/AudioRelay` 部署。

## 使用

1. 确保 Android 和 Mac 在同一局域网
2. 在 Android 端打开 Audio Relay，点击开始，授权屏幕录制
3. 在 Mac 端打开 Audio Relay，设备搜索会自动发现 Android 端
4. 点击 Connect 连接，即可在 Mac 上听到 Android 的音频

Mac 端功能：
- **音量滑块** — 调节播放音量
- **Noise Reduction** — 开启 de-clicker 降噪，适合听课场景
- **设备搜索开关** — 启动时自动搜索 60 秒，也可手动控制

## 项目结构

```
android/                      # Android 发送端 (Kotlin + Jetpack Compose)
├── audio/
│   ├── AudioCaptureManager.kt  # 系统音频捕获
│   └── OpusEncoder.kt          # Opus 编码
├── AudioCaptureService.kt      # 前台服务 + TCP 服务器
└── MainActivity.kt             # UI

mac/                          # Mac 接收端 (Swift + SwiftUI)
├── Sources/AudioRelayReceiver/
│   ├── Audio/
│   │   ├── AudioPlayer.swift    # AVAudioEngine 播放
│   │   ├── OpusDecoder.swift    # Opus 解码
│   │   └── JitterBuffer.swift   # 自适应抖动缓冲
│   ├── Network/
│   │   ├── TcpClient.swift      # TCP 客户端
│   │   ├── MdnsBrowser.swift    # mDNS 服务发现
│   │   └── PacketProtocol.swift # 协议解析
│   └── App/
│       └── ContentView.swift    # UI + ViewModel
├── Sources/COpus/               # libopus 系统库绑定
└── Sources/COpusHelpers/        # opus_decoder_ctl 的 C shim

docs/
├── requirements.md             # 需求文档
└── tech-selection.md           # 技术选型
```

## 依赖

| 组件 | 依赖 | 用途 |
|------|------|------|
| Android | Concentus (concentus.jar) | 纯 Java Opus 编码 |
| Android | Jetpack Compose | UI |
| Mac | libopus (Homebrew) | Opus 解码 |
| Mac | Swift Package Manager | 构建 |

## License

[Apache License 2.0](LICENSE)
