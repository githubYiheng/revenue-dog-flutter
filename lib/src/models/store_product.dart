import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'introductory_price.dart';
import 'presented_offering_context.dart';
import 'product_category.dart';
import 'store_product_discount.dart';
import 'subscription_option.dart';

/// 商店商品。对照 RC：字段集（19 字段）、构造签名逐字照 RC 10.13.1 `StoreProduct`；填充规则见设计 §5.4。
///
/// 通道形状：`{identifier, title, description, priceAmountMicros, priceString, currencyCode, subscriptionPeriod,
/// productCategory, introductoryPrice, defaultOption, subscriptionOptions, presentedOfferingContext}`。
/// - [price] 由 Dart 从 `priceAmountMicros` 派生（`micros / 10⁶`）；
/// - Android 订阅商品 [identifier] = `subscriptionId:basePlanId`（同 RC）；
/// - [discounts]、[pricePerWeek] / [pricePerMonth] / [pricePerYear] 及其字符串为文档化常量 `null`（通道不发）；
/// - [defaultOption] / [subscriptionOptions] iOS 恒 null（同 RC iOS），Android 一次性商品为 null；
/// - [presentedOfferingContext] 两端都填（偏离 RC iOS 不填：iOS 上用 storeProduct 购买也不丢归因）。
class StoreProduct extends Equatable {
  /// 商品标识。
  final String identifier;

  /// 商店本地化描述。
  final String description;

  /// 商店本地化标题。
  final String title;

  /// 价格（`priceAmountMicros / 10⁶`）。
  final double price;

  /// 商店本地化价串。
  final String priceString;

  /// ISO 4217 币种码。
  final String currencyCode;

  /// 介绍性优惠；null = 无优惠。
  final IntroductoryPrice? introductoryPrice;

  /// iOS 促销优惠（我方恒 null）。
  final List<StoreProductDiscount>? discounts;

  /// 商品类别。
  final ProductCategory? productCategory;

  /// 默认订阅选项（Android 订阅）。
  final SubscriptionOption? defaultOption;

  /// 全部订阅选项（Android 订阅）。
  final List<SubscriptionOption>? subscriptionOptions;

  /// 所属 offering 上下文。
  final PresentedOfferingContext? presentedOfferingContext;

  /// ISO 8601 订阅周期（如 `P1M`）；null = 非订阅。
  final String? subscriptionPeriod;

  /// 周价（我方恒 null）。
  final double? pricePerWeek;

  /// 月价（我方恒 null）。
  final double? pricePerMonth;

  /// 年价（我方恒 null）。
  final double? pricePerYear;

  /// 周价串（我方恒 null）。
  final String? pricePerWeekString;

  /// 月价串（我方恒 null）。
  final String? pricePerMonthString;

  /// 年价串（我方恒 null）。
  final String? pricePerYearString;

  const StoreProduct(
    this.identifier,
    this.description,
    this.title,
    this.price,
    this.priceString,
    this.currencyCode, {
    this.introductoryPrice,
    this.discounts,
    this.productCategory,
    this.defaultOption,
    this.subscriptionOptions,
    this.presentedOfferingContext,
    this.subscriptionPeriod,
    this.pricePerWeek,
    this.pricePerMonth,
    this.pricePerYear,
    this.pricePerWeekString,
    this.pricePerMonthString,
    this.pricePerYearString,
  });

  /// 由通道 map 构造（设计 §5.4）。缺键 / 类型错抛码 12。
  ///
  /// 偏离 RC：输入是我方 wire 形状（`priceAmountMicros` 而非 `price`、`introductoryPrice` 而非 `introPrice`、
  /// lower_snake_case 枚举）。
  factory StoreProduct.fromJson(Map<String, dynamic> json) => decodeStoreProduct(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [
        identifier,
        description,
        title,
        price,
        priceString,
        currencyCode,
        introductoryPrice,
        discounts,
        productCategory,
        defaultOption,
        subscriptionOptions,
        presentedOfferingContext,
        subscriptionPeriod,
        pricePerWeek,
        pricePerMonth,
        pricePerYear,
        pricePerWeekString,
        pricePerMonthString,
        pricePerYearString,
      ];
}

/// 对照 RC：`ExtendedStoreProduct`（弃用的 offering 标识 getter）逐字照抄。
extension ExtendedStoreProduct on StoreProduct {
  /// 所属 offering 标识。
  @Deprecated('use presentedOfferingContext')
  String? get presentedOfferingIdentifier => presentedOfferingContext?.offeringIdentifier;
}

/// wire → [StoreProduct]（不导出）。
StoreProduct decodeStoreProduct(WireMap w) {
  final intro = w.optionalMap('introductoryPrice');
  final defaultOption = w.optionalMap('defaultOption');
  return StoreProduct(
    w.requireString('identifier'),
    w.requireString('description'),
    w.requireString('title'),
    priceFromMicros(w.requireInt('priceAmountMicros')),
    w.requireString('priceString'),
    w.requireString('currencyCode'),
    introductoryPrice: intro == null ? null : decodeIntroductoryPrice(intro),
    productCategory: w.requireEnum<ProductCategory?>('productCategory', productCategoryByWire, null),
    defaultOption: defaultOption == null ? null : decodeSubscriptionOption(defaultOption),
    subscriptionOptions: w.optionalMapList('subscriptionOptions')?.map(decodeSubscriptionOption).toList(),
    presentedOfferingContext: decodePresentedOfferingContext(w.requireMap('presentedOfferingContext')),
    subscriptionPeriod: w.optionalString('subscriptionPeriod'),
  );
}
