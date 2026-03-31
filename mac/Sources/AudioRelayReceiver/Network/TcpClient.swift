import Network
import Foundation

/// TCP client that connects to the Android audio relay server.
///
/// Uses length-prefix framing (4 bytes big-endian) over a `NWConnection`.
/// The `PacketFramer` accumulates raw TCP stream data and extracts complete
/// packets, while `PacketProtocol` handles serialization/deserialization.
final class TcpClient {

    // MARK: - Callbacks

    /// Called when a complete packet is received (on the internal queue).
    var onPacketReceived: ((AudioPacket) -> Void)?

    /// Called when the connection state changes (on the internal queue).
    var onStateChanged: ((ConnectionState.State) -> Void)?

    // MARK: - Private state

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.audiorelay.tcp", qos: .userInteractive)
    private let framer = PacketFramer()
    private var isIntentionalDisconnect = false

    // Reconnection backoff
    private var reconnectAttempt = 0
    private let maxBackoff: TimeInterval = 30
    private let initialBackoff: TimeInterval = 1
    private var reconnectWorkItem: DispatchWorkItem?

    // Last connection target for reconnection
    private var lastHost: String?
    private var lastPort: UInt16?

    // MARK: - Public API

    /// Connect to the Android server at the given host and port.
    func connect(host: String, port: UInt16) {
        isIntentionalDisconnect = false
        reconnectAttempt = 0
        lastHost = host
        lastPort = port
        framer.reset()
        establishConnection(host: host, port: port)
    }

    /// Disconnect and stop any reconnection attempts.
    func disconnect() {
        isIntentionalDisconnect = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connection?.cancel()
        connection = nil
        framer.reset()
        onStateChanged?(.disconnected)
    }

    // MARK: - Connection lifecycle

    private func establishConnection(host: String, port: UInt16) {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let params = NWParameters.tcp
        params.requiredInterfaceType = .wifi

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection = conn

        onStateChanged?(.connecting)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.reconnectAttempt = 0
                self.onStateChanged?(.connected)
                self.sendHandshake()
                self.startReadLoop()

            case .failed(let error):
                print("[TcpClient] Connection failed: \(error)")
                self.onStateChanged?(.reconnecting)
                self.scheduleReconnect()

            case .cancelled:
                break

            case .waiting(let error):
                print("[TcpClient] Connection waiting: \(error)")
                self.onStateChanged?(.connecting)

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    // MARK: - Read loop

    /// Start the read loop. We read data in chunks and feed it to the
    /// `PacketFramer`, which handles partial-packet reassembly.
    private func startReadLoop() {
        readChunk()
    }

    /// Read the next chunk of data from the connection.
    private func readChunk() {
        guard let conn = connection else { return }

        // Read between 1 byte and 64 KB at a time.
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[TcpClient] Read error: \(error)")
                self.handleDisconnect()
                return
            }

            if let data = data, !data.isEmpty {
                self.framer.append(data: data)

                // Drain all complete packets from the framer.
                while let packet = self.framer.nextPacket() {
                    self.handlePacket(packet)
                }
            }

            if isComplete {
                self.handleDisconnect()
                return
            }

            // Continue reading.
            self.readChunk()
        }
    }

    // MARK: - Packet handling

    private func handlePacket(_ packet: AudioPacket) {
        switch packet.packetType {
        case .audio:
            onPacketReceived?(packet)

        case .handshake:
            print("[TcpClient] Received handshake from server")
            // Send our handshake response
            sendHandshake()

        case .heartbeat:
            sendHeartbeatReply()

        case .config:
            print("[TcpClient] Received config packet (seq: \(packet.sequenceNumber))")
        }
    }

    // MARK: - Sending

    private func sendHandshake() {
        let packet = PacketProtocol.createHandshakeResponse()
        sendRaw(PacketProtocol.serialize(packet: packet))
    }

    private func sendHeartbeatReply() {
        let packet = PacketProtocol.createHeartbeatResponse()
        sendRaw(PacketProtocol.serialize(packet: packet))
    }

    private func sendRaw(_ data: Data) {
        guard let conn = connection else { return }
        conn.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[TcpClient] Send error: \(error)")
            }
        })
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        connection?.cancel()
        connection = nil
        framer.reset()
        onStateChanged?(.reconnecting)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect, let host = lastHost, let port = lastPort else {
            return
        }

        let backoff = min(initialBackoff * pow(2.0, Double(reconnectAttempt)), maxBackoff)
        reconnectAttempt += 1

        print("[TcpClient] Reconnecting in \(backoff)s (attempt \(reconnectAttempt))")
        onStateChanged?(.reconnecting)

        let workItem = DispatchWorkItem { [weak self] in
            self?.framer.reset()
            self?.establishConnection(host: host, port: port)
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + backoff, execute: workItem)
    }
}
