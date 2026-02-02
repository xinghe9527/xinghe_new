/// 更新信息模型
class UpdateInfo {
  final String currentVersion;  // 当前版本
  final String latestVersion;   // 最新版本
  final String? minVersion;     // 最低支持版本
  final bool forceUpdate;       // 是否强制更新
  final String downloadUrl;     // 下载链接
  final String? updateLog;      // 更新日志
  final int? fileSize;          // 文件大小（字节）
  final bool isBlocked;         // 是否被阻止使用（版本过低）

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    this.minVersion,
    required this.forceUpdate,
    required this.downloadUrl,
    this.updateLog,
    this.fileSize,
    this.isBlocked = false,
  });

  /// 是否需要更新
  bool get needUpdate => compareVersion(currentVersion, latestVersion) < 0;

  /// 获取文件大小的友好显示
  String get fileSizeText {
    if (fileSize == null) return '未知';
    final mb = fileSize! / 1024 / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  /// 版本号比较（公开方法，供外部调用）
  /// 返回值: -1 表示 v1 < v2, 0 表示相等, 1 表示 v1 > v2
  static int compareVersion(String v1, String v2) {
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
}
