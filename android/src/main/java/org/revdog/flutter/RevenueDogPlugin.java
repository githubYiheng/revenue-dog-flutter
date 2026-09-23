package org.revdog.flutter;

import android.app.Activity;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.revdog.flutter.bridge.DiagnosticsSink;
import org.revdog.flutter.bridge.ErrorEnvelope;
import org.revdog.flutter.bridge.ErrorMapper;
import org.revdog.flutter.bridge.Mappers;
import org.revdog.flutter.bridge.WireContractException;
import org.revdog.purchases.LogHandler;
import org.revdog.purchases.LogInCallback;
import org.revdog.purchases.LogLevel;
import org.revdog.purchases.Purchases;
import org.revdog.purchases.PurchasesAreCompletedBy;
import org.revdog.purchases.PurchasesConfiguration;
import org.revdog.purchases.PurchasesError;
import org.revdog.purchases.PurchasesErrorCode;
import org.revdog.purchases.ReceiveCustomerInfoCallback;
import org.revdog.purchases.UncheckedPurchasesException;
import org.revdog.purchases.customerinfo.CustomerInfo;

import java.io.Closeable;
import java.io.IOException;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * RevenueDog Flutter 插件 Android 侧（设计 §2 / §4 / §5 / §6，ADR 0099：Java、{@code implementation} 依赖）。
 *
 * 职责只有：通道分派、未配置守卫、R3 进程级记录、线程切换、引擎级状态（订阅句柄、当前 Activity）。
 * 模型映射与错误信封在 {@code bridge/}（不依赖 Flutter，可单测）。
 *
 * 对照 RC：purchases_flutter {@code PurchasesFlutterPlugin.java} —— 同为 Java、{@code FlutterPlugin + MethodCallHandler
 * + ActivityAware}、一条 {@code MethodChannel}、事件经同一通道反向 {@code invokeMethod}。偏离：
 * ① 每引擎一条 CustomerInfo 订阅（D14，RC 单 listener 在多引擎下互相覆盖）；② 未配置守卫回码 23（RC 抛非数字 "error"）；
 * ③ 主线程 Handler 创建失败时内联执行（坑 38 / purchases-flutter#408，RC 未做）；④ 大对象 map 放自有单线程 executor。
 */
public class RevenueDogPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {

    private static final String TAG = "RevenueDogFlutter";
    static final String CHANNEL_NAME = "revenue_dog";

    // 事件名（设计 §5.7，与 lib/src/channel.dart 的 ChannelEvents 逐字一致）。
    static final String EVENT_CUSTOMER_INFO_UPDATED = "Purchases-CustomerInfoUpdated";
    static final String EVENT_LOG_HANDLER = "Purchases-LogHandlerEvent";

    // 诊断码（设计 §5 总则「诊断」，裁定 10）。
    static final String WARNING_OPTION_IGNORED = "hybrid_option_ignored";
    static final String WARNING_DUPLICATE_CONFIGURE = "hybrid_duplicate_configure";

    // -------------------------------------------------------------------------------------------
    // R3 进程级记录（设计 §4）：首次成功 setupPurchases 的 (apiKey, appUserID)。
    // 静态 = 进程级：热重启（Dart 静态态清零）与多引擎（每引擎一个插件实例）共享同一份，与原生单例同寿命。
    // 两个字段总在 CONFIGURE_LOCK 内一起写；读方先读 volatile 的 recordedConfigured 再读另两项。
    // -------------------------------------------------------------------------------------------
    private static final Object CONFIGURE_LOCK = new Object();
    private static volatile boolean recordedConfigured = false;
    private static volatile String recordedApiKey = null;
    private static volatile String recordedAppUserID = null;

    /** 插件自有单线程 executor：CustomerInfo 等大对象的 map 不占主线程（设计 §6）。进程级共享。 */
    private static final ExecutorService MAPPING_EXECUTOR = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "revenue-dog-flutter-mapper");
        thread.setDaemon(true);
        return thread;
    });

    /** 经原生 M0 内部入口记诊断；未配置时不记（入口依赖单例）。 */
    // recordDiagnosticsWarning 标 @InternalRevenueDogAPI：混合框架专用入口（裁定 10），Java 不受 opt-in 约束（javac 不校验 Kotlin opt-in，无 warning，故不加 @SuppressWarnings）
    static final DiagnosticsSink NATIVE_DIAGNOSTICS = (code, detail) -> {
        if (Purchases.isConfigured()) {
            Purchases.getSharedInstance().recordDiagnosticsWarning(code, detail);
        }
    };

    // -------------------------------------------------------------------------------------------
    // 引擎级状态（每个 FlutterEngine 一个插件实例）
    // -------------------------------------------------------------------------------------------
    @Nullable private MethodChannel channel;
    @Nullable private Context applicationContext;
    /** 主线程 Handler；创建失败（坑 38）为 null → 内联执行。 */
    @Nullable private Handler mainHandler;
    /** 本引擎的 CustomerInfo 订阅（D14）；只在主线程读写。 */
    @Nullable private Closeable customerInfoSubscription;
    /** 当前 Activity（M2 购买用）；只在主线程读写。 */
    @Nullable private Activity activity;

    // -------------------------------------------------------------------------------------------
    // FlutterPlugin
    // -------------------------------------------------------------------------------------------

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        mainHandler = createMainHandler();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        // 只取消本引擎的订阅、清 handler；**绝不**关原生 SDK（设计 §4「多引擎」，RC 3.5.0 教训）。
        closeCustomerInfoSubscription();
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        applicationContext = null;
        activity = null;
    }

    // -------------------------------------------------------------------------------------------
    // ActivityAware（M2 购买需要当前 Activity）
    // -------------------------------------------------------------------------------------------

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }

    @Nullable
    Activity getActivity() {
        return activity;
    }

    // -------------------------------------------------------------------------------------------
    // 分派
    // -------------------------------------------------------------------------------------------

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        String method = call.method;
        // 未配置守卫（设计 §4）：除下列 5 个外，未配置一律回码 23（绝不让 getSharedInstance() 抛出去）。
        switch (method) {
            case "setupPurchases":
            case "getConfiguredParams":
            case "isConfigured":
            case "setLogLevel":
            case "setLogHandler":
                break;
            default:
                if (isKnownMethod(method) && !Purchases.isConfigured()) {
                    replyError(result, ErrorMapper.synthetic(
                            PurchasesErrorCode.ConfigurationError, ErrorMapper.NOT_CONFIGURED_UNDERLYING));
                    return;
                }
        }
        try {
            switch (method) {
                case "setupPurchases":
                    setupPurchases(call, result);
                    break;
                case "getConfiguredParams":
                    getConfiguredParams(result);
                    break;
                case "attachCustomerInfoStream":
                    attachCustomerInfoStream(call, result);
                    break;
                case "isConfigured":
                    result.success(Purchases.isConfigured());
                    break;
                case "getAppUserID":
                    result.success(Purchases.getSharedInstance().getAppUserID());
                    break;
                case "isAnonymous":
                    result.success(Purchases.getSharedInstance().isAnonymous());
                    break;
                case "logIn":
                    logIn(call, result);
                    break;
                case "logOut":
                    logOut(result);
                    break;
                case "getCustomerInfo":
                    getCustomerInfo(result);
                    break;
                case "setLogLevel":
                    setLogLevel(call, result);
                    break;
                case "setLogHandler":
                    setLogHandler(result);
                    break;
                case "enableAdServicesAttributionTokenCollection":
                    // iOS only；Android 静默成功（宿主不判平台就调，08 §8.3 #15；对照 RC Android 同为空实现）。
                    result.success(null);
                    break;
                default:
                    // M2 的方法（getOfferings / purchasePackage / restore / sync / eligibility）尚未实现。
                    result.notImplemented();
            }
        } catch (UncheckedPurchasesException e) {
            replyError(result, ErrorMapper.fromPurchasesError(e.getError()));
        } catch (InvalidArgumentException e) {
            replyError(result, ErrorMapper.synthetic(e.code, e.getMessage()));
        }
    }

    private static boolean isKnownMethod(String method) {
        switch (method) {
            case "attachCustomerInfoStream":
            case "getAppUserID":
            case "isAnonymous":
            case "logIn":
            case "logOut":
            case "getCustomerInfo":
            case "enableAdServicesAttributionTokenCollection":
                return true;
            default:
                return false;
        }
    }

    // -------------------------------------------------------------------------------------------
    // 配置（setupPurchases / getConfiguredParams / attachCustomerInfoStream）
    // -------------------------------------------------------------------------------------------

    // platformInfo 标 @InternalRevenueDogAPI：混合框架专用入口（R1），Java 不受 opt-in 约束（javac 不校验 Kotlin opt-in，无 warning，故不加 @SuppressWarnings）
    private void setupPurchases(MethodCall call, Result result) {
        String apiKey = requireString(call, "apiKey", PurchasesErrorCode.ConfigurationError);
        String appUserID = optionalString(call, "appUserID", PurchasesErrorCode.ConfigurationError);
        Boolean diagnosticsEnabled = optionalBoolean(call, "diagnosticsEnabled", PurchasesErrorCode.ConfigurationError);
        String logLevelName = optionalString(call, "logLevel", PurchasesErrorCode.ConfigurationError);
        Boolean waitsForLogInBeforeSync =
                optionalBoolean(call, "waitsForLogInBeforeSync", PurchasesErrorCode.ConfigurationError);
        String baseUrl = optionalString(call, "baseUrl", PurchasesErrorCode.ConfigurationError);
        String platformFlavorVersion =
                optionalString(call, "platformFlavorVersion", PurchasesErrorCode.ConfigurationError);
        String completedByName = optionalString(call, "purchasesAreCompletedBy", PurchasesErrorCode.ConfigurationError);
        Boolean showInAppMessages =
                optionalBoolean(call, "shouldShowInAppMessagesAutomatically", PurchasesErrorCode.ConfigurationError);
        Boolean pendingPrepaid = optionalBoolean(
                call, "pendingTransactionsForPrepaidPlansEnabled", PurchasesErrorCode.ConfigurationError);
        String userDefaultsSuiteName =
                optionalString(call, "userDefaultsSuiteName", PurchasesErrorCode.ConfigurationError);

        // 取值校验在任何原生调用之前：未知值 → 码 23，不做静默默认（支付服务 fail-loud）。
        LogLevel logLevel = logLevelName == null ? null : parseLogLevel(logLevelName);
        PurchasesAreCompletedBy completedBy = completedByName == null ? null : parseCompletedBy(completedByName);

        Context context = applicationContext;
        if (context == null) {
            throw new InvalidArgumentException(PurchasesErrorCode.ConfigurationError,
                    "plugin is not attached to a Flutter engine");
        }

        synchronized (CONFIGURE_LOCK) {
            if (recordedConfigured && Purchases.isConfigured()) {
                // R3 兜底：Dart 先查 getConfiguredParams，正常不会到这里；两引擎并发 configure 时后到者走这里。
                // 同参 → 不重配、为本引擎挂订阅并记诊断；异参 → 码 23（原生不改，不替换实例）。
                if (Objects.equals(recordedApiKey, apiKey) && Objects.equals(recordedAppUserID, appUserID)) {
                    NATIVE_DIAGNOSTICS.recordWarning(WARNING_DUPLICATE_CONFIGURE, null);
                    subscribeCustomerInfoIfNeeded();
                    result.success(null);
                    return;
                }
                replyError(result, ErrorMapper.synthetic(PurchasesErrorCode.ConfigurationError,
                        "configure called again with different parameters"));
                return;
            }

            PurchasesConfiguration.Builder builder = new PurchasesConfiguration.Builder(context, apiKey)
                    .appUserID(appUserID)
                    .platformInfo("flutter", platformFlavorVersion);
            if (diagnosticsEnabled != null) {
                builder.diagnosticsEnabled(diagnosticsEnabled);
            }
            if (logLevel != null) {
                // R4：Dart 记住的最近 setLogLevel 值随配置下发（原生 configure 会用配置覆盖日志级别）。
                builder.logLevel(logLevel);
            }
            if (baseUrl != null) {
                builder.baseURL(baseUrl);
            }
            if (completedBy != null) {
                builder.purchasesCompletedBy(completedBy);
            }
            if (showInAppMessages != null) {
                builder.showInAppMessagesAutomatically(showInAppMessages);
            }
            if (pendingPrepaid != null) {
                builder.pendingTransactionsForPrepaidPlansEnabled(pendingPrepaid);
            }

            try {
                Purchases.configure(builder.build());
            } catch (UncheckedPurchasesException e) {
                replyError(result, ErrorMapper.fromPurchasesError(e.getError()));
                return;
            } catch (IllegalArgumentException e) {
                // Builder.build() 的 require（如 apiKey 为空）→ 码 23。
                replyError(result, ErrorMapper.synthetic(PurchasesErrorCode.ConfigurationError, e.getMessage()));
                return;
            }

            recordedApiKey = apiKey;
            recordedAppUserID = appUserID;
            recordedConfigured = true;
        }

        // iOS-only 选项：不进配置，configure 成功后各记一条（设计 §5 方法表、§10「身份」）。
        if (Boolean.TRUE.equals(waitsForLogInBeforeSync)) {
            NATIVE_DIAGNOSTICS.recordWarning(WARNING_OPTION_IGNORED, "waitsForLogInBeforeSync");
        }
        if (userDefaultsSuiteName != null) {
            NATIVE_DIAGNOSTICS.recordWarning(WARNING_OPTION_IGNORED, "userDefaultsSuiteName");
        }

        subscribeCustomerInfoIfNeeded();
        result.success(null);
    }

    private void getConfiguredParams(Result result) {
        Map<String, Object> map = new HashMap<>();
        boolean configured = recordedConfigured && Purchases.isConfigured();
        map.put("isConfigured", configured);
        map.put("apiKey", configured ? recordedApiKey : null);
        map.put("appUserID", configured ? recordedAppUserID : null);
        result.success(map);
    }

    private void attachCustomerInfoStream(MethodCall call, Result result) {
        Boolean duplicate = optionalBoolean(call, "duplicateConfigure", PurchasesErrorCode.PurchaseInvalidError);
        if (Boolean.TRUE.equals(duplicate)) {
            NATIVE_DIAGNOSTICS.recordWarning(WARNING_DUPLICATE_CONFIGURE, null);
        }
        subscribeCustomerInfoIfNeeded();
        result.success(null);
    }

    /**
     * 本引擎未订阅则订阅（D14）。原生 {@code addCustomerInfoObserver} 订阅即回放最近值（裁定 1），
     * 所以 configure / attach 之后 Dart 先收到一次当前值。回调在主线程；map 放 executor，事件回主线程发。
     */
    // addCustomerInfoObserver 标 @InternalRevenueDogAPI：多引擎订阅入口（裁定 1），Java 不受 opt-in 约束（javac 不校验 Kotlin opt-in，无 warning，故不加 @SuppressWarnings）
    private void subscribeCustomerInfoIfNeeded() {
        if (customerInfoSubscription != null || channel == null) {
            return;
        }
        customerInfoSubscription = Purchases.getSharedInstance().addCustomerInfoObserver(customerInfo ->
                mapInBackground(
                        () -> Mappers.customerInfo(customerInfo, NATIVE_DIAGNOSTICS),
                        map -> invokeEvent(EVENT_CUSTOMER_INFO_UPDATED, map),
                        envelope -> Log.e(TAG, "dropping " + EVENT_CUSTOMER_INFO_UPDATED + ": "
                                + envelope.details.get("underlyingErrorMessage"))));
    }

    private void closeCustomerInfoSubscription() {
        Closeable subscription = customerInfoSubscription;
        customerInfoSubscription = null;
        if (subscription != null) {
            try {
                subscription.close();
            } catch (IOException e) {
                Log.w(TAG, "failed to close CustomerInfo subscription", e);
            }
        }
    }

    // -------------------------------------------------------------------------------------------
    // 日志
    // -------------------------------------------------------------------------------------------

    private void setLogLevel(MethodCall call, Result result) {
        String level = requireString(call, "level", PurchasesErrorCode.PurchaseInvalidError);
        // 静态入口，configure 前也可调（R4 另由 Dart 记住最近值随 configure 下发）。
        Purchases.setLogLevel(parseLogLevel(level));
        result.success(null);
    }

    /**
     * 装一个把原生日志转成 {@code Purchases-LogHandlerEvent {logLevel, message}} 的 handler（设计 §5.7）。
     * 原生 LogHandler 进程级只有一个：后装的引擎生效（同 RC）。原生可能在任意线程打日志，事件一律回主线程发。
     */
    private void setLogHandler(Result result) {
        Purchases.setLogHandler(new LogHandler() {
            @Override
            public void log(@NonNull LogLevel level, @NonNull String message, @Nullable Throwable throwable) {
                Map<String, Object> event = new HashMap<>();
                event.put("logLevel", level.getName().toLowerCase(Locale.ROOT));
                event.put("message", throwable == null ? message : message + "\n" + throwable);
                runOnMain(() -> invokeEvent(EVENT_LOG_HANDLER, event));
            }
        });
        result.success(null);
    }

    // -------------------------------------------------------------------------------------------
    // 身份 / CustomerInfo
    // -------------------------------------------------------------------------------------------

    private void logIn(MethodCall call, Result result) {
        String appUserID = requireString(call, "appUserID", PurchasesErrorCode.PurchaseInvalidError);
        Purchases.getSharedInstance().logIn(appUserID, new LogInCallback() {
            @Override
            public void onReceived(@NonNull CustomerInfo customerInfo, boolean created) {
                mapInBackground(
                        () -> Mappers.logInResult(customerInfo, created, NATIVE_DIAGNOSTICS),
                        result::success,
                        envelope -> replyError(result, envelope));
            }

            @Override
            public void onError(@NonNull PurchasesError error) {
                replyError(result, ErrorMapper.fromPurchasesError(error));
            }
        });
    }

    private void logOut(Result result) {
        Purchases.getSharedInstance().logOut(new ReceiveCustomerInfoCallback() {
            @Override
            public void onReceived(@NonNull CustomerInfo customerInfo) {
                replyCustomerInfo(result, customerInfo);
            }

            @Override
            public void onError(@NonNull PurchasesError error) {
                // logOut 路径专用映射：14 → 22（裁定 6）。
                replyError(result, ErrorMapper.fromLogOutError(error));
            }
        });
    }

    private void getCustomerInfo(Result result) {
        Purchases.getSharedInstance().getCustomerInfo(new ReceiveCustomerInfoCallback() {
            @Override
            public void onReceived(@NonNull CustomerInfo customerInfo) {
                replyCustomerInfo(result, customerInfo);
            }

            @Override
            public void onError(@NonNull PurchasesError error) {
                replyError(result, ErrorMapper.fromPurchasesError(error));
            }
        });
    }

    private void replyCustomerInfo(Result result, CustomerInfo customerInfo) {
        mapInBackground(
                () -> Mappers.customerInfo(customerInfo, NATIVE_DIAGNOSTICS),
                result::success,
                envelope -> replyError(result, envelope));
    }

    // -------------------------------------------------------------------------------------------
    // 线程（设计 §6）
    // -------------------------------------------------------------------------------------------

    private interface Mapping {
        Map<String, Object> map();
    }

    private interface Consumer<T> {
        void accept(T value);
    }

    /**
     * 在插件 executor 上 map，成功 / 失败都回主线程交付。契约违约（{@link WireContractException}）→ 码 12 信封
     * + error 日志（设计 §5 总则）。executor 拒绝任务（进程退出中）时内联 map，保证 result 必有回复。
     */
    private void mapInBackground(Mapping mapping, Consumer<Map<String, Object>> onMapped,
                                 Consumer<ErrorEnvelope> onFailed) {
        Runnable task = () -> {
            Map<String, Object> mapped;
            try {
                mapped = mapping.map();
            } catch (WireContractException e) {
                Log.e(TAG, "native model violates the wire contract: " + e.getMessage());
                ErrorEnvelope envelope = ErrorMapper.synthetic(
                        PurchasesErrorCode.UnexpectedBackendResponseError, e.getMessage());
                runOnMain(() -> onFailed.accept(envelope));
                return;
            }
            runOnMain(() -> onMapped.accept(mapped));
        };
        try {
            MAPPING_EXECUTOR.execute(task);
        } catch (RejectedExecutionException e) {
            task.run();
        }
    }

    /** 回主线程执行；主线程 Handler 不可用（坑 38）或已在主线程时内联执行。 */
    private void runOnMain(Runnable runnable) {
        Handler handler = mainHandler;
        if (handler == null || Looper.myLooper() == Looper.getMainLooper()) {
            runnable.run();
        } else {
            handler.post(runnable);
        }
    }

    /** 反向事件（原生 → Dart）。引擎已 detach 时丢弃。只在主线程调用。 */
    private void invokeEvent(String event, Map<String, Object> arguments) {
        MethodChannel current = channel;
        if (current != null) {
            current.invokeMethod(event, arguments);
        }
    }

    private static void replyError(Result result, ErrorEnvelope envelope) {
        result.error(envelope.code, envelope.message, envelope.details);
    }

    /**
     * 坑 38 / purchases-flutter#408：个别环境（后台引擎、测试宿主）下 {@code new Handler(getMainLooper())}
     * 会抛；此时返回 null，由 {@link #runOnMain} 内联执行。
     */
    @Nullable
    private static Handler createMainHandler() {
        try {
            Looper looper = Looper.getMainLooper();
            return looper == null ? null : new Handler(looper);
        } catch (RuntimeException e) {
            Log.w(TAG, "main Handler unavailable; delivering inline", e);
            return null;
        }
    }

    // -------------------------------------------------------------------------------------------
    // 参数解析（数值一律经 Number，设计 §6 / 08 坑 12）
    // -------------------------------------------------------------------------------------------

    /** 参数缺失 / 类型错：转成合成错误信封（配置类 23，其余 4）。 */
    private static final class InvalidArgumentException extends RuntimeException {
        final PurchasesErrorCode code;

        InvalidArgumentException(PurchasesErrorCode code, String message) {
            super(message);
            this.code = code;
        }
    }

    private static String requireString(MethodCall call, String key, PurchasesErrorCode code) {
        String value = optionalString(call, key, code);
        if (value == null) {
            throw new InvalidArgumentException(code, "missing argument " + key);
        }
        return value;
    }

    @Nullable
    private static String optionalString(MethodCall call, String key, PurchasesErrorCode code) {
        Object value = call.argument(key);
        if (value == null || value instanceof String) {
            return (String) value;
        }
        throw new InvalidArgumentException(code, "argument " + key + " must be a String");
    }

    @Nullable
    private static Boolean optionalBoolean(MethodCall call, String key, PurchasesErrorCode code) {
        Object value = call.argument(key);
        if (value == null || value instanceof Boolean) {
            return (Boolean) value;
        }
        throw new InvalidArgumentException(code, "argument " + key + " must be a bool");
    }

    /** {@code verbose|debug|info|warn|error} → 原生常量；未知值 → 码 23（不静默落默认级别）。 */
    private static LogLevel parseLogLevel(String name) {
        switch (name) {
            case "verbose":
                return LogLevel.VERBOSE;
            case "debug":
                return LogLevel.DEBUG;
            case "info":
                return LogLevel.INFO;
            case "warn":
                return LogLevel.WARN;
            case "error":
                return LogLevel.ERROR;
            default:
                throw new InvalidArgumentException(PurchasesErrorCode.ConfigurationError,
                        "unsupported logLevel " + name);
        }
    }

    /** {@code revenue_dog|my_app} → 原生常量；未知值 → 码 23。 */
    private static PurchasesAreCompletedBy parseCompletedBy(String name) {
        switch (name) {
            case "revenue_dog":
                return PurchasesAreCompletedBy.REVENUE_DOG;
            case "my_app":
                return PurchasesAreCompletedBy.MY_APP;
            default:
                throw new InvalidArgumentException(PurchasesErrorCode.ConfigurationError,
                        "unsupported purchasesAreCompletedBy " + name);
        }
    }
}
