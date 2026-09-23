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
export 'src/models/log_in_result.dart' show LogInResult;
export 'src/models/log_level.dart' show LogLevel;
export 'src/models/purchases_completed_by.dart'
    show
        PurchasesAreCompletedBy,
        PurchasesAreCompletedByMyApp,
        PurchasesAreCompletedByRevenueCat,
        PurchasesAreCompletedByType;
export 'src/models/purchases_configuration.dart' show PurchasesConfiguration;
export 'src/models/store.dart' show Store;
export 'src/models/store_transaction.dart' show StoreTransaction;
export 'src/models/storekit_version.dart' show StoreKitVersion;
export 'src/models/subscription_info.dart' show SubscriptionInfo;
export 'src/models/verification_result.dart' show VerificationResult;
export 'src/purchases.dart' show Purchases;
export 'src/purchases_state.dart' show CustomerInfoUpdateListener, LogHandler;
export 'src/unsupported_platform_exception.dart' show UnsupportedPlatformException;

// M2 留位（模型文件落在 src/models/）：Offerings / Offering / Package / PackageType / StoreProduct /
// IntroductoryPrice / PeriodUnit / ProductCategory / PresentedOfferingContext / SubscriptionOption /
// PricingPhase / Price / Period / PurchaseParams / PurchaseResult / IntroEligibility / IntroEligibilityStatus。
