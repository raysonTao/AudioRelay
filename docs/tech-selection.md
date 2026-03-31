# Audio Relay 技术选型文档

## 音频捕获：AudioPlaybackCapture API

**选择理由**：
- Android 10+ 原生 API，无需 root
- 通过 MediaProjection 捕获系统音频
- 可按 AudioAttributes.Usage 过滤音频源
- 音量为 0 时仍可正常捕获

**配置**：
- 采样率：48000 Hz
- 声道：立体声
- 格式：16-bit PCM
- 匹配 Usage：MEDIA, GAME, UNKNOWN

## 编解码：Opus 96kbps 立体声

**选择理由**：
- 专为实时音频设计，低延迟编解码
- 96kbps 立体声质量优秀
- 内置丢包补偿（PLC）
- 20ms 帧长，平衡延迟和效率

**Android 端库：Concentus（纯 Java）**
- 避免 NDK/JNI 复杂性
- 纯 Java 实现，96kbps 编码性能足够
- Maven 依赖：`org.concentus:concentus`

**Mac 端库：alta/swift-opus（SPM）**
- Swift 原生集成
- 通过 SPM 编译 libopus C 库
- 提供 Swift 友好的 API

## 传输协议：TCP

**选择理由**：
- 家庭局域网丢包率极低（<0.1%）
- TCP 保证有序可靠传输，无需自行处理重传
- 实现简单，避免 UDP 需要额外处理的乱序/丢包问题
- 500ms+ 延迟容忍度下 TCP 完全够用

**端口**：48000

## 设备发现：mDNS/Bonjour

**选择理由**：
- 零配置，无需手动输入 IP
- Android NsdManager 原生支持
- macOS Bonjour 原生支持
- 服务类型：`_audiorelay._tcp.`

## Mac 音频播放：AVAudioEngine

**选择理由**：
- 现代 Apple 音频 API
- 原生支持蓝牙音频路由
- 支持实时音频调度
- 格式：48kHz 立体声 Float32

## 抖动缓冲：自适应 100-300ms

**设计**：
- 环形缓冲区，按序列号索引
- 默认目标深度 150ms
- 基于到达间隔抖动的指数移动平均自适应调整
- 下溢时调用 Opus PLC 生成插值音频
- 上溢时丢弃最旧的包

## 数据包协议

TCP 流长度前缀分帧，大端序：
- 4 字节包总长度 + 可变长度包数据
- 包类型：音频(0x01)、握手(0x02)、心跳(0x03)、配置(0x04)
- 包含序列号、时间戳、负载长度和负载数据
