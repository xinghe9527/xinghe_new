import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/auth_state.dart';

class AuthStorageService {
  static const String _authStateKey = 'auth_state';
  static const String _rememberMeKey = 'remember_me';
  static const String _savedEmailKey = 'saved_email';
  static const String _savedPasswordKey = 'saved_password';

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
        
        // 检查 token 是否有效且用户未过期
        if (authState.isAuthenticated && 
            authState.user != null && 
            !authState.user!.isExpired) {
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
