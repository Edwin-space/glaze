import GlazeCore
import XCTest

final class UPnPParsingTests: XCTestCase {
    func testParsesSSDPMediaServerResponse() throws {
        let packet = Data("""
        HTTP/1.1 200 OK\r
        LOCATION: http://192.168.0.20:5000/description.xml\r
        ST: urn:schemas-upnp-org:device:MediaServer:1\r
        USN: uuid:synology::urn:schemas-upnp-org:device:MediaServer:1\r
        SERVER: Synology/DSM UPnP/1.0\r
        \r
        """.utf8)

        let response = try XCTUnwrap(UPnPSSDP.parseResponse(packet))
        XCTAssertEqual(response.location.absoluteString, "http://192.168.0.20:5000/description.xml")
        XCTAssertEqual(response.uniqueServiceName, "uuid:synology::urn:schemas-upnp-org:device:MediaServer:1")
    }

    func testParsesContentDirectoryControlURL() throws {
        let data = Data("""
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <friendlyName>Living Room NAS</friendlyName>
            <UDN>uuid:nas-1</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
                <controlURL>/MediaServer/ContentDirectory/control</controlURL>
              </service>
            </serviceList>
          </device>
        </root>
        """.utf8)
        let descriptionURL = try XCTUnwrap(URL(string: "http://192.168.0.20:5000/description.xml"))

        let server = try XCTUnwrap(
            UPnPDeviceDescriptionParser.parse(
                data: data,
                descriptionURL: descriptionURL,
                fallbackID: "fallback"
            )
        )

        XCTAssertEqual(server.id, "uuid:nas-1")
        XCTAssertEqual(server.friendlyName, "Living Room NAS")
        XCTAssertEqual(
            server.contentDirectoryControlURL.absoluteString,
            "http://192.168.0.20:5000/MediaServer/ContentDirectory/control"
        )
    }

    func testParsesDIDLLiteContainersAndVideoResources() throws {
        let data = Data("""
        <?xml version="1.0"?>
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
          <container id="10" parentID="0" childCount="2">
            <dc:title>Movies</dc:title>
            <upnp:class>object.container</upnp:class>
          </container>
          <item id="11" parentID="10">
            <dc:title>Sample Movie</dc:title>
            <upnp:class>object.item.videoItem.movie</upnp:class>
            <res protocolInfo="http-get:*:video/x-matroska:*" size="123456" duration="01:02:03.500">http://192.168.0.20:5000/video/11</res>
          </item>
        </DIDL-Lite>
        """.utf8)

        let nodes = DIDLLiteParser.parse(data: data, serverID: "uuid:nas-1")
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].kind, .container(childCount: 2))

        guard case .video(let resource) = nodes[1].kind else {
            return XCTFail("Expected a video resource")
        }
        XCTAssertEqual(resource.serverID, "uuid:nas-1")
        XCTAssertEqual(resource.objectID, "11")
        XCTAssertEqual(resource.mimeType, "video/x-matroska")
        XCTAssertEqual(resource.byteCount, 123_456)
        XCTAssertEqual(try XCTUnwrap(resource.duration), 3_723.5, accuracy: 0.001)
    }
}
