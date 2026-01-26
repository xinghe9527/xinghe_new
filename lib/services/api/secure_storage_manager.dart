import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储管理器 - 用于加密存储API密钥
class SecureStorageManager {
  static final SecureStorageManager _instance = SecureStorageManager._internal();
  factory SecureStorageManager() => _instance;
  SecureStorageManager._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // 密钥前缀，用于命名空间隔离
  static const String _keyPrefix = 'xinghe_api_';

  /// 保存API密钥
  Future<void> saveApiKey({
    required String provider,
    required String apiKey,
  }) async {
    await _storage.write(
      key: '${_keyPrefix}${provider}_key',
      value: apiKey,
    );
  }

  /// 获取API密钥
  Future<String?> getApiKey({required String provider}) async {
    return await _storage.read(key: '${_keyPrefix}${provider}_key');
  }

  /// 删除API密钥
  Future<void> deleteApiKey({required String provider}) async {
    await _storage.delete(key: '${_keyPrefix}${provider}_key');
  }

  /// 保存Base URL
  Future<void> saveBaseUrl({
    required String provider,
    required String baseUrl,
  }) async {
    await _storage.write(
      key: '${_keyPrefix}${provider}_url',
      value: baseUrl,
    );
  }

  /// 获取Base URL
  Future<String?> getBaseUrl({required String provider}) async {
    return await _storage.read(key: '${_keyPrefix}${provider}_url');
  }

  /// 保存模型名称
  Future<void> saveModel({
    required String provider,
    required String modelType, // 'llm', 'image', 'video'
    required String model,
  }) async {
    await _storage.write(
      key: '${_keyPrefix}${provider}_${modelType}_model',
      value: model,
    );
  }

  /// 获取模型名称
  Future<String?> getModel({
    required String provider,
    required String modelType,
  }) async {
    return await _storage.read(
      key: '${_keyPrefix}${provider}_${modelType}_model',
    );
  }

  /// 检查是否已配置某个服务商
  Future<bool> hasProvider({required String provider}) async {
    final apiKey = await getApiKey(provider: provider);
    return apiKey != null && apiKey.isNotEmpty;
  }

  /// 清除所有存储（用于调试或重置）
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// 获取所有已配置的服务商列表
  Future<List<String>> getConfiguredProviders() async {
    final all = await _storage.readAll();
    final providers = <String>{};
    
    for (var key in all.keys) {
      if (key.startsWith(_keyPrefix) && key.endsWith('_key')) {
        final provider = key
            .replaceFirst(_keyPrefix, '')
            .replaceFirst('_key', '');
        providers.add(provider);
      }
    }
    
    return providers.toList();
  }
}
