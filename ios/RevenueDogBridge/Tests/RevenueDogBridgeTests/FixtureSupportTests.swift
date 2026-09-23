import XCTest

/// 比较器自身的反例：确保对账不是空转。
final class FixtureSupportTests: XCTestCase {

    func testDeepDiffCatchesMismatches() {
        XCTAssertNil(deepDiff(["a": 1, "b": NSNull()] as [String: Any], ["a": 1, "b": NSNull()] as [String: Any]))
        XCTAssertNotNil(deepDiff(["a": true] as [String: Any], ["a": 1] as [String: Any]))
        XCTAssertNotNil(deepDiff(["a": 1] as [String: Any], ["a": 1, "b": NSNull()] as [String: Any]))
        XCTAssertNotNil(deepDiff([1, 2] as [Any], [2, 1] as [Any]))
        XCTAssertNotNil(deepDiff(["a": NSNull()] as [String: Any], ["a": 0] as [String: Any]))
    }
}
