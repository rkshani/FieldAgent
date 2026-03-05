import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DeviceInfoService {
  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;
  DeviceInfoService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _androidId;
  String? _manufacturer;
  String? _brand;
  String? _model;
  String? _appVersion;
  String? _androidVersion;
  String? _sdkLevel;

  Future<void> initialize() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      _androidId = androidInfo.id;
      _manufacturer = androidInfo.manufacturer;
      _brand = androidInfo.brand;
      _model = androidInfo.model;
      _androidVersion = androidInfo.version.release;
      _sdkLevel = androidInfo.version.sdkInt.toString();
    }

    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = packageInfo.version;
  }

  String get androidId => _androidId ?? '';
  String get manufacturer => _manufacturer ?? '';
  String get brand => _brand ?? '';
  String get model => _model ?? '';
  String get appVersion => _appVersion ?? '';
  String get androidVersion => _androidVersion ?? '';
  String get sdkLevel => _sdkLevel ?? '';

  Map<String, String> getDeviceParams() {
    return {
      'Android_id': androidId,
      'manufacturer': manufacturer,
      'brand': brand,
      'model': model,
      'app_version': appVersion,
      'android_version': androidVersion,
      'sdk': sdkLevel,
    };
  }
}
