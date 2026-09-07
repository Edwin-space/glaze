import CryptoKit
import Foundation
import Testing
@testable import GlazeCore

@Suite("Handing a server from the phone to the television")
struct DevicePairingTests {
    private let payload = PairingPayload(
        name: "집",
        server: .synology(
            baseURL: URL(string: "https://nas.example.com:5001")!,
            account: "someone",
            password: "a password",
            libraryPath: "/video"
        )
    )

    @Test("What is sealed comes back the same")
    func roundTrips() throws {
        let key = PairingInvitation.makeKey()
        let sealed = try PairingCipher.seal(payload, with: key)
        #expect(try PairingCipher.open(sealed, with: key) == payload)
    }

    @Test("The password is not readable in what crosses the network")
    func passwordIsNotInTheClear() throws {
        let key = PairingInvitation.makeKey()
        let sealed = try PairingCipher.seal(payload, with: key)
        let asText = String(decoding: sealed, as: UTF8.self)
        #expect(!asText.contains("a password"))
        #expect(!asText.contains("someone"))
    }

    @Test("Another television's key opens nothing")
    func wrongKeyIsRefused() throws {
        let sealed = try PairingCipher.seal(payload, with: PairingInvitation.makeKey())
        #expect(throws: PairingError.wrongKey) {
            _ = try PairingCipher.open(sealed, with: PairingInvitation.makeKey())
        }
    }

    @Test("A tampered message is refused rather than half-read")
    func tamperingIsRefused() throws {
        let key = PairingInvitation.makeKey()
        var sealed = try PairingCipher.seal(payload, with: key)
        sealed[sealed.count - 1] ^= 0xFF
        #expect(throws: PairingError.wrongKey) {
            _ = try PairingCipher.open(sealed, with: key)
        }
    }

    @Test("The code on the screen reads back as what it was")
    func invitationRoundTrips() throws {
        let invitation = PairingInvitation(
            host: "192.168.0.31", port: 51_234, key: PairingInvitation.makeKey()
        )
        let read = try #require(PairingInvitation(encoded: invitation.encoded))
        #expect(read.host == invitation.host)
        #expect(read.port == invitation.port)
        #expect(read.key == invitation.key)
    }

    @Test("Anything else scanned is not a pairing code")
    func rejectsOtherCodes() {
        for text in ["https://example.com", "glaze-pair:only:two", "", "glaze-pair:h:0:short"] {
            #expect(PairingInvitation(encoded: text) == nil, "\(text) is not a pairing code")
        }
    }

    @Test("The code stays short enough for a camera across a room")
    func codeStaysShort() {
        let invitation = PairingInvitation(
            host: "192.168.100.200", port: 65_535, key: PairingInvitation.makeKey()
        )
        // Well inside what a QR can hold at a low density.
        #expect(invitation.encoded.count < 80)
    }
}
