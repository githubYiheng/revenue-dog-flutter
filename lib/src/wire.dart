
import 'errors.dart';
import 'generated/error_codes.dart';

/// 通道 wire 解码工具（设计 §5 总则，D2）。
///
/// 规则：
/// - 通道来的 `Map<Object?, Object?>` 递归转成 `Map<String, dynamic>`；值只允许
///   `int` / `double` / `bool` / `String` / `List` / `Map` / `null`，否则报码 12。
/// - 时间 = epoch 毫秒 `int` → `DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String()`
///   （带毫秒、`Z` 结尾），交给 RC 同型的 `String` 字段。
/// - 枚举 = lower_snake_case 字符串，查表映射到 RC 枚举，未知值落 unknown 档。
/// - 契约非空键缺失 / 为 null / 类型错 → `PlatformException(code: '12', details.wireKey = 路径)`。
///
/// 偏离 RC：RC 模型 `fromJson` 直接 `as String` 强转，缺键抛裸 `TypeError`，宿主的
/// `on PlatformException` 接不住；我方统一转成码 12（设计 §5 总则）。

/// 抛码 12 `unexpectedBackendResponseError`，`details.wireKey` 指出出错的 wire 路径。
Never throwWireError(String wireKey, String reason) =>
    throw buildPurchasesPlatformException(
      PurchasesErrorCode.unexpectedBackendResponseError,
      underlyingErrorMessage: '$reason at $wireKey',
      extraDetails: {'wireKey': wireKey},
    );

String _join(String path, String key) => path.isEmpty ? key : '$path.$key';

/// 递归归一通道值；[path] 用于报错定位。
Object? normalizeWireValue(Object? value, String path) {
  if (value == null || value is int || value is double || value is bool || value is String) {
    return value;
  }
  if (value is Map) return normalizeWireMap(value, path);
  if (value is List) {
    return [
      for (var i = 0; i < value.length; i++) normalizeWireValue(value[i], '$path[$i]'),
    ];
  }
  throwWireError(path.isEmpty ? '<root>' : path, 'unsupported wire value type ${value.runtimeType}');
}

/// 递归把通道 map 转成 `Map<String, dynamic>`；键必须是 `String`。
Map<String, dynamic> normalizeWireMap(Map<Object?, Object?> raw, String path) {
  final out = <String, dynamic>{};
  raw.forEach((key, value) {
    if (key is! String) {
      throwWireError(path.isEmpty ? '<root>' : path, 'non-string map key $key');
    }
    out[key] = normalizeWireValue(value, _join(path, key));
  });
  return out;
}

/// epoch 毫秒 → UTC ISO 8601（带毫秒、`Z` 结尾）。
String isoFromEpochMillis(int ms, String wireKey) {
  try {
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
  } on ArgumentError {
    throwWireError(wireKey, 'epoch millis out of range');
  }
}

/// 带路径的只读 wire map 视图。模型 `fromJson` 都经它取值。
class WireMap {
  WireMap(this.map, this.path);

  /// 从通道原始返回构造；非 map → 码 12。
  factory WireMap.fromChannel(Object? raw, {String path = ''}) {
    if (raw is! Map) {
      throwWireError(path.isEmpty ? '<root>' : path, 'expected map, got ${raw.runtimeType}');
    }
    return WireMap(normalizeWireMap(raw, path), path);
  }

  final Map<String, dynamic> map;
  final String path;

  String keyPath(String key) => _join(path, key);

  Object? _required(String key) {
    if (!map.containsKey(key)) throwWireError(keyPath(key), 'missing key');
    final value = map[key];
    if (value == null) throwWireError(keyPath(key), 'null value for non-null key');
    return value;
  }

  T _typed<T>(String key, Object? value) {
    if (value is! T) {
      throwWireError(keyPath(key), 'expected $T, got ${value.runtimeType}');
    }
    return value;
  }

  String requireString(String key) => _typed<String>(key, _required(key));

  String? optionalString(String key) {
    final value = map[key];
    return value == null ? null : _typed<String>(key, value);
  }

  bool requireBool(String key) => _typed<bool>(key, _required(key));

  int requireInt(String key) => _typed<int>(key, _required(key));

  /// 非空时间键：毫秒 → ISO。
  String requireDate(String key) => isoFromEpochMillis(requireInt(key), keyPath(key));

  /// 可空时间键：null / 缺失 → null；类型错 → 码 12。
  String? optionalDate(String key) {
    final value = map[key];
    if (value == null) return null;
    return isoFromEpochMillis(_typed<int>(key, value), keyPath(key));
  }

  WireMap requireMap(String key) =>
      WireMap(_typed<Map<String, dynamic>>(key, _required(key)), keyPath(key));

  List<Object?> requireList(String key) => _typed<List<Object?>>(key, _required(key));

  List<String> requireStringList(String key) {
    final list = requireList(key);
    return [
      for (var i = 0; i < list.length; i++)
        if (list[i] is String) list[i]! as String else throwWireError('${keyPath(key)}[$i]', 'expected String'),
    ];
  }

  /// `List<map>` → 逐项 [WireMap]。
  List<WireMap> requireMapList(String key) {
    final list = requireList(key);
    return [
      for (var i = 0; i < list.length; i++)
        if (list[i] is Map<String, dynamic>)
          WireMap(list[i]! as Map<String, dynamic>, '${keyPath(key)}[$i]')
        else
          throwWireError('${keyPath(key)}[$i]', 'expected map'),
    ];
  }

  /// `Map<String, map>` → 逐项 [WireMap]，路径为 `key.<entry>`。
  Map<String, WireMap> requireMapOfMaps(String key) {
    final inner = requireMap(key);
    return inner.map.map((entryKey, value) {
      final entryPath = inner.keyPath(entryKey);
      if (value is! Map<String, dynamic>) throwWireError(entryPath, 'expected map');
      return MapEntry(entryKey, WireMap(value, entryPath));
    });
  }

  /// `Map<String, int?>`（毫秒）→ `Map<String, String?>`（ISO），值 null 合法。
  Map<String, String?> requireDateMap(String key) {
    final inner = requireMap(key);
    return inner.map.map((entryKey, _) => MapEntry(entryKey, inner.optionalDate(entryKey)));
  }

  /// 非空枚举键：查 [table]，未知值 → [unknown]；缺失 / null / 非字符串 → 码 12。
  T requireEnum<T>(String key, Map<String, T> table, T unknown) =>
      table[requireString(key)] ?? unknown;
}
