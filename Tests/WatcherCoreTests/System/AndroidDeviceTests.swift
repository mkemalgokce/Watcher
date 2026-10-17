import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct AndroidDeviceTests {
    @Test
    func parsesAuthorisedDevicesAndDrivesAdb() throws {
        let output = """
        List of devices attached
        emulator-5554          device product:sdk model:sdk_gphone64 device:emu
        R58M123                device usb:1-1 model:Pixel_7 transport_id:2
        ZZZ                    unauthorized usb:1-2
        """
        let devices = AndroidDevice.parse(output)
        #expect(devices.map(\.serial) == ["emulator-5554", "R58M123"])
        try #require(devices.count == 2)
        #expect(devices[0].isEmulator); #expect(devices[1].model == "Pixel_7")
        #expect(devices[0].proxyEndpoint(port: 9090, lanAddress: "1.2.3.4") == "10.0.2.2:9090")
        #expect(devices[1].proxyEndpoint(port: 9090, lanAddress: "1.2.3.4") == "1.2.3.4:9090")
        #expect(devices[1].proxyEndpoint(port: 9090, lanAddress: nil) == nil)
        let calls = LockedBox<[[String]]>([])
        try devices[1].setProxy("1.2.3.4:9090") { calls.mutate($0); return "" }
        try devices[1].setProxy(nil) { calls.mutate($0); return "" }
        try devices[1].pushCertificate(URL(fileURLWithPath: "/c.pem")) { calls.mutate($0); return "" }
        try #require(calls.value.count == 3)
        #expect(calls.value[0].suffix(2) == ["http_proxy", "1.2.3.4:9090"]); #expect(calls.value[1].last == ":0")
        #expect(calls.value[2] == ["-s", "R58M123", "push", "/c.pem", "/sdcard/Download/watcher-ca.cer"])
    }
}
