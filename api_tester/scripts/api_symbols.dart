// 公开符号清单（设计 §7「公开 API 基线」、D6）。
//
//   dart scripts/api_symbols.dart            # 重新生成 api-baseline/public-api.txt
//   dart scripts/api_symbols.dart --check    # 与基线比对，不一致退出 1 并打印差异
//
// 用 analyzer 解析 `package:revenue_dog/revenue_dog.dart` 的导出命名空间（= 宿主 import 之后能看到的全部符号），
// 逐个列出类 / 枚举 / 扩展 / typedef 的公开成员签名（构造、字段、getter / setter、方法、静态成员）。
// 对照 Android 的 metalava `api/*.api` 与 iOS 的 api-baseline：签名文本化 + 入库 + 门禁比对。
//
// 排序规则：顶层符号按名字排序；成员按「种类 + 名字」排序；**枚举值保持声明顺序**（值序是 RC 源码兼容的一部分，
// 宿主可能按下标用，调序 = 破坏性变更）。
//
// 语义化版本：基线里「删 / 改」一行 = 主版本；只「增」= 次版本（CHANGELOG 顶部规则）。
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';

const _library = 'package:revenue_dog/revenue_dog.dart';

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final root = File.fromUri(Platform.script).parent.parent.resolveSymbolicLinksSync();
  final baseline = File('$root/api-baseline/public-api.txt');

  final collection = AnalysisContextCollection(includedPaths: [root]);
  final session = collection.contextFor(root).currentSession;
  final result = await session.getLibraryByUri(_library);
  if (result is! LibraryElementResult) {
    stderr.writeln('❌ 解析不到 $_library：$result（先在 api_tester 里 pub get）');
    exit(1);
  }

  final lines = <String>[
    '# revenue_dog 公开 API 基线（api_tester/scripts/api_symbols.dart 生成，勿手改）',
    '# 来源：$_library 的导出命名空间。删 / 改一行 = 主版本；只增 = 次版本。',
  ];
  final exported = result.element.exportNamespace.definedNames2;
  final names = exported.keys.toList()..sort();
  for (final name in names) {
    lines.addAll(_describe(exported[name]!));
  }
  final text = '${lines.join('\n')}\n';

  if (!check) {
    baseline.parent.createSync(recursive: true);
    baseline.writeAsStringSync(text);
    stdout.writeln('已写 ${baseline.path}（${names.length} 个顶层符号，${lines.length - 2} 行）');
    return;
  }

  if (!baseline.existsSync()) {
    stderr.writeln('❌ 基线不存在：${baseline.path}（先不带 --check 跑一次生成并提交）');
    exit(1);
  }
  final expected = baseline.readAsStringSync();
  if (expected == text) {
    stdout.writeln('公开 API 与基线一致（${names.length} 个顶层符号，${lines.length - 2} 行）');
    return;
  }
  final before = expected.split('\n').toSet();
  final after = text.split('\n').toSet();
  stderr.writeln('❌ 公开 API 与基线不一致：');
  for (final l in before.difference(after)) {
    stderr.writeln('  - $l');
  }
  for (final l in after.difference(before)) {
    stderr.writeln('  + $l');
  }
  stderr.writeln('确认是有意改动：不带 --check 重新生成并 review；有「-」行 = 破坏性变更，按语义化版本升主版本。');
  exit(1);
}

String _sig(Element e) =>
    '${e.displayString().replaceAll('\n', ' ')}${e.metadata.hasDeprecated ? ' @Deprecated' : ''}';

List<String> _describe(Element e) {
  final out = <String>[];
  switch (e) {
    case EnumElement():
      final values = e.fields.where((f) => f.isEnumConstant).map((f) => f.name).join(', ');
      out.add('enum ${e.name} { $values }');
      out.addAll(_members(e, e.name!, skipEnumConstants: true));
    case InterfaceElement():
      out.add(_sig(e));
      out.addAll(_members(e, e.name!));
    case ExtensionElement():
      out.add(_sig(e));
      out.addAll(_members(e, e.name!));
    default:
      out.add(_sig(e));
  }
  return out;
}

List<String> _members(InstanceElement e, String owner, {bool skipEnumConstants = false}) {
  final members = <String>[];
  String line(String kind, Element m) => '  $owner.${m.name == '' || m.name == null ? 'new' : m.name} [$kind] ${_sig(m)}';
  if (e is InterfaceElement && e is! EnumElement) {
    for (final c in e.constructors) {
      if (c.isPublic) members.add(line('constructor', c));
    }
  }
  for (final f in e.fields) {
    if (!f.isPublic || !f.isOriginDeclaration) continue;
    if (skipEnumConstants && f.isEnumConstant) continue;
    if (f.name == 'values' && e is EnumElement) continue;
    members.add(line(f.isStatic ? 'static field' : 'field', f));
  }
  for (final g in e.getters) {
    if (!g.isPublic || !g.isOriginDeclaration) continue;
    members.add(line(g.isStatic ? 'static getter' : 'getter', g));
  }
  for (final s in e.setters) {
    if (!s.isPublic || !s.isOriginDeclaration) continue;
    members.add(line(s.isStatic ? 'static setter' : 'setter', s));
  }
  for (final m in e.methods) {
    if (!m.isPublic || !m.isOriginDeclaration) continue;
    members.add(line(m.isStatic ? 'static method' : 'method', m));
  }
  members.sort();
  return members;
}
