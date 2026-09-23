package org.revdog.revenue_dog_example;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Collections;

import io.flutter.FlutterInjector;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;

/**
 * 测试 app 宿主 Activity。launchMode = singleTop（同 Selah，设计 §3 B6）。
 *
 * <p>真机清单 F9：通道 {@code revdog_example/background_engine} 起 / 停第二个 {@link FlutterEngine}，
 * 执行 Dart 入口 {@code backgroundMain}（lib/main.dart），模拟 workmanager / FCM 的后台引擎。
 * 新引擎自动注册全部插件（含 revenue_dog），插件为它单独挂一条 CustomerInfo 订阅（D14）；
 * 销毁时插件只取消本引擎订阅，绝不关原生 SDK。只在测试 app 里，插件本身不依赖它。
 */
public class MainActivity extends FlutterActivity {
    private static final String BACKGROUND_ENGINE_CHANNEL = "revdog_example/background_engine";

    @Nullable
    private FlutterEngine backgroundEngine;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), BACKGROUND_ENGINE_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "start": {
                            if (backgroundEngine != null) {
                                result.error("already_running", "background engine already running", null);
                                return;
                            }
                            String appUserID = call.argument("appUserID");
                            FlutterEngine engine = new FlutterEngine(getApplicationContext());
                            String bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath();
                            engine.getDartExecutor().executeDartEntrypoint(
                                    new DartExecutor.DartEntrypoint(bundlePath, "backgroundMain"),
                                    Collections.singletonList(appUserID == null ? "" : appUserID));
                            backgroundEngine = engine;
                            result.success(null);
                            return;
                        }
                        case "stop": {
                            destroyBackgroundEngine();
                            result.success(null);
                            return;
                        }
                        default:
                            result.notImplemented();
                    }
                });
    }

    @Override
    protected void onDestroy() {
        destroyBackgroundEngine();
        super.onDestroy();
    }

    private void destroyBackgroundEngine() {
        if (backgroundEngine != null) {
            backgroundEngine.destroy();
            backgroundEngine = null;
        }
    }
}
