// RevenueDog Flutter 测试 app（设计 §7「测试 app」、M3）。
//
// 单页手测台：真机清单 F 系列（docs/audit/2026-09-24-flutter-device-checklist.md）里的每一步都在这里点。
// key 与后端地址只经 --dart-define 注入（`example/run.sh` 从 ~/selah-keys 读取），源码与仓库里没有任何 key：
//   REVDOG_API_KEY_IOS      iOS public key（staging 项目 demo）
//   REVDOG_API_KEY_ANDROID  Android public key（staging 项目 revdog-example）
//   REVDOG_BASE_URL         缺省 https://api-staging.revdog.org
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:revenue_dog/revenue_dog.dart';

const String _apiKeyIos = String.fromEnvironment('REVDOG_API_KEY_IOS');
const String _apiKeyAndroid = String.fromEnvironment('REVDOG_API_KEY_ANDROID');
const String _baseUrl = String.fromEnvironment(
  'REVDOG_BASE_URL',
  defaultValue: 'https://api-staging.revdog.org',
);

/// 日志面板最多保留的行数（新的在上）。
const int _maxLogLines = 500;

/// F9（Android）：MainActivity 起 / 停第二个 FlutterEngine 的通道（只在测试 app 里，插件无关）。
const MethodChannel _backgroundEngineChannel = MethodChannel('revdog_example/background_engine');

/// F15：打开后 configure 带一个本平台不适用的选项（`userDefaultsSuiteName`），两端插件都应忽略并记
/// `sdk_warning{code=hybrid_option_ignored}`。
const String _ignoredSuiteName = 'group.revdog.example.f15';

bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

String get _apiKey => _isIOS ? _apiKeyIos : _apiKeyAndroid;

/// 测试 app 的唯一配置形态：diagnosticsEnabled + staging baseUrl（主引擎与 F9 后台引擎共用，R3 比较 apiKey / appUserID）。
PurchasesConfiguration buildConfiguration(String? appUserID, {bool withIgnoredOption = false}) =>
    PurchasesConfiguration(_apiKey)
      ..appUserID = appUserID
      ..diagnosticsEnabled = true
      ..baseUrl = _baseUrl
      ..userDefaultsSuiteName = withIgnoredOption ? _ignoredSuiteName : null;

void main() {
  runApp(const MyApp());
}

/// F9 后台引擎入口（Android `MainActivity` 用 `DartEntrypoint(…, "backgroundMain")` 起）。
///
/// 模拟 workmanager / FCM 后台引擎：用与主引擎**相同**的参数 configure（R3「相同」分支：不重复配置、为本引擎挂订阅），
/// 再挂自己的监听；日志只进 logcat（前缀 `[bg-engine]`）。期望：主引擎监听不被顶掉（D14）。
@pragma('vm:entry-point')
Future<void> backgroundMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final appUserID = args.isEmpty || args.first.isEmpty ? null : args.first;
  Purchases.addCustomerInfoUpdateListener(
    (info) => debugPrint('[bg-engine] listener ← active=${info.entitlements.active.keys.toList()} '
        'requestDate=${info.requestDate}'),
  );
  try {
    await Purchases.configure(buildConfiguration(appUserID));
    debugPrint('[bg-engine] configure 完成（appUserID=$appUserID）');
  } on PlatformException catch (e) {
    debugPrint('[bg-engine] configure 失败 code=${e.code} details=${e.details}');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RevenueDog Flutter',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const TesterPage(),
      );
}

class TesterPage extends StatefulWidget {
  const TesterPage({super.key});

  @override
  State<TesterPage> createState() => _TesterPageState();
}

class _TesterPageState extends State<TesterPage> {
  final TextEditingController _logInController = TextEditingController();
  final TextEditingController _configureUserController = TextEditingController();
  final List<String> _logs = [];

  bool? _isConfigured;
  String? _appUserID;
  bool? _isAnonymous;
  CustomerInfo? _customerInfo;
  Offerings? _offerings;
  Map<String, IntroEligibility>? _eligibility;
  bool _busy = false;

  /// 首次成功 configure 的参数（R3 同参 / 异参按钮用）。
  String? _configuredAppUserID;
  bool _hasConfiguredOnce = false;

  /// F15 开关。
  bool _withIgnoredOption = false;

  @override
  void initState() {
    super.initState();
    // 监听器与日志回调都可以在 configure 之前挂（前者是纯 Dart 集合，后者不受未配置守卫）。
    try {
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);
      unawaited(Purchases.setLogHandler(_onNativeLog).catchError(_onError('setLogHandler')));
    } on UnsupportedPlatformException {
      WidgetsBinding.instance.addPostFrameCallback((_) => _log('当前平台不受支持（只 iOS / Android）'));
    }
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    _logInController.dispose();
    _configureUserController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 日志与错误
  // ---------------------------------------------------------------------------

  void _log(String line) {
    final now = DateTime.now();
    final ts = '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    debugPrint('[example] $line');
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '$ts  $line');
      if (_logs.length > _maxLogLines) _logs.removeRange(_maxLogLines, _logs.length);
    });
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  void _onNativeLog(LogLevel level, String message) => _log('[native ${level.name}] $message');

  void _onCustomerInfoUpdated(CustomerInfo info) {
    _log('listener ← CustomerInfo ${_summarize(info)}');
    if (mounted) setState(() => _customerInfo = info);
  }

  /// 统一错误显示：code / readableErrorCode / revdogCode / userCancelled / underlyingErrorMessage。
  String _describeError(Object error) {
    if (error is PlatformException) {
      final details = error.details;
      String detail(String key) => details is Map ? '${details[key]}' : '-';
      return 'PlatformException code=${error.code} '
          '(${PurchasesErrorHelper.getErrorCode(error).name}) '
          'readableErrorCode=${detail('readableErrorCode')} '
          'revdogCode=${detail('revdogCode')} '
          'userCancelled=${detail('userCancelled')} '
          'underlyingErrorMessage=${detail('underlyingErrorMessage')} '
          'message=${error.message}';
    }
    if (error is UnsupportedPlatformException) return 'UnsupportedPlatformException';
    return '${error.runtimeType}: $error';
  }

  void Function(Object, StackTrace) _onError(String action) =>
      (Object error, StackTrace _) => _log('✗ $action: ${_describeError(error)}');

  /// 跑一个动作：统一的忙碌态、日志与错误显示，结束后刷新顶部状态。
  Future<void> _run(String action, Future<void> Function() body) async {
    if (_busy) {
      _log('忙，忽略 $action');
      return;
    }
    setState(() => _busy = true);
    _log('→ $action');
    try {
      await body();
    } catch (e, st) {
      _onError(action)(e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final configured = await Purchases.isConfigured;
      String? userId;
      bool? anonymous;
      if (configured) {
        userId = await Purchases.appUserID;
        anonymous = await Purchases.isAnonymous;
      }
      if (!mounted) return;
      setState(() {
        _isConfigured = configured;
        _appUserID = userId;
        _isAnonymous = anonymous;
      });
    } catch (e) {
      _log('✗ 刷新状态: ${_describeError(e)}');
    }
  }

  static String _summarize(CustomerInfo info) =>
      'appUser=${info.originalAppUserId} '
      'activeEntitlements=${info.entitlements.active.keys.toList()} '
      'activeSubscriptions=${info.activeSubscriptions} '
      'requestDate=${info.requestDate}';

  // ---------------------------------------------------------------------------
  // 动作
  // ---------------------------------------------------------------------------

  Future<void> _configure({String? appUserID}) => _run('configure(appUserID: ${appUserID ?? 'null'})', () async {
        if (_apiKey.isEmpty) {
          throw StateError('没有注入 ${_isIOS ? 'REVDOG_API_KEY_IOS' : 'REVDOG_API_KEY_ANDROID'}；'
              '用 example/run.sh 启动');
        }
        // R4：setLogLevel 先于 configure，插件把它带进配置。
        await Purchases.setLogLevel(LogLevel.debug);
        await Purchases.configure(buildConfiguration(appUserID, withIgnoredOption: _withIgnoredOption));
        if (!_hasConfiguredOnce) {
          _hasConfiguredOnce = true;
          _configuredAppUserID = appUserID;
        }
        _log('✓ configure 完成（baseUrl=$_baseUrl）');
      });

  Future<void> _configureFirst() {
    final id = _configureUserController.text.trim();
    return _configure(appUserID: id.isEmpty ? null : id);
  }

  /// R3 同参：与首次 configure 完全相同 → 不报错、打 warn、重挂订阅（F13）。
  Future<void> _configureSame() => _configure(appUserID: _configuredAppUserID);

  /// R3 异参：appUserID 改掉 → 期望码 23（F13）。
  Future<void> _configureDifferent() =>
      _configure(appUserID: '${_configuredAppUserID ?? 'anon'}_r3_different');

  Future<void> _logIn() => _run('logIn', () async {
        final id = _logInController.text.trim();
        if (id.isEmpty) throw ArgumentError('先在输入框填 appUserID');
        final result = await Purchases.logIn(id);
        setState(() => _customerInfo = result.customerInfo);
        _log('✓ logIn($id) created=${result.created} ${_summarize(result.customerInfo)}');
      });

  Future<void> _logOut() => _run('logOut', () async {
        final info = await Purchases.logOut();
        setState(() => _customerInfo = info);
        _log('✓ logOut ${_summarize(info)}');
      });

  Future<void> _getCustomerInfo() => _run('getCustomerInfo', () async {
        final info = await Purchases.getCustomerInfo();
        setState(() => _customerInfo = info);
        _log('✓ getCustomerInfo ${_summarize(info)}');
      });

  Future<void> _restore() => _run('restorePurchases', () async {
        final info = await Purchases.restorePurchases();
        setState(() => _customerInfo = info);
        _log('✓ restorePurchases ${_summarize(info)}');
      });

  Future<void> _sync() => _run('syncPurchases', () async {
        await Purchases.syncPurchases();
        _log('✓ syncPurchases 完成');
      });

  Future<void> _getOfferings() => _run('getOfferings', () async {
        final offerings = await Purchases.getOfferings();
        setState(() => _offerings = offerings);
        _log('✓ getOfferings current=${offerings.current?.identifier} '
            'all=${offerings.all.keys.toList()}');
        for (final offering in offerings.all.values) {
          for (final p in offering.availablePackages) {
            _log('   ${offering.identifier}/${p.identifier} ${p.packageType.name} '
                '${p.storeProduct.identifier} ${p.storeProduct.priceString} '
                '${p.storeProduct.currencyCode} period=${p.storeProduct.subscriptionPeriod} '
                'intro=${_introText(p.storeProduct.introductoryPrice)}');
          }
        }
      });

  Future<void> _checkEligibility() => _run('checkTrialOrIntroductoryPriceEligibility', () async {
        final offerings = _offerings;
        if (offerings == null) throw StateError('先点 getOfferings');
        final ids = <String>{
          for (final o in offerings.all.values)
            for (final p in o.availablePackages) p.storeProduct.identifier,
        }.toList()
          ..sort();
        final result = await Purchases.checkTrialOrIntroductoryPriceEligibility(ids);
        setState(() => _eligibility = result);
        result.forEach((id, e) => _log('   $id → ${e.status.name}（${e.description}）'));
        _log('✓ eligibility ${result.length} 项');
      });

  Future<void> _purchase(Package package) => _run(
        'purchase ${package.presentedOfferingContext.offeringIdentifier}/${package.identifier}',
        () async {
          final result = await Purchases.purchase(PurchaseParams.package(package));
          setState(() => _customerInfo = result.customerInfo);
          final t = result.storeTransaction;
          _log('✓ purchase tx=${t.transactionIdentifier} product=${t.productIdentifier} '
              'at=${t.purchaseDate} ${_summarize(result.customerInfo)}');
        },
      );

  Future<void> _startBackgroundEngine() => _run('启动后台引擎（F9）', () async {
        if (!_hasConfiguredOnce) throw StateError('先在主引擎 configure');
        await _backgroundEngineChannel.invokeMethod<void>('start', {'appUserID': _configuredAppUserID ?? ''});
        _log('✓ 后台引擎已起（其日志在 logcat，前缀 [bg-engine]）');
      });

  Future<void> _stopBackgroundEngine() => _run('停止后台引擎（F9）', () async {
        await _backgroundEngineChannel.invokeMethod<void>('stop');
        _log('✓ 后台引擎已销毁（原生 SDK 应不受影响，再点 getCustomerInfo 验证）');
      });

  static String _introText(IntroductoryPrice? intro) {
    if (intro == null) return '无';
    final kind = intro.price == 0 ? '免费试用' : '优惠价 ${intro.priceString}';
    return '$kind ${intro.periodNumberOfUnits} ${intro.periodUnit.name}'
        '（${intro.period}）× ${intro.cycles}';
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final info = _customerInfo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RevenueDog Flutter 测试'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            tooltip: '清空日志',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => setState(_logs.clear),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _statusCard(info),
                const SizedBox(height: 8),
                _actions(),
                const SizedBox(height: 8),
                _offeringsCard(),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(flex: 2, child: _logPanel()),
        ],
      ),
    );
  }

  Widget _statusCard(CustomerInfo? info) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('platform=${_isIOS ? 'ios' : 'android'}  key=${_apiKey.isEmpty ? '缺失' : '已注入'}'),
                Text('baseUrl=$_baseUrl'),
                Text('isConfigured=$_isConfigured  isAnonymous=$_isAnonymous'),
                Text('appUserID=$_appUserID'),
                Text('active entitlements=${info?.entitlements.active.keys.toList()}'),
                Text('activeSubscriptions=${info?.activeSubscriptions}'),
                Text('requestDate=${info?.requestDate}'),
              ],
            ),
          ),
        ),
      );

  Widget _button(String label, VoidCallback onPressed) => FilledButton.tonal(
        onPressed: _busy ? null : onPressed,
        child: Text(label),
      );

  Widget _actions() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _configureUserController,
                  decoration: const InputDecoration(
                    labelText: 'configure appUserID（空 = 匿名）',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _button('configure', _configureFirst),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _logInController,
                  decoration: const InputDecoration(labelText: 'logIn appUserID', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              _button('logIn', _logIn),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _button('logOut', _logOut),
              _button('getCustomerInfo', _getCustomerInfo),
              _button('restorePurchases', _restore),
              _button('syncPurchases', _sync),
              _button('getOfferings', _getOfferings),
              _button('eligibility', _checkEligibility),
              _button('再次 configure（同参）', _configureSame),
              _button('再次 configure（异参）', _configureDifferent),
              if (!_isIOS) ...[
                _button('启动后台引擎（F9）', _startBackgroundEngine),
                _button('停止后台引擎（F9）', _stopBackgroundEngine),
              ],
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('configure 带不适用选项（F15：userDefaultsSuiteName → hybrid_option_ignored）'),
            value: _withIgnoredOption,
            onChanged: _busy ? null : (v) => setState(() => _withIgnoredOption = v),
          ),
        ],
      );

  Widget _offeringsCard() {
    final offerings = _offerings;
    if (offerings == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('点 getOfferings 列出档位；点档位即 purchase'),
        ),
      );
    }
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final offering in offerings.all.values) ...[
            ListTile(
              dense: true,
              title: Text(
                '${offering.identifier}${offering.identifier == offerings.current?.identifier ? '（current）' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(offering.serverDescription),
            ),
            for (final package in offering.availablePackages)
              ListTile(
                dense: true,
                enabled: !_busy,
                onTap: () => _purchase(package),
                title: Text('${package.identifier} · ${package.storeProduct.priceString}'),
                subtitle: Text(
                  '${package.packageType.name} · ${package.storeProduct.identifier}'
                  ' · period=${package.storeProduct.subscriptionPeriod}'
                  '\n试用 / 优惠：${_introText(package.storeProduct.introductoryPrice)}'
                  '${_eligibilityText(package.storeProduct.identifier)}',
                ),
                trailing: const Icon(Icons.shopping_cart),
              ),
          ],
        ],
      ),
    );
  }

  String _eligibilityText(String productId) {
    final e = _eligibility?[productId];
    return e == null ? '' : '\n资格：${e.status.name}';
  }

  Widget _logPanel() => Container(
        color: Colors.black,
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: _logs.length,
          itemBuilder: (context, i) => SelectableText(
            _logs[i],
            style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      );
}
