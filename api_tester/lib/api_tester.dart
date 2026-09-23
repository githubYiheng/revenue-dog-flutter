// revenue_dog 公开 API 编译期守门（设计 §7「公开 API 基线」、D6）。
//
// **只编译、不运行**：`flutter analyze` 零错即通过（门禁 ⑤）。纪律照 `sdk/android/api-tester`：
// - `package:revenue_dog/revenue_dog.dart` 导出的**每个**公开符号都在这里被引用一次；
// - 方法按各种参数形态各调一遍，返回值赋给**显式类型**的变量 —— 改签名 / 改返回类型 / 改可空性都会在这里编译失败；
// - 模型逐个构造（位置参数 + 全部命名参数 + fromJson）并读每个 getter；可变字段（配置、IntroEligibility）逐个写；
// - 枚举一律**穷尽 switch、不写 default**：增删值都会让这里失败，逼着同步更新本文件与公开符号基线。
// 与 RC purchases_flutter 的 api_tester 同形：公开面「只进不出」，删 / 改 = 主版本（CHANGELOG 顶部规则）。
//
// 覆盖：Purchases 32 项（设计 §1）+ isAnonymous / setLogHandler + 全部模型构造与 getter + 16 个枚举穷尽 switch
// + PurchasesErrorHelper.getErrorCode + UnsupportedPlatformException + 两个 typedef + 5 个扩展。
// 符号清单另见 `api-baseline/public-api.txt`（`scripts/api_symbols.dart --check` 比对）。
// ignore_for_file: unused_element

import 'package:flutter/services.dart';
import 'package:revenue_dog/revenue_dog.dart';

// ---------------------------------------------------------------------------
// Purchases 门面（设计 §1 #1–#32 + isAnonymous / setLogHandler）
// ---------------------------------------------------------------------------

Future<void> _checkPurchases(Package package, PurchasesConfiguration configuration) async {
  // #3 / #4 / R4
  final Future<void> configureFuture = Purchases.configure(configuration);
  await configureFuture;
  await Purchases.setLogLevel(LogLevel.debug);
  final LogHandler logHandler = (LogLevel level, String message) {};
  await Purchases.setLogHandler(logHandler);
  await Purchases.setLogHandler((level, message) {});

  // #5 / #8 / isAnonymous
  final bool isConfigured = await Purchases.isConfigured;
  final String appUserID = await Purchases.appUserID;
  final bool isAnonymous = await Purchases.isAnonymous;

  // #6 / #7
  final LogInResult logInResult = await Purchases.logIn('user_1');
  final bool created = logInResult.created;
  final CustomerInfo logInCustomerInfo = logInResult.customerInfo;
  final CustomerInfo logOutInfo = await Purchases.logOut();

  // #9
  await Purchases.enableAdServicesAttributionTokenCollection();

  // #10 / #11
  final CustomerInfo customerInfo = await Purchases.getCustomerInfo();
  final CustomerInfoUpdateListener listener = (CustomerInfo info) {};
  Purchases.addCustomerInfoUpdateListener(listener);
  Purchases.addCustomerInfoUpdateListener((info) {});
  Purchases.removeCustomerInfoUpdateListener(listener);

  // #12
  final Offerings offerings = await Purchases.getOfferings();

  // #19
  final Map<String, IntroEligibility> eligibility =
      await Purchases.checkTrialOrIntroductoryPriceEligibility(['product_a', 'product_b']);
  final Map<String, IntroEligibility> eligibilityEmpty =
      await Purchases.checkTrialOrIntroductoryPriceEligibility(const []);

  // #21 / #22
  final PurchaseResult purchaseResult = await Purchases.purchase(PurchaseParams.package(package));
  const PurchaseParams? noParams = null;
  // ignore: deprecated_member_use
  final PurchaseResult legacyResult = await Purchases.purchasePackage(package);

  // #23 / #24
  final CustomerInfo restored = await Purchases.restorePurchases();
  final Future<void> syncFuture = Purchases.syncPurchases();
  await syncFuture;

  // 类型本身（RC 同样可被实例化；全静态门面）
  final Purchases purchasesInstance = Purchases();
}

// ---------------------------------------------------------------------------
// 配置（设计 §1 #1 / #2，RC 字段全量 + 我方扩展）
// ---------------------------------------------------------------------------

PurchasesConfiguration _checkConfiguration() {
  final PurchasesConfiguration c = PurchasesConfiguration('pk_test');
  final String apiKey = c.apiKey;
  c.appUserID = 'user_1';
  c.appUserID = null;
  final String? appUserID = c.appUserID;
  c.diagnosticsEnabled = true;
  final bool diagnosticsEnabled = c.diagnosticsEnabled;
  c.preferredUILocaleOverride = 'en_US';
  final String? locale = c.preferredUILocaleOverride;
  c.purchasesAreCompletedBy = const PurchasesAreCompletedByRevenueCat();
  c.purchasesAreCompletedBy = PurchasesAreCompletedByMyApp(storeKitVersion: StoreKitVersion.storeKit2);
  c.purchasesAreCompletedBy = null;
  final PurchasesAreCompletedBy? completedBy = c.purchasesAreCompletedBy;
  c.userDefaultsSuiteName = 'group.suite';
  final String? suite = c.userDefaultsSuiteName;
  c.storeKitVersion = StoreKitVersion.defaultVersion;
  final StoreKitVersion? storeKitVersion = c.storeKitVersion;
  c.shouldShowInAppMessagesAutomatically = false;
  final bool inAppMessages = c.shouldShowInAppMessagesAutomatically;
  c.store = Store.playStore;
  final Store? store = c.store;
  c.entitlementVerificationMode = EntitlementVerificationMode.disabled;
  final EntitlementVerificationMode verificationMode = c.entitlementVerificationMode;
  c.pendingTransactionsForPrepaidPlansEnabled = true;
  final bool prepaid = c.pendingTransactionsForPrepaidPlansEnabled;
  c.automaticDeviceIdentifierCollectionEnabled = false;
  final bool deviceIds = c.automaticDeviceIdentifierCollectionEnabled;
  // 我方扩展
  c.waitsForLogInBeforeSync = true;
  final bool waits = c.waitsForLogInBeforeSync;
  c.baseUrl = 'https://api-staging.revdog.org';
  final String? baseUrl = c.baseUrl;

  // RC 的级联写法（宿主最常见的形态）
  final PurchasesConfiguration cascade = PurchasesConfiguration('pk_test')
    ..appUserID = 'user_1'
    ..diagnosticsEnabled = true;

  final PurchasesAreCompletedByMyApp myApp =
      PurchasesAreCompletedByMyApp(storeKitVersion: StoreKitVersion.storeKit2);
  final StoreKitVersion myAppStoreKit = myApp.storeKitVersion;
  const PurchasesAreCompletedByRevenueCat revenueCat = PurchasesAreCompletedByRevenueCat();
  const PurchasesAreCompletedBy base = revenueCat;
  return c;
}

// ---------------------------------------------------------------------------
// CustomerInfo 系（设计 §5.1 / §5.1b / §5.2 / §5.5）
// ---------------------------------------------------------------------------

void _checkCustomerInfo(CustomerInfo info, Map<String, dynamic> json) {
  final EntitlementInfos entitlements = info.entitlements;
  final Map<String, String?> allPurchaseDates = info.allPurchaseDates;
  final List<String> activeSubscriptions = info.activeSubscriptions;
  final List<String> allPurchasedProductIdentifiers = info.allPurchasedProductIdentifiers;
  final List<StoreTransaction> nonSubscriptionTransactions = info.nonSubscriptionTransactions;
  final String firstSeen = info.firstSeen;
  final String originalAppUserId = info.originalAppUserId;
  final Map<String, String?> allExpirationDates = info.allExpirationDates;
  final String requestDate = info.requestDate;
  final String? latestExpirationDate = info.latestExpirationDate;
  final String? originalPurchaseDate = info.originalPurchaseDate;
  final String? originalApplicationVersion = info.originalApplicationVersion;
  final String? managementURL = info.managementURL;
  final Map<String, SubscriptionInfo> subscriptions = info.subscriptionsByProductIdentifier;
  final List<Object?> props = info.props;

  final CustomerInfo minimal = CustomerInfo(
    entitlements,
    allPurchaseDates,
    activeSubscriptions,
    allPurchasedProductIdentifiers,
    nonSubscriptionTransactions,
    firstSeen,
    originalAppUserId,
    allExpirationDates,
    requestDate,
  );
  final CustomerInfo full = CustomerInfo(
    entitlements,
    allPurchaseDates,
    activeSubscriptions,
    allPurchasedProductIdentifiers,
    nonSubscriptionTransactions,
    firstSeen,
    originalAppUserId,
    allExpirationDates,
    requestDate,
    latestExpirationDate: latestExpirationDate,
    originalPurchaseDate: originalPurchaseDate,
    originalApplicationVersion: originalApplicationVersion,
    managementURL: managementURL,
    subscriptionsByProductIdentifier: subscriptions,
  );
  final CustomerInfo decoded = CustomerInfo.fromJson(json);
  final bool equal = minimal == full;
}

void _checkEntitlements(EntitlementInfos infos, Map<String, dynamic> json) {
  final Map<String, EntitlementInfo> all = infos.all;
  final Map<String, EntitlementInfo> active = infos.active;
  final VerificationResult verification = infos.verification;
  final List<Object?> props = infos.props;
  final EntitlementInfos constructed = EntitlementInfos(all, active);
  final EntitlementInfos constructedFull =
      EntitlementInfos(all, active, verification: VerificationResult.notRequested);
  final EntitlementInfos decoded = EntitlementInfos.fromJson(json);
}

void _checkEntitlement(EntitlementInfo e, Map<String, dynamic> json) {
  final String identifier = e.identifier;
  final bool isActive = e.isActive;
  final bool willRenew = e.willRenew;
  final String latestPurchaseDate = e.latestPurchaseDate;
  final String originalPurchaseDate = e.originalPurchaseDate;
  final String productIdentifier = e.productIdentifier;
  final bool isSandbox = e.isSandbox;
  final OwnershipType ownershipType = e.ownershipType;
  final Store store = e.store;
  final PeriodType periodType = e.periodType;
  final String? expirationDate = e.expirationDate;
  final String? unsubscribeDetectedAt = e.unsubscribeDetectedAt;
  final String? billingIssueDetectedAt = e.billingIssueDetectedAt;
  final String? productPlanIdentifier = e.productPlanIdentifier;
  final VerificationResult verification = e.verification;
  final List<Object?> props = e.props;

  const EntitlementInfo minimal = EntitlementInfo('pro', true, true, '2026-01-01T00:00:00.000Z',
      '2026-01-01T00:00:00.000Z', 'monthly', false);
  const EntitlementInfo full = EntitlementInfo(
    'pro',
    true,
    true,
    '2026-01-01T00:00:00.000Z',
    '2026-01-01T00:00:00.000Z',
    'monthly',
    false,
    ownershipType: OwnershipType.purchased,
    store: Store.appStore,
    periodType: PeriodType.normal,
    expirationDate: null,
    unsubscribeDetectedAt: null,
    billingIssueDetectedAt: null,
    productPlanIdentifier: null,
    verification: VerificationResult.notRequested,
  );
  final EntitlementInfo decoded = EntitlementInfo.fromJson(json);
}

void _checkSubscriptionInfo(SubscriptionInfo s, Map<String, dynamic> json) {
  final String productIdentifier = s.productIdentifier;
  final String purchaseDate = s.purchaseDate;
  final bool isSandbox = s.isSandbox;
  final bool isActive = s.isActive;
  final bool willRenew = s.willRenew;
  final String? originalPurchaseDate = s.originalPurchaseDate;
  final String? expiresDate = s.expiresDate;
  final Store store = s.store;
  final String? unsubscribeDetectedAt = s.unsubscribeDetectedAt;
  final String? billingIssuesDetectedAt = s.billingIssuesDetectedAt;
  final String? gracePeriodExpiresDate = s.gracePeriodExpiresDate;
  final OwnershipType ownershipType = s.ownershipType;
  final PeriodType periodType = s.periodType;
  final String? refundedAt = s.refundedAt;
  final String? storeTransactionId = s.storeTransactionId;
  final String? autoResumeDate = s.autoResumeDate;
  final String? displayName = s.displayName;
  final String? managementURL = s.managementURL;
  final String? productPlanIdentifier = s.productPlanIdentifier;
  final List<Object?> props = s.props;

  const SubscriptionInfo minimal = SubscriptionInfo('monthly', '2026-01-01T00:00:00.000Z', false, true, true);
  const SubscriptionInfo full = SubscriptionInfo(
    'monthly',
    '2026-01-01T00:00:00.000Z',
    false,
    true,
    true,
    originalPurchaseDate: null,
    expiresDate: null,
    store: Store.playStore,
    unsubscribeDetectedAt: null,
    billingIssuesDetectedAt: null,
    gracePeriodExpiresDate: null,
    ownershipType: OwnershipType.purchased,
    periodType: PeriodType.trial,
    refundedAt: null,
    storeTransactionId: 'GPA.1',
    autoResumeDate: null,
    displayName: 'Monthly',
    managementURL: null,
    productPlanIdentifier: 'monthly-base',
  );
  final SubscriptionInfo decoded = SubscriptionInfo.fromJson(json);
}

void _checkTransactionAndResults(
  StoreTransaction t,
  PurchaseResult r,
  LogInResult l,
  CustomerInfo info,
  Map<String, dynamic> json,
) {
  final String transactionIdentifier = t.transactionIdentifier;
  final String productIdentifier = t.productIdentifier;
  final String purchaseDate = t.purchaseDate;
  final List<Object> transactionProps = t.props;
  const StoreTransaction constructed = StoreTransaction('tx_1', 'monthly', '2026-01-01T00:00:00.000Z');
  final StoreTransaction decoded = StoreTransaction.fromJson(json);

  final CustomerInfo resultInfo = r.customerInfo;
  final StoreTransaction resultTransaction = r.storeTransaction;
  final List<Object> resultProps = r.props;
  final PurchaseResult constructedResult = PurchaseResult(info, t);
  final PurchaseResult decodedResult = PurchaseResult.fromJson(json);

  final bool created = l.created;
  final CustomerInfo logInInfo = l.customerInfo;
  final LogInResult constructedLogIn = LogInResult(created: true, customerInfo: info);
}

// ---------------------------------------------------------------------------
// 目录系（设计 §5.3 / §5.4 / §5.4b）
// ---------------------------------------------------------------------------

void _checkOfferings(Offerings offerings, Map<String, dynamic> json) {
  final Map<String, Offering> all = offerings.all;
  final Offering? current = offerings.current;
  final Offering? byId = offerings.getOffering('default');
  final List<Object?> props = offerings.props;
  final Offerings constructed = Offerings(all);
  final Offerings constructedFull = Offerings(all, current: current);
  final Offerings decoded = Offerings.fromJson(json);
}

void _checkOffering(Offering o, Package p, Map<String, dynamic> json) {
  final String identifier = o.identifier;
  final String serverDescription = o.serverDescription;
  final Map<String, Object> metadata = o.metadata;
  final List<Package> availablePackages = o.availablePackages;
  final Package? lifetime = o.lifetime;
  final Package? annual = o.annual;
  final Package? sixMonth = o.sixMonth;
  final Package? threeMonth = o.threeMonth;
  final Package? twoMonth = o.twoMonth;
  final Package? monthly = o.monthly;
  final Package? weekly = o.weekly;
  final String? webCheckoutUrl = o.webCheckoutUrl;
  final Package? byId = o.getPackage(r'$rc_monthly');
  final List<Object?> props = o.props;
  // OfferingX / PackageListX（RC 扩展）
  final String metadataString = o.getMetadataString('key', 'fallback');
  final Package? firstMonthly =
      o.availablePackages.firstWhereOrNull((Package element) => element.packageType == PackageType.monthly);

  final Offering constructed = Offering('default', 'desc', const {}, [p]);
  final Offering constructedFull = Offering(
    'default',
    'desc',
    const {},
    [p],
    lifetime: p,
    annual: p,
    sixMonth: p,
    threeMonth: p,
    twoMonth: p,
    monthly: p,
    weekly: p,
    webCheckoutUrl: null,
  );
  final Offering decoded = Offering.fromJson(json);
}

void _checkPackage(Package p, StoreProduct product, Map<String, dynamic> json) {
  final String identifier = p.identifier;
  final PackageType packageType = p.packageType;
  final StoreProduct storeProduct = p.storeProduct;
  final PresentedOfferingContext context = p.presentedOfferingContext;
  final String? webCheckoutUrl = p.webCheckoutUrl;
  final List<Object?> props = p.props;
  // ExtendedPackage（RC 弃用扩展）
  // ignore: deprecated_member_use
  final String offeringIdentifier = p.offeringIdentifier;

  const PresentedOfferingContext ctx = PresentedOfferingContext('default', null, null);
  final Package constructed = Package(r'$rc_monthly', PackageType.monthly, product, ctx);
  final Package constructedFull =
      Package(r'$rc_monthly', PackageType.monthly, product, ctx, webCheckoutUrl: null);
  final Package decoded = Package.fromJson(json);

  final PurchaseParams params = PurchaseParams.package(p);
  final Package? paramsPackage = params.package;
}

void _checkPresentedOfferingContext(PresentedOfferingContext c, Map<String, dynamic> json) {
  final String offeringIdentifier = c.offeringIdentifier;
  final String? placementIdentifier = c.placementIdentifier;
  final PresentedOfferingTargetingContext? targetingContext = c.targetingContext;
  final Map<String, Object?> asJson = c.toJson();
  final List<Object?> props = c.props;
  const PresentedOfferingTargetingContext targeting = PresentedOfferingTargetingContext(1, 'rule');
  final int revision = targeting.revision;
  final String ruleId = targeting.ruleId;
  final Map<String, Object?> targetingJson = targeting.toJson();
  final List<Object> targetingProps = targeting.props;
  const PresentedOfferingContext constructed = PresentedOfferingContext('default', 'placement', targeting);
  final PresentedOfferingContext decoded = PresentedOfferingContext.fromJson(json);
  final PresentedOfferingTargetingContext decodedTargeting = PresentedOfferingTargetingContext.fromJson(json);
}

void _checkStoreProduct(
  StoreProduct s,
  IntroductoryPrice intro,
  SubscriptionOption option,
  Map<String, dynamic> json,
) {
  final String identifier = s.identifier;
  final String description = s.description;
  final String title = s.title;
  final double price = s.price;
  final String priceString = s.priceString;
  final String currencyCode = s.currencyCode;
  final IntroductoryPrice? introductoryPrice = s.introductoryPrice;
  final List<StoreProductDiscount>? discounts = s.discounts;
  final ProductCategory? productCategory = s.productCategory;
  final SubscriptionOption? defaultOption = s.defaultOption;
  final List<SubscriptionOption>? subscriptionOptions = s.subscriptionOptions;
  final PresentedOfferingContext? presentedOfferingContext = s.presentedOfferingContext;
  final String? subscriptionPeriod = s.subscriptionPeriod;
  final double? pricePerWeek = s.pricePerWeek;
  final double? pricePerMonth = s.pricePerMonth;
  final double? pricePerYear = s.pricePerYear;
  final String? pricePerWeekString = s.pricePerWeekString;
  final String? pricePerMonthString = s.pricePerMonthString;
  final String? pricePerYearString = s.pricePerYearString;
  final List<Object?> props = s.props;
  // ExtendedStoreProduct（RC 弃用扩展）
  // ignore: deprecated_member_use
  final String? presentedOfferingIdentifier = s.presentedOfferingIdentifier;

  const StoreProduct minimal = StoreProduct('monthly', 'desc', 'Monthly', 4.99, r'$4.99', 'USD');
  final StoreProduct full = StoreProduct(
    'monthly',
    'desc',
    'Monthly',
    4.99,
    r'$4.99',
    'USD',
    introductoryPrice: intro,
    discounts: const [],
    productCategory: ProductCategory.subscription,
    defaultOption: option,
    subscriptionOptions: [option],
    presentedOfferingContext: const PresentedOfferingContext('default', null, null),
    subscriptionPeriod: 'P1M',
    pricePerWeek: null,
    pricePerMonth: null,
    pricePerYear: null,
    pricePerWeekString: null,
    pricePerMonthString: null,
    pricePerYearString: null,
  );
  final StoreProduct decoded = StoreProduct.fromJson(json);

  const StoreProductDiscount discount = StoreProductDiscount('offer', 0.99, r'$0.99', 1, 'P1M', 'MONTH', 1);
  final String discountIdentifier = discount.identifier;
  final double discountPrice = discount.price;
  final String discountPriceString = discount.priceString;
  final int discountCycles = discount.cycles;
  final String discountPeriod = discount.period;
  final String discountPeriodUnit = discount.periodUnit;
  final int discountPeriodNumberOfUnits = discount.periodNumberOfUnits;
  final List<Object?> discountProps = discount.props;
}

void _checkIntroductoryPrice(IntroductoryPrice i, Map<String, dynamic> json) {
  final double price = i.price;
  final String priceString = i.priceString;
  final String period = i.period;
  final int cycles = i.cycles;
  final PeriodUnit periodUnit = i.periodUnit;
  final int periodNumberOfUnits = i.periodNumberOfUnits;
  final List<Object?> props = i.props;
  const IntroductoryPrice constructed = IntroductoryPrice(0, 'Free', 'P1W', 1, PeriodUnit.week, 1);
  final IntroductoryPrice decoded = IntroductoryPrice.fromJson(json);
}

void _checkSubscriptionOption(SubscriptionOption o, Map<String, dynamic> json) {
  final String id = o.id;
  final String storeProductId = o.storeProductId;
  final String productId = o.productId;
  final List<PricingPhase> pricingPhases = o.pricingPhases;
  final List<String> tags = o.tags;
  final bool isBasePlan = o.isBasePlan;
  final Period? billingPeriod = o.billingPeriod;
  final bool isPrepaid = o.isPrepaid;
  final PricingPhase? fullPricePhase = o.fullPricePhase;
  final PricingPhase? freePhase = o.freePhase;
  final PricingPhase? introPhase = o.introPhase;
  final PresentedOfferingContext? presentedOfferingContext = o.presentedOfferingContext;
  final InstallmentsInfo? installmentsInfo = o.installmentsInfo;
  final List<Object?> props = o.props;
  // ExtendedSubscriptionOption（RC 弃用扩展）
  // ignore: deprecated_member_use
  final String? presentedOfferingIdentifier = o.presentedOfferingIdentifier;

  const Period period = Period(PeriodUnit.month, 1, 'P1M');
  final PeriodUnit unit = period.unit;
  final int value = period.value;
  final String iso8601 = period.iso8601;
  final List<Object> periodProps = period.props;
  final Period decodedPeriod = Period.fromJson(json);

  const Price price = Price(r'$4.99', 4990000, 'USD');
  final String formatted = price.formatted;
  final int amountMicros = price.amountMicros;
  final String currencyCode = price.currencyCode;
  final List<Object?> priceProps = price.props;
  final Price decodedPrice = Price.fromJson(json);

  const PricingPhase phase =
      PricingPhase(period, RecurrenceMode.infiniteRecurring, null, price, OfferPaymentMode.freeTrial);
  const PricingPhase phaseNulls = PricingPhase(null, null, null, price, null);
  final Period? phaseBillingPeriod = phase.billingPeriod;
  final RecurrenceMode? recurrenceMode = phase.recurrenceMode;
  final int? billingCycleCount = phase.billingCycleCount;
  final Price phasePrice = phase.price;
  final OfferPaymentMode? offerPaymentMode = phase.offerPaymentMode;
  final List<Object?> phaseProps = phase.props;
  final PricingPhase decodedPhase = PricingPhase.fromJson(json);

  const InstallmentsInfo installments = InstallmentsInfo(12, 12);
  final int commitmentPaymentsCount = installments.commitmentPaymentsCount;
  final int renewalCommitmentPaymentsCount = installments.renewalCommitmentPaymentsCount;
  final List<Object?> installmentsProps = installments.props;
  final InstallmentsInfo decodedInstallments = InstallmentsInfo.fromJson(json);

  const SubscriptionOption constructed = SubscriptionOption(
    'monthly-base',
    'monthly:monthly-base',
    'monthly',
    [phase],
    ['tag'],
    true,
    period,
    false,
    phase,
    null,
    null,
    PresentedOfferingContext('default', null, null),
    installments,
  );
  final SubscriptionOption decoded = SubscriptionOption.fromJson(json);
}

void _checkIntroEligibility(IntroEligibility e, Map<String, dynamic> json) {
  final IntroEligibilityStatus status = e.status;
  final String description = e.description;
  // RC 的 IntroEligibility 字段可写（非 final），照抄。
  e.status = IntroEligibilityStatus.introEligibilityStatusEligible;
  e.description = 'eligible';
  final IntroEligibility decoded = IntroEligibility.fromJson(json);
}

// ---------------------------------------------------------------------------
// 错误（设计 §5.6、D4）
// ---------------------------------------------------------------------------

void _checkErrors(PlatformException e) {
  final PurchasesErrorCode code = PurchasesErrorHelper.getErrorCode(e);
  final PurchasesErrorCode fromLiteral =
      PurchasesErrorHelper.getErrorCode(PlatformException(code: '901', details: {'userCancelled': false}));
  final PurchasesErrorHelper helperInstance = PurchasesErrorHelper();
  _describeErrorCode(code);

  try {
    throw UnsupportedPlatformException();
  } on UnsupportedPlatformException catch (unsupported) {
    final Exception asException = unsupported;
  }
}

String _describeErrorCode(PurchasesErrorCode code) {
  switch (code) {
    case PurchasesErrorCode.unknownError:
    case PurchasesErrorCode.purchaseCancelledError:
    case PurchasesErrorCode.storeProblemError:
    case PurchasesErrorCode.purchaseNotAllowedError:
    case PurchasesErrorCode.purchaseInvalidError:
    case PurchasesErrorCode.productNotAvailableForPurchaseError:
    case PurchasesErrorCode.productAlreadyPurchasedError:
    case PurchasesErrorCode.receiptAlreadyInUseError:
    case PurchasesErrorCode.invalidReceiptError:
    case PurchasesErrorCode.missingReceiptFileError:
    case PurchasesErrorCode.networkError:
    case PurchasesErrorCode.invalidCredentialsError:
    case PurchasesErrorCode.unexpectedBackendResponseError:
    case PurchasesErrorCode.receiptInUseByOtherSubscriberError:
    case PurchasesErrorCode.invalidAppUserIdError:
    case PurchasesErrorCode.operationAlreadyInProgressError:
    case PurchasesErrorCode.unknownBackendError:
    case PurchasesErrorCode.invalidAppleSubscriptionKeyError:
    case PurchasesErrorCode.ineligibleError:
    case PurchasesErrorCode.insufficientPermissionsError:
    case PurchasesErrorCode.paymentPendingError:
    case PurchasesErrorCode.invalidSubscriberAttributesError:
    case PurchasesErrorCode.logOutWithAnonymousUserError:
    case PurchasesErrorCode.configurationError:
    case PurchasesErrorCode.unsupportedError:
    case PurchasesErrorCode.emptySubscriberAttributesError:
    case PurchasesErrorCode.productDiscountMissingIdentifierError:
    case PurchasesErrorCode.unknownNonNativeError:
    case PurchasesErrorCode.productDiscountMissingSubscriptionGroupIdentifierError:
    case PurchasesErrorCode.customerInfoError:
    case PurchasesErrorCode.systemInfoError:
    case PurchasesErrorCode.beginRefundRequestError:
    case PurchasesErrorCode.productRequestTimeout:
    case PurchasesErrorCode.apiEndpointBlocked:
    case PurchasesErrorCode.invalidPromotionalOfferError:
    case PurchasesErrorCode.offlineConnectionError:
    case PurchasesErrorCode.featureNotAvailableInCustomEntitlementsComputationMode:
    case PurchasesErrorCode.signatureVerificationFailed:
    case PurchasesErrorCode.featureNotSupportedWithStoreKit1:
    case PurchasesErrorCode.invalidWebPurchaseToken:
    case PurchasesErrorCode.purchaseBelongsToOtherUser:
    case PurchasesErrorCode.expiredWebPurchaseToken:
    case PurchasesErrorCode.testStoreSimulatedPurchaseError:
    case PurchasesErrorCode.notImplementedError:
    case PurchasesErrorCode.purchasePendingServerConfirmation:
    case PurchasesErrorCode.purchaseRejectedByServer:
      return code.name;
  }
}

// ---------------------------------------------------------------------------
// 枚举穷尽 switch（不写 default：增删值即编译失败）
// ---------------------------------------------------------------------------

void _checkEnums(
  LogLevel logLevel,
  Store store,
  PeriodType periodType,
  OwnershipType ownershipType,
  VerificationResult verificationResult,
  StoreKitVersion storeKitVersion,
  EntitlementVerificationMode entitlementVerificationMode,
  PurchasesAreCompletedByType completedByType,
  PackageType packageType,
  PeriodUnit periodUnit,
  ProductCategory productCategory,
  RecurrenceMode recurrenceMode,
  OfferPaymentMode offerPaymentMode,
  IntroEligibilityStatus introEligibilityStatus,
) {
  switch (logLevel) {
    case LogLevel.verbose:
    case LogLevel.debug:
    case LogLevel.info:
    case LogLevel.warn:
    case LogLevel.error:
      break;
  }
  switch (store) {
    case Store.appStore:
    case Store.macAppStore:
    case Store.playStore:
    case Store.stripe:
    case Store.promotional:
    case Store.unknownStore:
    case Store.amazon:
    case Store.rcBilling:
    case Store.paddle:
    case Store.testStore:
    case Store.externalStore:
    case Store.galaxy:
      break;
  }
  switch (periodType) {
    case PeriodType.intro:
    case PeriodType.normal:
    case PeriodType.trial:
    case PeriodType.prepaid:
    case PeriodType.unknown:
      break;
  }
  switch (ownershipType) {
    case OwnershipType.purchased:
    case OwnershipType.familyShared:
    case OwnershipType.unknown:
      break;
  }
  switch (verificationResult) {
    case VerificationResult.notRequested:
    case VerificationResult.verified:
    case VerificationResult.verifiedOnDevice:
    case VerificationResult.failed:
      break;
  }
  switch (storeKitVersion) {
    case StoreKitVersion.storeKit1:
    case StoreKitVersion.storeKit2:
    case StoreKitVersion.defaultVersion:
      break;
  }
  switch (entitlementVerificationMode) {
    case EntitlementVerificationMode.disabled:
    case EntitlementVerificationMode.informational:
      break;
  }
  switch (completedByType) {
    case PurchasesAreCompletedByType.myApp:
    case PurchasesAreCompletedByType.revenueCat:
      break;
  }
  switch (packageType) {
    case PackageType.unknown:
    case PackageType.custom:
    case PackageType.lifetime:
    case PackageType.annual:
    case PackageType.sixMonth:
    case PackageType.threeMonth:
    case PackageType.twoMonth:
    case PackageType.monthly:
    case PackageType.weekly:
      break;
  }
  switch (periodUnit) {
    case PeriodUnit.day:
    case PeriodUnit.week:
    case PeriodUnit.month:
    case PeriodUnit.year:
    case PeriodUnit.unknown:
      break;
  }
  switch (productCategory) {
    case ProductCategory.nonSubscription:
    case ProductCategory.subscription:
      break;
  }
  switch (recurrenceMode) {
    case RecurrenceMode.infiniteRecurring:
    case RecurrenceMode.finiteRecurring:
    case RecurrenceMode.nonRecurring:
    case RecurrenceMode.unknown:
      break;
  }
  switch (offerPaymentMode) {
    case OfferPaymentMode.freeTrial:
    case OfferPaymentMode.singlePayment:
    case OfferPaymentMode.discountedRecurringPayment:
      break;
  }
  switch (introEligibilityStatus) {
    case IntroEligibilityStatus.introEligibilityStatusUnknown:
    case IntroEligibilityStatus.introEligibilityStatusIneligible:
    case IntroEligibilityStatus.introEligibilityStatusEligible:
    case IntroEligibilityStatus.introEligibilityStatusNoIntroOfferExists:
      break;
  }
}

// ---------------------------------------------------------------------------
// sealed-like 配置完成方（RC 为 abstract class + 两个子类，宿主用 is 判别）
// ---------------------------------------------------------------------------

String _checkCompletedBy(PurchasesAreCompletedBy completedBy) {
  if (completedBy is PurchasesAreCompletedByMyApp) {
    return completedBy.storeKitVersion.name;
  }
  if (completedBy is PurchasesAreCompletedByRevenueCat) {
    return 'revenueCat';
  }
  return 'unknown';
}

/// `PurchasesAreCompletedBy` 是 abstract class（非 sealed，同 RC），其 const 构造属于公开面：子类化必须仍可编译。
class _CustomCompletedBy extends PurchasesAreCompletedBy {
  const _CustomCompletedBy();
}
