import XCTest
import RevenueDog
@testable import RevenueDogBridge

final class LogLevelCodecTests: XCTestCase {

    func testRoundTrip() {
        for name in ["verbose", "debug", "info", "warn", "error"] {
            let level = LogLevelCodec.logLevel(from: name)
            XCTAssertNotNil(level, name)
            XCTAssertEqual(level.flatMap(LogLevelCodec.wire(from:)), name)
        }
    }

    func testUnknownAndOff() {
        XCTAssertNil(LogLevelCodec.logLevel(from: "off"))
        XCTAssertNil(LogLevelCodec.logLevel(from: "VERBOSE"))
        XCTAssertNil(LogLevelCodec.wire(from: .off))
    }
}
