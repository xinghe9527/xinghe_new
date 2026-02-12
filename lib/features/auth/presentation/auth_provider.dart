import 'package:flutter/foundation.dart';
import '../domain/models/auth_state.dart';
import '../domain/models/user.dart';
import '../data/auth_api_service.dart';
import '../data/auth_storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthApiService _apiService = AuthApiService();
  final AuthStorageService storageService = AuthStorageService();

  AuthState _authState = AuthState.initial();
  AuthState get authState => _authState;

  bool get isAuthenticated => _authState.isAuthenticated;
  User? get currentUser => _authState.user;

  // 初始化 - 自动登录
  Future<void> initialize() async {
    final savedAuthState = await storageService.loadAuthState();
    if (savedAuthState != null) {
      _authState = savedAuthState;
      notifyListeners();
    }
  }

  // 登录
  Future<void> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      final result = await _apiService.login(email: email, password: password);
      
      if (result != null) {
        _authState = AuthState.authenticated(
          user: result['user'],
          token: result['token'],
        );
        
        await storageService.saveAuthState(_authState);
        await storageService.saveCredentials(
          email: email,
          password: password,
          rememberMe: rememberMe,
        );
        
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  // 注册
  Future<void> register({
    required String username,
    required String email,
    required String password,
    required String invitationCode,
  }) async {
    try {
      final result = await _apiService.register(
        username: username,
        email: email,
        password: password,
        invitationCode: invitationCode,
      );
      
      if (result != null) {
        _authState = AuthState.authenticated(
          user: result['user'],
          token: result['token'],
        );
        
        await storageService.saveAuthState(_authState);
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  // 登出
  Future<void> logout() async {
    _authState = AuthState.initial();
    await storageService.clearAuthState();
    notifyListeners();
  }

  // 更新头像
  Future<void> updateAvatar(String avatarUrl) async {
    if (_authState.user == null || _authState.token == null) return;

    try {
      final updatedUser = await _apiService.updateAvatar(
        userId: _authState.user!.id,
        avatarUrl: avatarUrl,
        token: _authState.token!,
      );

      if (updatedUser != null) {
        _authState = _authState.copyWith(user: updatedUser);
        await storageService.saveAuthState(_authState);
        notifyListeners();
      }
    } catch (e) {
      print('更新头像失败: $e');
      rethrow;
    }
  }

  // 刷新用户信息
  Future<void> refreshUserInfo() async {
    if (_authState.user == null || _authState.token == null) return;

    try {
      final user = await _apiService.getUserInfo(
        _authState.user!.id,
        _authState.token!,
      );

      if (user != null) {
        _authState = _authState.copyWith(user: user);
        await storageService.saveAuthState(_authState);
        notifyListeners();
      }
    } catch (e) {
      print('刷新用户信息失败: $e');
    }
  }
}
