import Foundation
import Testing
@testable import GlazeCore

@Suite("What people type becomes an address DSM answers on")
struct SynologyAddressTests {
    @Test("A bare host gets HTTPS and DSM's secure port")
    func bareHost() throws {
        let url = try #require(SynologyAddress.normalised("203.0.113.10"))
        #expect(url.absoluteString == "https://203.0.113.10:5001")
    }

    @Test("A name works the same way")
    func bareName() throws {
        let url = try #require(SynologyAddress.normalised("nas.example.com"))
        #expect(url.absoluteString == "https://nas.example.com:5001")
    }

    @Test("Plain HTTP keeps its own port")
    func plainHTTP() throws {
        let url = try #require(SynologyAddress.normalised("http://192.168.0.20"))
        #expect(url.absoluteString == "http://192.168.0.20:5000")
    }

    @Test("A port that was typed is left alone")
    func explicitPort() throws {
        let url = try #require(SynologyAddress.normalised("https://nas.example.com:7001"))
        #expect(url.absoluteString == "https://nas.example.com:7001")
    }

    @Test("A pasted path is not part of the address of the box")
    func stripsThePath() throws {
        let url = try #require(SynologyAddress.normalised("https://nas.example.com:5001/webman/index.cgi"))
        #expect(url.absoluteString == "https://nas.example.com:5001")
    }

    @Test("Nothing typed gives nothing back")
    func nothing() {
        #expect(SynologyAddress.normalised("   ") == nil)
    }

    @Test("Cleartext to the open internet is flagged, on the home network is not")
    func flagsCleartextOutside() throws {
        let outside = try #require(SynologyAddress.normalised("http://203.0.113.10"))
        #expect(SynologyAddress.needsHTTPS(outside))

        for local in ["http://192.168.0.20", "http://10.0.1.5", "http://nas.local", "http://172.20.3.4"] {
            let url = try #require(SynologyAddress.normalised(local))
            #expect(!SynologyAddress.needsHTTPS(url), "\(local) is on the home network")
        }
    }
}
