import SwiftUI

// MARK: - Discovered service model

struct DiscoveredService: Identifiable, Hashable {
    let id: String   // service name
    let name: String
    let host: String
    let port: UInt16

    var displayAddress: String { "\(host):\(port)" }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    connectionStatusSection
                    discoveredServicesSection
                    manualConnectionSection
                    audioMetersSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            viewModel.isSearching = true
        }
        .onDisappear {
            viewModel.isSearching = false
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("Audio Relay")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            if viewModel.state.isActive {
                Button("Disconnect") {
                    viewModel.disconnect()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Connection status

    private var connectionStatusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let address = viewModel.state.serverAddress {
                Text("(\(address))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var statusColor: Color {
        switch viewModel.state.currentState {
        case .disconnected:  return .red
        case .discovering:   return .yellow
        case .connecting:    return .orange
        case .connected:     return .green
        case .reconnecting:  return .orange
        }
    }

    private var statusText: String {
        switch viewModel.state.currentState {
        case .disconnected:  return "Disconnected"
        case .discovering:   return "Discovering..."
        case .connecting:    return "Connecting..."
        case .connected:     return "Connected"
        case .reconnecting:  return "Reconnecting..."
        }
    }

    // MARK: - Discovered services

    private var discoveredServicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Discovered Devices", systemImage: "wifi")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $viewModel.isSearching)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(viewModel.state.isActive)
            }

            if viewModel.isSearching && viewModel.discoveredServices.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Searching for devices...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else if !viewModel.isSearching && viewModel.discoveredServices.isEmpty {
                Text("Toggle search to discover devices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.discoveredServices) { service in
                    ServiceRow(
                        service: service,
                        isConnected: viewModel.state.isActive
                    ) {
                        viewModel.connect(to: service)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Manual connection

    private var manualConnectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Manual Connection", systemImage: "network")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("IP Address", text: $viewModel.manualHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Text(":")
                    .foregroundColor(.secondary)

                TextField("Port", text: $viewModel.manualPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                Button("Connect") {
                    viewModel.connectManual()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.manualHost.isEmpty || viewModel.state.isActive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Audio meters

    private var audioMetersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Audio", systemImage: "speaker.wave.2")
                .font(.headline)

            // Volume control
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Slider(value: $viewModel.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text("\(Int(viewModel.volume * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            // Noise reduction toggle
            HStack {
                Label("Noise Reduction", systemImage: "waveform.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $viewModel.noiseReductionEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            // Buffer level
            MeterBar(
                label: "Buffer",
                value: viewModel.state.bufferLevel,
                valueText: "\(Int(viewModel.state.bufferLevel * 100))%",
                color: bufferColor
            )

            // Audio level
            MeterBar(
                label: "Level",
                value: viewModel.state.audioLevel,
                valueText: String(format: "%.1f dB", linearToDb(viewModel.state.audioLevel)),
                color: audioLevelColor
            )

            // Stats row
            if viewModel.state.isActive {
                HStack(spacing: 16) {
                    StatLabel(title: "Latency", value: String(format: "%.0f ms", viewModel.state.latencyMs))
                    StatLabel(title: "Received", value: "\(viewModel.state.packetsReceived)")
                    StatLabel(title: "Loss", value: String(format: "%.1f%%", viewModel.state.lossRate * 100))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bufferColor: Color {
        let level = viewModel.state.bufferLevel
        if level < 0.2 { return .red }
        if level < 0.4 { return .orange }
        return .green
    }

    private var audioLevelColor: Color {
        let level = viewModel.state.audioLevel
        if level > 0.9 { return .red }
        if level > 0.7 { return .orange }
        return .green
    }

    private func linearToDb(_ linear: Double) -> Double {
        guard linear > 0 else { return -60 }
        return 20 * log10(linear)
    }
}

// MARK: - Subviews

struct ServiceRow: View {
    let service: DiscoveredService
    let isConnected: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.body)
                Text(service.displayAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Connect") {
                onConnect()
            }
            .buttonStyle(.bordered)
            .disabled(isConnected)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct MeterBar: View {
    let label: String
    let value: Double
    let valueText: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(valueText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(
                            width: geometry.size.width * min(max(value, 0), 1),
                            height: 8
                        )
                }
            }
            .frame(height: 8)
        }
    }
}

struct StatLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .monospacedDigit()
        }
    }
}

// MARK: - ViewModel

final class ContentViewModel: ObservableObject {
    @Published var state = ConnectionState()
    @Published var discoveredServices: [DiscoveredService] = []
    @Published var manualHost: String = ""
    @Published var manualPort: String = "48000"
    private var searchTimer: Timer?

    @Published var isSearching: Bool = false {
        didSet {
            searchTimer?.invalidate()
            searchTimer = nil
            if isSearching {
                discoveredServices.removeAll()
                browser.startBrowsing()
                searchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { self?.isSearching = false }
                }
            } else {
                browser.stopBrowsing()
            }
        }
    }
    @Published var volume: Double = 1.0 {
        didSet { audioPlayer.volume = Float(volume) }
    }
    @Published var noiseReductionEnabled: Bool = false {
        didSet { audioPlayer.noiseReductionEnabled = noiseReductionEnabled }
    }

    private let browser = MdnsBrowser()
    private let tcpClient = TcpClient()
    private let jitterBuffer = JitterBuffer()
    private let audioPlayer = AudioPlayer()
    private var opusDecoder: OpusDecoder?

    /// Timer that periodically refreshes UI-visible metrics from the audio pipeline.
    private var metricsTimer: Timer?

    init() {
        setupBrowser()
        setupTcpClient()
    }

    deinit {
        metricsTimer?.invalidate()
        searchTimer?.invalidate()
    }

    // MARK: - Browser

    private func setupBrowser() {
        browser.onServiceFound = { [weak self] name, host, port in
            guard let self = self else { return }
            let service = DiscoveredService(id: name, name: name, host: host, port: port)
            DispatchQueue.main.async {
                if !self.discoveredServices.contains(where: { $0.id == name }) {
                    self.discoveredServices.append(service)
                }
            }
        }

        browser.onServiceLost = { [weak self] name in
            DispatchQueue.main.async {
                self?.discoveredServices.removeAll { $0.id == name }
            }
        }
    }

    // MARK: - TCP client

    private func setupTcpClient() {
        tcpClient.onStateChanged = { [weak self] newState in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.state.currentState = newState

                if newState == .connected {
                    self.isSearching = false
                    self.startAudioPipeline()
                } else if newState == .disconnected {
                    self.stopAudioPipeline()
                    self.state.reset()
                }
                // Trigger SwiftUI update
                self.objectWillChange.send()
            }
        }

        tcpClient.onPacketReceived = { [weak self] packet in
            self?.handleAudioPacket(packet)
        }

        tcpClient.onStreamReset = { [weak self] in
            self?.handleStreamReset(reason: "sender requested reset")
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        browser.startBrowsing()
    }

    func stopDiscovery() {
        browser.stopBrowsing()
    }

    // MARK: - Connection

    func connect(to service: DiscoveredService) {
        state.serverName = service.name
        state.serverAddress = service.displayAddress
        tcpClient.connect(host: service.host, port: service.port)
    }

    func connectManual() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        let port = UInt16(manualPort) ?? 48000
        state.serverAddress = "\(host):\(port)"
        tcpClient.connect(host: host, port: port)
    }

    func disconnect() {
        tcpClient.disconnect()
        stopAudioPipeline()
        state.reset()
        clockOffsetMicros = nil
    }

    // MARK: - Audio pipeline

    private func startAudioPipeline() {
        jitterBuffer.reset()

        do {
            opusDecoder = try OpusDecoder()
        } catch {
            print("[ContentViewModel] Failed to create Opus decoder: \(error)")
            return
        }

        guard let decoder = opusDecoder else { return }
        audioPlayer.start(jitterBuffer: jitterBuffer, decoder: decoder)
        startMetricsTimer()
    }

    private func stopAudioPipeline() {
        stopMetricsTimer()
        audioPlayer.stop()
        jitterBuffer.reset()
        opusDecoder = nil
        lastAudioPacketTimestamp = nil
    }

    /// Clock offset calibrated from first packet (Android time - Mac time).
    private var clockOffsetMicros: Int64?
    private var lastAudioPacketTimestamp: UInt64?

    private func handleStreamReset(reason: String) {
        print("[ContentViewModel] Stream reset: \(reason)")
        jitterBuffer.reset()
        audioPlayer.requestStreamReset()
        clockOffsetMicros = nil
        lastAudioPacketTimestamp = nil

        DispatchQueue.main.async {
            self.state.bufferLevel = 0
            self.state.audioLevel = 0
            self.state.latencyMs = 0
            self.objectWillChange.send()
        }
    }

    private func handleAudioPacket(_ packet: AudioPacket) {
        if let lastTimestamp = lastAudioPacketTimestamp {
            let timestampRolledBack = packet.timestamp < lastTimestamp
            let deltaMicros = timestampRolledBack ? 0 : packet.timestamp - lastTimestamp
            if timestampRolledBack || deltaMicros > 200_000 {
                let deltaMs = timestampRolledBack ? 0 : Double(deltaMicros) / 1000.0
                handleStreamReset(reason: String(format: "audio timestamp gap %.0f ms", deltaMs))
            }
        }
        lastAudioPacketTimestamp = packet.timestamp

        let jitterPacket = JitterBuffer.AudioPacket(
            sequenceNumber: packet.sequenceNumber,
            timestamp: packet.timestamp,
            opusData: packet.payload
        )
        jitterBuffer.push(packet: jitterPacket)

        let nowMicros = Int64(Date().timeIntervalSince1970 * 1_000_000)
        let packetMicros = Int64(bitPattern: packet.timestamp)

        // Calibrate clock offset on first packet.
        if clockOffsetMicros == nil {
            clockOffsetMicros = packetMicros - nowMicros
        }

        // Latency = how much later this packet arrived compared to the first one's baseline.
        let latencyMs = Double(nowMicros - packetMicros + clockOffsetMicros!) / 1000.0
        DispatchQueue.main.async {
            self.state.recordPacketReceived(latency: latencyMs)
        }
    }

    // MARK: - Metrics refresh

    private func startMetricsTimer() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.state.bufferLevel = self.jitterBuffer.bufferLevel
            self.state.audioLevel = Double(self.audioPlayer.audioLevel)
            self.objectWillChange.send()
        }
    }

    private func stopMetricsTimer() {
        metricsTimer?.invalidate()
        metricsTimer = nil
    }
}
