// 错误码：生成文件一致性 + getErrorCode 逐码 + 错误信封 fixture。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog/revenue_dog.dart';
import 'package:revenue_dog/src/errors.dart';
import 'package:revenue_dog/src/generated/error_codes.dart';

import '../scripts/gen_error_codes.dart' as gen;
import 'helpers.dart';

void main() {
  final json = jsonDecode(File('../error-codes.json').readAsStringSync()) as Map<String, dynamic>;
  final jsonCodes = {
    for (final c in (json['codes'] as List).cast<Map<String, dynamic>>()) c['code'] as int: c['name'] as String,
  };

  test('重新生成到内存与已提交文件逐字一致', () {
    expect(gen.generateErrorCodesSource(json), File('lib/src/generated/error_codes.dart').readAsStringSync());
  });

  test('枚举 = RC 43 值原序 + 我方 3 值', () {
    expect(PurchasesErrorCode.values, hasLength(46));
    expect(PurchasesErrorCode.values.take(43).map((e) => e.name), gen.rcPurchasesErrorCodeNames);
    expect(PurchasesErrorCode.values.skip(43).map((e) => e.name), [
      'notImplementedError',
      'purchasePendingServerConfirmation',
      'purchaseRejectedByServer',
    ]);
  });

  test('json 每个码都在表里，且按 name 对齐；每个 name 必在 RC 枚举或我方 3 个追加值里', () {
    final allowed = PurchasesErrorCode.values.map((e) => e.name).toSet();
    for (final entry in jsonCodes.entries) {
      expect(allowed, contains(entry.value), reason: '码 ${entry.key}');
      expect(purchasesErrorCodeByNumber[entry.key]!.name, entry.value, reason: '码 ${entry.key}');
    }
  });

  test('json 没有的 0–42 码位按 RC 下标填', () {
    for (var i = 0; i <= 42; i++) {
      if (jsonCodes.containsKey(i)) continue;
      expect(purchasesErrorCodeByNumber[i]!.name, gen.rcPurchasesErrorCodeNames[i], reason: '码 $i');
    }
  });

  test('28 / 29 按 name 对齐（与 RC 下标错位是有意的）', () {
    expect(PurchasesErrorHelper.getErrorCode(PlatformException(code: '28')), PurchasesErrorCode.customerInfoError);
    expect(PurchasesErrorHelper.getErrorCode(PlatformException(code: '29')), PurchasesErrorCode.systemInfoError);
    expect(readableErrorCodeByNumber[28], 'CustomerInfoError');
    expect(readableErrorCodeByNumber[29], 'SystemInfoError');
  });

  test('900 / 901 / 902 映射', () {
    expect(purchasesErrorCodeByNumber[900], PurchasesErrorCode.notImplementedError);
    expect(purchasesErrorCodeByNumber[901], PurchasesErrorCode.purchasePendingServerConfirmation);
    expect(purchasesErrorCodeByNumber[902], PurchasesErrorCode.purchaseRejectedByServer);
    expect(readableErrorCodeByNumber[901], 'PurchasePendingServerConfirmation');
    expect(readableErrorCodeByNumber[1], 'PurchaseCancelledError');
    expect(readableErrorCodeByNumber[22], 'LogOutWithAnonymousUserError');
  });

  test('getErrorCode 对 46 个码逐一断言', () {
    final numbers = [for (var i = 0; i <= 42; i++) i, 900, 901, 902];
    expect(numbers, hasLength(46));
    for (final n in numbers) {
      final expectedName = jsonCodes[n] ?? gen.rcPurchasesErrorCodeNames[n];
      expect(
        PurchasesErrorHelper.getErrorCode(PlatformException(code: '$n')).name,
        expectedName,
        reason: '码 $n',
      );
    }
  });

  test("'22' → logOutWithAnonymousUserError；非数字 / 未知码 → unknownError，不抛", () {
    expect(PurchasesErrorHelper.getErrorCode(PlatformException(code: '22')), PurchasesErrorCode.logOutWithAnonymousUserError);
    for (final code in ['abc', '999', '', '-1', '43', '1.5', 'error']) {
      expect(PurchasesErrorHelper.getErrorCode(PlatformException(code: code)), PurchasesErrorCode.unknownError, reason: code);
    }
  });

  group('错误信封 fixture（§5.6）', () {
    const expected = {
      'purchase-cancelled-1': PurchasesErrorCode.purchaseCancelledError,
      'payment-pending-20': PurchasesErrorCode.paymentPendingError,
      'log-out-anonymous-22': PurchasesErrorCode.logOutWithAnonymousUserError,
      'configuration-23': PurchasesErrorCode.configurationError,
      'unexpected-backend-12': PurchasesErrorCode.unexpectedBackendResponseError,
      'pending-server-901': PurchasesErrorCode.purchasePendingServerConfirmation,
      'rejected-by-server-902': PurchasesErrorCode.purchaseRejectedByServer,
    };
    const requiredDetailKeys = {
      'code', 'message', 'readableErrorCode', 'readable_error_code', 'revdogCode', 'underlyingErrorMessage', //
    };
    const optionalDetailKeys = {'userCancelled', 'backendCode', 'httpStatusCode', 'requestId'};

    expected.forEach((name, code) {
      test(name, () {
        final envelope = loadFixture('wire/errors/$name.json')! as Map<String, dynamic>;
        final details = envelope['details'] as Map<String, dynamic>;
        final exception = PlatformException(
          code: envelope['code'] as String,
          message: envelope['message'] as String?,
          details: details,
        );
        final number = int.parse(exception.code);

        expect(PurchasesErrorHelper.getErrorCode(exception), code);
        expect(details['code'], number);
        expect(details['message'], envelope['message']);
        expect(details['readableErrorCode'], readableErrorCodeByNumber[number]);
        expect(details['readable_error_code'], details['readableErrorCode']);
        expect(details['underlyingErrorMessage'], isA<String>());
        expect(details.keys.toSet().containsAll(requiredDetailKeys), isTrue);
        expect(details.keys.toSet().difference(requiredDetailKeys).difference(optionalDetailKeys), isEmpty);
        // 合成错误的 message 逐字取码表英文短句。
        if (syntheticErrorMessages.containsKey(number)) {
          expect(envelope['message'], syntheticErrorMessages[number]);
        }
        // revdogCode：logOut 路径 22 为我方 14 的名字（裁定 6），其余 = 码表名。
        expect(
          details['revdogCode'],
          number == 22 ? 'invalidAppUserIdError' : purchasesErrorCodeByNumber[number]!.name,
        );
        // userCancelled：码 1 为 true，其余出现时为 false（D3）。
        if (details.containsKey('userCancelled')) {
          expect(details['userCancelled'], number == 1);
        }
      });
    });

    test('Dart 合成的码 12 / 23 与 fixture 同形（同键集、同 message）', () {
      for (final (code, name) in [
        (PurchasesErrorCode.unexpectedBackendResponseError, 'unexpected-backend-12'),
        (PurchasesErrorCode.configurationError, 'configuration-23'),
      ]) {
        final built = buildPurchasesPlatformException(code, underlyingErrorMessage: 'x');
        final envelope = loadFixture('wire/errors/$name.json')! as Map<String, dynamic>;
        final fixtureDetails = envelope['details'] as Map<String, dynamic>;
        final builtDetails = built.details as Map<String, Object?>;
        expect(built.code, envelope['code']);
        expect(built.message, envelope['message']);
        for (final key in ['code', 'message', 'readableErrorCode', 'readable_error_code', 'revdogCode']) {
          expect(builtDetails[key], fixtureDetails[key], reason: key);
        }
      }
    });
  });
}
