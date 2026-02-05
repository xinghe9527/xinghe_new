import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 版本更新服务（使用阿里云 OSS）
class UpdateService {
  // ✅ 阿里云 OSS 版本配置文件地址
  static const String _versionUrl = 'https://xinghe-aigc.oss-cn-chengdu.aliyuncs.com/version.json';

  /// 检查更新
  /// 返回: UpdateInfo 如果有更新, null 如果无需更新或检查失败
  Future<UpdateInfo?> checkUpdate() async {
    try {
      // 1. 获取本地版本
      final packageInfo = await PackageInfo.fromPlatform();
      final localVersion = packageInfo.version;

      debugPrint('📱 当前版本: $localVersion');

      // 2. 从阿里云 OSS 获取版本信息
      debugPrint('🔍 检查更新: $_versionUrl');
      final response = await http.get(Uri.parse(_versionUrl)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );

      if (response.statusCode != 200) {
        debugPrint('⚠️ 获取版本信息失败: HTTP ${response.statusCode}');
        return null;
      }

      // 3. 解析版本信息
      final versionData = jsonDecode(response.body) as Map<String, dynamic>;
      
      final latestVersion = versionData['version'] as String;
      final minVersion = versionData['min_version'] as String?;
      final forceUpdate = versionData['force_update'] as bool? ?? false;
      final downloadUrl = versionData['download_url'] as String;
      final updateLog = versionData['update_log'] as String?;

      debugPrint('🆕 最新版本: $latestVersion');
      debugPrint('🔒 最低版本: $minVersion');

      // 4. 版本比较
      final hasUpdate = _compareVersion(localVersion, latestVersion) < 0;
      final isForceUpdate = minVersion != null && _compareVersion(localVersion, minVersion) < 0;

      if (!hasUpdate) {
        debugPrint('✅ 已是最新版本');
        return null;
      }

      debugPrint('🔔 发现新版本');
      if (isForceUpdate) {
        debugPrint('🚫 版本过低，强制更新');
      }

      return UpdateInfo(
        localVersion: localVersion,
        latestVersion: latestVersion,
        minVersion: minVersion,
        downloadUrl: downloadUrl,
        updateLog: updateLog,
        hasUpdate: hasUpdate,
        isForceUpdate: isForceUpdate,
        forceUpdate: forceUpdate,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ 检查更新失败: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// 版本号比较
  /// 返回: -1 表示 v1 < v2, 0 表示相等, 1 表示 v1 > v2
  int _compareVersion(String v1, String v2) {
    final a = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final b = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // 补齐长度
    while (a.length < 3) a.add(0);
    while (b.length < 3) b.add(0);

    for (int i = 0; i < 3; i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    return 0;
  }

  /// 显示更新对话框
  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
    return showDialog(
      context: context,
      barrierDismissible: !info.isForceUpdate, // 强制更新时不可关闭
      builder: (context) => WillPopScope(
        onWillPop: () async => !info.isForceUpdate, // 强制更新时不可返回
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                info.isForceUpdate ? Icons.warning_amber_rounded : Icons.system_update,
                color: info.isForceUpdate ? Colors.orange : const Color(0xFF00E5FF),
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                info.isForceUpdate ? '⚠️ 版本过低，必须更新' : '🎉 发现新版本',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 版本信息
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '当前版本',
                          style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info.localVersion,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_forward, color: Color(0xFF888888)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          '最新版本',
                          style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info.latestVersion,
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 更新日志
                if (info.updateLog != null && info.updateLog!.isNotEmpty) ...[
                  const Text(
                    '更新内容：',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252629),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      info.updateLog!,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 强制更新警告
                if (info.isForceUpdate) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前版本过低，必须更新后才能使用软件',
                            style: TextStyle(
                              color: Colors.orange.shade300,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            // 取消按钮（仅非强制更新时显示）
            if (!info.isForceUpdate)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '稍后提醒',
                  style: TextStyle(color: Color(0xFF888888)),
                ),
              ),

            // 立即更新按钮
            ElevatedButton.icon(
              onPressed: () => _openDownloadUrl(info.downloadUrl),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('立即更新'),
              style: ElevatedButton.styleFrom(
                backgroundColor: info.isForceUpdate 
                    ? Colors.orange 
                    : const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开下载链接
  static Future<void> _openDownloadUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint('✅ 已打开下载链接');
      } else {
        debugPrint('❌ 无法打开链接: $url');
      }
    } catch (e) {
      debugPrint('❌ 打开链接失败: $e');
    }
  }

  /// 在应用启动时检查更新
  /// 
  /// 在 HomePage/MainScreen 的 initState 中调用
  static Future<void> checkOnStartup(BuildContext context) async {
    // 延迟2秒，等待应用完全启动
    await Future.delayed(const Duration(seconds: 2));

    if (!context.mounted) return;

    final service = UpdateService();
    final updateInfo = await service.checkUpdate();

    if (updateInfo == null) return;
    if (!context.mounted) return;

    // 显示更新对话框
    await showUpdateDialog(context, updateInfo);
  }
}

/// 更新信息模型
class UpdateInfo {
  final String localVersion;     // 本地版本
  final String latestVersion;    // 最新版本
  final String? minVersion;      // 最低支持版本
  final String downloadUrl;      // 下载链接（.exe 安装包）
  final String? updateLog;       // 更新日志
  final bool hasUpdate;          // 是否有更新
  final bool isForceUpdate;      // 是否强制更新（版本低于 min_version）
  final bool forceUpdate;        // 是否强制更新标记（来自数据库）

  UpdateInfo({
    required this.localVersion,
    required this.latestVersion,
    this.minVersion,
    required this.downloadUrl,
    this.updateLog,
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.forceUpdate,
  });

  @override
  String toString() {
    return 'UpdateInfo(local: $localVersion, latest: $latestVersion, '
        'min: $minVersion, hasUpdate: $hasUpdate, isForce: $isForceUpdate)';
  }
}
