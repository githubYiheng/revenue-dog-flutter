import '../wire.dart';
import 'customer_info.dart';

/// `logIn` 的结果。对照 RC：类形状逐字照 RC `LogInResult`（非 Equatable，命名必填构造）。
class LogInResult {
  /// 该 appUserID 是否首次在后端创建。
  final bool created;

  /// 登录后的用户快照。
  final CustomerInfo customerInfo;

  /// 构造。
  LogInResult({required this.created, required this.customerInfo});
}

/// wire `{customerInfo, created}` → [LogInResult]（不导出）。错误路径带 `customerInfo.` 前缀。
LogInResult decodeLogInResult(WireMap w) => LogInResult(
      created: w.requireBool('created'),
      customerInfo: decodeCustomerInfo(w.requireMap('customerInfo')),
    );
