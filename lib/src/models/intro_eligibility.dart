import '../wire.dart';

/// 试用 / 优惠价资格。对照 RC：值集（4 值）与顺序逐字照 RC 10.13.1 `IntroEligibilityStatus`。
///
/// 通道值 `unknown|ineligible|eligible|no_intro_offer_exists`，Dart 查表映射（偏离 RC 按下标取值）。
enum IntroEligibilityStatus {
  /// 信息不足，无法判定（Android 恒为此值，同 RC）。
  introEligibilityStatusUnknown,

  /// 不符合资格。
  introEligibilityStatusIneligible,

  /// 符合资格。
  introEligibilityStatusEligible,

  /// 该商品没有试用 / 优惠价。
  introEligibilityStatusNoIntroOfferExists,
}

/// 通道值 → [IntroEligibilityStatus]（不导出）。
const Map<String, IntroEligibilityStatus> introEligibilityStatusByWire = {
  'unknown': IntroEligibilityStatus.introEligibilityStatusUnknown,
  'ineligible': IntroEligibilityStatus.introEligibilityStatusIneligible,
  'eligible': IntroEligibilityStatus.introEligibilityStatusEligible,
  'no_intro_offer_exists': IntroEligibilityStatus.introEligibilityStatusNoIntroOfferExists,
};

/// 单个商品的资格结果。对照 RC：类形状逐字照 RC 10.13.1 `IntroEligibility`（非 Equatable、可变字段、只有 `fromJson` 构造）。
///
/// 通道形状（设计 §5.5）：`{status, description}`，description 每状态一句固定英文（见 `test/fixtures/README.md`）。
/// 派生口径（设计 §1 #19）：iOS 由 offerings 里商品的介绍性优惠派生（有优惠且有资格 → eligible，有优惠无资格 → ineligible，
/// 无优惠 → noIntroOfferExists，不在 offerings 里 → unknown；偏离 RC iOS 直查 StoreKit）；Android 恒 unknown（同 RC）。
class IntroEligibility {
  /// 资格状态。
  IntroEligibilityStatus status;

  /// 状态说明。
  String description;

  /// 由通道 map 构造。缺键 / 类型错抛码 12；未知状态 → [IntroEligibilityStatus.introEligibilityStatusUnknown]。
  IntroEligibility.fromJson(Map<String, dynamic> map) : this._fromWire(WireMap.fromChannel(map));

  IntroEligibility._fromWire(WireMap w)
      : status = w.requireEnum(
          'status',
          introEligibilityStatusByWire,
          IntroEligibilityStatus.introEligibilityStatusUnknown,
        ),
        description = w.requireString('description');
}

/// wire `{productId: {status, description}}` → `Map<String, IntroEligibility>`（不导出）。
/// 每个请求的商品都必须有结果（设计 §1 #19：不在 offerings 里 → unknown），缺失 → 码 12。
Map<String, IntroEligibility> decodeIntroEligibilityMap(WireMap w, List<String> productIdentifiers) {
  for (final id in productIdentifiers) {
    if (!w.map.containsKey(id)) throwWireError(w.keyPath(id), 'missing eligibility for requested product');
  }
  return w.map.map((productId, _) => MapEntry(productId, IntroEligibility._fromWire(w.requireMap(productId))));
}
