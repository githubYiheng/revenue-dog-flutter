// wire fixture → 模型字段（三方对账的 Dart 一方，fixtures/README.md）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog/revenue_dog.dart';

import 'helpers.dart';

CustomerInfo decode(String fixture) =>
    CustomerInfo.fromJson(Map<String, dynamic>.from(loadFixtureAsChannelValue(fixture)! as Map));

Map<String, dynamic> mutableFixture(String fixture) => loadFixture(fixture)! as Map<String, dynamic>;

/// 断言 [body] 抛码 12 且 `details.wireKey == wireKey`。
void expectWireError(void Function() body, String wireKey) {
  expect(
    body,
    throwsA(
      isA<PlatformException>()
          .having((e) => e.code, 'code', '12')
          .having((e) => e.message, 'message', 'unexpected backend response')
          .having((e) => (e.details as Map)['wireKey'], 'wireKey', wireKey)
          .having((e) => (e.details as Map)['code'], 'details.code', 12)
          .having((e) => (e.details as Map)['readableErrorCode'], 'readable', 'UnexpectedBackendResponseError')
          .having((e) => (e.details as Map)['revdogCode'], 'revdogCode', 'unexpectedBackendResponseError'),
    ),
  );
}

/// 三条不变式（fixtures/README.md「不变式」）。
void expectInvariants(CustomerInfo info) {
  expect(
    info.entitlements.active.keys.toSet(),
    info.entitlements.all.entries.where((e) => e.value.isActive).map((e) => e.key).toSet(),
    reason: 'entitlements.active 键集 == isActive 的键集',
  );
  expect(
    info.activeSubscriptions.toSet(),
    info.subscriptionsByProductIdentifier.entries.where((e) => e.value.isActive).map((e) => e.key).toSet(),
    reason: 'activeSubscriptions == subscriptionsByProductIdentifier 中 isActive 的键',
  );
  expect(
    info.allPurchaseDates.keys.toSet(),
    info.allPurchasedProductIdentifiers.toSet(),
    reason: 'allPurchaseDates 键集 == allPurchasedProductIdentifiers',
  );
}

void main() {
  group('customer-info-minimal', () {
    final info = decode('wire/customer-info-minimal.json');

    test('字段', () {
      expect(info.originalAppUserId, r'$RDAnonymousID:0123456789abcdef0123456789abcdef');
      expect(info.requestDate, '2026-09-23T12:00:00.000Z');
      expect(info.firstSeen, '2026-09-23T11:58:00.000Z');
      expect(info.entitlements.all, isEmpty);
      expect(info.entitlements.active, isEmpty);
      expect(info.entitlements.verification, VerificationResult.notRequested);
      expect(info.activeSubscriptions, isEmpty);
      expect(info.allPurchasedProductIdentifiers, isEmpty);
      expect(info.allPurchaseDates, isEmpty);
      expect(info.allExpirationDates, isEmpty);
      expect(info.nonSubscriptionTransactions, isEmpty);
      expect(info.subscriptionsByProductIdentifier, isEmpty);
      expect(info.latestExpirationDate, isNull);
      expect(info.originalPurchaseDate, isNull);
      expect(info.originalApplicationVersion, isNull);
      expect(info.managementURL, isNull);
    });

    test('不变式', () => expectInvariants(info));
  });

  group('customer-info-full', () {
    final info = decode('wire/customer-info-full.json');

    test('顶层', () {
      expect(info.originalAppUserId, 'user_full_001');
      expect(info.requestDate, '2026-09-23T12:00:00.000Z');
      expect(info.firstSeen, '2018-08-01T00:00:00.000Z');
      expect(info.managementURL, 'https://play.google.com/store/account/subscriptions');
      expect(info.originalPurchaseDate, '2018-08-01T00:00:00.000Z');
      expect(info.originalApplicationVersion, isNull);
      expect(info.latestExpirationDate, '2099-01-01T00:00:00.000Z');
      expect(info.activeSubscriptions, ['premium_monthly']);
      expect(info.allPurchasedProductIdentifiers, ['coin_pack_100', 'lifetime_unlock', 'premium_monthly', 'pro_annual']);
      expect(info.allExpirationDates, {
        'premium_monthly': '2099-01-01T00:00:00.000Z',
        'pro_annual': '2020-08-01T00:00:00.000Z',
      });
      expect(info.allPurchaseDates, {
        'coin_pack_100': '2026-09-01T07:00:00.000Z',
        'lifetime_unlock': '2026-07-15T09:30:00.000Z',
        'premium_monthly': '2026-09-20T12:00:00.000Z',
        'pro_annual': '2019-08-01T00:00:00.000Z',
      });
    });

    test('权益：活跃订阅 / 已过期订阅 / 一次性商品的终身权益', () {
      expect(info.entitlements.all.keys.toSet(), {'premium', 'legacy_pro', 'lifetime'});
      expect(info.entitlements.active.keys.toSet(), {'premium', 'lifetime'});

      expect(
        info.entitlements.all['premium'],
        const EntitlementInfo(
          'premium',
          true,
          true,
          '2026-09-20T12:00:00.000Z',
          '2026-06-20T12:00:00.000Z',
          'premium_monthly',
          true,
          ownershipType: OwnershipType.purchased,
          store: Store.playStore,
          periodType: PeriodType.normal,
          expirationDate: '2099-01-01T00:00:00.000Z',
          productPlanIdentifier: 'monthly-base',
        ),
      );

      final legacy = info.entitlements.all['legacy_pro']!;
      expect(legacy.isActive, isFalse);
      expect(legacy.willRenew, isFalse);
      expect(legacy.expirationDate, '2020-08-01T00:00:00.000Z');
      expect(legacy.unsubscribeDetectedAt, '2020-07-01T00:00:00.000Z');
      expect(legacy.billingIssueDetectedAt, '2020-07-30T00:00:00.000Z');
      expect(legacy.productPlanIdentifier, 'annual-base');

      final lifetime = info.entitlements.all['lifetime']!;
      expect(lifetime.isActive, isTrue);
      expect(lifetime.willRenew, isFalse);
      expect(lifetime.expirationDate, isNull);
      expect(lifetime.store, Store.appStore);
      expect(lifetime.ownershipType, OwnershipType.purchased);
      expect(lifetime.productIdentifier, 'lifetime_unlock');
      expect(lifetime.productPlanIdentifier, isNull);
      expect(lifetime.originalPurchaseDate, '2026-07-15T09:30:00.000Z');
      expect(lifetime.verification, VerificationResult.notRequested);
    });

    test('订阅明细（19 字段）', () {
      expect(
        info.subscriptionsByProductIdentifier['premium_monthly'],
        const SubscriptionInfo(
          'premium_monthly',
          '2026-09-20T12:00:00.000Z',
          true,
          true,
          true,
          originalPurchaseDate: '2026-06-20T12:00:00.000Z',
          expiresDate: '2099-01-01T00:00:00.000Z',
          store: Store.playStore,
          ownershipType: OwnershipType.purchased,
          periodType: PeriodType.normal,
          storeTransactionId: 'GPA.3301-1111-2222-33333..3',
          displayName: 'Premium Monthly',
          managementURL: 'https://play.google.com/store/account/subscriptions',
          productPlanIdentifier: 'monthly-base',
        ),
      );
      final expired = info.subscriptionsByProductIdentifier['pro_annual']!;
      expect(expired.isActive, isFalse);
      expect(expired.willRenew, isFalse);
      expect(expired.unsubscribeDetectedAt, '2020-07-01T00:00:00.000Z');
      expect(expired.billingIssuesDetectedAt, '2020-07-30T00:00:00.000Z');
      expect(expired.gracePeriodExpiresDate, '2020-08-04T00:00:00.000Z');
      expect(expired.refundedAt, isNull);
      expect(expired.autoResumeDate, isNull);
      expect(expired.displayName, 'Pro Annual');
    });

    test('非订阅交易按购买时间升序', () {
      expect(info.nonSubscriptionTransactions, const [
        StoreTransaction('ns_lifetime_001', 'lifetime_unlock', '2026-07-15T09:30:00.000Z'),
        StoreTransaction('ns_coins_001', 'coin_pack_100', '2026-09-01T07:00:00.000Z'),
      ]);
    });

    test('不变式', () => expectInvariants(info));

    test('值相等（equatable）：同一 fixture 解两次相等', () {
      expect(decode('wire/customer-info-full.json'), info);
    });
  });

  group('customer-info-original-purchase-date-null', () {
    final info = decode('wire/customer-info-original-purchase-date-null.json');

    test('权益 originalPurchaseDate 已由插件回退为 latestPurchaseDate；订阅明细保持 null', () {
      final premium = info.entitlements.all['premium']!;
      expect(premium.originalPurchaseDate, premium.latestPurchaseDate);
      expect(premium.originalPurchaseDate, '2026-09-20T12:00:00.000Z');
      expect(info.subscriptionsByProductIdentifier['premium_monthly']!.originalPurchaseDate, isNull);
    });

    test('不变式', () => expectInvariants(info));
  });

  group('log-in-result', () {
    test('字段', () {
      final raw = loadFixture('wire/log-in-result.json')! as Map<String, dynamic>;
      expect(raw['created'], isTrue);
      final info = CustomerInfo.fromJson(Map<String, dynamic>.from(raw['customerInfo'] as Map));
      expect(info, decode('wire/customer-info-minimal.json'));
    });
  });

  group('解码失败 → 码 12 + wireKey', () {
    const fixture = 'wire/customer-info-full.json';

    test('顶层非空键缺失', () {
      for (final key in [
        'entitlements',
        'activeSubscriptions',
        'allPurchasedProductIdentifiers',
        'firstSeen',
        'originalAppUserId',
        'requestDate',
        'allExpirationDates',
        'allPurchaseDates',
        'nonSubscriptionTransactions',
        'subscriptionsByProductIdentifier',
      ]) {
        final json = mutableFixture(fixture)..remove(key);
        expectWireError(() => CustomerInfo.fromJson(json), key);
      }
    });

    test('订阅明细 purchaseDate 缺失 → 路径到键', () {
      final json = mutableFixture(fixture);
      ((json['subscriptionsByProductIdentifier'] as Map)['premium_monthly'] as Map).remove('purchaseDate');
      expectWireError(() => CustomerInfo.fromJson(json), 'subscriptionsByProductIdentifier.premium_monthly.purchaseDate');
    });

    test('权益 originalPurchaseDate 为 null（插件本应回退）', () {
      final json = mutableFixture(fixture);
      (((json['entitlements'] as Map)['all'] as Map)['premium'] as Map)['originalPurchaseDate'] = null;
      expectWireError(() => CustomerInfo.fromJson(json), 'entitlements.all.premium.originalPurchaseDate');
    });

    test('时间类型错（ISO 字符串而非毫秒）', () {
      final json = mutableFixture(fixture)..['requestDate'] = '2026-09-23T12:00:00Z';
      expectWireError(() => CustomerInfo.fromJson(json), 'requestDate');
    });

    test('时间为 double', () {
      final json = mutableFixture(fixture)..['firstSeen'] = 1.5;
      expectWireError(() => CustomerInfo.fromJson(json), 'firstSeen');
    });

    test('可空时间类型错', () {
      final json = mutableFixture(fixture)..['latestExpirationDate'] = 'soon';
      expectWireError(() => CustomerInfo.fromJson(json), 'latestExpirationDate');
    });

    test('bool 类型错', () {
      final json = mutableFixture(fixture);
      (((json['entitlements'] as Map)['all'] as Map)['lifetime'] as Map)['isActive'] = 'true';
      expectWireError(() => CustomerInfo.fromJson(json), 'entitlements.all.lifetime.isActive');
    });

    test('枚举键缺失', () {
      final json = mutableFixture(fixture);
      ((json['subscriptionsByProductIdentifier'] as Map)['pro_annual'] as Map).remove('store');
      expectWireError(() => CustomerInfo.fromJson(json), 'subscriptionsByProductIdentifier.pro_annual.store');
    });

    test('列表元素类型错', () {
      final json = mutableFixture(fixture)..['activeSubscriptions'] = ['premium_monthly', 1];
      expectWireError(() => CustomerInfo.fromJson(json), 'activeSubscriptions[1]');
    });

    test('非订阅交易 id 为空串 → 码 12（不吞成空串，偏离 RC）', () {
      final json = mutableFixture(fixture);
      ((json['nonSubscriptionTransactions'] as List)[0] as Map)['transactionIdentifier'] = '';
      expectWireError(() => CustomerInfo.fromJson(json), 'nonSubscriptionTransactions[0].transactionIdentifier');
    });

    test('非字符串 map 键', () {
      final json = mutableFixture(fixture)..['allPurchaseDates'] = <Object?, Object?>{1: 0};
      expectWireError(() => CustomerInfo.fromJson(json), 'allPurchaseDates');
    });

    test('通道允许类型之外的值', () {
      final json = mutableFixture(fixture)..['managementURL'] = Uri.parse('https://x');
      expectWireError(() => CustomerInfo.fromJson(json), 'managementURL');
    });
  });

  group('枚举：未知值落 unknown 档', () {
    test('store / periodType / ownershipType / verification', () {
      final json = mutableFixture('wire/customer-info-full.json');
      final premium = ((json['entitlements'] as Map)['all'] as Map)['premium'] as Map
        ..['store'] = 'roku'
        ..['periodType'] = 'promotional'
        ..['ownershipType'] = 'borrowed'
        ..['verification'] = 'maybe';
      expect(premium, isNotNull);
      final info = CustomerInfo.fromJson(json).entitlements.all['premium']!;
      expect(info.store, Store.unknownStore);
      expect(info.periodType, PeriodType.unknown);
      expect(info.ownershipType, OwnershipType.unknown);
      expect(info.verification, VerificationResult.notRequested);
    });

    test('store 全表', () {
      const table = {
        'app_store': Store.appStore,
        'mac_app_store': Store.macAppStore,
        'play_store': Store.playStore,
        'stripe': Store.stripe,
        'promotional': Store.promotional,
        'amazon': Store.amazon,
        'rc_billing': Store.rcBilling,
        'paddle': Store.paddle,
        'test_store': Store.testStore,
        'external': Store.externalStore,
        'galaxy': Store.galaxy,
        'unknown': Store.unknownStore,
      };
      table.forEach((wire, store) {
        final json = mutableFixture('wire/customer-info-full.json');
        ((json['subscriptionsByProductIdentifier'] as Map)['pro_annual'] as Map)['store'] = wire;
        expect(CustomerInfo.fromJson(json).subscriptionsByProductIdentifier['pro_annual']!.store, store, reason: wire);
      });
    });
  });

  test('时间格式：UTC、带毫秒、Z 结尾', () {
    final json = mutableFixture('wire/customer-info-minimal.json')..['requestDate'] = 1790164800123;
    expect(CustomerInfo.fromJson(json).requestDate, '2026-09-23T12:00:00.123Z');
  });

  test('枚举值集与顺序照 RC 10.13.1', () {
    expect(Store.values.map((e) => e.name), [
      'appStore', 'macAppStore', 'playStore', 'stripe', 'promotional', 'unknownStore', //
      'amazon', 'rcBilling', 'paddle', 'testStore', 'externalStore', 'galaxy',
    ]);
    expect(PeriodType.values.map((e) => e.name), ['intro', 'normal', 'trial', 'prepaid', 'unknown']);
    expect(OwnershipType.values.map((e) => e.name), ['purchased', 'familyShared', 'unknown']);
    expect(VerificationResult.values.map((e) => e.name), ['notRequested', 'verified', 'verifiedOnDevice', 'failed']);
    expect(LogLevel.values.map((e) => e.name), ['verbose', 'debug', 'info', 'warn', 'error']);
    expect(StoreKitVersion.values.map((e) => e.name), ['storeKit1', 'storeKit2', 'defaultVersion']);
    expect(EntitlementVerificationMode.values.map((e) => e.name), ['disabled', 'informational']);
    expect(PurchasesAreCompletedByType.values.map((e) => e.name), ['myApp', 'revenueCat']);
  });
}
