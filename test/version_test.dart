import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog/src/version.dart';

void main() {
  // 版本三处一致（D12）：M1 只校 version.dart == pubspec version；
  // Package.swift exact: 与 android build.gradle 固定版本由 M3 的钉版本脚本与门禁补齐。
  test('version.dart == pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((l) => l.startsWith('version:'));
    expect(revenueDogFlutterVersion, line.substring('version:'.length).trim());
  });

  test('CHANGELOG 有 Unreleased 段', () {
    expect(File('CHANGELOG.md').readAsStringSync(), contains('## [Unreleased]'));
  });
}
