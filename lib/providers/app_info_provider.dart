import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppInfoProvider extends ChangeNotifier {
  PackageInfo? _packageInfo;
  bool _isLoaded = false;

  PackageInfo? get packageInfo => _packageInfo;
  bool get isLoaded => _isLoaded;

  String get appName => _packageInfo?.appName ?? 'OpenLogTool';
  String get version => _packageInfo?.version ?? '1.0.0';
  String get buildNumber => _packageInfo?.buildNumber ?? '1';
  String get buildSignature => _packageInfo?.buildSignature ?? '';

  Future<void> loadAppInfo() async {
    if (_isLoaded) return;
    
    try {
      _packageInfo = await PackageInfo.fromPlatform();
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load package info: $e');
      _isLoaded = true;
      notifyListeners();
    }
  }
}
