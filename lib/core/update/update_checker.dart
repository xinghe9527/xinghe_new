import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'update_info.dart';
import 'update_dialog.dart';

/// 版本检测器
class UpdateChecker {
  final supabase = Supabase.instance.client;

  /// 检查更新
  /// 
  /// 返回: UpdateInfo 如果有更新, null 如果无需更新或检查失败
  Future<UpdateInfo?> checkUpdate() async {
    try {
      // 1. 获取当前应用版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint('📱 当前版本: $currentVersion');

      // 2. 从 Supabase 查询最新版本信息
      final response = await supabase
          .from('app_versions')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        debugPrint('⚠️ 未找到版本信息');
        return null;
      }

      final latestVersion = response['version'] as String;
      final minVersion = response['min_version'] as String?;
      final forceUpdate = response['force_update'] as bool? ?? false;
      final updateUrl = response['update_package_url'] as String;
      final updateLog = response['update_log'] as String?;
      final fileSize = response['file_size'] as int?;

      debugPrint('🆕 最新版本: $latestVersion');
      debugPrint('📦 下载链接: $updateUrl');

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
