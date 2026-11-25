// 保留属性 setter（rc.4，设计 §5.8，ADR 0245）：门面逐行对 `test/fixtures/wire/reserved-attributes.json`。
// 原生两端的 Bridge 测试读同一份表（三方对账），任一方改键 / 值类型 / Android 行为，另两方红。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog/revenue_dog.dart';
import 'package:revenue_dog/src/purchases_state.dart';

import 'helpers.dart';

/// 门面方法名 → 用给定值调用该 setter（string 行传 String?，bool 行传 bool?）。
final Map<String, Future<void> Function(Object? value)> _setters = {
  'setEmail': (v) => Purchases.setEmail(v as String?),
  'setPhoneNumber': (v) => Purchases.setPhoneNumber(v as String?),
  'setATTConsentStatus': (v) => Purchases.setATTConsentStatus(v as String?),
  'setIDFA': (v) => Purchases.setIDFA(v as String?),
  'setIDFV': (v) => Purchases.setIDFV(v as String?),
  'setFBAnonymousID': (v) => Purchases.setFBAnonymousID(v as String?),
  'setFirebaseAppInstanceId': (v) => Purchases.setFirebaseAppInstanceId(v as String?),
  'setTimezone': (v) => Purchases.setTimezone(v as String?),
  'setAdMeasurementConsent': (v) => Purchases.setAdMeasurementConsent(v as bool?),
  'setFBCampaignIDs': (v) => Purchases.setFBCampaignIDs(v as String?),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final table = loadFixture('wire/reserved-attributes.json')! as Map<String, dynamic>;
  final method = table['method'] as String;
  final rows = (table['attributes'] as List).cast<Map<String, dynamic>>();
  final log = <MethodCall>[];

  setUp(() {
    PurchasesState.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, (call) async {
      log.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, null);
    log.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  test('表与门面一一对应（十个，无重复键）', () {
    expect(method, 'setReservedAttribute');
    expect(rows.map((r) => r['dart']).toSet(), _setters.keys.toSet());
    expect(rows.length, _setters.length);
    expect(rows.map((r) => r['key']).toSet().length, rows.length);
    for (final row in rows) {
      expect(row['value'], anyOf('string', 'bool'), reason: '${row['dart']}');
      expect(row['android'], anyOf('passthrough', 'noop'), reason: '${row['dart']}');
    }
  });

  for (final row in rows) {
    final name = row['dart'] as String;
    final key = row['key'] as String;
    final isBool = row['value'] == 'bool';

    test('$name → $method {key: $key, value}：有值、空值、null 都原样下发', () async {
      final samples = isBool ? <Object?>[true, false, null] : <Object?>['value_1', '', null];
      for (final sample in samples) {
        await _setters[name]!(sample);
      }
      expect(log, [
        for (final sample in samples) isMethodCall(method, arguments: {'key': key, 'value': sample}),
      ]);
    });
  }

  test('原生错误原样抛出（未配置 → 码 23）', () async {
    final envelope = loadFixture('wire/errors/configuration-23.json')! as Map<String, dynamic>;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, (call) async {
      throw PlatformException(
        code: envelope['code'] as String,
        message: envelope['message'] as String,
        details: envelope['details'],
      );
    });
    await expectLater(
      Purchases.setIDFA(null),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', '23')),
    );
  });

  test('iOS / Android 以外的平台 → UnsupportedPlatformException，且不触达通道', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    for (final setter in _setters.values) {
      await expectLater(setter(null), throwsA(isA<UnsupportedPlatformException>()));
    }
    expect(log, isEmpty);
  });
}
