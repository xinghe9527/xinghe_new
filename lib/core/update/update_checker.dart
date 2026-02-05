import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'update_info.dart';
import 'update_dialog.dart';

/// 版本检测器（使用阿里云函数计算）
class UpdateChecker {
  // ✅ 阿里云函数计算公网地址
  static const String _versionUrl = 'https://xinghe-angchuan-agxvbiyacd.cn-chengdu.fcapp.run';
  
  // ✅ 安全暗号 (Token)
  static const String _token = 'xinghe5201314';
  
  // ✅ 固定的下载地址
  static const String _downloadUrl = 'https://xinghe-aigc.oss-cn-chengdu.aliyuncs.com/app_release/xingheAI_v1.0.1.exe';

  /// 检查更新
  /// 
  /// 返回: UpdateInfo 如果有更新, null 如果无需更新或检查失败
  Future<UpdateInfo?> checkUpdate() async {
    try {
      // 1. 获取当前应用版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint('📱 当前版本: $currentVersion');

      // 2. 从阿里云函数计算获取版本信息
      debugPrint('🔍 检查更新: $_versionUrl');
      final response = await http.get(
        Uri.parse(_versionUrl),
        headers: {
          'x-xinghe-token': _token,  // ✅ 添加安全暗号
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );

      if (response.statusCode != 200) {
        debugPrint('⚠️ 获取版本信息失败: HTTP ${response.statusCode}');
        return null;
      }

      // 3. 解析版本信息（后端返回格式: {"status":"running", "version":"1.0.0"}）
      final versionData = jsonDecode(response.body) as Map<String, dynamic>;
      
      debugPrint('📦 后端返回数据: $versionData');
      
      // 从后端返回中提取版本号
      final latestVersion = versionData['version'] as String? ?? '1.0.0';
      final minVersion = versionData['min_version'] as String?;
      final forceUpdate = versionData['force_update'] as bool? ?? false;
      final updateLog = versionData['update_log'] as String?;
      // ✅ 支持 double 类型的 file_size（例如 11.63）
      final fileSize = (versionData['file_size'] as num?)?.toDouble();
      
      // 使用固定的下载地址
      final updateUrl = _downloadUrl;

      debugPrint('🆕 最新版本: $latestVersion');
      debugPrint('📥 下载地址: $updateUrl');

      // 3. 对比版本
      final needUpdate = UpdateInfo.compareVersion(currentVersion, latestVersion) < 0;

      if (!needUpdate) {
        debugPrint('✅ 已是最新版本');
        return null;
      }

      // 4. 检查是否版本过低（被阻止使用）
      bool isBlocked = false;
      if (minVersion != null) {
        isBlocked = UpdateInfo.compareVersion(currentVersion, minVersion) < 0;
        if (isBlocked) {
          debugPrint('🚫 版本过低，必须更新');
        }
      }

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        minVersion: minVersion,
        forceUpdate: forceUpdate,
        downloadUrl: updateUrl,
        updateLog: updateLog,
        fileSize: fileSize,
        isBlocked: isBlocked,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ 检查更新失败: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// 在应用启动时检查更新
  /// 
  /// 如果有更新，会自动显示更新对话框
  static Future<void> checkOnStartup(BuildContext context) async {
    // 延迟一下，等待应用完全启动
    await Future.delayed(const Duration(seconds: 2));

    if (!context.mounted) return;

    final checker = UpdateChecker();
    final updateInfo = await checker.checkUpdate();

    if (updateInfo == null) return;
    if (!context.mounted) return;

    // 显示更新对话框
    await showUpdateDialog(context, updateInfo);
  }
}
