import 'base/api_service_base.dart';
import 'base/api_config.dart';
import 'providers/openai_service.dart';
import 'providers/custom_service.dart';

/// API服务工厂
/// 根据服务商名称创建对应的API服务实例
class ApiFactory {
  static final ApiFactory _instance = ApiFactory._internal();
  factory ApiFactory() => _instance;
  ApiFactory._internal();

  /// 创建API服务实例
  /// 
  /// provider: 服务商标识 (openai, anthropic, custom等)
  /// config: API配置
  ApiServiceBase createService(String provider, ApiConfig config) {
    switch (provider.toLowerCase()) {
      case 'openai':
        return OpenAIService(config);
      
      case 'anthropic':
        // TODO: 当添加Anthropic支持时，返回AnthropicService实例
        return CustomApiService(config, customProviderName: 'Anthropic');
      
      case 'midjourney':
        // TODO: 当添加Midjourney支持时，返回MidjourneyService实例
        return CustomApiService(config, customProviderName: 'Midjourney');
      
      case 'runway':
        // TODO: 当添加Runway支持时，返回RunwayService实例
        return CustomApiService(config, customProviderName: 'Runway');
      
      case 'pika':
        // TODO: 当添加Pika支持时，返回PikaService实例
        return CustomApiService(config, customProviderName: 'Pika');
      
      // 可以继续添加其他服务商...
      
      default:
        // 对于未实现的服务商，使用自定义服务模板
        return CustomApiService(
          config,
          customProviderName: _formatProviderName(provider),
        );
    }
  }

  /// 格式化服务商名称
  String _formatProviderName(String provider) {
    return provider.substring(0, 1).toUpperCase() + 
           provider.substring(1).toLowerCase();
  }

  /// 获取支持的服务商列表
  List<String> getSupportedProviders() {
    return [
      'openai',
      'anthropic',
      'midjourney',
      'runway',
      'pika',
      // 可以继续添加...
    ];
  }

  /// 检查服务商是否被完全支持
  bool isFullySupported(String provider) {
    switch (provider.toLowerCase()) {
      case 'openai':
        return true; // 已完全实现
      default:
        return false; // 使用自定义服务模板
    }
  }
}
