// 错误码生成脚本（D4，设计 §1 #31）。
//
// 用法（在 sdk/flutter 目录下）：
//   dart run scripts/gen_error_codes.dart          # 重写 lib/src/generated/error_codes.dart
//   dart run scripts/gen_error_codes.dart --check  # 只比对，不一致时退出码 1
//
// 输入：../error-codes.json（我方错误码唯一真相源）+ 下方内置的 RC PurchasesErrorCode 有序名表。
// 输出：enum PurchasesErrorCode（RC 43 值原序 + 我方 900+ 按码位升序追加）、
//       purchasesErrorCodeByNumber（码 → 枚举，按 name 对齐查表，禁下标）、
//       readableErrorCodeByNumber（码 → PascalCase，原生插件 details.readableErrorCode 的对照表）。
//
// 对照 RC：RC 的 lib/src/generated/error_codes.dart 由 purchases-error-codes 仓库生成、
// getErrorCode 按枚举下标取值；偏离：我方按码位查表（900+ 专有码必须对宿主可见，D4）。
import 'dart:convert';
import 'dart:io';

/// RC purchases-flutter 10.13.1 `lib/src/generated/error_codes.dart` 的枚举名，下标 = 码位（0–42）。
/// 顺序即契约（宿主穷尽 switch 与 RC 源码兼容），只能照 RC 追加，不能改动。
const List<String> rcPurchasesErrorCodeNames = [
  'unknownError', // 0
  'purchaseCancelledError', // 1
  'storeProblemError', // 2
  'purchaseNotAllowedError', // 3
  'purchaseInvalidError', // 4
  'productNotAvailableForPurchaseError', // 5
  'productAlreadyPurchasedError', // 6
  'receiptAlreadyInUseError', // 7
  'invalidReceiptError', // 8
  'missingReceiptFileError', // 9
  'networkError', // 10
  'invalidCredentialsError', // 11
  'unexpectedBackendResponseError', // 12
  'receiptInUseByOtherSubscriberError', // 13
  'invalidAppUserIdError', // 14
  'operationAlreadyInProgressError', // 15
  'unknownBackendError', // 16
  'invalidAppleSubscriptionKeyError', // 17
  'ineligibleError', // 18
  'insufficientPermissionsError', // 19
  'paymentPendingError', // 20
  'invalidSubscriberAttributesError', // 21
  'logOutWithAnonymousUserError', // 22
  'configurationError', // 23
  'unsupportedError', // 24
  'emptySubscriberAttributesError', // 25
  'productDiscountMissingIdentifierError', // 26
  'unknownNonNativeError', // 27
  'productDiscountMissingSubscriptionGroupIdentifierError', // 28
  'customerInfoError', // 29
  'systemInfoError', // 30
  'beginRefundRequestError', // 31
  'productRequestTimeout', // 32
  'apiEndpointBlocked', // 33
  'invalidPromotionalOfferError', // 34
  'offlineConnectionError', // 35
  'featureNotAvailableInCustomEntitlementsComputationMode', // 36
  'signatureVerificationFailed', // 37
  'featureNotSupportedWithStoreKit1', // 38
  'invalidWebPurchaseToken', // 39
  'purchaseBelongsToOtherUser', // 40
  'expiredWebPurchaseToken', // 41
  'testStoreSimulatedPurchaseError', // 42
];

/// 我方专有码位下限（error-codes.json 纪律 4）。
const int revdogOwnCodeFloor = 900;

/// 枚举名 → readableErrorCode（首字母大写，如 `PurchaseCancelledError`）。
String readableFromName(String name) => name[0].toUpperCase() + name.substring(1);

/// 由 error-codes.json 的内容生成 Dart 源码。纯函数：测试重新生成到内存与已提交文件逐字比对。
///
/// 码 → 枚举**按 name 对齐，不按下标**（主代理裁定）：
/// - json 里的每个码，用它的 `name` 在 RC 枚举名或我方追加名里找同名值；
/// - json 里没有的码位（RC 占用、我方未采用），0–42 按 RC 下标填；
/// - 因此我方 28 `customerInfoError` / 29 `systemInfoError` 与 RC 下标错位是有意的：
///   `e.code` 仍是我方数字，`getErrorCode` 得到正确语义。
///
/// 校验（任一不符即抛 [StateError]，生成失败即门禁红）：
/// - json 中 43–899 的码不允许出现（RC 未占的中间段不归我方）；
/// - 900+ 名字不得与 RC 名冲突（它们作为新枚举值追加）；
/// - 0–42 的 json 名字必须是 RC 枚举名之一。
String generateErrorCodesSource(Map<String, dynamic> json) {
  final codes = (json['codes'] as List).cast<Map<String, dynamic>>();
  final own = <int, String>{};
  final byNumber = <int, String>{
    for (var i = 0; i < rcPurchasesErrorCodeNames.length; i++) i: rcPurchasesErrorCodeNames[i],
  };
  final misaligned = <int, String>{};
  for (final entry in codes) {
    final code = entry['code'] as int;
    final name = entry['name'] as String;
    if (code < rcPurchasesErrorCodeNames.length) {
      if (!rcPurchasesErrorCodeNames.contains(name)) {
        throw StateError('error-codes.json 码 $code 的名字 $name 不在 RC 枚举名里');
      }
      if (rcPurchasesErrorCodeNames[code] != name) misaligned[code] = name;
      byNumber[code] = name;
    } else if (code >= revdogOwnCodeFloor) {
      if (rcPurchasesErrorCodeNames.contains(name)) {
        throw StateError('我方码 $code 的名字 $name 与 RC 名冲突');
      }
      own[code] = name;
    } else {
      throw StateError('error-codes.json 码 $code 落在 RC 未占且非我方专有的区间（43–899）');
    }
  }
  final ownCodes = own.keys.toList()..sort();
  for (final code in ownCodes) {
    byNumber[code] = own[code]!;
  }
  final numbers = byNumber.keys.toList()..sort();

  final b = StringBuffer()
    ..writeln('// 自动生成，勿手改。')
    ..writeln('// 生成脚本：scripts/gen_error_codes.dart；输入：sdk/error-codes.json（version ${json['version']}）+ RC 10.13.1 名表。')
    ..writeln('// 修改流程：改 sdk/error-codes.json → 在 sdk/flutter 下 `dart run scripts/gen_error_codes.dart`。')
    ..writeln('//')
    ..writeln('// 码 → 枚举按 name 对齐，不按下标：json 里的码按其 name 取同名枚举值，json 没有的码位按 RC 下标填。')
    ..writeln('// 28/29 与 RC 下标错位是有意的（主代理裁定）：e.code 仍是我方数字，getErrorCode 得到正确语义。');
  for (final e in misaligned.entries) {
    b.writeln('//   ${e.key}: 我方 ${e.value}（RC 下标 ${e.key} 为 ${rcPurchasesErrorCodeNames[e.key]}）');
  }
  b
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln('/// 错误码枚举：RC `PurchasesErrorCode` 43 值原序（0–42）+ 我方专有码按码位升序追加（D4）。')
    ..writeln('///')
    ..writeln('/// 对照 RC：值集与顺序逐字同形。偏离：码位 → 枚举走 [purchasesErrorCodeByNumber] 按 name 显式查表，')
    ..writeln('/// 不按下标（900+ 不在下标范围内；我方 28/29 与 RC 下标错位）。')
    ..writeln('enum PurchasesErrorCode {');
  for (var i = 0; i < rcPurchasesErrorCodeNames.length; i++) {
    b.writeln('  ${rcPurchasesErrorCodeNames[i]}, // RC $i');
  }
  for (final code in ownCodes) {
    b.writeln('  ${own[code]}, // $code（我方专有）');
  }
  b
    ..writeln('}')
    ..writeln()
    ..writeln('/// 码位 → 枚举。json 里的码按 name 对齐，json 没有的 0–42 码位按 RC 下标。')
    ..writeln('///')
    ..writeln('/// 路径专用映射（裁定 6，不在本表体现）：原生 logOut 路径的我方 14 `invalidAppUserIdError`')
    ..writeln('/// 由原生插件改报 22（`logOutWithAnonymousUserError`，readable `LogOutWithAnonymousUserError`，')
    ..writeln('/// `details.revdogCode` 仍为 `invalidAppUserIdError`），只在 logOut 路径生效。')
    ..writeln('const Map<int, PurchasesErrorCode> purchasesErrorCodeByNumber = {');
  for (final n in numbers) {
    b.writeln('  $n: PurchasesErrorCode.${byNumber[n]},');
  }
  b
    ..writeln('};')
    ..writeln()
    ..writeln('/// 码位 → `details.readableErrorCode` / `details.readable_error_code`（最终枚举名首字母大写）。')
    ..writeln('/// 原生插件两端按此表填值（D4：两端同值）；Dart 只用于测试与文档。')
    ..writeln('const Map<int, String> readableErrorCodeByNumber = {');
  for (final n in numbers) {
    b.writeln("  $n: '${readableFromName(byNumber[n]!)}',");
  }
  b.writeln('};');
  return b.toString();
}

/// 相对 sdk/flutter 的路径。
const String errorCodesJsonPath = '../error-codes.json';
const String generatedErrorCodesPath = 'lib/src/generated/error_codes.dart';

void main(List<String> args) {
  final json = jsonDecode(File(errorCodesJsonPath).readAsStringSync()) as Map<String, dynamic>;
  final source = generateErrorCodesSource(json);
  final target = File(generatedErrorCodesPath);
  if (args.contains('--check')) {
    final current = target.existsSync() ? target.readAsStringSync() : '';
    if (current != source) {
      stderr.writeln('$generatedErrorCodesPath 与 error-codes.json 不一致，请重新生成');
      exitCode = 1;
      return;
    }
    stdout.writeln('ok: $generatedErrorCodesPath 与 error-codes.json 一致');
    return;
  }
  target.writeAsStringSync(source);
  stdout.writeln('wrote $generatedErrorCodesPath');
}
