import CryptoKit
import Foundation
import Testing
@testable import GlazeCore

@Suite("The server actually crosses to the other device", .serialized)
struct PairingTransportTests {
    private let payload = PairingPayload(
        name: "집",
        server: .webDAV(
            rootURL: URL(string: "https://nas.example.com:5006/video")!,
            username: "someone",
            password: "a password",
            libraryPath: "/video/Media"
        )
    )

    @Test("What the phone sends is what the television receives", .timeLimit(.minutes(1)))
    func carriesTheServerAcross() async throws {
        let receiver = PairingReceiver()
        // Every test shuts the listener down; a live one keeps the test process from
        // exiting long after the assertions have passed.
        defer { Task { await receiver.stop() } }
        let invitation = try await receiver.start()

        async let received = receiver.waitForServer()
        // The television prints its own address in the code; a test has to reach it
        // over loopback rather than whatever Wi-Fi says.
        let overLoopback = PairingInvitation(
            host: "127.0.0.1", port: invitation.port, key: invitation.key
        )
        try await PairingSender.send(payload, to: overLoopback)

        #expect(try await received == payload)
    }

    @Test("A code from another television is turned away", .timeLimit(.minutes(1)))
    func refusesTheWrongKey() async throws {
        let receiver = PairingReceiver()
        defer { Task { await receiver.stop() } }
        let invitation = try await receiver.start()
        async let received = receiver.waitForServer()

        let wrong = PairingInvitation(
            host: "127.0.0.1", port: invitation.port, key: PairingInvitation.makeKey()
        )
        // Specifically refused rather than merely failing: the television opened the
        // message, could not, and said so.
        await #expect(throws: PairingError.wrongKey) {
            try await PairingSender.send(payload, to: wrong)
        }

        await receiver.stop()
        _ = try? await received
    }

    @Test("A code pointing nowhere fails instead of waiting for ever", .timeLimit(.minutes(1)))
    func refusesAnAddressWithNothingThere() async throws {
        // Network.framework leaves such a connection *waiting* and retries silently;
        // for a code that was on screen a moment ago that is a wrong address.
        let nowhere = PairingInvitation(host: "127.0.0.1", port: 1, key: PairingInvitation.makeKey())
        await #expect(throws: PairingError.self) {
            try await PairingSender.send(payload, to: nowhere)
        }
    }

    @Test("There is an address to put in the code")
    func findsALocalAddress() {
        // Nothing to pair with if the television cannot say where it is.
        #expect(PairingReceiver.localAddress() != nil)
    }
}
