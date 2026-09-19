import GlazeCore
import Testing

@Suite("Building a Synology address from a host name and a DDNS domain")
struct SynologyAddressComposeTests {
    @Test("A host name and a domain become an https address on DSM's port")
    func composesTheUsualCase() {
        let url = SynologyAddress.compose(hostName: "my-nas", domain: "synology.me")
        #expect(url?.absoluteString == "https://my-nas.synology.me:5001")
    }

    @Test("Pasting the whole name in the name box does not double the domain")
    func doesNotRepeatTheDomain() {
        let url = SynologyAddress.compose(hostName: "my-nas.synology.me", domain: "synology.me")
        #expect(url?.absoluteString == "https://my-nas.synology.me:5001")
    }

    @Test("A pasted address keeps its own host, scheme and port")
    func acceptsSomethingAlreadyComplete() {
        let url = SynologyAddress.compose(hostName: "http://192.168.0.9:5000", domain: "")
        #expect(url?.absoluteString == "http://192.168.0.9:5000")
    }

    @Test("Nothing typed is not an address")
    func rejectsAnEmptyName() {
        #expect(SynologyAddress.compose(hostName: "  ", domain: "synology.me") == nil)
    }

    @Test("Stray spaces and a trailing dot are the typist's, not the address's")
    func trimsWhatPeopleType() {
        let url = SynologyAddress.compose(hostName: " My-NAS. ", domain: "synology.me")
        #expect(url?.absoluteString == "https://my-nas.synology.me:5001")
    }
}
