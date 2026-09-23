/// RevenueDog Flutter SDK。
///
/// 从 RC 迁移：把 `import 'package:purchases_flutter/purchases_flutter.dart';` 换成本文件，其余代码不动
/// （公开面与 RC `purchases_flutter` 10.13.1 逐字同形，差异见 README「与 purchases_flutter 的差异」）。
library;

export 'src/errors.dart' show PurchasesErrorHelper;
export 'src/generated/error_codes.dart' show PurchasesErrorCode;
export 'src/models/customer_info.dart' show CustomerInfo;
export 'src/models/entitlement_info.dart' show EntitlementInfo, OwnershipType, PeriodType;
export 'src/models/entitlement_infos.dart' show EntitlementInfos;
export 'src/models/entitlement_verification_mode.dart' show EntitlementVerificationMode;
export 'src/models/installments_info.dart' show InstallmentsInfo;
export 'src/models/intro_eligibility.dart' show IntroEligibility, IntroEligibilityStatus;
export 'src/models/introductory_price.dart' show IntroductoryPrice;
export 'src/models/log_in_result.dart' show LogInResult;
export 'src/models/log_level.dart' show LogLevel;
export 'src/models/offering.dart' show Offering, OfferingX, PackageListX;
export 'src/models/offerings.dart' show Offerings;
export 'src/models/package.dart' show ExtendedPackage, Package, PackageType;
export 'src/models/period.dart' show Period;
export 'src/models/period_unit.dart' show PeriodUnit;
export 'src/models/presented_offering_context.dart'
    show PresentedOfferingContext, PresentedOfferingTargetingContext;
export 'src/models/price.dart' show Price;
export 'src/models/pricing_phase.dart' show OfferPaymentMode, PricingPhase, RecurrenceMode;
export 'src/models/product_category.dart' show ProductCategory;
export 'src/models/purchase_params.dart' show PurchaseParams;
export 'src/models/purchase_result.dart' show PurchaseResult;
export 'src/models/purchases_completed_by.dart'
    show
        PurchasesAreCompletedBy,
        PurchasesAreCompletedByMyApp,
        PurchasesAreCompletedByRevenueCat,
        PurchasesAreCompletedByType;
export 'src/models/purchases_configuration.dart' show PurchasesConfiguration;
export 'src/models/store.dart' show Store;
export 'src/models/store_product.dart' show ExtendedStoreProduct, StoreProduct;
export 'src/models/store_product_discount.dart' show StoreProductDiscount;
export 'src/models/store_transaction.dart' show StoreTransaction;
export 'src/models/storekit_version.dart' show StoreKitVersion;
export 'src/models/subscription_info.dart' show SubscriptionInfo;
export 'src/models/subscription_option.dart' show ExtendedSubscriptionOption, SubscriptionOption;
export 'src/models/verification_result.dart' show VerificationResult;
export 'src/purchases.dart' show Purchases;
export 'src/purchases_state.dart' show CustomerInfoUpdateListener, LogHandler;
export 'src/unsupported_platform_exception.dart' show UnsupportedPlatformException;
