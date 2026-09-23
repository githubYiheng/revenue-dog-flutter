import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'entitlement_infos.dart';
import 'store_transaction.dart';
import 'subscription_info.dart';

/// 用户的完整购买 / 权益快照。对照 RC：字段集（14 字段）、构造签名、默认值逐字照 RC `CustomerInfo`；
/// 填充规则见设计 §5.1。时间字段为 UTC ISO 8601 字符串（通道上是 epoch 毫秒，Dart 格式化）。
class CustomerInfo extends Equatable {
  /// 权益。
  final EntitlementInfos entitlements;

  /// 商品 → 购买时间。不变式：键集 == [allPurchasedProductIdentifiers]。
  final Map<String, String?> allPurchaseDates;

  /// 有效订阅的商品（原生已排序）。不变式：== [subscriptionsByProductIdentifier] 中 `isActive` 的键。
  final List<String> activeSubscriptions;

  /// 买过的全部商品（订阅 + 一次性，原生已排序）。
  final List<String> allPurchasedProductIdentifiers;

  /// 全部非订阅交易，按购买时间升序。
  final List<StoreTransaction> nonSubscriptionTransactions;

  /// 首次见到该用户的时间。
  final String firstSeen;

  /// 最初的 App User ID。
  final String originalAppUserId;

  /// 订阅商品 → 到期时间。
  final Map<String, String?> allExpirationDates;

  /// 本次数据的服务端时间。
  final String requestDate;

  /// 全部订阅中最晚的到期时间；null = 无到期。
  final String? latestExpirationDate;

  /// 首次购买 app 的时间（iOS）。
  final String? originalPurchaseDate;

  /// 首次购买时的 app 版本（iOS；Android 恒 null，同 RC）。
  final String? originalApplicationVersion;

  /// 订阅管理页 URL。
  final String? managementURL;

  /// 商品 → 订阅明细。
  final Map<String, SubscriptionInfo> subscriptionsByProductIdentifier;

  const CustomerInfo(
    this.entitlements,
    this.allPurchaseDates,
    this.activeSubscriptions,
    this.allPurchasedProductIdentifiers,
    this.nonSubscriptionTransactions,
    this.firstSeen,
    this.originalAppUserId,
    this.allExpirationDates,
    this.requestDate, {
    this.latestExpirationDate,
    this.originalPurchaseDate,
    this.originalApplicationVersion,
    this.managementURL,
    this.subscriptionsByProductIdentifier = const {},
  });

  /// 由通道 map 构造（设计 §5.1）。
  ///
  /// 偏离 RC：输入是我方 wire 形状（epoch 毫秒 + lower_snake_case 枚举），不是 RC 的 ISO + 大写枚举；
  /// 缺键 / 类型错抛码 12 的 `PlatformException`（`details.wireKey` 为出错路径），不抛裸 `TypeError`；
  /// `subscriptionsByProductIdentifier` 为必需键（RC 缺省 `{}`）。
  factory CustomerInfo.fromJson(Map<String, dynamic> json) =>
      decodeCustomerInfo(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [
        entitlements,
        allPurchaseDates,
        activeSubscriptions,
        allPurchasedProductIdentifiers,
        nonSubscriptionTransactions,
        firstSeen,
        originalAppUserId,
        allExpirationDates,
        requestDate,
        latestExpirationDate,
        originalPurchaseDate,
        originalApplicationVersion,
        managementURL,
        subscriptionsByProductIdentifier,
      ];
}

/// wire → [CustomerInfo]（不导出）。
CustomerInfo decodeCustomerInfo(WireMap w) => CustomerInfo(
      decodeEntitlementInfos(w.requireMap('entitlements')),
      w.requireDateMap('allPurchaseDates'),
      w.requireStringList('activeSubscriptions'),
      w.requireStringList('allPurchasedProductIdentifiers'),
      w.requireMapList('nonSubscriptionTransactions').map(decodeStoreTransaction).toList(),
      w.requireDate('firstSeen'),
      w.requireString('originalAppUserId'),
      w.requireDateMap('allExpirationDates'),
      w.requireDate('requestDate'),
      latestExpirationDate: w.optionalDate('latestExpirationDate'),
      originalPurchaseDate: w.optionalDate('originalPurchaseDate'),
      originalApplicationVersion: w.optionalString('originalApplicationVersion'),
      managementURL: w.optionalString('managementURL'),
      subscriptionsByProductIdentifier: w
          .requireMapOfMaps('subscriptionsByProductIdentifier')
          .map((k, v) => MapEntry(k, decodeSubscriptionInfo(v))),
    );
