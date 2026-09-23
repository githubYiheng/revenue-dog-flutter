import Flutter
import UIKit

/// RevenueDog Flutter 插件（iOS 桩）。
///
/// M1 Dart 侧先行：此处只保留通道注册与空分派，全部方法回 `FlutterMethodNotImplemented`。
/// 真正的实现（通道分派、未配置守卫、R3 记录、订阅、Bridge 映射）由后续子代理按
/// `test/fixtures/` 的 wire fixture 与设计 §5 实现。通道名 `revenue_dog` 与 Dart 侧一致。
public class RevenueDogPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "revenue_dog", binaryMessenger: registrar.messenger())
    let instance = RevenueDogPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
