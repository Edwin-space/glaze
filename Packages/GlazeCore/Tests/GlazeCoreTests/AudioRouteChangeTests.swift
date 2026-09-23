import GlazeCore
import Testing

@Suite("When the headphones come out")
struct AudioRouteChangeTests {
    @Test("Taking AirPods out stops the film")
    func pausesWhenBluetoothGoesAway() {
        #expect(
            AudioRouteChange.shouldPause(
                reasonIsDeviceUnavailable: true,
                previousOutputs: ["BluetoothA2DPOutput"]
            )
        )
    }

    @Test("So does pulling a cable")
    func pausesWhenHeadphonesAreUnplugged() {
        #expect(
            AudioRouteChange.shouldPause(
                reasonIsDeviceUnavailable: true,
                previousOutputs: ["Headphones"]
            )
        )
    }

    @Test("Plugging something in does not")
    func keepsPlayingWhenSomethingArrives() {
        #expect(
            AudioRouteChange.shouldPause(
                reasonIsDeviceUnavailable: false,
                previousOutputs: ["Speaker"]
            ) == false
        )
    }

    @Test("A speaker that goes away is not someone taking headphones out")
    func ignoresTheSpeaker() {
        #expect(
            AudioRouteChange.shouldPause(
                reasonIsDeviceUnavailable: true,
                previousOutputs: ["Speaker"]
            ) == false
        )
    }
}
