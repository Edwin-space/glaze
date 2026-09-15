import CryptoKit
import Foundation
import Security

/// A certificate a server presented that the system would not vouch for.
public struct ServerCertificate: Sendable, Equatable {
    public let host: String
    /// SHA-256 of the leaf certificate, in the grouped hex people compare by eye.
    public let fingerprint: String
    /// What the certificate calls itself, for the person deciding.
    public let summary: String
    /// Set when the certificate is **perfectly good** — signed by a real authority,
    /// in date, chaining to a root the system trusts — and issued to this name rather
    /// than the address that was typed.
    ///
    /// A Synology reached over the internet is almost always this case: DSM gets a
    /// free Let's Encrypt certificate for its `*.synology.me` name, and someone types
    /// the IP address it resolves to. Nothing is wrong with the NAS, and pinning the
    /// certificate would be the wrong answer — the right one is to use its name.
    public let certifiedName: String?

    public init(host: String, fingerprint: String, summary: String, certifiedName: String? = nil) {
        self.host = host
        self.fingerprint = fingerprint
        self.summary = summary
        self.certifiedName = certifiedName
    }
}

/// Which servers the viewer has decided to trust anyway.
///
/// A NAS out of the box signs its own certificate. Nothing in the world vouches for
/// it, so `URLSession` refuses the connection — which is correct, and which is why
/// a home Synology cannot be reached at all without this. The way out is not to
/// disable checking; it is to let the person look at the certificate once and say
/// "yes, that is my NAS", and then pin **that exact certificate**. A different one
/// later is refused again, which is the whole point.
public final class ServerTrustStore: @unchecked Sendable {
    public static let shared = ServerTrustStore()

    private let defaults: UserDefaults
    private let acceptedKey = "network.trustedCertificates"
    private let lock = NSLock()
    /// The last certificate refused for a host, so the screen that failed can offer
    /// it to the viewer rather than making them go and find it.
    private var refusals: [String: ServerCertificate] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func acceptedFingerprint(for host: String) -> String? {
        (defaults.dictionary(forKey: acceptedKey) as? [String: String])?[host.lowercased()]
    }

    public func accept(_ certificate: ServerCertificate) {
        var all = (defaults.dictionary(forKey: acceptedKey) as? [String: String]) ?? [:]
        all[certificate.host.lowercased()] = certificate.fingerprint
        defaults.set(all, forKey: acceptedKey)

        // The refusal has been answered. Left behind, it makes every later failure on
        // this host — a timeout, a wrong port, anything — look like the same
        // certificate problem, and the viewer is asked to trust it again and again.
        lock.lock()
        refusals[certificate.host.lowercased()] = nil
        lock.unlock()
    }

    public func forget(host: String) {
        var all = (defaults.dictionary(forKey: acceptedKey) as? [String: String]) ?? [:]
        guard all.removeValue(forKey: host.lowercased()) != nil else { return }
        defaults.set(all, forKey: acceptedKey)
    }

    public func refused(for host: String) -> ServerCertificate? {
        lock.lock()
        defer { lock.unlock() }
        return refusals[host.lowercased()]
    }

    /// Records what a host presented and would not be trusted for. Called by the
    /// delegate; `internal` so the prompt's decision can be tested without standing up
    /// a TLS server for every case.
    func note(refused certificate: ServerCertificate) {
        lock.lock()
        refusals[certificate.host.lowercased()] = certificate
        lock.unlock()
    }
}

public enum ServerTrust {
    /// What actually went wrong, in enough detail to act on.
    ///
    /// `localizedDescription` for a TLS failure is "An SSL error has occurred and a
    /// secure connection to the server cannot be made" for every cause there is —
    /// a protocol version the system refuses, a certificate it will not chain, a port
    /// that is not speaking TLS at all. Each needs a different thing done about it, so
    /// the codes underneath have to come out.
    public static func detail(_ error: URLError) -> String {
        var parts = [error.localizedDescription, "(\(error.errorCode))"]

        // TLS failures carry the real reason as an OSStatus from Secure Transport.
        if let stream = error.userInfo["_kCFStreamErrorCodeKey"] as? Int, stream != 0 {
            parts.append("tls \(stream)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("\(underlying.domain) \(underlying.code)")
        }
        return parts.joined(separator: " · ")
    }

    /// Whether a failure could have come from the handshake being refused.
    ///
    /// Refusing a challenge surfaces as a bare cancellation, which is why that is in
    /// the list — and why the list has to be a list rather than "any failure".
    public static func mayBeHandshake(_ error: URLError) -> Bool {
        switch error.code {
        case .cancelled,
             .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .serverCertificateUntrusted,
             .clientCertificateRejected,
             .clientCertificateRequired:
            true
        default:
            false
        }
    }
}

/// Answers the server-trust challenge, and only that.
final class ServerTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let store: ServerTrustStore

    init(store: ServerTrustStore) {
        self.store = store
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // A certificate the system is happy with needs no help from us.
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        guard let certificate = Self.leaf(of: trust, host: host) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if store.acceptedFingerprint(for: host) == certificate.fingerprint {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // Remembered rather than accepted: the screen that asked for this connection
        // can now show the viewer what it saw and let them decide.
        store.note(refused: certificate)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private static func leaf(of trust: SecTrust, host: String) -> ServerCertificate? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else { return nil }

        let data = SecCertificateCopyData(leaf) as Data
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
        let summary = (SecCertificateCopySubjectSummary(leaf) as String?) ?? host

        return ServerCertificate(
            host: host,
            fingerprint: digest,
            summary: summary,
            certifiedName: certifiedName(of: chain, whenAskedFor: host)
        )
    }

    /// The name this chain *would* have been trusted for.
    ///
    /// Evaluates the same certificates again against the name printed on them. If that
    /// passes, the only thing wrong with the connection was the address, and the fix is
    /// to use that name — not to override the check.
    private static func certifiedName(of chain: [SecCertificate], whenAskedFor host: String) -> String? {
        guard let leaf = chain.first else { return nil }
        var common: CFString?
        guard SecCertificateCopyCommonName(leaf, &common) == errSecSuccess,
              var name = common as String?
        else { return nil }

        // A wildcard cannot be typed into an address bar. `*.my-nas.synology.me` is
        // no use to anyone; the bare name beneath it usually is, and is covered by the
        // same certificate.
        if name.hasPrefix("*.") { name.removeFirst(2) }
        guard !name.isEmpty, name.caseInsensitiveCompare(host) != .orderedSame else { return nil }

        var candidate: SecTrust?
        guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateSSL(true, name as CFString), &candidate) == errSecSuccess,
              let candidate,
              SecTrustEvaluateWithError(candidate, nil)
        else { return nil }

        return name
    }
}

/// The session every server connection goes through.
public enum NetworkSession {
    /// Behaves exactly like `URLSession.shared` except that a certificate the viewer
    /// has explicitly accepted for a host is allowed through.
    public static let trusting: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        return URLSession(
            configuration: configuration,
            delegate: ServerTrustDelegate(store: .shared),
            delegateQueue: nil
        )
    }()
}
