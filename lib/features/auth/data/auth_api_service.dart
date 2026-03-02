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
      final body = {
        'username': username.trim(),
        'name': username.trim(), // PocketBase 可能使用 name 字段
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
      return {
        'user': User.fromJson(userData),
        'token': 'token_$userId',
      };
    } catch (e) {
      // 如果是我们自己抛出的异常，直接传递
      if (e.toString().startsWith('Exception: ')) {
        rethrow;
      }
      throw Exception('注册失败: $e');
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
      final user = User.fromJson(data['record']);
      
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

  // 5. 更新头像
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

  // 6. 获取用户信息
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

  // 7. 发送邮箱验证码（占位方法，需要后端支持）
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
