# AudioRelay

AudioRelay 是一款轻量级的音频中继/转发工具，旨在实现跨设备、跨网络的音频流实时传输，解决不同设备间音频互通的需求（如将电脑音频转发到手机、远程设备音频采集等）。

## 功能特性
- 🎵 低延迟音频流转发，兼顾实时性与音质
- 🌐 支持TCP/UDP网络传输，适配不同网络场景
- 🖥️ 跨平台兼容（Windows/macOS/Linux，需根据实际仓库补充）
- ⚙️ 简单易配置，支持自定义音频源、传输端口、编码格式
- 📦 轻量化设计，依赖少，部署成本低

## 环境要求
- Python 3.7+（若为Python实现，若无则替换为对应环境，如Go 1.20+、Node.js 16+等）
- 音频相关依赖（如 `pyaudio`、`sounddevice` 等，需匹配仓库实际依赖）
- 网络互通：服务端与客户端需在同一网络或公网可达

## 安装步骤
### 1. 克隆仓库
```bash
git clone https://github.com/raysonTao/AudioRelay.git
cd AudioRelay
```

### 2. 安装依赖
若项目基于Python，执行：
```bash
pip install -r requirements.txt
```
若为其他语言（如Go），执行：
```bash
go mod download
```

## 使用说明
### 1. 启动服务端（音频接收/转发节点）
```bash
# 示例：Python版本启动服务端
python server.py --host 0.0.0.0 --port 8080 --audio-format pcm
```

### 2. 启动客户端（音频采集/发送节点）
```bash
# 示例：Python版本启动客户端
python client.py --server-ip 192.168.1.100 --server-port 8080 --audio-source mic
```

### 核心参数说明
| 参数 | 说明 | 示例值 |
|------|------|--------|
| `--host`/`--server-ip` | 服务端IP地址 | 0.0.0.0/192.168.1.100 |
| `--port`/`--server-port` | 传输端口 | 8080 |
| `--audio-format` | 音频编码格式 | pcm/mp3/wav |
| `--audio-source` | 客户端音频源 | mic（麦克风）/speaker（系统扬声器）/file（本地文件） |

## 配置文件（可选）
若项目支持配置文件（如 `config.yaml`），可自定义以下参数：
```yaml
server:
  host: 0.0.0.0
  port: 8080
  buffer_size: 1024
audio:
  format: pcm
  sample_rate: 44100
  channels: 2
client:
  auto_reconnect: true
  reconnect_interval: 3 # 重连间隔（秒）
```

## 常见问题
1. **音频延迟过高？**
   - 降低音频缓冲区大小（`buffer_size`）
   - 使用UDP协议（实时性优于TCP）
   - 选择更低的采样率/声道数

2. **客户端无法连接服务端？**
   - 检查服务端是否启动，且IP/端口正确
   - 关闭防火墙/安全组，确保端口放行
   - 确认客户端与服务端网络互通

3. **无音频输出？**
   - 检查音频源是否正确（如麦克风权限、扬声器采集是否开启）
   - 验证音频格式是否与服务端/客户端匹配

## 贡献指南
1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/xxx`）
3. 提交代码（`git commit -m 'feat: 新增xxx功能'`）
4. 推送分支（`git push origin feature/xxx`）
5. 发起 Pull Request

## 许可证
本项目基于 [MIT License](LICENSE) 开源（若仓库无LICENSE文件，可注明“待补充”或根据仓库实际协议调整）。

## 致谢
感谢所有为音频传输、音频处理领域提供开源工具/库的开发者（可补充具体依赖库/项目）。

---
若有问题或建议，欢迎提交 [Issue](https://github.com/raysonTao/AudioRelay/issues) 反馈！
