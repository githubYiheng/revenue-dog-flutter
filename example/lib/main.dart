// M1 占位示例：只演示 isConfigured。M3 会改造成测试 app（设计 §7「测试 app」）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:revenue_dog/revenue_dog.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'unknown';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    String status;
    try {
      status = (await Purchases.isConfigured) ? 'configured' : 'not configured';
    } on PlatformException catch (e) {
      status = 'error ${e.code}';
    } on MissingPluginException {
      status = 'plugin not implemented';
    }
    if (!mounted) return;
    setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('RevenueDog example')),
          body: Center(child: Text('Purchases: $_status\n')),
        ),
      );
}
