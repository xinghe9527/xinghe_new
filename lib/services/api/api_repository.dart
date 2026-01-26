import 'base/api_service_base.dart';
import 'base/api_config.dart';
import 'base/api_response.dart';
import 'api_factory.dart';
import 'secure_storage_manager.dart';

/// API仓库 - 应用层与API服务层的统一接口
/// 负责管理API服务实例和路由请求
class ApiRepository {
  static final ApiRepository _instance = ApiRepository._internal();
  factory ApiRepository() => _instance;
  ApiRepository._internal();

  final ApiFactory _factory = ApiFactory();
  final SecureStorageManager _storage = SecureStorageManager();

  // 缓存的API服务实例
  final Map<String, ApiServiceBase> _serviceCache = {};

  /// 获取API服务实例
  /// 
  /// provider: 服务商名称
  /// forceRefresh: 是否强制刷新（重新从存储加载配置）
  Future<ApiServiceBase?> getService({
    required String provider,
    bool forceRefresh = false,
  }) async {
    // 如果不强制刷新且缓存中有实例，直接返回
    if (!forceRefresh && _serviceCache.containsKey(provider)) {
      return _serviceCache[provider];
    }

    // 从安全存储中加载配置
    final apiKey = await _storage.getApiKey(provider: provider);
    final baseUrl = await _storage.getBaseUrl(provider: provider);

    if (apiKey == null || baseUrl == null) {
      return null; // 配置不完整
    }

    // 创建配置对象
    final config = ApiConfig(
      provider: provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
    );

    // 使用工厂创建服务实例
    final service = _factory.createService(provider, config);
    
    // 缓存实例
    _serviceCache[provider] = service;
    
    return service;
  }

  /// 测试API连接
  Future<ApiResponse<bool>> testConnection({
    required String provider,
  }) async {
    final service = await getService(provider: provider);
    if (service == null) {
      return ApiResponse.failure('API未配置');
    }

    return await service.testConnection();
  }

  /// LLM文本生成
  Future<ApiResponse<LlmResponse>> generateText({
    required String provider,
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final service = await getService(provider: provider);
    if (service == null) {
      return ApiResponse.failure('API未配置');
    }

    return await service.generateText(
      prompt: prompt,
      model: model,
      parameters: parameters,
    );
  }

  /// 图片生成
  Future<ApiResponse<List<ImageResponse>>> generateImages({
    required String provider,
    required String prompt,
    String? model,
    int count = 1,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) async {
    final service = await getService(provider: provider);
    if (service == null) {
      return ApiResponse.failure('API未配置');
    }

    return await service.generateImages(
      prompt: prompt,
      model: model,
      count: count,
      ratio: ratio,
      quality: quality,
      referenceImages: referenceImages,
      parameters: parameters,
    );
  }

  /// 视频生成
  Future<ApiResponse<List<VideoResponse>>> generateVideos({
    required String provider,
    required String prompt,
    String? model,
    int count = 1,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) async {
    final service = await getService(provider: provider);
    if (service == null) {
      return ApiResponse.failure('API未配置');
    }

    return await service.generateVideos(
      prompt: prompt,
      model: model,
      count: count,
      ratio: ratio,
      quality: quality,
      referenceImages: referenceImages,
      parameters: parameters,
    );
  }

  /// 上传素材
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String provider,
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    final service = await getService(provider: provider);
    if (service == null) {
      return ApiResponse.failure('API未配置');
    }

    return await service.uploadAsset(
      filePath: filePath,
      assetType: assetType,
      metadata: metadata,
    );
  }

  /// 获取可用模型列表
  Future<ApiResponse<List<String>>> getAvailableModels({
    required String provider,
    String? modelType,
  }) async {
    final service = await getService(provider: provider);
    if (service == null) {
      return ApiResponse.failure('API未配置');
    }

    return await service.getAvailableModels(modelType: modelType);
  }

  /// 保存API配置
  Future<void> saveConfig({
    required String provider,
    required String apiKey,
    required String baseUrl,
  }) async {
    await _storage.saveApiKey(provider: provider, apiKey: apiKey);
    await _storage.saveBaseUrl(provider: provider, baseUrl: baseUrl);
    
    // 清除缓存，下次获取时重新加载
    _serviceCache.remove(provider);
  }

  /// 保存模型配置
  Future<void> saveModel({
    required String provider,
    required String modelType,
    required String model,
  }) async {
    await _storage.saveModel(
      provider: provider,
      modelType: modelType,
      model: model,
    );
  }

  /// 获取模型配置
  Future<String?> getModel({
    required String provider,
    required String modelType,
  }) async {
    return await _storage.getModel(
      provider: provider,
      modelType: modelType,
    );
  }

  /// 检查服务商是否已配置
  Future<bool> hasProvider({required String provider}) async {
    return await _storage.hasProvider(provider: provider);
  }

  /// 获取所有已配置的服务商
  Future<List<String>> getConfiguredProviders() async {
    return await _storage.getConfiguredProviders();
  }

  /// 删除服务商配置
  Future<void> deleteProvider({required String provider}) async {
    await _storage.deleteApiKey(provider: provider);
    _serviceCache.remove(provider);
  }

  /// 清除所有缓存
  void clearCache() {
    _serviceCache.clear();
  }
}
