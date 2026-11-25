//
//  ReservedAttribute.swift
//  通道方法 `setReservedAttribute {key, value}` 的键表与解析（rc.4，设计 §5.8，ADR 0245）。
//
//  范围 = 服务端广告转发读取的全部保留属性；顺序与 `test/fixtures/wire/reserved-attributes.json` 逐行相同（测试比对）。
//  解析结果 `ReservedAttributeWrite` 每个 case 对应一个原生 setter，插件穷尽 switch 分派（漏一个编译不过）；
//  本文件不碰原生单例。
//

import Foundation

public enum ReservedAttribute: String, CaseIterable, Sendable {
    case email = "$email"
    case phoneNumber = "$phoneNumber"
    case attConsentStatus = "$attConsentStatus"
    case idfa = "$idfa"
    case idfv = "$idfv"
    case fbAnonymousID = "$fbAnonId"
    case firebaseAppInstanceID = "$firebaseAppInstanceId"
    case timezone = "$timezone"
    case adMeasurementConsent = "$adMeasurementConsent"
    case fbCampaignIDs = "$fbCampaignIds"

    public enum ValueKind: String, Sendable {
        case string
        case bool
    }

    public var valueKind: ValueKind {
        self == .adMeasurementConsent ? .bool : .string
    }
}

/// 一次保留属性写入；值为 nil = 删除（空串原样交给原生，原生同样按删除处理）。
public enum ReservedAttributeWrite: Equatable, Sendable {
    case email(String?)
    case phoneNumber(String?)
    case attConsentStatus(String?)
    case idfa(String?)
    case idfv(String?)
    case fbAnonymousID(String?)
    case firebaseAppInstanceID(String?)
    case timezone(String?)
    case adMeasurementConsent(Bool?)
    case fbCampaignIDs(String?)

    /// `{key, value}` → 一次写入。缺键 / 未知键 / 值类型不符 → 码 4（与其它方法的参数错误同口径）。
    /// `value` 为 nil 或 `NSNull` = 删除；bool 只收 CFBoolean（数字 0 / 1 不当 bool 收）。
    public static func parse(key: String?, value: Any?) throws -> ReservedAttributeWrite {
        guard let key else {
            throw BridgeError(.purchaseInvalidError, underlyingMessage: "missing argument key")
        }
        guard let attribute = ReservedAttribute(rawValue: key) else {
            throw BridgeError(.purchaseInvalidError, underlyingMessage: "unknown reserved attribute key \(key)")
        }
        let raw: Any? = (value is NSNull) ? nil : value

        func string() throws -> String? {
            guard let raw else { return nil }
            guard let string = raw as? String else {
                throw BridgeError(.purchaseInvalidError, underlyingMessage: "argument value must be a String for \(key)")
            }
            return string
        }
        func bool() throws -> Bool? {
            guard let raw else { return nil }
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw BridgeError(.purchaseInvalidError, underlyingMessage: "argument value must be a bool for \(key)")
            }
            return number.boolValue
        }

        switch attribute {
        case .email: return .email(try string())
        case .phoneNumber: return .phoneNumber(try string())
        case .attConsentStatus: return .attConsentStatus(try string())
        case .idfa: return .idfa(try string())
        case .idfv: return .idfv(try string())
        case .fbAnonymousID: return .fbAnonymousID(try string())
        case .firebaseAppInstanceID: return .firebaseAppInstanceID(try string())
        case .timezone: return .timezone(try string())
        case .adMeasurementConsent: return .adMeasurementConsent(try bool())
        case .fbCampaignIDs: return .fbCampaignIDs(try string())
        }
    }
}
