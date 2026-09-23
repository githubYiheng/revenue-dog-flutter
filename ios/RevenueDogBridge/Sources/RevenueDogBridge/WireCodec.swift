//
//  WireCodec.swift
//  通道 wire 的小工具（设计 §5 总则）：时间 → epoch 毫秒、枚举 → lower_snake_case、nil → NSNull。
//
//  对照 RC：hybrid-common 用 `(date.timeIntervalSince1970 * 1000)` 发毫秒、枚举发名字；
//  我方枚举一律小写串（D2），Dart 未知值落 RC 的 unknown 档。
//

import Foundation
import RevenueDog

public enum WireCodec {

    /// 时间 → epoch 毫秒 `Int`（四舍五入，后端秒精度下无损）。
    public static func millis(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// 可空时间 → 毫秒或 nil（wire 上 nil 键必须在，见 `channelValue`）。
    public static func millis(_ date: Date?) -> Int? {
        date.map { millis($0) }
    }

    /// `Store.rawValue` 原生已小写（`app_store` / `play_store` …），原样发。
    public static func store(_ store: Store) -> String { store.rawValue.lowercased() }

    /// `PeriodType.rawValue` 原生已小写（`normal` / `trial` / `intro` / `prepaid` / `unknown`）。
    public static func periodType(_ type: PeriodType) -> String { type.rawValue.lowercased() }

    /// `OwnershipType.rawValue` 原生是大写（`PURCHASED` / `FAMILY_SHARED` / `UNKNOWN`）→ 小写。
    public static func ownershipType(_ type: OwnershipType) -> String { type.rawValue.lowercased() }

    /// 把 mapper 产出的 `[String: Any?]` 递归转成通道可直接编码的值：`nil` → `NSNull`
    /// （可空键必须在，设计 §5 总则），嵌套字典 / 数组同样处理。
    ///
    /// 插件回 `result(...)` / 反向 `invokeMethod` 前统一过一遍，不依赖 Swift 隐式桥接 Optional 的行为；
    /// Bridge 测试也用同一函数产出「真机同款」的值再与 wire fixture 比较。
    public static func channelValue(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        // `Any` 里可能包着 Optional（来自 `[String: Any?]` 的元素），先拆一层。
        if let optional = value as? OptionalProtocol {
            guard let unwrapped = optional.unwrapped else { return NSNull() }
            return channelValue(unwrapped)
        }
        switch value {
        case let dictionary as [String: Any?]:
            return dictionary.mapValues { channelValue($0) }
        case let dictionary as [String: Any]:
            return dictionary.mapValues { channelValue($0) }
        case let array as [Any?]:
            return array.map { channelValue($0) }
        case let array as [Any]:
            return array.map { channelValue($0) }
        default:
            return value
        }
    }
}

/// 拆 `Any` 里包着的 Optional 用。
private protocol OptionalProtocol {
    var unwrapped: Any? { get }
}

extension Optional: OptionalProtocol {
    fileprivate var unwrapped: Any? {
        switch self {
        case .some(let wrapped): return wrapped
        case .none: return nil
        }
    }
}
