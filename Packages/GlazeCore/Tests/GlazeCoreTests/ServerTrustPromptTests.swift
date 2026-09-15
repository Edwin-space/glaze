import Foundation
import Testing
@testable import GlazeCore

/// Which advice a refused server gets, decided once for all three apps.
///
/// The phone learned this from a real NAS: a certificate that is perfectly valid for
/// `my-nas.synology.me`, reached by its IP address. Telling that person to "trust the
/// certificate anyway" would teach them to wave away a warning that is telling the
/// truth, when changing the address fixes it properly.
@Suite(.serialized)
struct ServerTrustPromptTests {
    private func store() -> ServerTrustStore {
        ServerTrustStore(defaults: UserDefaults(suiteName: "prompt-\(UUID().uuidString)")!)
    }

    @Test("A certificate issued to another name asks for the address, not for trust")
    func offersTheName() {
        let store = store()
        store.note(refused: ServerCertificate(
            host: "203.0.113.10",
            fingerprint: "AA:BB",
            summary: "my-nas.synology.me",
            certifiedName: "my-nas.synology.me"
        ))
        let prompt = ServerTrustPrompt.forHost("203.0.113.10", store: store)
        #expect(prompt == .useCertifiedName("my-nas.synology.me", ServerCertificate(
            host: "203.0.113.10",
            fingerprint: "AA:BB",
            summary: "my-nas.synology.me",
            certifiedName: "my-nas.synology.me"
        )))
    }

    @Test("A certificate nobody vouches for is offered for the viewer to judge")
    func offersTheFingerprint() {
        let store = store()
        let certificate = ServerCertificate(host: "nas.local", fingerprint: "11:22", summary: "nas")
        store.note(refused: certificate)
        #expect(ServerTrustPrompt.forHost("nas.local", store: store) == .trustCertificate(certificate))
    }

    /// The failure has to actually be a handshake. Offering to trust a certificate
    /// after a timeout is how people learn to accept warnings that mean nothing.
    @Test("An unrelated failure offers nothing")
    func staysQuietForOtherFailures() {
        let store = store()
        store.note(refused: ServerCertificate(host: "nas.local", fingerprint: "11:22", summary: "nas"))
        let timeout = URLError(.timedOut)
        #expect(ServerTrustPrompt.forHost("nas.local", error: timeout, store: store) == nil)
    }

    @Test("A host nothing was refused for offers nothing")
    func staysQuietForUnknownHosts() {
        #expect(ServerTrustPrompt.forHost("never-seen.local", store: store()) == nil)
    }
}
