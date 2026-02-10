# 实施清单

## 准备工作

### 1. 获取 OSS AccessKey
- [ ] 登录阿里云控制台
- [ ] 访问 RAM 访问控制：https://ram.console.aliyun.com/manage/ak
- [ ] 创建或查看 AccessKey
- [ ] 记录 AccessKeyId 和 AccessKeySecret

### 2. 验证 OSS Bucket 配置
- [ ] 登录阿里云 OSS 控制台
- [ ] 确认 Bucket 名称：`xinghe-aigc`
- [ ] 确认 Endpoint：`oss-cn-chengdu.aliyuncs.com`
- [ ] 确认 Bucket 权限：公共读（Public Read）

### 3. 安装依赖
- [ ] 运行 `flutter pub get`
- [ ] 确认 `ffmpeg_kit_flutter: ^6.0.3` 已安装
- [ ] 确认 `crypto: ^3.0.6` 已安装

## 配置步骤

### 方式一：代码配置（快速测试）

1. 在 `main.dart` 中添加配置代码：

```dart
import 'package:xinghe_new/services/oss_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 配置 OSS（仅首次运行需要）
  await OssConfig.saveConfig(
    accessKeyId: 'YOUR_ACCESS_KEY_ID',
    accessKeySecret: 'YOUR_ACCESS_KEY_SECRET',
  );
  
  runApp(MyApp());
}
```

2. 替换 `YOUR_ACCESS_KEY_ID` 和 `YOUR_ACCESS_KEY_SECRET`

3. 运行应用

### 方式二：设置界面配置（推荐）

1. 在设置页面添加 OSS 配置表单
2. 添加以下字段：
   - AccessKeyId（文本输入框）
   - AccessKeySecret（密码输入框）
   - 保存按钮
   - 测试连接按钮

3. 实现保存逻辑：

```dart
ElevatedButton(
  onPressed: () async {
    await OssConfig.saveConfig(
      accessKeyId: _accessKeyIdController.text,
      accessKeySecret: _accessKeySecretController.text,
    );
    
    if (await OssConfig.isConfigured()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ OSS 配置已保存')),
      );
    }
  },
  child: Text('保存配置'),
)
```

## 测试步骤

### 1. 验证配置
- [ ] 运行应用
- [ ] 检查控制台是否有配置错误
- [ ] 验证 `OssConfig.isConfigured()` 返回 true

### 2. 测试本地转码
- [ ] 打开角色生成页面
- [ ] 添加或推理角色
- [ ] 生成角色图片
- [ ] 观察控制台日志，确认图片生成成功

### 3. 测试上传功能
- [ ] 点击角色的"上传"按钮
- [ ] 观察控制台日志：
  ```
  [本地视频生成] 开始转换图片
  [本地视频生成] ✅ 转换成功
  [直连 OSS] 开始上传视频
  [直连 OSS] ✅ 上传成功
  [队列管理器] ✅ 角色创建成功
  ```
- [ ] 确认角色描述中显示映射代码（`@username,`）

### 4. 验证视频可访问
- [ ] 复制控制台中的视频 URL
- [ ] 在浏览器中打开
- [ ] 确认视频可以正常播放
- [ ] 确认视频时长为 3 秒

### 5. 测试完整流程
- [ ] 创建新作品
- [ ] 推理角色
- [ ] 批量生成角色图片
- [ ] 批量上传角色
- [ ] 确认所有角色都获得了映射代码

## 故障排查

### 问题 1：OSS 未配置
**症状：**
```
OSS 未配置，请在设置中配置 AccessKey
```

**解决方案：**
- [ ] 检查是否调用了 `OssConfig.saveConfig()`
- [ ] 检查 AccessKeyId 和 AccessKeySecret 是否正确
- [ ] 重新配置并重启应用

### 问题 2：FFmpeg 执行失败
**症状：**
```
FFmpeg 执行失败: ReturnCode
```

**解决方案：**
- [ ] 检查 `ffmpeg_kit_flutter` 是否正确安装
- [ ] 检查图片文件是否存在
- [ ] 检查图片格式是否支持（PNG、JPG）
- [ ] 查看 FFmpeg 错误日志

### 问题 3：OSS 上传失败 403
**症状：**
```
OSS 返回错误 (403): AccessDenied
```

**解决方案：**
- [ ] 验证 AccessKey 是否正确
- [ ] 检查 RAM 权限：需要 `oss:PutObject` 权限
- [ ] 确认 Bucket 名称和 Endpoint 正确
- [ ] 检查 Bucket 是否存在

### 问题 4：视频无法访问
**症状：**
```
403 Forbidden
```

**解决方案：**
- [ ] 检查 Bucket 权限：需要公共读
- [ ] 验证上传时是否设置了 `x-oss-object-acl: public-read`
- [ ] 检查 URL 格式是否正确

### 问题 5：Sora API 调用失败
**症状：**
```
角色创建失败：API 返回空结果
```

**解决方案：**
- [ ] 检查上传 API 配置（provider、baseUrl、apiKey）
- [ ] 验证视频 URL 是否可以公开访问
- [ ] 检查 Sora API 是否正常工作
- [ ] 查看 API 错误日志

## 性能验证

### 1. 转码性能
- [ ] 测试不同大小的图片（1MB、5MB、10MB）
- [ ] 记录转码时间
- [ ] 确认转码时间在可接受范围内（通常 1-3 秒）

### 2. 上传性能
- [ ] 测试不同网络环境（WiFi、4G）
- [ ] 记录上传时间
- [ ] 确认上传速度符合预期

### 3. 并发性能
- [ ] 同时上传多个角色（3-5 个）
- [ ] 观察 CPU 和内存使用情况
- [ ] 确认转码串行执行（避免资源竞争）
- [ ] 确认上传并发执行（提高效率）

## 安全检查

### 1. AccessKey 安全
- [ ] 确认 AccessKey 未硬编码在代码中
- [ ] 确认使用 `flutter_secure_storage` 存储
- [ ] 确认 AccessKey 不会被打印到日志中

### 2. 权限检查
- [ ] 确认使用 RAM 子账号（不是主账号）
- [ ] 确认 RAM 权限仅包含必要的 OSS 权限
- [ ] 确认未授予不必要的权限

### 3. 文件权限
- [ ] 确认上传的视频设置了公共读权限
- [ ] 确认 Bucket 未开启公共写权限
- [ ] 确认敏感文件未上传到 OSS

## 文档检查

- [ ] 阅读 `OSS_DIRECT_UPLOAD_GUIDE.md`
- [ ] 阅读 `OSS_SETUP_INSTRUCTIONS.md`
- [ ] 阅读 `REFACTORING_SUMMARY.md`
- [ ] 理解新架构的工作原理
- [ ] 了解故障排查方法

## 代码审查

### 1. 新增文件
- [ ] `lib/services/local_video_generator.dart`
- [ ] `lib/services/direct_oss_upload_service.dart`
- [ ] `lib/services/oss_config.dart`

### 2. 修改文件
- [ ] `lib/services/upload_queue_manager.dart`
- [ ] `pubspec.yaml`

### 3. 文档文件
- [ ] `OSS_DIRECT_UPLOAD_GUIDE.md`
- [ ] `OSS_SETUP_INSTRUCTIONS.md`
- [ ] `REFACTORING_SUMMARY.md`
- [ ] `IMPLEMENTATION_CHECKLIST.md`
- [ ] `test_oss_upload.dart`

## 部署准备

### 1. 生产环境配置
- [ ] 准备生产环境的 AccessKey
- [ ] 配置生产环境的 Bucket
- [ ] 测试生产环境的网络连接

### 2. 用户指南
- [ ] 编写用户配置指南
- [ ] 准备常见问题解答（FAQ）
- [ ] 准备故障排查指南

### 3. 监控和日志
- [ ] 添加上传成功率监控
- [ ] 添加上传失败日志
- [ ] 添加性能监控（转码时间、上传时间）

## 验收标准

- [ ] 所有测试通过
- [ ] 性能符合预期
- [ ] 安全检查通过
- [ ] 文档完整
- [ ] 代码审查通过
- [ ] 用户可以正常使用

## 完成标志

当以上所有项目都打勾后，重构工作即完成。

## 联系支持

如遇到问题，请提供以下信息：
1. 错误日志（控制台输出）
2. OSS 配置状态
3. 测试图片大小和格式
4. 网络环境
5. 操作系统和 Flutter 版本

---

**祝你成功！** 🎉
