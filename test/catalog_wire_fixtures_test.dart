// M2 wire fixture → 模型字段（目录 / 购买 / 资格；三方对账的 Dart 一方，fixtures/README.md）。
// ignore_for_file: deprecated_member_use
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog/revenue_dog.dart';

import 'helpers.dart';

Map<String, dynamic> channelMap(String fixture) =>
    Map<String, dynamic>.from(loadFixtureAsChannelValue(fixture)! as Map);

Offerings decodeOfferingsFixture(String fixture) => Offerings.fromJson(channelMap(fixture));

Map<String, dynamic> mutableFixture(String fixture) => loadFixture(fixture)! as Map<String, dynamic>;

/// 断言 [body] 抛码 12 且 `details.wireKey == wireKey`。
void expectWireError(void Function() body, String wireKey) {
  expect(
    body,
    throwsA(
      isA<PlatformException>()
          .having((e) => e.code, 'code', '12')
          .having((e) => (e.details as Map)['wireKey'], 'wireKey', wireKey)
          .having((e) => (e.details as Map)['revdogCode'], 'revdogCode', 'unexpectedBackendResponseError'),
    ),
  );
}

const context = PresentedOfferingContext('default', null, null);

void main() {
  group('offerings-ios', () {
    final offerings = decodeOfferingsFixture('wire/offerings-ios.json');
    final offering = offerings.current!;

    test('剔除：retention_offer 唯一 package 缺商品 → 整个 offering 去掉；current = default', () {
      expect(offerings.all.keys, ['default']);
      expect(offerings.getOffering('retention_offer'), isNull);
      expect(offerings.getOffering('default'), same(offerings.all['default']));
      expect(offering, offerings.all['default']);
    });

    test('Offering 字段与便捷档位（Dart 从 availablePackages 派生）', () {
      expect(offering.identifier, 'default');
      expect(offering.serverDescription, 'The default offering');
      expect(offering.metadata, isEmpty);
      expect(offering.webCheckoutUrl, isNull);
      expect(offering.availablePackages.map((p) => p.identifier), [r'$rc_monthly', r'$rc_annual', r'$rc_lifetime', 'custom_pack']);
      expect(offering.monthly, offering.availablePackages[0]);
      expect(offering.annual, offering.availablePackages[1]);
      expect(offering.lifetime, offering.availablePackages[2]);
      expect(offering.weekly, isNull);
      expect(offering.twoMonth, isNull);
      expect(offering.threeMonth, isNull);
      expect(offering.sixMonth, isNull);
      expect(offering.getPackage('custom_pack')!.packageType, PackageType.custom);
      expect(offering.getPackage('CUSTOM_PACK'), isNull, reason: '精确匹配（B2）');
      expect(offering.getMetadataString('k', 'fallback'), 'fallback');
    });

    test('Package 字段', () {
      final monthly = offering.monthly!;
      expect(monthly.identifier, r'$rc_monthly');
      expect(monthly.packageType, PackageType.monthly);
      expect(monthly.presentedOfferingContext, context);
      expect(monthly.offeringIdentifier, 'default');
      expect(monthly.webCheckoutUrl, isNull);
    });

    test('StoreProduct：月订阅 + 7 天免费试用；iOS 无 subscriptionOptions', () {
      final product = offering.monthly!.storeProduct;
      expect(product.identifier, 'premium_monthly');
      expect(product.title, 'Premium Monthly');
      expect(product.description, 'Unlock all premium features, billed monthly');
      expect(product.price, 9.99);
      expect(product.priceString, r'$9.99');
      expect(product.currencyCode, 'USD');
      expect(product.subscriptionPeriod, 'P1M');
      expect(product.productCategory, ProductCategory.subscription);
      expect(product.presentedOfferingContext, context);
      expect(product.presentedOfferingIdentifier, 'default');
      expect(product.defaultOption, isNull);
      expect(product.subscriptionOptions, isNull);
      expect(product.discounts, isNull);
      expect(product.pricePerWeek, isNull);
      expect(product.pricePerMonth, isNull);
      expect(product.pricePerYear, isNull);
      expect(product.pricePerWeekString, isNull);
      expect(product.pricePerMonthString, isNull);
      expect(product.pricePerYearString, isNull);
      expect(product.introductoryPrice, const IntroductoryPrice(0, r'$0.00', 'P1W', 1, PeriodUnit.week, 1));
      expect(product.introductoryPrice!.price, 0);
    });

    test('StoreProduct：年订阅无优惠；一次性商品', () {
      final annual = offering.annual!.storeProduct;
      expect(annual.identifier, 'premium_annual');
      expect(annual.price, 59.99);
      expect(annual.subscriptionPeriod, 'P1Y');
      expect(annual.introductoryPrice, isNull);

      final lifetime = offering.lifetime!.storeProduct;
      expect(lifetime.identifier, 'lifetime_unlock');
      expect(lifetime.price, 19.99);
      expect(lifetime.productCategory, ProductCategory.nonSubscription);
      expect(lifetime.subscriptionPeriod, isNull);
      expect(lifetime.introductoryPrice, isNull);

      final coins = offering.getPackage('custom_pack')!.storeProduct;
      expect(coins.identifier, 'coin_pack_100');
      expect(coins.price, 0.99);
      expect(coins.priceString, r'$0.99');
    });

    test('值相等（equatable）：同一 fixture 解两次相等', () {
      expect(decodeOfferingsFixture('wire/offerings-ios.json'), offerings);
    });
  });

  group('offerings-android', () {
    final offerings = decodeOfferingsFixture('wire/offerings-android.json');
    final offering = offerings.current!;

    test('剔除与 current 同 iOS', () {
      expect(offerings.all.keys, ['default']);
      expect(offering, offerings.all['default']);
      expect(offering.availablePackages.map((p) => p.identifier), [r'$rc_monthly', r'$rc_annual', r'$rc_lifetime', 'custom_pack']);
    });

    test('订阅商品 id = subscriptionId:basePlanId；试用按 Play 原始单位与商店价串', () {
      final product = offering.monthly!.storeProduct;
      expect(product.identifier, 'premium_monthly:monthly-base');
      expect(product.title, 'Premium Monthly (RevenueDog Example)');
      expect(product.price, 9.99);
      expect(product.subscriptionPeriod, 'P1M');
      expect(product.productCategory, ProductCategory.subscription);
      expect(product.introductoryPrice, const IntroductoryPrice(0, 'Free', 'P1W', 1, PeriodUnit.week, 1));
    });

    test('subscriptionOptions / defaultOption（最长免费试用）解码', () {
      final product = offering.monthly!.storeProduct;
      final options = product.subscriptionOptions!;
      expect(options.map((o) => o.id), ['monthly-base', 'monthly-base:trial7']);
      expect(product.defaultOption, options[1]);

      const fullPhase = PricingPhase(
        Period(PeriodUnit.month, 1, 'P1M'),
        RecurrenceMode.infiniteRecurring,
        null,
        Price(r'$9.99', 9990000, 'USD'),
        null,
      );
      const trialPhase = PricingPhase(
        Period(PeriodUnit.week, 1, 'P1W'),
        RecurrenceMode.finiteRecurring,
        1,
        Price('Free', 0, 'USD'),
        OfferPaymentMode.freeTrial,
      );

      final base = options[0];
      expect(base.storeProductId, 'premium_monthly:monthly-base');
      expect(base.productId, 'premium_monthly');
      expect(base.pricingPhases, [fullPhase]);
      expect(base.tags, isEmpty);
      expect(base.isBasePlan, isTrue);
      expect(base.billingPeriod, const Period(PeriodUnit.month, 1, 'P1M'));
      expect(base.isPrepaid, isFalse);
      expect(base.fullPricePhase, fullPhase);
      expect(base.freePhase, isNull);
      expect(base.introPhase, isNull);
      expect(base.presentedOfferingContext, context);
      expect(base.presentedOfferingIdentifier, 'default');
      expect(base.installmentsInfo, isNull);

      final trial = options[1];
      expect(trial.pricingPhases, [trialPhase, fullPhase]);
      expect(trial.tags, ['trial']);
      expect(trial.isBasePlan, isFalse);
      expect(trial.freePhase, trialPhase);
      expect(trial.fullPricePhase, fullPhase);
      expect(trial.introPhase, isNull);
    });

    test('年订阅：只有 base plan，defaultOption = base，无优惠', () {
      final product = offering.annual!.storeProduct;
      expect(product.identifier, 'premium_annual:annual-base');
      expect(product.subscriptionOptions!.single.id, 'annual-base');
      expect(product.defaultOption, product.subscriptionOptions!.single);
      expect(product.introductoryPrice, isNull);
    });

    test('一次性商品：无 subscriptionOptions / defaultOption', () {
      final lifetime = offering.lifetime!.storeProduct;
      expect(lifetime.identifier, 'lifetime_unlock');
      expect(lifetime.price, 19.99);
      expect(lifetime.productCategory, ProductCategory.nonSubscription);
      expect(lifetime.subscriptionOptions, isNull);
      expect(lifetime.defaultOption, isNull);
      expect(offering.getPackage('custom_pack')!.storeProduct.identifier, 'coin_pack_100');
    });
  });

  for (final platform in ['ios', 'android']) {
    test('offerings-current-dropped-$platform：current 指向被剔空的 offering → null', () {
      final offerings = decodeOfferingsFixture('wire/offerings-current-dropped-$platform.json');
      expect(offerings.all.keys, ['default']);
      expect(offerings.current, isNull);
    });
  }

  test('purchase-result', () {
    final result = PurchaseResult.fromJson(channelMap('wire/purchase-result.json'));
    expect(result.storeTransaction, const StoreTransaction('2000000987654321', 'premium_monthly', '2026-09-23T12:00:00.000Z'));
    expect(result.customerInfo, CustomerInfo.fromJson(channelMap('wire/customer-info-minimal.json')));
  });

  group('intro-eligibility', () {
    Map<String, IntroEligibility> decode(String fixture) =>
        channelMap(fixture).map((k, v) => MapEntry(k, IntroEligibility.fromJson(Map<String, dynamic>.from(v as Map))));

    test('iOS：由 offerings 派生', () {
      final map = decode('wire/intro-eligibility-ios.json');
      expect(map['premium_monthly']!.status, IntroEligibilityStatus.introEligibilityStatusEligible);
      expect(map['premium_monthly']!.description, 'Eligible for trial or introductory price.');
      expect(map['premium_annual']!.status, IntroEligibilityStatus.introEligibilityStatusNoIntroOfferExists);
      expect(map['premium_annual']!.description, 'Product does not have trial or introductory price.');
      expect(map['unknown_product']!.status, IntroEligibilityStatus.introEligibilityStatusUnknown);
      expect(map['unknown_product']!.description, 'Status indeterminate.');
    });

    test('Android：恒 unknown', () {
      final map = decode('wire/intro-eligibility-android.json');
      expect(map.keys, ['premium_monthly', 'premium_annual', 'unknown_product']);
      for (final e in map.values) {
        expect(e.status, IntroEligibilityStatus.introEligibilityStatusUnknown);
        expect(e.description, 'Status indeterminate.');
      }
    });

    test('未知状态值 → unknown；缺 description → 码 12', () {
      expect(
        IntroEligibility.fromJson({'status': 'maybe', 'description': 'x'}).status,
        IntroEligibilityStatus.introEligibilityStatusUnknown,
      );
      expectWireError(() => IntroEligibility.fromJson({'status': 'eligible'}), 'description');
    });
  });

  group('解码失败 → 码 12 + wireKey', () {
    Offerings decodeMutated(void Function(Map<String, dynamic> raw) mutate, {String fixture = 'wire/offerings-ios.json'}) {
      final raw = mutableFixture(fixture);
      mutate(raw);
      return Offerings.fromJson(raw);
    }

    Map<String, dynamic> firstPackage(Map<String, dynamic> raw) =>
        ((raw['all'] as Map)['default'] as Map)['availablePackages'][0] as Map<String, dynamic>;

    test('current 键缺失（键恒在）', () {
      expectWireError(() => decodeMutated((raw) => raw.remove('current')), 'current');
    });

    test('current 不在 all 中', () {
      expectWireError(
        () => decodeMutated((raw) => (raw['current'] as Map)['identifier'] = 'other'),
        'current',
      );
    });

    test('all 的键与 offering identifier 不一致', () {
      expectWireError(
        () => decodeMutated((raw) {
          final all = raw['all'] as Map<String, dynamic>;
          all['renamed'] = all.remove('default');
          raw['current'] = null;
        }),
        'all.renamed.identifier',
      );
    });

    test('storeProduct 缺 priceAmountMicros → 路径到键', () {
      expectWireError(
        () => decodeMutated((raw) => (firstPackage(raw)['storeProduct'] as Map).remove('priceAmountMicros')),
        'all.default.availablePackages[0].storeProduct.priceAmountMicros',
      );
    });

    test('通道发了 double 价格（契约只发 micros）', () {
      expectWireError(
        () => decodeMutated((raw) => (firstPackage(raw)['storeProduct'] as Map)['priceAmountMicros'] = 9.99),
        'all.default.availablePackages[0].storeProduct.priceAmountMicros',
      );
    });

    test('introductoryPrice 缺 cycles', () {
      expectWireError(
        () => decodeMutated(
          (raw) => ((firstPackage(raw)['storeProduct'] as Map)['introductoryPrice'] as Map).remove('cycles'),
        ),
        'all.default.availablePackages[0].storeProduct.introductoryPrice.cycles',
      );
    });

    test('package offeringIdentifier 与 presentedOfferingContext 不一致', () {
      expectWireError(
        () => decodeMutated((raw) => firstPackage(raw)['offeringIdentifier'] = 'other'),
        'all.default.availablePackages[0].presentedOfferingContext.offeringIdentifier',
      );
    });

    test('storeProduct.presentedOfferingContext 缺失（两端都必须填）', () {
      expectWireError(
        () => decodeMutated((raw) => (firstPackage(raw)['storeProduct'] as Map).remove('presentedOfferingContext')),
        'all.default.availablePackages[0].storeProduct.presentedOfferingContext',
      );
    });

    test('Android pricingPhase 缺 price', () {
      expectWireError(
        () => decodeMutated(
          (raw) => ((((firstPackage(raw)['storeProduct'] as Map)['subscriptionOptions'] as List)[0] as Map)['pricingPhases']
                  as List)[0]
              .remove('price'),
          fixture: 'wire/offerings-android.json',
        ),
        'all.default.availablePackages[0].storeProduct.subscriptionOptions[0].pricingPhases[0].price',
      );
    });

    test('purchase-result 缺 storeTransaction / 交易 id 为空', () {
      final raw = mutableFixture('wire/purchase-result.json')..remove('storeTransaction');
      expectWireError(() => PurchaseResult.fromJson(raw), 'storeTransaction');
      final empty = mutableFixture('wire/purchase-result.json');
      (empty['storeTransaction'] as Map)['transactionIdentifier'] = '';
      expectWireError(() => PurchaseResult.fromJson(empty), 'storeTransaction.transactionIdentifier');
    });
  });

  group('枚举：未知值落 RC 的 unknown 档', () {
    test('packageType / productCategory / periodUnit / recurrenceMode / offerPaymentMode', () {
      final raw = mutableFixture('wire/offerings-android.json');
      final pkg = ((raw['all'] as Map)['default'] as Map)['availablePackages'][0] as Map<String, dynamic>;
      pkg['packageType'] = 'quarterly';
      final product = pkg['storeProduct'] as Map<String, dynamic>;
      product['productCategory'] = 'consumable';
      (product['introductoryPrice'] as Map)['periodUnit'] = 'fortnight';
      final phase = ((product['subscriptionOptions'] as List)[1] as Map)['pricingPhases'][0] as Map<String, dynamic>;
      phase['recurrenceMode'] = 'sometimes';
      phase['offerPaymentMode'] = 'barter';
      raw['current'] = null;

      final decoded = Offerings.fromJson(raw).all['default']!.availablePackages[0];
      expect(decoded.packageType, PackageType.unknown);
      expect(decoded.storeProduct.productCategory, isNull);
      expect(decoded.storeProduct.introductoryPrice!.periodUnit, PeriodUnit.unknown);
      final decodedPhase = decoded.storeProduct.subscriptionOptions![1].pricingPhases[0];
      expect(decodedPhase.recurrenceMode, RecurrenceMode.unknown);
      expect(decodedPhase.offerPaymentMode, isNull);
    });

    test('packageType 全表', () {
      const table = {
        'unknown': PackageType.unknown,
        'custom': PackageType.custom,
        'lifetime': PackageType.lifetime,
        'annual': PackageType.annual,
        'six_month': PackageType.sixMonth,
        'three_month': PackageType.threeMonth,
        'two_month': PackageType.twoMonth,
        'monthly': PackageType.monthly,
        'weekly': PackageType.weekly,
      };
      final template = mutableFixture('wire/offerings-ios.json');
      final pkg = ((template['all'] as Map)['default'] as Map)['availablePackages'][0] as Map<String, dynamic>;
      table.forEach((wire, expected) {
        expect(Package.fromJson({...pkg, 'packageType': wire}).packageType, expected, reason: wire);
      });
    });
  });

  test('枚举值集与顺序照 RC 10.13.1', () {
    expect(PackageType.values.map((e) => e.name),
        ['unknown', 'custom', 'lifetime', 'annual', 'sixMonth', 'threeMonth', 'twoMonth', 'monthly', 'weekly']);
    expect(PeriodUnit.values.map((e) => e.name), ['day', 'week', 'month', 'year', 'unknown']);
    expect(ProductCategory.values.map((e) => e.name), ['nonSubscription', 'subscription']);
    expect(RecurrenceMode.values.map((e) => e.name), ['infiniteRecurring', 'finiteRecurring', 'nonRecurring', 'unknown']);
    expect(OfferPaymentMode.values.map((e) => e.name), ['freeTrial', 'singlePayment', 'discountedRecurringPayment']);
    expect(IntroEligibilityStatus.values.map((e) => e.name), [
      'introEligibilityStatusUnknown',
      'introEligibilityStatusIneligible',
      'introEligibilityStatusEligible',
      'introEligibilityStatusNoIntroOfferExists',
    ]);
  });

  test('PresentedOfferingContext.toJson 照 RC', () {
    expect(context.toJson(), {'offeringIdentifier': 'default', 'placementIdentifier': null, 'targetingContext': null});
    expect(
      const PresentedOfferingContext('o', 'p', PresentedOfferingTargetingContext(3, 'r')).toJson(),
      {'offeringIdentifier': 'o', 'placementIdentifier': 'p', 'targetingContext': {'revision': 3, 'ruleId': 'r'}},
    );
  });
}
