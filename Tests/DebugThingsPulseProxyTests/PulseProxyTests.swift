import Foundation
import Testing

@testable import DebugThingsPulseProxy

@Suite("DebugThingsPulseProxy", .serialized)
struct PulseProxyTests {

    @Test
    func pulseNetworkCaptureSettingsMapsToConfiguration() {
        let settings = PulseNetworkCaptureSettings(
            label: "network",
            isWaitingForDecoding: true,
            includedHosts: ["api.example.com"],
            includedURLs: ["/v1/**"],
            excludedHosts: ["cdn.example.com"],
            excludedURLs: ["/v1/stream/**"],
            sensitiveHeaders: ["Authorization"],
            sensitiveQueryItems: ["token"],
            sensitiveDataFields: ["password"],
            isRegexEnabled: true
        )
        let configuration = settings.networkLoggerConfiguration()
        #expect(configuration.label == "network")
        #expect(configuration.isWaitingForDecoding == true)
        #expect(configuration.includedHosts == Set(["api.example.com"]))
        #expect(configuration.includedURLs == Set(["/v1/**"]))
        #expect(configuration.excludedHosts == Set(["cdn.example.com"]))
        #expect(configuration.excludedURLs == Set(["/v1/stream/**"]))
        #expect(configuration.sensitiveHeaders == Set(["Authorization"]))
        #expect(configuration.sensitiveQueryItems == Set(["token"]))
        #expect(configuration.sensitiveDataFields == Set(["password"]))
        #expect(configuration.isRegexEnabled == true)
    }

    @Test
    func streamingDetectionRecognizesSSEHeader() throws {
        let url = try #require(URL(string: "https://example.com/events"))
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream; charset=utf-8"]
            )
        )
        #expect(URLSessionTaskLoggerStreamingDetection.responseIndicatesSSEOrMJPEG(response))
    }

    @Test
    func streamingDetectionRecognizesMultipartMJPEG() throws {
        let url = try #require(URL(string: "https://example.com/camera"))
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "multipart/x-mixed-replace; boundary=foo"]
            )
        )
        #expect(URLSessionTaskLoggerStreamingDetection.responseIndicatesSSEOrMJPEG(response))
    }

    @Test
    func applyToSharedNetworkLoggerRuns() {
        var settings = PulseNetworkCaptureSettings.default
        settings.excludedHosts.insert("example.invalid")
        settings.applyToSharedNetworkLogger()
        print("[PulseProxyTests] applied PulseNetworkCaptureSettings to NetworkLogger.shared")
    }
}
