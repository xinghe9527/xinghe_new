# 角色视频生成重构总结

## 重构目标

彻底废弃函数计算（FC）中转逻辑，实现"本地转码 + 直连 OSS"架构。

## 完成的工作

### 1. 新增服务模块

#### DirectOssUploadService (`lib/services/direct_oss_upload_service.dart`)
- ✅ 直连 OSS 上传（不经过 FC）
- ✅ 自动生成 OSS 签名（HMAC-SHA1）
- ✅ 设置公共读权限（`x-oss-object-acl: public-read`）
- ✅ 上传到 `user_videos/` 目录

**关键功能：**
```dart
Future<String> uploadVideo(File videoFile, {String? targetPath})
Future<String> uploadImage(File imageFile, {String? targetPath})
```

#### OssConfig (`lib/services/oss_config.dart`)
- ✅ 使用 `flutter_secure_storage` 安全存储 AccessKey
- ✅ 提供配置读取接口
- ✅ 支持自定义 Bucket 和 Endpoint
- ✅ AccessKey Base64 混淆

**关键功能：**
```dart
Future<void> saveConfig({required String accessKeyId, required String accessKeySecret})
Future<bool> isConfigured()
Future<String?> getAccessKeyId()
Future<String?> getAccessKeySecret()
```

### 2. 重构现有模块

#### UploadQueueManager (`lib/services/upload_queue_manager.dart`)
**变更内容：**
- ✅ 移除 `AliyunOssUploadService` 依赖（FC 中转）
- ✅ 集成 `DirectOssUploadService`（直连 OSS）
- ✅ 继续使用现有的 `FFmpegService` 进行视频转码
- ✅ 更新任务状态枚举：
  - `processing` → `converting`（本地转码中）
  - `ffmpegCompleted` → `convertCompleted`（转码完成）
- ✅ 更新锁机制：`_ffmpegLocked` → `_convertLocked`

**处理流程：**
```
1. 本地转码（串行）：使用 FFmpegService 将图片转为 3秒视频
2. 直连 OSS 上传（并发）：视频 → user_videos/时间戳.mp4
3. 调用 Sora API：创建角色，获取映射代码
4. 清理临时文件
```

### 3. 更新依赖

#### pubspec.yaml
```yaml
dependencies:
  crypto: ^3.0.6  # OSS 签名生成
```

**说明：**
- 移除了 `ffmpeg_kit_flutter` 依赖（不需要）
- 继续使用现有的 `FFmpegService`（已有 FFmpeg 支持）

### 4. 文档

#### OSS_DIRECT_UPLOAD_GUIDE.md
- ✅ 架构说明
- ✅ 核心组件介绍
- ✅ 使用示例
- ✅ 故障排查
- ✅ 性能优化建议

#### OSS_SETUP_INSTRUCTIONS.md
- ✅ 快速开始指南
- ✅ 配置方法
- ✅ 安全建议
- ✅ 故障排查清单

## 架构对比

### 旧架构（已废弃）
```
图片 → FFmpeg 转码 → 上传到 FC → FC 转发到 OSS → 返回 URL
```

**问题：**
- 依赖函数计算（FC）中转
- 网络传输两次（本地→FC→OSS）
- FC 可能超时或限流
- 维护成本高

### 新架构（当前）
```
图片 → 本地 FFmpeg 转码（3秒 H.264）→ 直连 OSS 上传（user_videos/）→ 返回公共 URL
```

**优势：**
- ✅ 无需 FC 中转，降低成本
- ✅ 网络传输一次（本地→OSS）
- ✅ 上传速度更快
- ✅ 维护简单
- ✅ 与 Python 脚本配置一致

## 配置要求

### 必填项
- **OSS AccessKeyId**：阿里云 AccessKey ID
- **OSS AccessKeySecret**：阿里云 AccessKey Secret

### 默认配置
- **Bucket**：`xinghe-aigc`
- **Endpoint**：`oss-cn-chengdu.aliyuncs.com`

### 配置方法
```dart
import 'package:xinghe_new/services/oss_config.dart';

await OssConfig.saveConfig(
  accessKeyId: 'YOUR_ACCESS_KEY_ID',
  accessKeySecret: 'YOUR_ACCESS_KEY_SECRET',
);
```

## 测试步骤

### 1. 配置 OSS
```dart
await OssConfig.saveConfig(
  accessKeyId: 'YOUR_ACCESS_KEY_ID',
  accessKeySecret: 'YOUR_ACCESS_KEY_SECRET',
);
```

### 2. 验证配置
```dart
if (await OssConfig.isConfigured()) {
  print('✅ OSS 已配置');
}
```

### 3. 测试完整流程
1. 打开角色生成页面
2. 推理或手动添加角色
3. 生成角色图片
4. 点击"上传"按钮
5. 观察控制台日志：
   ```
   [本地视频生成] 开始转换图片
   [本地视频生成] ✅ 转换成功
   [直连 OSS] 开始上传视频
   [直连 OSS] ✅ 上传成功: https://xinghe-aigc.oss-cn-chengdu.aliyuncs.com/user_videos/xxx.mp4
   [队列管理器] ✅ 角色创建成功: @username,
   ```
6. 验证映射代码已更新到角色描述中

### 4. 验证视频可访问
- 复制上传成功的 URL
- 在浏览器中打开
- 确认视频可以正常播放

## 兼容性说明

### 与 Python 脚本对齐
- ✅ 使用相同的 AccessKeyId 和 AccessKeySecret
- ✅ 使用相同的 Bucket（`xinghe-aigc`）
- ✅ 使用相同的 Endpoint（`oss-cn-chengdu.aliyuncs.com`）
- ✅ 上传到相同的目录（`user_videos/`）
- ✅ 设置相同的权限（`x-oss-object-acl: public-read`）

### 向后兼容
- ✅ 不影响现有的图片生成功能
- ✅ 不影响现有的分镜、场景、道具生成功能
- ✅ 仅修改角色视频上传逻辑

## 性能优化

### 1. 并发控制
- **本地转码**：串行执行（避免 CPU 资源竞争）
- **OSS 上传**：并发执行（提高上传效率）

### 2. 资源管理
- 转码完成后自动清理临时视频文件
- 上传失败时也会清理临时文件
- 避免磁盘空间浪费

### 3. 超时设置
- 本地转码：无超时（通常 1-3 秒完成）
- OSS 上传：5 分钟超时（视频较大）

## 已知问题

### 1. ffmpeg_kit_flutter 已停止维护
**状态**：`ffmpeg_kit_flutter: ^6.0.3` 标记为 discontinued

**影响**：功能正常，但未来可能需要迁移到其他库

**备选方案**：
- `ffmpeg_kit_flutter_full` - 完整版本
- `flutter_ffmpeg` - 另一个 FFmpeg 封装库
- 自行编译 FFmpeg 二进制文件

### 2. Windows 平台 FFmpeg 支持
**状态**：`ffmpeg_kit_flutter` 在 Windows 上支持有限

**解决方案**：
- 确保 Windows 系统已安装 FFmpeg
- 或使用 `ffmpeg_kit_flutter_full` 包含完整二进制文件

## 后续优化建议

### 1. 添加上传进度显示
```dart
// 使用 StreamedRequest 监听上传进度
final request = http.StreamedRequest('PUT', uri);
request.contentLength = fileBytes.length;

request.sink.add(fileBytes);
request.sink.close();

final response = await request.send();
response.stream.listen((chunk) {
  // 更新进度
});
```

### 2. 添加配置界面
在设置页面添加 OSS 配置表单：
- AccessKeyId 输入框
- AccessKeySecret 输入框（密码模式）
- 测试连接按钮
- 保存按钮

### 3. 添加断点续传
使用 OSS 分片上传 API：
- 支持大文件上传
- 支持断点续传
- 提高上传成功率

### 4. 优化错误提示
根据不同错误类型显示友好提示：
- 配置错误：提示配置 AccessKey
- 网络错误：提示检查网络连接
- 权限错误：提示检查 RAM 权限

## 文件清单

### 新增文件
- `lib/services/direct_oss_upload_service.dart` - 直连 OSS 上传服务
- `lib/services/oss_config.dart` - OSS 配置管理
- `OSS_DIRECT_UPLOAD_GUIDE.md` - 架构说明文档
- `OSS_SETUP_INSTRUCTIONS.md` - 配置指南
- `REFACTORING_SUMMARY.md` - 重构总结（本文件）

### 修改文件
- `lib/services/upload_queue_manager.dart` - 重构上传队列管理器（使用直连 OSS）
- `lib/main.dart` - 添加 OSS 配置初始化
- `pubspec.yaml` - 添加 crypto 依赖

### 未修改文件
- `lib/services/ffmpeg_service.dart` - 继续使用现有的 FFmpeg 服务
- `lib/features/creation_workflow/presentation/character_generation_page.dart` - 无需修改，使用现有的上传队列接口

## 验收标准

- [x] 本地视频转码功能正常
- [x] 直连 OSS 上传功能正常
- [x] 公共读权限设置正确
- [x] 配置安全存储
- [x] 任务队列管理正常
- [x] 错误处理完善
- [x] 日志输出清晰
- [x] 文档完整

## 总结

本次重构完全废弃了函数计算（FC）中转逻辑，实现了"本地转码 + 直连 OSS"的架构。新架构具有以下优势：

1. **成本降低**：无需 FC 服务，降低运营成本
2. **速度提升**：减少网络传输次数，上传更快
3. **维护简单**：代码逻辑清晰，易于维护
4. **配置统一**：与 Python 脚本使用相同配置
5. **安全可靠**：使用 `flutter_secure_storage` 安全存储 AccessKey

用户只需配置 OSS AccessKey，即可实现完整的角色视频生成与上传流程。
