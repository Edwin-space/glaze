import Foundation
import Testing
@testable import GlazeCore

@Suite("A server that signs its own certificate can be trusted, once, on purpose")
struct ServerTrustTests {
    private func store() -> ServerTrustStore {
        ServerTrustStore(defaults: UserDefaults(suiteName: "trust-\(UUID().uuidString)")!)
    }

    @Test("Nothing is trusted until someone says so")
    func startsEmpty() {
        #expect(store().acceptedFingerprint(for: "nas.local") == nil)
    }

    @Test("Accepting pins that one certificate for that one host")
    func accepts() {
        let store = self.store()
        store.accept(ServerCertificate(host: "NAS.local", fingerprint: "AA:BB", summary: "synology"))

        // Hosts are compared without case; certificates are not.
        #expect(store.acceptedFingerprint(for: "nas.local") == "AA:BB")
        #expect(store.acceptedFingerprint(for: "other.local") == nil)
    }

    /// The point of pinning: the NAS being replaced, or something pretending to be it,
    /// presents a different certificate and has to be asked about again.
    @Test("A different certificate on the same host is not covered")
    func doesNotCoverADifferentCertificate() {
        let store = self.store()
        store.accept(ServerCertificate(host: "nas.local", fingerprint: "AA:BB", summary: ""))
        #expect(store.acceptedFingerprint(for: "nas.local") != "CC:DD")
    }

    @Test("Trust can be withdrawn")
    func forgets() {
        let store = self.store()
        store.accept(ServerCertificate(host: "nas.local", fingerprint: "AA:BB", summary: ""))
        store.forget(host: "nas.local")
        #expect(store.acceptedFingerprint(for: "nas.local") == nil)
    }
}
