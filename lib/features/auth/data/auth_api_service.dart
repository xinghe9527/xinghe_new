import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../domain/models/user.dart';
import '../domain/models/invitation_code.dart';

class AuthApiService {
  // 🎉 生产环境正式域名（已通过 ICP 备案，拥有合法 SSL 证书）
  static const String baseUrl = 'https://api.xhaigc.cn';

  // 1. 验证邀请码（一次性动态卡密，查询未使用的码）
  Future<InvitationCode> verifyInvitationCode(String code) async {
    final trimmedCode = code.trim();

    if (trimmedCode.isEmpty) {
      throw Exception('邀请码不能为空');
    }

    try {
      // Step A: 查卡 — 查询未使用的邀请码
      final uri = Uri.parse('$baseUrl/api/collections/invitation_codes/records')
          .replace(
            queryParameters: {'filter': "code='$trimmedCode' && is_used=false"},
          );

      final response = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('HTTP 错误 ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body);

      // Step B: 拦截 — 查询为空则码无效或已被使用
      if (data is! Map ||
          data['items'] == null ||
          (data['items'] as List).isEmpty) {
        throw Exception('邀请码无效或已被使用');
      }

      return InvitationCode.fromJson(data['items'][0]);
    } catch (e) {
      if (e.toString().contains('邀请码无效或已被使用') ||
          e.toString().contains('邀请码不能为空')) {
        rethrow;
      }
      throw Exception('验证邀请码失败: $e');
    }
  }

  // 2. 检查邮箱是否已注册
  Future<bool> checkEmailExists(String email) async {
    try {
      // 使用 PocketBase List/Search API 规范
      final uri = Uri.parse(
        '$baseUrl/api/collections/users/records',
      ).replace(queryParameters: {'filter': "email='$email'"});

      final response = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('HTTP 错误 ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body);
      return data is Map &&
          data['items'] != null &&
          (data['items'] as List).isNotEmpty;
    } catch (e) {
      throw Exception('检查邮箱失败: $e');
    }
  }

  // 3. 注册方法（新兵入营模式：查卡 → 创建用户 → 登录拿Token → 毁卡）
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String invitationCode,
    String? verificationCode,
  }) async {
    try {
      // Step A: 查卡 + 拦截（验证邀请码未使用）
      final code = await verifyInvitationCode(invitationCode.trim());

      // Step B-1: 检查邮箱唯一性
      final emailExists = await checkEmailExists(email.trim());
      if (emailExists) {
        throw Exception('该邮箱已被注册');
      }

      // Step B-2: 创建用户（此时新用户无Token，无法毁卡）
      final expireDate = DateTime.now().add(Duration(days: code.durationDays));
      final body = {
        'name': username.trim(),
        'email': email.trim(),
        'password': password,
        'passwordConfirm': password,
        'expire_date': expireDate.toIso8601String(),
      };

      debugPrint('=== 准备注册用户 ===');
      debugPrint('请求体: $body');
      debugPrint('==================');

      final regResponse = await http
          .post(
            Uri.parse('$baseUrl/api/collections/users/records'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (regResponse.statusCode >= 400) {
        final errorMsg = _parseErrorMessage(regResponse.body);
        throw Exception(errorMsg);
      }

      final userData = json.decode(regResponse.body);
      final userId = userData['id'];

      debugPrint('=== 注册成功，用户数据 ===');
      debugPrint('userId: $userId');
      debugPrint('email: ${userData['email']}');
      debugPrint('=======================');

      // Step C: 关键！立即登录获取合法 Token
      String? authToken;
      try {
        final loginResult = await login(
          email: email.trim(),
          password: password,
        );
        authToken = loginResult['token'] as String?;
        debugPrint('✅ 注册后自动登录成功，获得合法 Token');
      } catch (e) {
        debugPrint('⚠️ 注册后自动登录失败: $e');
      }

      // Step D: 拿合法 Token 毁卡
      // 注册场景下接受极小概率毁卡失败风险，不阻断用户进入APP
      if (authToken != null) {
        try {
          await _markCodeAsUsedWithAuth(code.id, authToken);
          debugPrint('✅ 注册毁卡成功');
        } catch (e) {
          debugPrint('⚠️ 注册毁卡失败（不阻断注册流程）: $e');
        }
      } else {
        debugPrint('⚠️ 无合法Token，跳过毁卡（极端边缘情况）');
      }

      // ✅ 触发 PocketBase 原生邮件验证
      try {
        await _sendVerificationEmail(email.trim());
        debugPrint('✅ 验证邮件发送成功');
      } catch (e) {
        debugPrint('⚠️ 验证邮件发送失败（不影响注册）: $e');
      }

      // 如果自动登录成功，返回真实Token和登录后的用户数据
      if (authToken != null) {
        // 用 auth-refresh 获取最新用户数据
        try {
          final refreshResult = await authRefresh(authToken);
          if (refreshResult != null) {
            return {
              'user': refreshResult['user'],
              'token': refreshResult['token'],
              'needVerification': true,
            };
          }
        } catch (e) {
          debugPrint('⚠️ auth-refresh 失败，使用注册返回数据');
        }
      }

      return {
        'user': User.fromJson(userData),
        'token': authToken ?? 'token_$userId',
        'needVerification': true,
      };
    } catch (e) {
      if (e.toString().startsWith('Exception: ')) {
        rethrow;
      }
      throw Exception('注册失败: $e');
    }
  }

  // 毁卡（带认证Token，用于已登录用户）
  Future<void> _markCodeAsUsedWithAuth(
    String codeRecordId,
    String token,
  ) async {
    try {
      final response = await http
          .patch(
            Uri.parse(
              '$baseUrl/api/collections/invitation_codes/records/$codeRecordId',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'is_used': true}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        debugPrint('⚠️ 毁卡失败: HTTP ${response.statusCode} ${response.body}');
        throw Exception('核销邀请码失败');
      }
      debugPrint('✅ 毁卡成功（带Auth）: $codeRecordId');
    } catch (e) {
      debugPrint('❌ 毁卡异常: $e');
      rethrow;
    }
  }

  // 发送 PocketBase 原生验证邮件
  Future<void> _sendVerificationEmail(String email) async {
    final trimmedEmail = email.trim();

    if (trimmedEmail.isEmpty) {
      throw Exception('邮箱地址为空，无法发送验证邮件');
    }

    debugPrint('✅ 准备发送验证邮件到: $trimmedEmail');

    try {
      final body = jsonEncode({'email': trimmedEmail});
      debugPrint('✅ 请求体: $body');

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/collections/users/request-verification'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('✅ 验证邮件响应状态码: ${response.statusCode}');
      debugPrint('✅ 验证邮件响应体: ${response.body}');

      if (response.statusCode >= 400) {
        throw Exception('发送验证邮件失败: ${response.body}');
      }

      debugPrint('✅ PocketBase 验证邮件已发送到: $trimmedEmail');
    } catch (e) {
      debugPrint('❌ 发送验证邮件失败: $e');
      throw Exception('发送验证邮件失败: $e');
    }
  }

  // 解析 PocketBase 错误信息，转换为用户友好的中文提示
  String _parseErrorMessage(String errorBody) {
    try {
      final errorData = json.decode(errorBody);
      debugPrint('=== PocketBase 错误响应 ===');
      debugPrint('$errorData');
      debugPrint('==========================');

      // 检查是否有 data 字段（包含具体字段错误）
      if (errorData['data'] != null) {
        final data = errorData['data'] as Map<String, dynamic>;

        // 邮箱相关错误
        if (data['email'] != null) {
          final emailError = data['email'];
          final code = emailError['code']?.toString() ?? '';

          if (code == 'validation_is_email') {
            return '邮箱格式不正确，请输入有效的邮箱地址';
          }
          if (code == 'validation_not_unique' ||
              code == 'validation_invalid_unique') {
            return '该邮箱已被注册，请直接登录或使用其他邮箱';
          }
          if (code == 'validation_required') {
            return '请填写邮箱地址';
          }
          // 通用邮箱错误
          return '邮箱信息有误：${emailError['message'] ?? '请检查邮箱格式'}';
        }

        // 密码相关错误
        if (data['password'] != null) {
          final passwordError = data['password'];
          final code = passwordError['code']?.toString() ?? '';

          if (code == 'validation_min_text_constraint') {
            return '密码至少需要8个字符';
          }
          if (code == 'validation_required') {
            return '请填写密码';
          }
          return '密码格式不正确：${passwordError['message'] ?? '请检查密码'}';
        }

        // 用户名相关错误
        if (data['username'] != null) {
          final usernameError = data['username'];
          final code = usernameError['code']?.toString() ?? '';

          if (code == 'validation_not_unique' ||
              code == 'validation_invalid_unique') {
            return '该用户名已被占用，请换一个用户名';
          }
          return '用户名格式不正确';
        }

        // name 字段错误
        if (data['name'] != null) {
          final nameError = data['name'];
          final code = nameError['code']?.toString() ?? '';

          if (code == 'validation_not_unique' ||
              code == 'validation_invalid_unique') {
            return '该用户名已被占用，请换一个用户名';
          }
          return '用户名格式不正确';
        }

        // passwordConfirm 错误
        if (data['passwordConfirm'] != null) {
          return '两次输入的密码不一致';
        }

        // 遍历所有字段错误，返回第一个有意义的错误
        for (final entry in data.entries) {
          if (entry.value is Map && entry.value['message'] != null) {
            return '${entry.key} 字段错误：${entry.value['message']}';
          }
        }
      }

      // 处理顶层 message 的通用英文错误
      final message = (errorData['message'] ?? '').toString().toLowerCase();

      if (message.contains('failed to create record')) {
        return '注册失败：该邮箱或用户名可能已被注册，请尝试直接登录';
      }
      if (message.contains('not unique') ||
          message.contains('already exists')) {
        return '该账号信息已存在，请尝试直接登录';
      }
      if (message.contains('validation')) {
        return '输入信息不符合要求，请检查后重试';
      }

      // 返回通用错误信息
      return '注册失败，请检查输入信息后重试';
    } catch (e) {
      return '注册失败，请稍后重试';
    }
  }

  // 4. 登录（使用 PocketBase 认证 API）
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();

    if (trimmedEmail.isEmpty || password.isEmpty) {
      throw Exception('邮箱和密码不能为空');
    }

    try {
      // 使用 PocketBase 认证 API
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/collections/users/auth-with-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'identity': trimmedEmail, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('邮箱或密码错误');
      }

      final data = json.decode(response.body);

      // 调试输出：查看 PocketBase 返回的完整数据
      debugPrint('=== 登录成功，PocketBase 返回数据 ===');
      debugPrint('完整响应: $data');
      debugPrint('record 字段: ${data['record']}');
      debugPrint('===================================');

      final user = User.fromJson(data['record']);

      // 调试输出：查看解析后的用户信息
      debugPrint('=== 解析后的用户信息 ===');
      debugPrint('id: ${user.id}');
      debugPrint('username: ${user.username}');
      debugPrint('email: ${user.email}');
      debugPrint('avatar: ${user.avatar}');
      debugPrint('verified: ${user.verified}');
      debugPrint('========================');

      // 注意：不再在此处检查会员过期，由 AuthGuard 在 UI 层统一拦截

      return {'user': user, 'token': data['token'] ?? 'token_${user.id}'};
    } catch (e) {
      throw Exception('登录失败: $e');
    }
  }

  // 5. 更新用户名（使用 PocketBase PATCH API）
  Future<User?> updateUsername({
    required String userId,
    required String newUsername,
    required String token,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/api/collections/users/records/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token,
            },
            body: jsonEncode({
              'name': newUsername, // ✅ 使用 name 字段
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        return null;
      }

      return User.fromJson(json.decode(response.body));
    } catch (e) {
      return null;
    }
  }

  // 6. 更新头像
  Future<User?> updateAvatar({
    required String userId,
    required String avatarUrl,
    required String token,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/api/collections/users/records/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token,
            },
            body: json.encode({'avatar': avatarUrl}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        return null;
      }

      return User.fromJson(json.decode(response.body));
    } catch (e) {
      return null;
    }
  }

  // 7. 获取用户信息
  Future<User?> getUserInfo(String userId, String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/collections/users/records/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        return null;
      }

      return User.fromJson(json.decode(response.body));
    } catch (e) {
      return null;
    }
  }

  // 7a. 宣誓设备主权 — 将 last_device_id 更新为当前设备
  Future<void> claimDevice({
    required String userId,
    required String token,
    required String deviceId,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/api/collections/users/records/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token,
            },
            body: jsonEncode({'last_device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        debugPrint('⚠️ 设备宣誓失败: HTTP ${response.statusCode}');
      } else {
        debugPrint('✅ 设备宣誓成功: $deviceId');
      }
    } catch (e) {
      debugPrint('⚠️ 设备宣誓异常: $e');
    }
  }

  // 7b. PocketBase 官方 auth-refresh（刷新授权，获取最新用户数据 + 新 Token）
  /// 返回 { 'user': User, 'token': String } 或 null（失败时）
  Future<Map<String, dynamic>?> authRefresh(String token) async {
    try {
      debugPrint('=== authRefresh 请求 ===');
      debugPrint(
        'Authorization: Bearer ${token.substring(0, token.length > 20 ? 20 : token.length)}...',
      );

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/collections/users/auth-refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('authRefresh 响应状态码: ${response.statusCode}');

      if (response.statusCode >= 400) {
        debugPrint('❌ authRefresh 失败: ${response.body}');
        return null;
      }

      final data = json.decode(response.body);
      final user = User.fromJson(data['record']);
      final newToken = data['token'] as String?;

      debugPrint(
        '✅ authRefresh 成功: verified=${user.verified}, email=${user.email}',
      );

      return {'user': user, 'token': newToken ?? token};
    } catch (e) {
      debugPrint('❌ authRefresh 异常: $e');
      return null;
    }
  }

  // 8. 修改密码（使用 PocketBase PATCH API）
  Future<void> updatePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
    required String token,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/api/collections/users/records/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token,
            },
            body: jsonEncode({
              'oldPassword': oldPassword,
              'password': newPassword,
              'passwordConfirm': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        // 解析 PocketBase 错误信息，转换为中文
        final errorMsg = _parsePasswordErrorMessage(
          response.body,
          response.statusCode,
        );
        throw Exception(errorMsg);
      }
    } catch (e) {
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('修改密码失败: $e');
    }
  }

  // 解析密码修改错误信息，转换为中文
  String _parsePasswordErrorMessage(String errorBody, int statusCode) {
    try {
      final errorData = json.decode(errorBody);
      final message = errorData['message']?.toString().toLowerCase() ?? '';

      // 根据错误信息返回中文提示
      if (message.contains('old password') || message.contains('oldpassword')) {
        return '当前密码错误';
      }
      if (message.contains('password') && message.contains('short')) {
        return '新密码至少需要8个字符';
      }
      if (message.contains('password') && message.contains('match')) {
        return '两次输入的新密码不一致';
      }
      if (statusCode == 401 || statusCode == 403) {
        return '当前密码错误';
      }
      if (statusCode == 400) {
        // 检查 data 字段中的具体错误
        if (errorData['data'] != null) {
          final data = errorData['data'] as Map<String, dynamic>;

          if (data['oldPassword'] != null) {
            return '当前密码错误';
          }
          if (data['password'] != null) {
            final passwordError = data['password'];
            if (passwordError['code'] == 'validation_min_text_constraint') {
              return '新密码至少需要8个字符';
            }
            return '新密码格式不正确';
          }
          if (data['passwordConfirm'] != null) {
            return '两次输入的新密码不一致';
          }
        }
      }

      // 返回通用错误
      return '修改密码失败，请检查输入信息';
    } catch (e) {
      return '修改密码失败，请稍后重试';
    }
  }

  // 9. 重新发送验证邮件（用户可手动触发）
  Future<void> resendVerificationEmail(String email) async {
    await _sendVerificationEmail(email);
  }

  // 10. 使用邀请码续期（一次性动态卡密核销）
  Future<User?> renewWithInvitationCode({
    required String userId,
    required String invitationCode,
    required String token,
    required DateTime currentExpireDate,
  }) async {
    try {
      // Step A: 查卡 + Step B: 拦截
      final code = await verifyInvitationCode(invitationCode.trim());

      // Step C: 算账 — 基于当前过期时间或当前时间计算新过期时间
      final DateTime baseDate = currentExpireDate.isAfter(DateTime.now())
          ? currentExpireDate // 未过期：在现有过期时间上累加
          : DateTime.now(); // 已过期：从当前时间开始算
      final newExpireDate = baseDate.add(Duration(days: code.durationDays));

      debugPrint('=== 续期算账 ===');
      debugPrint('当前过期时间: $currentExpireDate');
      debugPrint('基准时间: $baseDate');
      debugPrint('卡密天数: ${code.durationDays}');
      debugPrint('新过期时间: $newExpireDate');
      debugPrint('================');

      // 🚨 Step D: 先毁卡（防御性扣款优先）
      // 必须在给用户加天数之前将卡密标记为已使用
      // 如果毁卡失败，立即中断，绝不允许给用户加天数！
      await _markCodeAsUsedWithAuth(code.id, token);

      // Step E: 后发货（加天数）— 只有毁卡成功后才执行
      final response = await http
          .patch(
            Uri.parse('$baseUrl/api/collections/users/records/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token,
            },
            body: jsonEncode({'expire_date': newExpireDate.toIso8601String()}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('续期失败: HTTP ${response.statusCode}');
      }

      return User.fromJson(json.decode(response.body));
    } catch (e) {
      if (e.toString().contains('邀请码无效或已被使用') ||
          e.toString().contains('邀请码不能为空') ||
          e.toString().contains('核销邀请码失败') ||
          e.toString().contains('续期失败')) {
        rethrow;
      }
      throw Exception('续期失败: $e');
    }
  }

  // 10. 发送邮箱验证码（占位方法，需要后端支持）
  Future<void> sendVerificationCode(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/send-verification-code'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('发送验证码失败: ${response.body}');
      }
    } catch (e) {
      throw Exception('发送验证码失败: $e');
    }
  }
}
