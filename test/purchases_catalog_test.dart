// M2 门面方法：目录与购买。对照 RC test/purchases_flutter_test.dart：mock handler 记录 MethodCall，
// 断言方法名 + 参数逐键；错误信封取 wire/errors fixture，断言 Dart 透传 + getErrorCode。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog/revenue_dog.dart';
import 'package:revenue_dog/src/purchases_state.dart';

import 'helpers.dart';

/// 由 wire/errors fixture 构造原生插件会抛的 `PlatformException`。
PlatformException envelope(String fixture) {
  final raw = loadFixture('wire/errors/$fixture')! as Map<String, dynamic>;
  return PlatformException(code: raw['code'] as String, message: raw['message'] as String, details: raw['details']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final log = <MethodCall>[];
  late Map<String, Object? Function(MethodCall call)> handlers;

  final offeringsIos = loadFixtureAsChannelValue('wire/offerings-ios.json');
  final purchaseResultWire = loadFixtureAsChannelValue('wire/purchase-result.json');
  final minimalWire = loadFixtureAsChannelValue('wire/customer-info-minimal.json');

  setUp(() {
    PurchasesState.reset();
    handlers = {};
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

  Future<Package> monthlyPackage() async {
    handlers['getOfferings'] = (_) => offeringsIos;
    final offerings = await Purchases.getOfferings();
    log.clear();
    return offerings.current!.monthly!;
  }

  group('getOfferings', () {
    test('方法名无参；返回解码后的 Offerings', () async {
      handlers['getOfferings'] = (_) => offeringsIos;
      final offerings = await Purchases.getOfferings();
      expect(log, [isMethodCall('getOfferings', arguments: null)]);
      expect(offerings.current!.identifier, 'default');
      expect(offerings.current!.monthly!.storeProduct.price, 9.99);
    });

    test('全部商品缺失 → 码 2 原样抛出（信封来自原生插件）', () async {
      handlers['getOfferings'] = (_) => throw envelope('store-problem-2.json');
      final e = await expectPlatformException(Purchases.getOfferings(), '2');
      expect(PurchasesErrorHelper.getErrorCode(e), PurchasesErrorCode.storeProblemError);
      expect((e.details as Map)['underlyingErrorMessage'], 'store products unavailable');
    });

    test('返回形状错 → 码 12', () async {
      handlers['getOfferings'] = (_) => {'all': <String, Object?>{}};
      final e = await expectPlatformException(Purchases.getOfferings(), '12');
      expect((e.details as Map)['wireKey'], 'current');
    });
  });

  group('purchase', () {
    test('PurchaseParams.package → purchasePackage {offeringIdentifier, packageIdentifier}', () async {
      final package = await monthlyPackage();
      handlers['purchasePackage'] = (_) => purchaseResultWire;
      final result = await Purchases.purchase(PurchaseParams.package(package));
      expect(log, [
        isMethodCall('purchasePackage', arguments: {'offeringIdentifier': 'default', 'packageIdentifier': r'$rc_monthly'}),
      ]);
      expect(result.storeTransaction.transactionIdentifier, '2000000987654321');
      expect(result.storeTransaction.productIdentifier, 'premium_monthly');
      expect(result.storeTransaction.purchaseDate, '2026-09-23T12:00:00.000Z');
      expect(result.customerInfo, CustomerInfo.fromJson(Map<String, dynamic>.from(minimalWire! as Map)));
    });

    test('PurchaseParams.package 保存 package（RC 同形字段）', () async {
      final package = await monthlyPackage();
      expect(PurchaseParams.package(package).package, same(package));
    });

    test('offeringIdentifier 取自 presentedOfferingContext', () async {
      const product = StoreProduct('p', 'd', 't', 1, r'$1.00', 'USD');
      const package = Package('custom_pack', PackageType.custom, product, PresentedOfferingContext('promo', null, null));
      handlers['purchasePackage'] = (_) => purchaseResultWire;
      await Purchases.purchase(const PurchaseParams.package(package));
      expect(log.single.arguments, {'offeringIdentifier': 'promo', 'packageIdentifier': 'custom_pack'});
    });

    test('purchasePackage（弃用）是 purchase 的薄包装：同一通道调用、同一结果', () async {
      final package = await monthlyPackage();
      handlers['purchasePackage'] = (_) => purchaseResultWire;
      final viaPurchase = await Purchases.purchase(PurchaseParams.package(package));
      // ignore: deprecated_member_use
      final viaDeprecated = await Purchases.purchasePackage(package);
      expect(log, [
        for (var i = 0; i < 2; i++)
          isMethodCall('purchasePackage', arguments: {'offeringIdentifier': 'default', 'packageIdentifier': r'$rc_monthly'}),
      ]);
      expect(viaDeprecated, viaPurchase);
    });

    test('结果交易 id 为空 → 码 12（不吞成空串）', () async {
      final package = await monthlyPackage();
      final raw = loadFixture('wire/purchase-result.json')! as Map<String, dynamic>;
      (raw['storeTransaction'] as Map)['transactionIdentifier'] = '';
      handlers['purchasePackage'] = (_) => raw;
      final e = await expectPlatformException(Purchases.purchase(PurchaseParams.package(package)), '12');
      expect((e.details as Map)['wireKey'], 'storeTransaction.transactionIdentifier');
    });

    group('错误透传（D3 映射在原生插件）', () {
      final cases = <String, (String, PurchasesErrorCode)>{
        'purchase-cancelled-1.json': ('1', PurchasesErrorCode.purchaseCancelledError),
        'payment-pending-20.json': ('20', PurchasesErrorCode.paymentPendingError),
        'product-not-found-5.json': ('5', PurchasesErrorCode.productNotAvailableForPurchaseError),
        'invalid-argument-4.json': ('4', PurchasesErrorCode.purchaseInvalidError),
        'pending-server-901.json': ('901', PurchasesErrorCode.purchasePendingServerConfirmation),
        'rejected-by-server-902.json': ('902', PurchasesErrorCode.purchaseRejectedByServer),
      };
      cases.forEach((fixture, expected) {
        test(fixture, () async {
          final package = await monthlyPackage();
          handlers['purchasePackage'] = (_) => throw envelope(fixture);
          final e = await expectPlatformException(Purchases.purchase(PurchaseParams.package(package)), expected.$1);
          expect(PurchasesErrorHelper.getErrorCode(e), expected.$2);
          final details = e.details as Map;
          expect(details['userCancelled'], expected.$1 == '1', reason: '购买路径：仅码 1 为 true');
          if (expected.$1 == '1') {
            expect(details['readableErrorCode'], 'PurchaseCancelledError');
          }
        });
      });
    });
  });

  group('restorePurchases / syncPurchases', () {
    test('restorePurchases 方法名无参；返回 CustomerInfo', () async {
      handlers['restorePurchases'] = (_) => minimalWire;
      final info = await Purchases.restorePurchases();
      expect(log, [isMethodCall('restorePurchases', arguments: null)]);
      expect(info.originalAppUserId, startsWith(r'$RDAnonymousID:'));
    });

    test('syncPurchases 方法名无参；等原生回调，返回值丢弃（不解码）', () async {
      handlers['syncPurchases'] = (_) => {'not': 'a customer info'};
      await Purchases.syncPurchases();
      expect(log, [isMethodCall('syncPurchases', arguments: null)]);
    });

    test('syncPurchases 原生错误原样抛出', () async {
      handlers['syncPurchases'] = (_) => throw PlatformException(code: '10', message: 'network');
      await expectPlatformException(Purchases.syncPurchases(), '10');
    });
  });

  group('checkTrialOrIntroductoryPriceEligibility', () {
    const ids = ['premium_monthly', 'premium_annual', 'unknown_product'];

    test('方法名 + productIdentifiers；iOS 结果解码', () async {
      handlers['checkTrialOrIntroductoryPriceEligibility'] =
          (_) => loadFixtureAsChannelValue('wire/intro-eligibility-ios.json');
      final result = await Purchases.checkTrialOrIntroductoryPriceEligibility(ids);
      expect(log, [
        isMethodCall('checkTrialOrIntroductoryPriceEligibility', arguments: {'productIdentifiers': ids}),
      ]);
      expect(result.map((k, v) => MapEntry(k, v.status)), {
        'premium_monthly': IntroEligibilityStatus.introEligibilityStatusEligible,
        'premium_annual': IntroEligibilityStatus.introEligibilityStatusNoIntroOfferExists,
        'unknown_product': IntroEligibilityStatus.introEligibilityStatusUnknown,
      });
    });

    test('Android 结果：全部 unknown', () async {
      handlers['checkTrialOrIntroductoryPriceEligibility'] =
          (_) => loadFixtureAsChannelValue('wire/intro-eligibility-android.json');
      final result = await Purchases.checkTrialOrIntroductoryPriceEligibility(ids);
      expect(result.values.map((e) => e.status).toSet(), {IntroEligibilityStatus.introEligibilityStatusUnknown});
    });

    test('请求的商品缺结果 → 码 12，wireKey = 商品 id', () async {
      handlers['checkTrialOrIntroductoryPriceEligibility'] = (_) => {
            'premium_monthly': {'status': 'eligible', 'description': 'Eligible for trial or introductory price.'},
          };
      final e = await expectPlatformException(
        Purchases.checkTrialOrIntroductoryPriceEligibility(['premium_monthly', 'premium_annual']),
        '12',
      );
      expect((e.details as Map)['wireKey'], 'premium_annual');
    });

    test('条目缺 status → 码 12，wireKey 带商品前缀', () async {
      handlers['checkTrialOrIntroductoryPriceEligibility'] = (_) => {
            'premium_monthly': {'description': 'x'},
          };
      final e = await expectPlatformException(
        Purchases.checkTrialOrIntroductoryPriceEligibility(['premium_monthly']),
        '12',
      );
      expect((e.details as Map)['wireKey'], 'premium_monthly.status');
    });
  });

  group('平台守卫（D13）', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia]) {
      test('$platform → UnsupportedPlatformException，且不触达通道', () async {
        const product = StoreProduct('p', 'd', 't', 1, r'$1.00', 'USD');
        const package = Package('x', PackageType.custom, product, PresentedOfferingContext('o', null, null));
        debugDefaultTargetPlatformOverride = platform;
        final calls = <Future<Object?> Function()>[
          () => Purchases.getOfferings(),
          () => Purchases.purchase(const PurchaseParams.package(package)),
          // ignore: deprecated_member_use
          () => Purchases.purchasePackage(package),
          () => Purchases.restorePurchases(),
          () => Purchases.syncPurchases(),
          () => Purchases.checkTrialOrIntroductoryPriceEligibility(['p']),
        ];
        for (final call in calls) {
          await expectLater(call(), throwsA(isA<UnsupportedPlatformException>()));
        }
        expect(log, isEmpty);
      });
    }
  });
}
