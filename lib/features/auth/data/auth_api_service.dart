import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../domain/models/user.dart';
import '../domain/models/invitation_code.dart';

class AuthApiService {
  // 🎉 生产环境正式域名（已通过 ICP 备案，拥有合法 SSL 证书）
  static const String baseUrl = 'https://api.xhaigc.cn';

  // 1. 验证邀请码（永久有效，无需核销）
  Future<InvitationCode> verifyInvitationCode(String code) async {
    final trimmedCode = code.trim();
    
    if (trimmedCode.isEmpty) {
      throw Exception('邀请码不能为空');
    }

    try {
      // 使用 PocketBase List/Search API 规范
      final uri = Uri.parse('$baseUrl/api/collections/invitation_codes/records').replace(
        queryParameters: {
          'filter': "code='$trimmedCode'",
        },
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('HTTP 错误 ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body);
      
      // PocketBase 返回格式：{ "items": [...], "page": 1, "perPage": 30, "totalItems": 1 }
      if (data is! Map || data['items'] == null || (data['items'] as List).isEmpty) {
        throw Exception('邀请码不存在');
      }
      
      return InvitationCode.fromJson(data['items'][0]);
    } catch (e) {
      throw Exception('验证邀请码失败: $e');
    }
  }

  // 2. 检查邮箱是否已注册
  Future<bool> checkEmailExists(String email) async {
    try {
      // 使用 PocketBase List/Search API 规范
      final uri = Uri.parse('$baseUrl/api/collections/users/records').replace(
        queryParameters: {
          'filter': "email='$email'",
        },
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('HTTP 错误 ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body);
      return data is Map && data['items'] != null && (data['items'] as List).isNotEmpty;
    } catch (e) {
      throw Exception('检查邮箱失败: $e');
    }
  }

  // 3. 注册方法（极速流程：查验 -> 创建用户）
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String invitationCode,
    String? verificationCode,
  }) async {
    try {
      // Step 1: 验证邀请码（永久有效）
      final code = await verifyInvitationCode(invitationCode.trim());

      // Step 2: 检查邮箱唯一性
      final emailExists = await checkEmailExists(email.trim());
      if (emailExists) {
        throw Exception('该邮箱已被注册');
      }

      // Step 3: 计算会员过期时间
      final expireDate = DateTime.now().add(Duration(days: code.durationDays));

      // Step 4: 创建用户（使用 PocketBase Create API）
      // PocketBase 使用 name 字段，不是 username
      final body = {
        'name': username.trim(), // ✅ 使用 name 字段
        'email': email.trim(),
        'password': password,
        'passwordConfirm': password, // PocketBase 要求
        'expire_date': expireDate.toIso8601String(),
      };

      debugPrint('=== 准备注册用户 ===');
      debugPrint('请求体: $body');
      debugPrint('==================');

      final regResponse = await http.post(
        Uri.parse('$baseUrl/api/collections/users/records'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (regResponse.statusCode >= 400) {
        // 解析 PocketBase 错误信息，转换为用户友好的中文提示
        final errorMsg = _parseErrorMessage(regResponse.body);
        throw Exception(errorMsg);
      }

      final userData = json.decode(regResponse.body);
      final userId = userData['id'];

      // 调试输出
      debugPrint('=== 注册成功，用户数据 ===');
      debugPrint('完整响应: $userData');
      debugPrint('userId: $userId');
      debugPrint('username: ${userData['username']}');
      debugPrint('email: ${userData['email']}');
      debugPrint('=======================');

      // ✅ 注册完成，邀请码永久有效无需核销
      // ✅ 触发 PocketBase 原生邮件验证
      try {
        await _sendVerificationEmail(email.trim());
        debugPrint('✅ 验证邮件发送成功');
      } catch (e) {
        debugPrint('⚠️ 验证邮件发送失败（不影响注册）: $e');
        // 邮件发送失败不影响注册流程
      }
      
      return {
        'user': User.fromJson(userData),
        'token': 'token_$userId',
        'needVerification': true, // 标记需要邮箱验证
      };
    } catch (e) {
      // 如果是我们自己抛出的异常，直接传递
      if (e.toString().startsWith('Exception: ')) {
        rethrow;
      }
      throw Exception('注册失败: $e');
    }
  }

  // 发送 PocketBase 原生验证邮件
  Future<void> _sendVerificationEmail(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/collections/users/request-verification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('发送验证邮件失败: ${response.body}');
      }
      
      debugPrint('✅ PocketBase 验证邮件已发送到: $email');
    } catch (e) {
      throw Exception('发送验证邮件失败: $e');
    }
  }

  // 解析 PocketBase 错误信息，转换为用户友好的中文提示
  String _parseErrorMessage(String errorBody) {
    try {
      final errorData = json.decode(errorBody);
      
      // 检查是否有 data 字段（包含具体字段错误）
      if (errorData['data'] != null) {
        final data = errorData['data'] as Map<String, dynamic>;
        
        // 邮箱格式错误
        if (data['email'] != null) {
          final emailError = data['email'];
          if (emailError['code'] == 'validation_is_email') {
            return '邮箱格式不正确';
          }
        }
        
        // 密码长度错误
        if (data['password'] != null) {
          final passwordError = data['password'];
          if (passwordError['code'] == 'validation_min_text_constraint') {
            return '密码至少需要8个字符';
          }
        }
        
        // 用户名错误
        if (data['username'] != null) {
          return '用户名格式不正确';
        }
      }
      
      // 返回通用错误信息
      return errorData['message'] ?? '注册失败，请检查输入信息';
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
      final response = await http.post(
        Uri.parse('$baseUrl/api/collections/users/auth-with-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identity': trimmedEmail,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

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
      debugPrint('========================');
      
      // 检查会员是否过期
      if (user.isExpired) {
        throw Exception('会员已过期，请联系管理员续费');
      }

      return {
        'user': user,
        'token': data['token'] ?? 'token_${user.id}',
      };
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
      final response = await http.patch(
        Uri.parse('$baseUrl/api/collections/users/records/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token,
        },
        body: jsonEncode({
          'name': newUsername, // ✅ 使用 name 字段
        }),
      ).timeout(const Duration(seconds: 15));

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
      final response = await http.patch(
        Uri.parse('$baseUrl/api/collections/users/records/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token,
        },
        body: json.encode({'avatar': avatarUrl}),
      ).timeout(const Duration(seconds: 15));

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
      final response = await http.get(
        Uri.parse('$baseUrl/api/collections/users/records/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        return null;
      }

      return User.fromJson(json.decode(response.body));
    } catch (e) {
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
      final response = await http.patch(
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
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        // 解析 PocketBase 错误信息，转换为中文
        final errorMsg = _parsePasswordErrorMessage(response.body, response.statusCode);
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

  // 10. 发送邮箱验证码（占位方法，需要后端支持）
  Future<void> sendVerificationCode(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/send-verification-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim()}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('发送验证码失败: ${response.body}');
      }
    } catch (e) {
      throw Exception('发送验证码失败: $e');
    }
  }
}
