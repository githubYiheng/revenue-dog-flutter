/// 日志级别。对照 RC：值集与顺序逐字照 RC `LogLevel { verbose, debug, info, warn, error }`。
///
/// 通道上发小写名（`verbose|debug|info|warn|error`，设计 §5 方法表）。
/// 偏离：RC 发大写名（`DEBUG`）；我方通道统一小写（D2）。
enum LogLevel { verbose, debug, info, warn, error }
