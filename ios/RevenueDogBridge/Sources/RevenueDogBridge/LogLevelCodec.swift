//
//  LogLevelCodec.swift
//  通道日志级别串 ↔ 原生 `LogLevel`（设计 §5 `setLogLevel` / §5.7 `Purchases-LogHandlerEvent`）。
//  通道值 `verbose|debug|info|warn|error`（= Dart `LogLevel.name`）。
//  对照 RC：hybrid-common 用大写名（`VERBOSE` …）且 Dart 按名字映射；我方统一小写（D2），未知值由调用方处理。
//

import Foundation
import RevenueDog

public enum LogLevelCodec {

    /// 通道串 → 原生级别；未知 → nil（调用方决定报什么码）。
    public static func logLevel(from wire: String) -> LogLevel? {
        switch wire {
        case "verbose": return .verbose
        case "debug": return .debug
        case "info": return .info
        case "warn": return .warn
        case "error": return .error
        default: return nil
        }
    }

    /// 原生级别 → 通道串；`off` / 未知 → nil（不推事件，§5.7「off 不推」）。
    public static func wire(from level: LogLevel) -> String? {
        switch level {
        case .verbose: return "verbose"
        case .debug: return "debug"
        case .info: return "info"
        case .warn: return "warn"
        case .error: return "error"
        default: return nil
        }
    }
}
