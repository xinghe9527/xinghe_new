import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'update_info.dart';
import 'update_dialog.dart';
import 'package:xinghe_new/services/oss_config.dart';  // ✅ 导入 OSS 配置

/// 版本检测器（使用阿里云 OSS 直连）
class UpdateChecker {
  // ✅ OSS 直连地址（公共读，无需签名）
  static const String _versionUrl = 'https://xinghe-aigc.oss-cn-chengdu.aliyuncs.com/version.json';

  /// 检查更新
  /// 
  /// 返回: UpdateInfo 如果有更新, null 如果无需更新或检查失败
  Future<UpdateInfo?> checkUpdate() async {
    try {
      // 1. 获取当前应用版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint('📱 当前版本: $currentVersion');

      // 2. 从 OSS 获取版本信息（无需 token）
      debugPrint('🔍 检查更新: $_versionUrl');
      final response = await http.get(
        Uri.parse(_versionUrl),
        // ✅ OSS 公共读，移除所有 Header
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏱️ 请求超时（10秒）');
          throw Exception('网络请求超时，请检查网络连接');
        },
      );

      if (response.statusCode != 200) {
        debugPrint('⚠️ 获取版本信息失败: HTTP ${response.statusCode}');
        throw Exception('服务器返回错误: ${response.statusCode}');
      }

      // 3. 解析版本信息
      final versionData = jsonDecode(response.body) as Map<String, dynamic>;
      
      debugPrint('📦 后端返回数据: $versionData');
      
      // ✅ 初始化 OSS 配置（从 version.json 获取）
      try {
        final ossStorage = versionData['oss_storage'] as Map<String, dynamic>?;
        if (ossStorage != null) {
          debugPrint('🔑 检测到 OSS 配置，开始初始化...');
          await OssConfig.initializeFromRemote(ossStorage);
          debugPrint('✅ OSS 配置初始化成功');
        } else {
          debugPrint('⚠️ version.json 中未找到 oss_storage 配置');
        }
      } catch (e) {
        debugPrint('❌ OSS 配置初始化失败: $e');
        // 不影响版本检查流程
      }
      
      // ✅ 解析所有字段（与后端对齐）
      final latestVersion = versionData['version'] as String?;
      final downloadUrl = versionData['download_url'] as String?;
      final updateLog = versionData['update_log'] as String?;
      final fileSize = (versionData['file_size'] as num?)?.toDouble();
      final forceUpdate = versionData['force_update'] as bool? ?? false;
      
      if (latestVersion == null || latestVersion.isEmpty) {
        debugPrint('❌ 后端未返回 version');
        return null;
      }
      
      if (downloadUrl == null || downloadUrl.isEmpty) {
        debugPrint('❌ 后端未返回 download_url');
        return null;
      }
      
      // ✅ 打印关键信息
      debugPrint('🆕 最新版本: $latestVersion');
      debugPrint('📥 下载地址: $downloadUrl');
      debugPrint('🔒 强制更新: $forceUpdate');

      // 4. 对比版本
      final needUpdate = UpdateInfo.compareVersion(currentVersion, latestVersion) < 0;

      if (!needUpdate) {
        debugPrint('✅ 已是最新版本');
        return null;
      }

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        minVersion: null,  // ✅ 废弃 minVersion，使用 forceUpdate
        forceUpdate: forceUpdate,
        downloadUrl: downloadUrl,
        updateLog: updateLog,
        fileSize: fileSize,
        isBlocked: forceUpdate,  // ✅ 强制更新时视为阻止使用
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
  /// 如果网络错误，会显示错误提示但不阻止应用启动
  static Future<void> checkOnStartup(BuildContext context) async {
    // 延迟一下，等待应用完全启动
    await Future.delayed(const Duration(seconds: 2));

    if (!context.mounted) return;

    try {
      final checker = UpdateChecker();
      final updateInfo = await checker.checkUpdate();

      if (updateInfo == null) {
        // 无需更新或检查失败，不影响应用启动
        return;
      }
      
      if (!context.mounted) return;

      // 显示更新对话框
      await showUpdateDialog(context, updateInfo);
    } catch (e) {
      // ✅ 网络错误处理：显示提示但不阻止应用启动
      debugPrint('❌ 启动时检查更新失败: $e');
      
      if (!context.mounted) return;
      
      // 显示友好的错误提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.wifi_off, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '检查更新失败，请检查网络连接',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFFF9800),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
