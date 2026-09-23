import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通道名（与 lib/src/channel.dart 一致）。
const MethodChannel testChannel = MethodChannel('revenue_dog');

/// 读取 test/fixtures 下的 JSON（`flutter test` 的工作目录是包根）。
Object? loadFixture(String relativePath) =>
    jsonDecode(File('test/fixtures/$relativePath').readAsStringSync());

/// 读取 fixture 并转成通道形态：`StandardMethodCodec` 编解码一遍，得到与真机一致的
/// `Map<Object?, Object?>` / `List<Object?>`（而不是 `Map<String, dynamic>`）。
Object? loadFixtureAsChannelValue(String relativePath) =>
    const StandardMessageCodec().decodeMessage(
      const StandardMessageCodec().encodeMessage(loadFixture(relativePath)),
    );

/// 模拟原生 → Dart 的反向调用（对照 RC 测试的 `_performDartSideChannelMethodCall`）。
/// 原生对事件回执的错误信封写进 [replies]，便于断言 Dart 侧解码失败时回了码 12。
void sendNativeEvent(String method, Object? arguments, {List<ByteData?>? replies}) {
  ServicesBinding.instance.channelBuffers.push(
    testChannel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (data) => replies?.add(data),
  );
}

/// 断言 [future] 以指定码的 `PlatformException` 失败，返回该异常供进一步断言。
Future<PlatformException> expectPlatformException(Future<Object?> future, String code) async {
  try {
    await future;
  } on PlatformException catch (e) {
    expect(e.code, code);
    return e;
  }
  fail('expected PlatformException($code)');
}
