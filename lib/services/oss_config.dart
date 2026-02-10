import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

/// OSS 配置管理
/// 
/// 功能：
/// - 安全存储 OSS AccessKey
/// - 提供配置读取接口
class OssConfig {
  static const _storage = FlutterSecureStorage();
  
  // 配置键名
  static const String _keyAccessKeyId = 'oss_access_key_id';
  static const String _keyAccessKeySecret = 'oss_access_key_secret';
  static const String _keyBucket = 'oss_bucket';
  static const String _keyEndpoint = 'oss_endpoint';
  
  // 默认配置（从远程 version.json 动态获取）
  static const String defaultBucket = 'xinghe-aigc';
  static const String defaultEndpoint = 'oss-cn-chengdu.aliyuncs.com';
  
  /// 保存 OSS 配置
  static Future<void> saveConfig({
    required String accessKeyId,
    required String accessKeySecret,
    String? bucket,
    String? endpoint,
  }) async {
    await _storage.write(key: _keyAccessKeyId, value: accessKeyId);
    await _storage.write(key: _keyAccessKeySecret, value: accessKeySecret);
    
    if (bucket != null) {
      await _storage.write(key: _keyBucket, value: bucket);
    }
    
    if (endpoint != null) {
      await _storage.write(key: _keyEndpoint, value: endpoint);
    }
  }
  
  /// 获取 AccessKeyId
  static Future<String?> getAccessKeyId() async {
    // 从存储读取
    final stored = await _storage.read(key: _keyAccessKeyId);
    if (stored != null && stored.isNotEmpty) {
      debugPrint('[OSS配置] 从存储读取 AccessKeyId: ${stored.substring(0, 10)}...');
      return stored;
    }
    
    debugPrint('[OSS配置] ⚠️ AccessKeyId 未配置，请确保已从 version.json 初始化');
    return null;
  }
  
  /// 获取 AccessKeySecret
  static Future<String?> getAccessKeySecret() async {
    // 从存储读取
    final stored = await _storage.read(key: _keyAccessKeySecret);
    if (stored != null && stored.isNotEmpty) {
      debugPrint('[OSS配置] 从存储读取 AccessKeySecret: ${stored.substring(0, 10)}...');
      return stored;
    }
    
    debugPrint('[OSS配置] ⚠️ AccessKeySecret 未配置，请确保已从 version.json 初始化');
    return null;
  }
  
  /// 获取 Bucket（如果未设置则返回默认值）
  static Future<String> getBucket() async {
    final bucket = await _storage.read(key: _keyBucket);
    return bucket ?? defaultBucket;
  }
  
  /// 获取 Endpoint（如果未设置则返回默认值）
  static Future<String> getEndpoint() async {
    final endpoint = await _storage.read(key: _keyEndpoint);
    return endpoint ?? defaultEndpoint;
  }
  
  /// 检查配置是否完整
  static Future<bool> isConfigured() async {
    final accessKeyId = await getAccessKeyId();
    final accessKeySecret = await getAccessKeySecret();
    return accessKeyId != null && 
           accessKeySecret != null && 
           accessKeyId.isNotEmpty && 
           accessKeySecret.isNotEmpty;
  }
  
  /// 从远程 version.json 初始化 OSS 配置
  /// 
  /// [ossStorageData] 从 version.json 中的 oss_storage 对象
  static Future<void> initializeFromRemote(Map<String, dynamic> ossStorageData) async {
    try {
      debugPrint('[OSS配置] 从远程配置初始化...');
      
      // 1. 读取 Base64 编码的密钥（兼容多种字段名）
      final encodedKeyId = ossStorageData['key_id'] as String? ?? 
                          ossStorageData['ak_id'] as String?;
      final encodedKeySecret = ossStorageData['key_secret'] as String? ?? 
                              ossStorageData['ak_secret'] as String?;
      final bucket = ossStorageData['bucket'] as String?;
      final endpoint = ossStorageData['endpoint'] as String?;
      
      if (encodedKeyId == null || encodedKeySecret == null) {
        debugPrint('[OSS配置] ❌ 远程配置缺少密钥信息');
        debugPrint('[OSS配置] 收到的数据: $ossStorageData');
        throw Exception('远程配置缺少必要的密钥信息');
      }
      
      // 2. 解码密钥
      debugPrint('[OSS配置] 解码远程密钥...');
      debugPrint('[OSS配置] Base64 编码: ${encodedKeyId.substring(0, 20)}...');
      
      final keyId = utf8.decode(base64.decode(encodedKeyId));
      final keySecret = utf8.decode(base64.decode(encodedKeySecret));
      
      debugPrint('[OSS配置] AccessKeyId: ${keyId.substring(0, 10)}...');
      debugPrint('[OSS配置] 完整 AccessKeyId: $keyId');  // ✅ 临时显示完整 ID 用于调试
      debugPrint('[OSS配置] AccessKeySecret: ${keySecret.substring(0, 10)}...');
      
      // ✅ 强制清除旧配置，确保使用新的密钥
      debugPrint('[OSS配置] 清除旧配置...');
      await clearConfig();
      
      // 3. 保存到本地存储
      await saveConfig(
        accessKeyId: keyId,
        accessKeySecret: keySecret,
        bucket: bucket,
        endpoint: endpoint,
      );
      
      debugPrint('[OSS配置] ✅ 远程配置已保存');
    } catch (e) {
      debugPrint('[OSS配置] ❌ 初始化失败: $e');
      rethrow;
    }
  }
  
  /// 初始化默认配置（应用启动时调用）
  /// 
  /// 注意：此方法已废弃，改为从远程 version.json 获取配置
  @Deprecated('使用 initializeFromRemote 代替')
  static Future<void> initializeDefaultConfig() async {
    debugPrint('[OSS配置] ⚠️ initializeDefaultConfig 已废弃，请使用 initializeFromRemote');
  }
  
  /// 清除所有配置
  static Future<void> clearConfig() async {
    await _storage.delete(key: _keyAccessKeyId);
    await _storage.delete(key: _keyAccessKeySecret);
    await _storage.delete(key: _keyBucket);
    await _storage.delete(key: _keyEndpoint);
  }
}
