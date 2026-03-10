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

  /// 全局时间戳：最后一次发送验证邮件的时间（用于 60s 防刷）
  DateTime? _lastVerificationEmailSentTime;
  DateTime? get lastVerificationEmailSentTime => _lastVerificationEmailSentTime;

  /// 被踢标志：账号在其他设备登录时设为提示消息，UI层检测弹窗后清除
  String? _kickedMessage;
  String? get kickedMessage => _kickedMessage;

  void clearKickedMessage() {
    _kickedMessage = null;
  }

  // 初始化 - 自动登录 + 静默同步云端最新状态
  Future<void> initialize() async {
    // 确保设备指纹已生成
    await storageService.getLocalDeviceId();

    final savedAuthState = await storageService.loadAuthState();
    if (savedAuthState != null) {
      // 先用本地缓存恢复状态（快速启动）
      _authState = savedAuthState;
      notifyListeners();
      
      // 后台静默调用 auth-refresh 同步云端最新数据（含设备雷达比对）
      _silentRefresh();
    }
  }

  /// 静默刷新：后台调用 auth-refresh 同步云端最新用户数据
  /// 如果 Token 无效则自动登出，同时执行设备指纹雷达比对
  Future<void> _silentRefresh() async {
    if (_authState.token == null) return;

    try {
      debugPrint('🔄 静默同步: 正在调用 auth-refresh...');
      final result = await _apiService.authRefresh(_authState.token!);

      if (result != null) {
        final User user = result['user'];
        final String newToken = result['token'];

        debugPrint('🔄 静默同步成功: verified=${user.verified}, isExpired=${user.isExpired}');

        // 🚨 雷达比对：检查设备指纹是否匹配
        final kicked = await _checkDeviceConflict(user);
        if (kicked) return; // 已被踢，不再更新状态
        
        _authState = AuthState.authenticated(
          user: user,
          token: newToken,
        );
        await storageService.saveAuthState(_authState);
        notifyListeners();
      } else {
        // Token 无效（被拉黑/过期等），强制登出
        debugPrint('🔄 静默同步失败: Token 无效，强制登出');
        await logout();
      }
    } catch (e) {
      debugPrint('🔄 静默同步异常: $e（保持本地状态）');
      // 网络异常时不登出，保持本地状态（离线容错）
    }
  }

  /// 🚨 设备雷达比对：云端 last_device_id 与本地 localDeviceId 对比
  /// 返回 true 表示被踢
  Future<bool> _checkDeviceConflict(User cloudUser) async {
    final localDeviceId = await storageService.getLocalDeviceId();
    final cloudDeviceId = cloudUser.lastDeviceId;

    debugPrint('🔍 设备雷达: local=$localDeviceId, cloud=$cloudDeviceId');

    if (cloudDeviceId != null &&
        cloudDeviceId.isNotEmpty &&
        cloudDeviceId != localDeviceId) {
      // 🚨 设备不匹配！账号已在其他设备登录
      debugPrint('🚨 设备冲突！账号已在其他设备登录，执行强制登出');
      _kickedMessage = '您的账号已在其他设备登录，您已被迫下线。';
      _authState = AuthState.initial();
      await storageService.clearAuthState();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// 宣誓设备主权：将 last_device_id 更新为当前设备
  Future<void> _claimDevice() async {
    if (_authState.user == null || _authState.token == null) return;
    final localDeviceId = await storageService.getLocalDeviceId();
    await _apiService.claimDevice(
      userId: _authState.user!.id,
      token: _authState.token!,
      deviceId: localDeviceId,
    );
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
        
        // 🚀 宣誓设备主权：将 last_device_id 更新为当前设备
        await _claimDevice();
        
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
        
        // 注册成功后 PocketBase 已自动发送激活邮件，记录时间戳
        _lastVerificationEmailSentTime = DateTime.now();
        
        await storageService.saveAuthState(_authState);

        // 🚀 宣誓设备主权：将 last_device_id 更新为当前设备
        await _claimDevice();

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

  // 刷新用户信息（使用 PocketBase 官方 auth-refresh + 设备雷达比对）
  Future<void> refreshUserInfo() async {
    if (_authState.token == null) {
      debugPrint('❌ refreshUserInfo: token 为空，执行登出');
      await logout();
      return;
    }

    try {
      final result = await _apiService.authRefresh(_authState.token!);

      if (result != null) {
        final User user = result['user'];
        final String newToken = result['token'];

        debugPrint('=== 刷新用户状态 ===');
        debugPrint('新 verified: ${user.verified}');
        debugPrint('新 isExpired: ${user.isExpired}');
        debugPrint('========================');

        // 🚨 雷达比对：检查设备指纹是否匹配
        final kicked = await _checkDeviceConflict(user);
        if (kicked) return; // 已被踢，不再更新状态

        _authState = AuthState.authenticated(
          user: user,
          token: newToken,
        );
        await storageService.saveAuthState(_authState);
        notifyListeners();
      } else {
        // auth-refresh 失败（Token 无效/过期），强制登出
        debugPrint('❌ authRefresh 失败，强制登出');
        await logout();
      }
    } catch (e) {
      debugPrint('❌ 刷新用户信息失败: $e');
      await logout();
    }
  }

  // 修改密码
  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (_authState.user == null || _authState.token == null) {
      throw Exception('用户未登录');
    }

    try {
      await _apiService.updatePassword(
        userId: _authState.user!.id,
        oldPassword: oldPassword,
        newPassword: newPassword,
        token: _authState.token!,
      );
    } catch (e) {
      rethrow;
    }
  }

  // 重新发送验证邮件
  Future<void> resendVerificationEmail() async {
    if (_authState.user == null) {
      throw Exception('用户未登录');
    }

    final email = _authState.user!.email;
    debugPrint('=== resendVerificationEmail ===');
    debugPrint('用户邮箱: "$email"');
    debugPrint('===============================');

    if (email.trim().isEmpty) {
      throw Exception('用户邮箱为空，无法发送验证邮件');
    }

    try {
      await _apiService.resendVerificationEmail(email);
      // 发送成功，更新全局时间戳
      _lastVerificationEmailSentTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // 使用邀请码续期（一次性动态卡密核销）
  Future<void> renewWithInvitationCode(String invitationCode) async {
    if (_authState.user == null || _authState.token == null) {
      throw Exception('用户未登录');
    }

    try {
      // 执行完整核销流程（查卡→拦截→算账→更新用户→毁卡）
      final updatedUser = await _apiService.renewWithInvitationCode(
        userId: _authState.user!.id,
        invitationCode: invitationCode,
        token: _authState.token!,
        currentExpireDate: _authState.user!.expireDate,
      );

      if (updatedUser != null) {
        _authState = _authState.copyWith(user: updatedUser);
        await storageService.saveAuthState(_authState);
        notifyListeners();

        // 静默状态同步：强制调用 auth-refresh 拉取最新云端状态
        // 确保本地 Auth 缓存被正确刷新，防线 C 自动解除
        await refreshUserInfo();
      }
    } catch (e) {
      rethrow;
    }
  }
}
