import Network
import Foundation

/// Discovers Audio Relay services on the local network using Bonjour (mDNS).
/// Browses for the `_audiorelay._tcp.` service type.
class MdnsBrowser {

    // MARK: - Callbacks

    /// Called when a new service is found: (name, host, port).
    var onServiceFound: ((String, String, UInt16) -> Void)?

    /// Called when a previously found service is no longer available.
    var onServiceLost: ((String) -> Void)?

    // MARK: - Private state

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.audiorelay.mdns", qos: .utility)

    /// Tracks discovered endpoints so we can resolve them and detect removals.
    private var discoveredServices: [String: NWBrowser.Result] = [:]

    // MARK: - Public API

    /// Start browsing for `_audiorelay._tcp.` services on the local network.
    func startBrowsing() {
        stopBrowsing()

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_audiorelay._tcp.", domain: nil)
        let params = NWParameters()
        params.requiredInterfaceType = .wifi

        let newBrowser = NWBrowser(for: descriptor, using: params)

        newBrowser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[MdnsBrowser] Browsing for _audiorelay._tcp. services")
            case .failed(let error):
                print("[MdnsBrowser] Browse failed: \(error)")
            case .cancelled:
                print("[MdnsBrowser] Browse cancelled")
            default:
                break
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            self.handleBrowseResults(results: results, changes: changes)
        }

        newBrowser.start(queue: queue)
        self.browser = newBrowser
    }

    /// Stop browsing for services.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        discoveredServices.removeAll()
    }

    // MARK: - Result handling

    private func handleBrowseResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                handleServiceAdded(result)
            case .removed(let result):
                handleServiceRemoved(result)
            case .changed(old: _, new: let newResult, flags: _):
                handleServiceAdded(newResult)
            case .identical:
                break
            @unknown default:
                break
            }
        }
    }

    private func handleServiceAdded(_ result: NWBrowser.Result) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }

        discoveredServices[name] = result
        resolveService(result: result, name: name)
    }

    private func handleServiceRemoved(_ result: NWBrowser.Result) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }

        discoveredServices.removeValue(forKey: name)
        DispatchQueue.main.async {
            self.onServiceLost?(name)
        }
    }

    /// Resolve the service endpoint to get a host and port by establishing
    /// a short-lived connection to extract the address.
    private func resolveService(result: NWBrowser.Result, name: String) {
        let params = NWParameters.tcp
        let connection = NWConnection(to: result.endpoint, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                // Extract the resolved host and port from the connection path
                if let endpoint = connection.currentPath?.remoteEndpoint {
                    let (host, port) = self.extractHostPort(from: endpoint)
                    if let host = host, let port = port {
                        DispatchQueue.main.async {
                            self.onServiceFound?(name, host, port)
                        }
                    }
                }
                connection.cancel()

            case .failed, .cancelled:
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: queue)

        // Timeout: cancel if we can't resolve within 5 seconds
        queue.asyncAfter(deadline: .now() + 5) {
            if connection.state != .cancelled {
                connection.cancel()
            }
        }
    }

    private func extractHostPort(from endpoint: NWEndpoint) -> (String?, UInt16?) {
        switch endpoint {
        case .hostPort(let host, let port):
            let hostString: String
            switch host {
            case .ipv4(let addr):
                hostString = "\(addr)"
            case .ipv6(let addr):
                hostString = "\(addr)"
            case .name(let name, _):
                hostString = name
            @unknown default:
                return (nil, nil)
            }
            return (hostString, port.rawValue)
        default:
            return (nil, nil)
        }
    }
}
