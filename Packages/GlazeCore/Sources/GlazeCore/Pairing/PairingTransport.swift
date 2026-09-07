import CryptoKit
import Foundation
import Network
import os

/// Carrying one sealed message from the phone to the television.
///
/// A plain TCP connection on the local network rather than HTTP: both ends are ours,
/// there is nothing to parse, and App Transport Security has no say in it — which
/// saves demanding a certificate from a television for a single message that is
/// already encrypted with a key the network never sees.
///
/// The wire is four bytes of length, then that many bytes of sealed message, then one
/// byte back saying whether it opened.
enum PairingWire {
    static let maximumMessageBytes = 64 * 1024
    static let accepted: UInt8 = 1
    static let refused: UInt8 = 0

    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        return framed
    }
}

/// The television's side: opens a port, and waits for one server to arrive.
public actor PairingReceiver {
    private var listener: NWListener?
    private var waiter: CheckedContinuation<PairingPayload, Error>?
    /// The answer, when it arrives before anyone is waiting for it. The phone can
    /// finish sending before the screen has got round to asking, and without this the
    /// result was dropped and the wait never woke.
    private var pending: Result<PairingPayload, Error>?
    private var key: SymmetricKey?
    private var hasFinished = false

    public init() {}

    /// - Returns: what to put in the code on screen.
    public func start() async throws -> PairingInvitation {
        let key = PairingInvitation.makeKey()
        self.key = key

        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            Task { await self?.receive(from: connection) }
        }

        // Wait for the listener to actually come up before reading its port. Asked
        // any earlier it answers 0 — the port that was *requested* — and a code with
        // port 0 in it sends the phone to an address that cannot be connected to.
        try await Self.waitUntilReady(listener)

        guard let port = listener.port?.rawValue, port != 0, let host = Self.localAddress() else {
            listener.cancel()
            throw PairingError.transport("no local address")
        }
        return PairingInvitation(host: host, port: port, key: key)
    }

    /// Waits for the phone. Cancelling the task, or `stop()`, ends the wait.
    public func waitForServer() async throws -> PairingPayload {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let pending {
                    self.pending = nil
                    continuation.resume(with: pending)
                } else {
                    waiter = continuation
                }
            }
        } onCancel: {
            Task { await self.stop() }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        finish(.failure(PairingError.timedOut))
    }

    private static func waitUntilReady(_ listener: NWListener) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                let shouldResume = resumed.withLock { already -> Bool in
                    guard !already else { return false }
                    switch state {
                    case .ready, .failed, .cancelled: already = true; return true
                    default: return false
                    }
                }
                guard shouldResume else { return }
                switch state {
                case .ready: continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: PairingError.transport(error.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: PairingError.transport("cancelled"))
                default: break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    private func finish(_ result: Result<PairingPayload, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        if let waiter {
            self.waiter = nil
            waiter.resume(with: result)
        } else {
            pending = result
        }
    }

    private func receive(from connection: NWConnection) async {
        defer { connection.cancel() }
        guard let key else { return }

        do {
            let header = try await Self.read(connection, exactly: 4)
            let length = Int(header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard length > 0, length <= PairingWire.maximumMessageBytes else {
                await send(PairingWire.refused, over: connection)
                return
            }
            let sealed = try await Self.read(connection, exactly: length)
            let payload = try PairingCipher.open(sealed, with: key)
            await send(PairingWire.accepted, over: connection)
            finish(.success(payload))
            listener?.cancel()
            listener = nil
        } catch {
            await send(PairingWire.refused, over: connection)
        }
    }

    private func send(_ byte: UInt8, over connection: NWConnection) async {
        await withCheckedContinuation { continuation in
            connection.send(
                content: Data([byte]),
                completion: .contentProcessed { _ in continuation.resume() }
            )
        }
    }

    static func read(_ connection: NWConnection, exactly count: Int) async throws -> Data {
        var collected = Data()
        while collected.count < count {
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: count - collected.count
                ) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: PairingError.transport(error.localizedDescription))
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: PairingError.transport("closed early"))
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
            guard !chunk.isEmpty else { throw PairingError.transport("closed early") }
            collected.append(chunk)
        }
        return collected
    }

    /// The address to put in the code. Wi-Fi first, because that is how a television
    /// is on the network in most homes, then wired.
    static func localAddress() -> String? {
        var addresses: [String: String] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }
            let address = String(cString: host)
            if address != "127.0.0.1" { addresses[name] = address }
        }

        return addresses["en0"] ?? addresses["en1"] ?? addresses.values.sorted().first
    }
}

/// The phone's side: hands the sealed message over and waits to hear it opened.
public enum PairingSender {
    public static func send(_ payload: PairingPayload, to invitation: PairingInvitation) async throws {
        let sealed = try PairingCipher.seal(payload, with: invitation.key)
        let connection = NWConnection(
            host: NWEndpoint.Host(invitation.host),
            port: NWEndpoint.Port(rawValue: invitation.port) ?? .any,
            using: .tcp
        )
        defer { connection.cancel() }

        try await waitUntilReady(connection)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: PairingWire.frame(sealed),
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: PairingError.transport(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            )
        }

        let answer = try await PairingReceiver.read(connection, exactly: 1)
        guard answer.first == PairingWire.accepted else { throw PairingError.wrongKey }
    }

    /// The handler goes on before the connection is started. Installed afterwards it
    /// can miss the state it was waiting for, and the send hangs for ever.
    private static func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            connection.stateUpdateHandler = { state in
                let shouldResume = resumed.withLock { already -> Bool in
                    guard !already else { return false }
                    switch state {
                    case .ready, .failed, .cancelled, .waiting: already = true; return true
                    default: return false
                    }
                }
                guard shouldResume else { return }
                switch state {
                case .ready: continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: PairingError.transport(error.localizedDescription))
                // Nothing listening at that address leaves the connection *waiting*
                // rather than failed, and it retries for ever. For a code that was on
                // screen a moment ago, that is a wrong address, not a slow one.
                case .waiting(let error):
                    continuation.resume(throwing: PairingError.transport(error.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: PairingError.transport("cancelled"))
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}
