//
//  LogInResultMapper.swift
//  `logIn` 结果 → wire `{created, customerInfo}`（设计 §5.5，fixture `wire/log-in-result.json`）。
//  对照 RC：hybrid-common `logIn` 回 `{customerInfo, created}`，键名照抄。
//

import Foundation
import RevenueDog

public enum LogInResultMapper {

    public static func map(customerInfo: CustomerInfo, created: Bool, now: Date) throws -> CustomerInfoMapper.Result {
        let mapped = try CustomerInfoMapper.map(customerInfo, now: now)
        return (map: ["created": created, "customerInfo": mapped.map], fallbacks: mapped.fallbacks)
    }
}
