// 门面方法测试。对照 RC test/purchases_flutter_test.dart 的手法：mock handler 记录 MethodCall，
// 断言方法名 + 参数逐键；channelBuffers.push 模拟原生反向事件。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog/revenue_dog.dart';
import 'package:revenue_dog/src/purchases_state.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final log = <MethodCall>[];
  late Map<String, Object? Function(MethodCall call)> handlers;

  final minimalWire = loadFixtureAsChannelValue('wire/customer-info-minimal.json');
  final fullWire = loadFixtureAsChannelValue('wire/customer-info-full.json');
  final notConfigured = {'isConfigured': false, 'apiKey': null, 'appUserID': null};

  Map<String, Object?> setupArgs({
    String apiKey = 'appl_public_key',
    String? appUserID,
    bool diagnosticsEnabled = false,
    String? logLevel,
    bool waitsForLogInBeforeSync = false,
    String? baseUrl,
    String purchasesAreCompletedBy = 'revenue_dog',
    bool shouldShowInAppMessagesAutomatically = true,
    bool pendingTransactionsForPrepaidPlansEnabled = false,
    String? userDefaultsSuiteName,
  }) =>
      {
        'apiKey': apiKey,
        'appUserID': appUserID,
        'diagnosticsEnabled': diagnosticsEnabled,
        'logLevel': logLevel,
        'waitsForLogInBeforeSync': waitsForLogInBeforeSync,
        'baseUrl': baseUrl,
        'platformFlavorVersion': '0.1.0',
        'purchasesAreCompletedBy': purchasesAreCompletedBy,
        'shouldShowInAppMessagesAutomatically': shouldShowInAppMessagesAutomatically,
        'pendingTransactionsForPrepaidPlansEnabled': pendingTransactionsForPrepaidPlansEnabled,
        'userDefaultsSuiteName': userDefaultsSuiteName,
      };

  setUp(() {
    PurchasesState.reset();
    handlers = {'getConfiguredParams': (_) => notConfigured};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, (call) async {
      log.add(call);
      final handler = handlers[call.method];
      return handler?.call(call);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, null);
    log.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  group('configure', () {
    test('未配置 → getConfiguredParams 后下发 setupPurchases，参数全部显式（null 也传）', () async {
      await Purchases.configure(PurchasesConfiguration('appl_public_key'));
      expect(log, [
        isMethodCall('getConfiguredParams', arguments: null),
        isMethodCall('setupPurchases', arguments: setupArgs()),
      ]);
    });

    test('全部字段逐键下发', () async {
      final configuration = PurchasesConfiguration('goog_public_key')
        ..appUserID = 'user_1'
        ..diagnosticsEnabled = true
        ..waitsForLogInBeforeSync = true
        ..baseUrl = 'https://staging.api.revdog.org'
        ..shouldShowInAppMessagesAutomatically = false
        ..pendingTransactionsForPrepaidPlansEnabled = true
        ..userDefaultsSuiteName = 'group.example'
        ..storeKitVersion = StoreKitVersion.storeKit2
        ..preferredUILocaleOverride = 'es-ES'
        ..automaticDeviceIdentifierCollectionEnabled = false;
      await Purchases.configure(configuration);
      expect(log.last, isMethodCall('setupPurchases', arguments: setupArgs(
        apiKey: 'goog_public_key',
        appUserID: 'user_1',
        diagnosticsEnabled: true,
        waitsForLogInBeforeSync: true,
        baseUrl: 'https://staging.api.revdog.org',
        shouldShowInAppMessagesAutomatically: false,
        pendingTransactionsForPrepaidPlansEnabled: true,
        userDefaultsSuiteName: 'group.example',
      )));
    });

    test('PurchasesAreCompletedByMyApp → purchasesAreCompletedBy = my_app', () async {
      await Purchases.configure(PurchasesConfiguration('k')
        ..purchasesAreCompletedBy =
            PurchasesAreCompletedByMyApp(storeKitVersion: StoreKitVersion.storeKit2));
      expect(log.last.arguments['purchasesAreCompletedBy'], 'my_app');
    });

    test('PurchasesAreCompletedByRevenueCat → revenue_dog', () async {
      await Purchases.configure(
        PurchasesConfiguration('k')..purchasesAreCompletedBy = const PurchasesAreCompletedByRevenueCat(),
      );
      expect(log.last.arguments['purchasesAreCompletedBy'], 'revenue_dog');
    });

    test('storeKitVersion storeKit2 / defaultVersion 放行', () async {
      for (final version in [StoreKitVersion.storeKit2, StoreKitVersion.defaultVersion]) {
        log.clear();
        await Purchases.configure(PurchasesConfiguration('k')..storeKitVersion = version);
        expect(log.map((c) => c.method), ['getConfiguredParams', 'setupPurchases']);
      }
    });

    group('配置校验 → 码 23，不下发', () {
      final cases = <String, PurchasesConfiguration>{
        'storeKit1': PurchasesConfiguration('k')..storeKitVersion = StoreKitVersion.storeKit1,
        'informational': PurchasesConfiguration('k')
          ..entitlementVerificationMode = EntitlementVerificationMode.informational,
        'amazon': PurchasesConfiguration('k')..store = Store.amazon,
        'myApp storeKit1': PurchasesConfiguration('k')
          ..purchasesAreCompletedBy = PurchasesAreCompletedByMyApp(storeKitVersion: StoreKitVersion.storeKit1),
      };
      cases.forEach((name, configuration) {
        test(name, () async {
          final e = await expectPlatformException(Purchases.configure(configuration), '23');
          expect(e.message, 'There is an issue with your configuration. Check the underlying error for more details.');
          final details = e.details as Map;
          expect(details['code'], 23);
          expect(details['message'], e.message);
          expect(details['readableErrorCode'], 'ConfigurationError');
          expect(details['readable_error_code'], 'ConfigurationError');
          expect(details['revdogCode'], 'configurationError');
          expect(details['underlyingErrorMessage'], isNotEmpty);
          expect(PurchasesErrorHelper.getErrorCode(e), PurchasesErrorCode.configurationError);
          expect(log, isEmpty);
        });
      });
    });

    group('R3 重复 configure', () {
      test('已配置且参数相同 → 不下发 setupPurchases，attachCustomerInfoStream + warn', () async {
        handlers['getConfiguredParams'] =
            (_) => {'isConfigured': true, 'apiKey': 'k', 'appUserID': 'user_1'};
        final logs = <(LogLevel, String)>[];
        await Purchases.setLogHandler((level, message) => logs.add((level, message)));
        log.clear();
        await Purchases.configure(PurchasesConfiguration('k')..appUserID = 'user_1');
        expect(log, [
          isMethodCall('getConfiguredParams', arguments: null),
          isMethodCall('attachCustomerInfoStream', arguments: {'duplicateConfigure': true}),
        ]);
        expect(logs.single.$1, LogLevel.warn);
      });

      test('已配置且匿名（appUserID 都为 null）也算相同', () async {
        handlers['getConfiguredParams'] = (_) => {'isConfigured': true, 'apiKey': 'k', 'appUserID': null};
        await Purchases.configure(PurchasesConfiguration('k'));
        expect(log.map((c) => c.method), ['getConfiguredParams', 'attachCustomerInfoStream']);
      });

      test('已配置但 apiKey 不同 → 码 23，message 指向 logIn / logOut', () async {
        handlers['getConfiguredParams'] = (_) => {'isConfigured': true, 'apiKey': 'other', 'appUserID': null};
        final e = await expectPlatformException(Purchases.configure(PurchasesConfiguration('k')), '23');
        expect(e.message, contains('logIn / logOut'));
        expect((e.details as Map)['revdogCode'], 'configurationError');
        expect(log.map((c) => c.method), ['getConfiguredParams']);
      });

      test('已配置但 appUserID 不同 → 码 23', () async {
        handlers['getConfiguredParams'] = (_) => {'isConfigured': true, 'apiKey': 'k', 'appUserID': 'a'};
        await expectPlatformException(Purchases.configure(PurchasesConfiguration('k')..appUserID = 'b'), '23');
        expect(log.map((c) => c.method), ['getConfiguredParams']);
      });

      test('getConfiguredParams 形状错 → 码 12', () async {
        handlers['getConfiguredParams'] = (_) => {'apiKey': 'k'};
        final e = await expectPlatformException(Purchases.configure(PurchasesConfiguration('k')), '12');
        expect((e.details as Map)['wireKey'], 'isConfigured');
      });
    });

    test('R4：先 setLogLevel 再 configure，logLevel 进 setupPurchases', () async {
      await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration('k'));
      expect(log, [
        isMethodCall('setLogLevel', arguments: {'level': 'debug'}),
        isMethodCall('getConfiguredParams', arguments: null),
        isMethodCall('setupPurchases', arguments: setupArgs(apiKey: 'k', logLevel: 'debug')),
      ]);
    });

    test('R4：记住的是最近一次', () async {
      await Purchases.setLogLevel(LogLevel.verbose);
      await Purchases.setLogLevel(LogLevel.error);
      await Purchases.configure(PurchasesConfiguration('k'));
      expect(log.last.arguments['logLevel'], 'error');
    });

    test('原生 setupPurchases 报错原样抛出', () async {
      handlers['setupPurchases'] = (_) => throw PlatformException(code: '11', message: 'Invalid API key');
      await expectPlatformException(Purchases.configure(PurchasesConfiguration('k')), '11');
    });
  });

  group('其它方法：方法名与参数', () {
    test('setLogLevel 全部级别发小写名', () async {
      for (final level in LogLevel.values) {
        await Purchases.setLogLevel(level);
      }
      expect(log, [
        for (final name in ['verbose', 'debug', 'info', 'warn', 'error'])
          isMethodCall('setLogLevel', arguments: {'level': name}),
      ]);
    });

    test('isConfigured', () async {
      handlers['isConfigured'] = (_) => true;
      expect(await Purchases.isConfigured, isTrue);
      expect(log, [isMethodCall('isConfigured', arguments: null)]);
    });

    test('appUserID → getAppUserID', () async {
      handlers['getAppUserID'] = (_) => 'user_1';
      expect(await Purchases.appUserID, 'user_1');
      expect(log, [isMethodCall('getAppUserID', arguments: null)]);
    });

    test('isAnonymous', () async {
      handlers['isAnonymous'] = (_) => false;
      expect(await Purchases.isAnonymous, isFalse);
      expect(log, [isMethodCall('isAnonymous', arguments: null)]);
    });

    test('标量返回类型错 → 码 12，wireKey = 方法名', () async {
      handlers['isAnonymous'] = (_) => 'yes';
      final e = await expectPlatformException(Purchases.isAnonymous, '12');
      expect((e.details as Map)['wireKey'], 'isAnonymous');
    });

    test('logIn', () async {
      handlers['logIn'] = (_) => loadFixtureAsChannelValue('wire/log-in-result.json');
      final result = await Purchases.logIn('user_42');
      expect(log, [isMethodCall('logIn', arguments: {'appUserID': 'user_42'})]);
      expect(result.created, isTrue);
      expect(result.customerInfo, CustomerInfo.fromJson(Map<String, dynamic>.from(minimalWire! as Map)));
    });

    test('logIn 结果里 customerInfo 缺键 → 码 12，wireKey 带 customerInfo 前缀', () async {
      final raw = loadFixture('wire/log-in-result.json')! as Map<String, dynamic>;
      (raw['customerInfo'] as Map).remove('firstSeen');
      handlers['logIn'] = (_) => raw;
      final e = await expectPlatformException(Purchases.logIn('u'), '12');
      expect((e.details as Map)['wireKey'], 'customerInfo.firstSeen');
    });

    test('logOut', () async {
      handlers['logOut'] = (_) => minimalWire;
      final info = await Purchases.logOut();
      expect(log, [isMethodCall('logOut', arguments: null)]);
      expect(info.originalAppUserId, startsWith(r'$RDAnonymousID:'));
    });

    test('logOut 匿名 → 码 22 原样抛出（信封来自原生插件）', () async {
      final envelope = loadFixture('wire/errors/log-out-anonymous-22.json')! as Map<String, dynamic>;
      handlers['logOut'] = (_) => throw PlatformException(
            code: envelope['code'] as String,
            message: envelope['message'] as String,
            details: envelope['details'],
          );
      final e = await expectPlatformException(Purchases.logOut(), '22');
      expect(PurchasesErrorHelper.getErrorCode(e), PurchasesErrorCode.logOutWithAnonymousUserError);
    });

    test('getCustomerInfo', () async {
      handlers['getCustomerInfo'] = (_) => fullWire;
      final info = await Purchases.getCustomerInfo();
      expect(log, [isMethodCall('getCustomerInfo', arguments: null)]);
      expect(info.originalAppUserId, 'user_full_001');
    });

    test('enableAdServicesAttributionTokenCollection', () async {
      await Purchases.enableAdServicesAttributionTokenCollection();
      expect(log, [isMethodCall('enableAdServicesAttributionTokenCollection', arguments: null)]);
    });

    test('setLogHandler', () async {
      await Purchases.setLogHandler((_, _) {});
      expect(log, [isMethodCall('setLogHandler', arguments: null)]);
    });
  });

  group('CustomerInfo 监听', () {
    test('事件推给全部监听者；新加的监听者立即回放最近值', () async {
      final first = <CustomerInfo>[];
      Purchases.addCustomerInfoUpdateListener(first.add);
      expect(first, isEmpty);

      sendNativeEvent('Purchases-CustomerInfoUpdated', fullWire);
      expect(first, hasLength(1));
      expect(first.single.originalAppUserId, 'user_full_001');

      final second = <CustomerInfo>[];
      Purchases.addCustomerInfoUpdateListener(second.add);
      expect(second.single, first.single);
    });

    test('移除后不再回调', () async {
      final received = <CustomerInfo>[];
      void listener(CustomerInfo info) => received.add(info);
      Purchases.addCustomerInfoUpdateListener(listener);
      Purchases.removeCustomerInfoUpdateListener(listener);
      sendNativeEvent('Purchases-CustomerInfoUpdated', fullWire);
      expect(received, isEmpty);
    });

    test('事件解码失败 → 不回调监听者，回执为码 12 错误信封', () async {
      final received = <CustomerInfo>[];
      Purchases.addCustomerInfoUpdateListener(received.add);
      final broken = loadFixture('wire/customer-info-full.json')! as Map<String, dynamic>;
      broken.remove('requestDate');
      final replies = <ByteData?>[];
      sendNativeEvent('Purchases-CustomerInfoUpdated', broken, replies: replies);
      await pumpEventQueue();
      expect(received, isEmpty);
      expect(
        () => const StandardMethodCodec().decodeEnvelope(replies.single!),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', '12')),
      );
    });

    test('热重启：Dart 静态态清零后 configure 命中「相同」分支，原生推当前值，监听者拿到首值', () async {
      await Purchases.configure(PurchasesConfiguration('k'));
      sendNativeEvent('Purchases-CustomerInfoUpdated', fullWire);

      // 模拟热重启：Dart 静态态清零，插件进程级记录与原生单例仍在。
      PurchasesState.reset();
      log.clear();
      handlers['getConfiguredParams'] = (_) => {'isConfigured': true, 'apiKey': 'k', 'appUserID': null};

      final received = <CustomerInfo>[];
      Purchases.addCustomerInfoUpdateListener(received.add);
      expect(received, isEmpty, reason: '热重启后不应回放重启前的值');

      await Purchases.configure(PurchasesConfiguration('k'));
      expect(log.map((c) => c.method), ['getConfiguredParams', 'attachCustomerInfoStream']);
      // attach 后原生推一次当前值（D14）。
      sendNativeEvent('Purchases-CustomerInfoUpdated', minimalWire);
      expect(received.single.originalAppUserId, startsWith(r'$RDAnonymousID:'));
    });
  });

  group('LogHandler', () {
    test('各级别事件映射到 LogLevel', () async {
      final received = <(LogLevel, String)>[];
      await Purchases.setLogHandler((level, message) => received.add((level, message)));
      for (final level in LogLevel.values) {
        sendNativeEvent('Purchases-LogHandlerEvent', {'logLevel': level.name, 'message': 'm-${level.name}'});
      }
      expect(received, [for (final level in LogLevel.values) (level, 'm-${level.name}')]);
    });

    test('未知级别落 info（照 RC）', () async {
      final received = <(LogLevel, String)>[];
      await Purchases.setLogHandler((level, message) => received.add((level, message)));
      sendNativeEvent('Purchases-LogHandlerEvent', {'logLevel': 'SEVERE', 'message': 'x'});
      expect(received, [(LogLevel.info, 'x')]);
    });
  });

  group('平台守卫（D13）', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia]) {
      test('$platform → UnsupportedPlatformException，且不触达通道', () async {
        debugDefaultTargetPlatformOverride = platform;
        final calls = <Future<Object?> Function()>[
          () => Purchases.configure(PurchasesConfiguration('k')),
          () => Purchases.setLogLevel(LogLevel.debug),
          () => Purchases.setLogHandler((_, _) {}),
          () => Purchases.isConfigured,
          () => Purchases.logIn('u'),
          () => Purchases.logOut(),
          () => Purchases.appUserID,
          () => Purchases.isAnonymous,
          () => Purchases.getCustomerInfo(),
          () => Purchases.enableAdServicesAttributionTokenCollection(),
        ];
        for (final call in calls) {
          await expectLater(call(), throwsA(isA<UnsupportedPlatformException>()));
        }
        expect(() => Purchases.addCustomerInfoUpdateListener((_) {}), throwsA(isA<UnsupportedPlatformException>()));
        expect(log, isEmpty);
      });
    }

    test('iOS 放行', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      handlers['isConfigured'] = (_) => false;
      expect(await Purchases.isConfigured, isFalse);
    });
  });
}
