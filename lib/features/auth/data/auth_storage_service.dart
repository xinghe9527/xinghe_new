import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/auth_state.dart';

class AuthStorageService {
  static const String _authStateKey = 'auth_state';
  static const String _rememberMeKey = 'remember_me';
  static const String _savedEmailKey = 'saved_email';
  static const String _savedPasswordKey = 'saved_password';
  static const String _deviceIdKey = 'local_device_id';

  /// 获取本地设备指纹（永久保存，首次自动生成）
  Future<String> getLocalDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _generateDeviceId();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  /// 生成设备唯一标识（UUID v4 格式）
  String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // 保存认证状态
  Future<void> saveAuthState(AuthState authState) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authStateKey, json.encode(authState.toJson()));
  }

  // 读取认证状态
  Future<AuthState?> loadAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authStateJson = prefs.getString(_authStateKey);
      
      if (authStateJson != null) {
        final authState = AuthState.fromJson(json.decode(authStateJson));
        
        // 只检查 token 是否有效和用户是否存在
        // 注意：不再检查 isExpired，过期用户由 AuthGuard 在 UI 层拦截
        if (authState.isAuthenticated && 
            authState.user != null) {
          return authState;
        }
      }
      return null;
    } catch (e) {
      print('加载认证状态失败: $e');
      return null;
    }
  }

  // 清除认证状态
  Future<void> clearAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authStateKey);
  }

  // 保存"记住我"状态和凭据
  Future<void> saveCredentials({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, rememberMe);
    
    if (rememberMe) {
      await prefs.setString(_savedEmailKey, email);
      await prefs.setString(_savedPasswordKey, password);
    } else {
      await prefs.remove(_savedEmailKey);
      await prefs.remove(_savedPasswordKey);
    }
  }

  // 读取保存的凭据
  Future<Map<String, dynamic>> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_rememberMeKey) ?? false;
    
    return {
      'rememberMe': rememberMe,
      'email': rememberMe ? (prefs.getString(_savedEmailKey) ?? '') : '',
      'password': rememberMe ? (prefs.getString(_savedPasswordKey) ?? '') : '',
    };
  }

  // 清除保存的凭据
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberMeKey);
    await prefs.remove(_savedEmailKey);
    await prefs.remove(_savedPasswordKey);
  }
}
