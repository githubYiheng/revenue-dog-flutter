//
//  FixtureSupport.swift
//  读共享 fixture（`sdk/flutter/test/fixtures`，三方对账）+ 严格深度比较。
//

import Foundation
import XCTest
import RevenueDogBridge

enum Fixtures {

    /// `#filePath` = …/sdk/flutter/ios/RevenueDogBridge/Tests/RevenueDogBridgeTests/FixtureSupport.swift
    /// → 上溯 5 级到 `sdk/flutter`，再进 `test/fixtures`。
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("test/fixtures", isDirectory: true)
    }()

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    static func json(_ relativePath: String) throws -> Any {
        try JSONSerialization.jsonObject(with: data(relativePath), options: [.fragmentsAllowed])
    }

    static func files(in directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
    }
}

/// 严格深度比较：字典键集、数组顺序、NSNull、Bool 与数字**不互通**（NSNumber 的 `isEqual` 会把 true 与 1 视为相等）。
/// 返回第一处差异的路径说明；相等返回 nil。
func deepDiff(_ actual: Any, _ expected: Any, path: String = "$") -> String? {
    switch (actual, expected) {
    case (is NSNull, is NSNull):
        return nil
    case let (a as [String: Any], e as [String: Any]):
        let aKeys = Set(a.keys), eKeys = Set(e.keys)
        if aKeys != eKeys {
            return "\(path): keys differ; extra=\(aKeys.subtracting(eKeys).sorted()) missing=\(eKeys.subtracting(aKeys).sorted())"
        }
        for key in aKeys.sorted() {
            if let diff = deepDiff(a[key]!, e[key]!, path: "\(path).\(key)") { return diff }
        }
        return nil
    case let (a as [Any], e as [Any]):
        guard a.count == e.count else { return "\(path): count \(a.count) != \(e.count)" }
        for (index, pair) in zip(a, e).enumerated() {
            if let diff = deepDiff(pair.0, pair.1, path: "\(path)[\(index)]") { return diff }
        }
        return nil
    case let (a as String, e as String):
        return a == e ? nil : "\(path): \"\(a)\" != \"\(e)\""
    case let (a as NSNumber, e as NSNumber):
        let aIsBool = isBool(a), eIsBool = isBool(e)
        guard aIsBool == eIsBool else { return "\(path): bool/number mismatch \(a) vs \(e)" }
        if aIsBool { return a.boolValue == e.boolValue ? nil : "\(path): \(a.boolValue) != \(e.boolValue)" }
        return a.int64Value == e.int64Value && a.doubleValue == e.doubleValue ? nil : "\(path): \(a) != \(e)"
    default:
        return "\(path): type mismatch \(type(of: actual)) (\(actual)) vs \(type(of: expected)) (\(expected))"
    }
}

private func isBool(_ number: NSNumber) -> Bool {
    CFGetTypeID(number) == CFBooleanGetTypeID()
}

/// Bridge 产出（`[String: Any?]`）→ 真机同款通道值（nil → NSNull）→ 经一次 JSON 往返归一成 Foundation 类型。
func channelNormalized(_ map: [String: Any?]) throws -> Any {
    let channel = WireCodec.channelValue(map)
    let data = try JSONSerialization.data(withJSONObject: channel, options: [.sortedKeys])
    return try JSONSerialization.jsonObject(with: data)
}
