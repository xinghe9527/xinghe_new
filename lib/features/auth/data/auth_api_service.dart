import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import '../domain/models/user.dart';
import '../domain/models/invitation_code.dart';

class AuthApiService {
  // ⚠️ 临时降级为 HTTP 以解决握手失败
  static const String baseUrl = 'http://api.xhaigc.cn';

  // 🚀 核心修复：创建一个"百毒不侵"的自定义客户端
  static http.Client _getSecureClient() {
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true; // 忽略证书
    httpClient.connectionTimeout = const Duration(seconds: 15);
    return IOClient(httpClient);
  }

  // 1. 验证邀请码 (使用自定义客户端)
  Future<InvitationCode> verifyInvitationCode(String code) async {
    final trimmedCode = code.trim();
    
    if (trimmedCode.isEmpty) {
      throw Exception('邀请码不能为空');
    }

    final client = _getSecureClient();
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/invitation_codes?code=$trimmedCode&is_used=false'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('HTTP 错误 ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body);
      if (data is! List || data.isEmpty) {
        throw Exception('邀请码不存在或已被使用');
      }
      
      return InvitationCode.fromJson(data[0]);
    } catch (e) {
      throw Exception('验证邀请码失败: $e');
    } finally {
      client.close();
    }
  }

  // 2. 检查邮箱是否已注册
  Future<bool> checkEmailExists(String email) async {
    final client = _getSecureClient();
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/users?email=$email'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('HTTP 错误 ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body);
      return data is List && data.isNotEmpty;
    } catch (e) {
      throw Exception('检查邮箱失败: $e');
    } finally {
      client.close();
    }
  }

  // 3. 注册方法 (整合验证码逻辑)
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String invitationCode,
    String? verificationCode, // 验证码参数（暂时可选）
  }) async {
    final client = _getSecureClient();
    try {
      // Step 1: 验证邀请码
      final code = await verifyInvitationCode(invitationCode.trim());

      // Step 2: 检查邮箱唯一性
      final emailExists = await checkEmailExists(email.trim());
      if (emailExists) {
        throw Exception('该邮箱已被注册');
      }

      // Step 3: 计算会员过期时间
      final expireDate = DateTime.now().add(Duration(days: code.durationDays));

      // Step 4: 创建用户
      final body = {
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        'expire_date': expireDate.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      };

      final regResponse = await client.post(
        Uri.parse('$baseUrl/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (regResponse.statusCode >= 400) {
        throw Exception('注册失败: ${regResponse.body}');
      }

      final userData = json.decode(regResponse.body);
      final userId = userData['_id'] ?? userData['id'];

      // Step 5: 核销邀请码
      await client.put(
        Uri.parse('$baseUrl/invitation_codes/${code.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'is_used': true,
          'used_at': DateTime.now().toIso8601String(),
          'used_by': userId,
        }),
      ).timeout(const Duration(seconds: 15));

      return {
        'user': User.fromJson(userData),
        'token': 'token_$userId',
      };
    } catch (e) {
      throw Exception('注册失败: $e');
    } finally {
      client.close();
    }
  }

  // 4. 登录
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    
    if (trimmedEmail.isEmpty || password.isEmpty) {
      throw Exception('邮箱和密码不能为空');
    }
    
    final client = _getSecureClient();
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/users?email=$trimmedEmail&password=$password'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('HTTP 错误 ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body);
      if (data is! List || data.isEmpty) {
        throw Exception('邮箱或密码错误');
      }
      
      final user = User.fromJson(data[0]);
      
      // 检查会员是否过期
      if (user.isExpired) {
        throw Exception('会员已过期，请联系管理员续费');
      }

      return {
        'user': user,
        'token': 'token_${user.id}',
      };
    } catch (e) {
      throw Exception('登录失败: $e');
    } finally {
      client.close();
    }
  }

  // 5. 更新头像
  Future<User?> updateAvatar({
    required String userId,
    required String avatarUrl,
    required String token,
  }) async {
    final client = _getSecureClient();
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'avatar': avatarUrl}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        return null;
      }

      return User.fromJson(json.decode(response.body));
    } catch (e) {
      return null;
    } finally {
      client.close();
    }
  }

  // 6. 获取用户信息
  Future<User?> getUserInfo(String userId, String token) async {
    final client = _getSecureClient();
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        return null;
      }

      return User.fromJson(json.decode(response.body));
    } catch (e) {
      return null;
    } finally {
      client.close();
    }
  }

  // 7. 发送邮箱验证码（占位方法，需要后端支持）
  Future<void> sendVerificationCode(String email) async {
    final client = _getSecureClient();
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/send-verification-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim()}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 400) {
        throw Exception('发送验证码失败: ${response.body}');
      }
    } catch (e) {
      throw Exception('发送验证码失败: $e');
    } finally {
      client.close();
    }
  }
}
