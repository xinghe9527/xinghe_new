# Sora 角色创建功能实现日志

## 📅 日期
2026-01-26

## 🎯 实现目标
根据提供的 OpenAPI 规范，为 Sora 视频生成服务添加角色创建和管理功能，允许从视频中提取角色并在后续生成中引用。

## 📋 OpenAPI 规范要点

根据提供的 OpenAPI 规范，新增了以下 API 端点：

- **端点**: `POST /sora/v1/characters`
- **请求格式**: `application/json`
- **请求参数**:
  - `timestamps` (string, 必需): 时间范围，格式 "起始,结束"，如 "1,3"
  - `url` (string, 可选): 视频地址（与 from_task 二选一）
  - `from_task` (string, 可选): 已完成的任务 ID（与 url 二选一）
- **响应**: 返回角色信息对象（id, username, permalink, profile_picture_url, profile_desc）

## ✅ 完成的工作

### 1. 核心服务更新

#### `lib/services/api/providers/veo_video_service.dart`

**A. `VeoVideoService` 类新增方法**

添加了 `createCharacter()` 方法：

```dart
Future<ApiResponse<SoraCharacter>> createCharacter({
  required String timestamps,
  String? url,
  String? fromTask,
}) async {
  // 验证参数（url 和 fromTask 必须提供其中一个）
  // 发送 POST 请求到 /sora/v1/characters
  // 返回 SoraCharacter 对象
}
```

**关键特点**：
- 使用 `application/json` 内容类型
- 支持两种创建方式：从 URL 或从任务 ID
- 参数验证：确保 url 和 fromTask 二选一
- 返回完整的角色信息对象

**B. `VeoVideoHelper` 类新增方法（3个）**

1. **`createCharacterFromUrl()`** - 从视频 URL 创建角色
   ```dart
   Future<ApiResponse<SoraCharacter>> createCharacterFromUrl({
     required String videoUrl,
     required String timestamps,
   })
   ```
   - 从在线视频 URL 提取角色
   - 简化的 API，无需记住参数名

2. **`createCharacterFromTask()`** - 从已完成的任务创建角色
   ```dart
   Future<ApiResponse<SoraCharacter>> createCharacterFromTask({
     required String taskId,
     required String timestamps,
   })
   ```
   - 从已完成的 Sora 任务提取角色
   - 适合使用刚生成的视频

3. **`soraCharacterWorkflow()`** - 完整的角色工作流程
   ```dart
   Future<Map<String, dynamic>> soraCharacterWorkflow({
     required String initialPrompt,
     required String characterTimestamps,
     required String characterPrompt,
     int seconds = 10,
   })
   ```
   - 一站式完成：生成视频 → 创建角色 → 使用角色生成新视频
   - 自动处理所有步骤和等待
   - 返回角色信息和新视频

**C. 新增数据模型**

添加了 `SoraCharacter` 类：

```dart
class SoraCharacter {
  final String id;                    // 角色 ID
  final String username;              // 角色名称
  final String permalink;             // 角色主页
  final String profilePictureUrl;     // 头像 URL
  final String? profileDesc;          // 描述（可选）
  final Map<String, dynamic> metadata;
  
  // 便捷 getter
  String get mentionTag => '@$username';  // 用于提示词的引用标签
}
```

### 2. 文档更新

#### `lib/services/api/providers/VEO_VIDEO_USAGE.md`

**A. 新增章节：7. Sora 角色管理**

包含以下小节：

1. **7.1 创建角色（从视频 URL）** - 从在线视频创建
2. **7.2 创建角色（从已完成的任务）** - 从任务 ID 创建
3. **7.3 完整的角色工作流程** - 一站式方法
4. **7.4 角色数据模型** - 字段和属性说明
5. **7.5 使用角色生成视频** - 实际应用示例
6. **7.6 角色创建注意事项** - 5 个重要注意事项

**B. 更新章节编号**

将原来的"7. Sora 角色引用"更新为"8. Sora 角色引用"

**C. 更新注意事项部分**

添加了第 12 条关于 Sora 角色管理的注意事项。

## 📊 功能特点

### 角色创建方式对比

| 方式 | 参数 | 使用场景 | 优势 |
|------|------|---------|------|
| 从 URL | `url` | 使用现有在线视频 | 快速、直接 |
| 从任务 | `from_task` | 使用刚生成的视频 | 无需上传、即时可用 |

### 角色管理工作流程

```
1. 生成/获取包含角色的视频
   ↓
2. 指定角色出现的时间范围（1-3秒）
   ↓
3. 调用创建角色 API
   ↓
4. 获取角色信息（ID、username、头像等）
   ↓
5. 在新视频提示词中使用 @username 引用
   ↓
6. 生成包含该角色的新视频
```

## 🔧 技术实现细节

### 1. API 调用方式

```dart
// 创建角色的请求结构
final requestBody = <String, dynamic>{
  'timestamps': timestamps,
};

// 二选一的参数
if (url != null) {
  requestBody['url'] = url;
}
if (fromTask != null) {
  requestBody['from_task'] = fromTask;
}

final response = await http.post(
  Uri.parse('${config.baseUrl}/sora/v1/characters'),
  headers: {
    'Authorization': 'Bearer ${config.apiKey}',
    'Content-Type': 'application/json',
  },
  body: jsonEncode(requestBody),
);
```

### 2. 参数验证

```dart
// 确保 url 和 fromTask 参数二选一
if (url == null && fromTask == null) {
  return ApiResponse.failure('必须提供 url 或 fromTask 参数之一');
}
if (url != null && fromTask != null) {
  return ApiResponse.failure('url 和 fromTask 参数只能提供其中一个');
}
```

### 3. 数据模型设计

```dart
class SoraCharacter {
  // 核心字段
  final String id;
  final String username;
  final String permalink;
  final String profilePictureUrl;
  final String? profileDesc;
  final Map<String, dynamic> metadata;
  
  // 便捷 getter - 用于提示词引用
  String get mentionTag => '@$username';
  
  // JSON 解析
  factory SoraCharacter.fromJson(Map<String, dynamic> json) {...}
  
  // 字符串表示
  @override
  String toString() => 'SoraCharacter(id: $id, username: @$username)';
}
```

## 📚 使用示例

### 示例 1：从视频 URL 创建角色

```dart
final character = await helper.createCharacterFromUrl(
  videoUrl: 'https://example.com/cute-cat.mp4',
  timestamps: '1,3',
);

if (character.isSuccess) {
  print('角色创建成功!');
  print('ID: ${character.data!.id}');
  print('名称: ${character.data!.mentionTag}');
  print('头像: ${character.data!.profilePictureUrl}');
}
```

### 示例 2：从已完成的任务创建角色

```dart
// 1. 生成包含角色的视频
final videoResult = await service.generateVideos(
  prompt: '一只可爱的橙色猫咪，特写镜头',
  model: VeoModel.sora2,
  ratio: '720x1280',
  parameters: {'seconds': 10},
);

// 2. 等待完成
final status = await helper.pollTaskUntilComplete(
  taskId: videoResult.data!.first.videoId!,
);

// 3. 创建角色
final character = await helper.createCharacterFromTask(
  taskId: status.data!.id,
  timestamps: '1,3',
);

print('角色: ${character.data!.mentionTag}');
```

### 示例 3：完整工作流程（推荐）

```dart
// 一站式完成所有步骤
final result = await helper.soraCharacterWorkflow(
  initialPrompt: '一只橙色小猫，可爱表情，高清特写',
  characterTimestamps: '1,3',
  characterPrompt: '在花园里追逐蝴蝶，阳光明媚',
  seconds: 10,
);

// 检查结果
if (result['character'] != null) {
  final character = result['character'] as SoraCharacter;
  print('✓ 角色: ${character.mentionTag}');
  
  if (result['video'] != null) {
    final video = result['video'] as VeoTaskStatus;
    print('✓ 视频: ${video.videoUrl}');
  }
} else {
  print('✗ 错误: ${result['error']}');
}
```

### 示例 4：角色复用

```dart
// 1. 创建角色
final character = await helper.createCharacterFromUrl(
  videoUrl: 'https://example.com/cat.mp4',
  timestamps: '1,2',
);

if (!character.isSuccess) return;

final cat = character.data!;

// 2. 使用角色生成多个场景
final scenarios = [
  '让 ${cat.mentionTag} 在草地上奔跑',
  '让 ${cat.mentionTag} 打盹',
  '让 ${cat.mentionTag} 跳舞',
  '让 ${cat.mentionTag} 吃东西',
];

for (final scenario in scenarios) {
  final result = await service.generateVideos(
    prompt: scenario,
    model: VeoModel.sora2,
    ratio: '720x1280',
    parameters: {'seconds': 10},
  );
  
  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    
    // 等待完成
    final video = await helper.pollTaskUntilComplete(taskId: taskId);
    
    if (video.isSuccess && video.data!.hasVideo) {
      print('场景: $scenario');
      print('视频: ${video.data!.videoUrl}');
    }
  }
}
```

## ⚠️ 重要注意事项

### 1. 时间范围验证

```dart
// ✅ 正确的时间范围
timestamps: '1,3'    // 差值 2 秒 ✓
timestamps: '0,3'    // 差值 3 秒 ✓
timestamps: '2,3'    // 差值 1 秒 ✓
timestamps: '0.5,2.5' // 差值 2 秒 ✓

// ❌ 错误的时间范围
timestamps: '0,5'    // 差值 5 秒 ✗（超过3秒）
timestamps: '1,1.5'  // 差值 0.5 秒 ✗（小于1秒）
timestamps: '1,0'    // 起始>结束 ✗
```

### 2. 参数互斥性

```dart
// ✅ 正确 - 提供 url
await service.createCharacter(
  timestamps: '1,3',
  url: 'https://example.com/video.mp4',
);

// ✅ 正确 - 提供 fromTask
await service.createCharacter(
  timestamps: '1,3',
  fromTask: 'video_123',
);

// ❌ 错误 - 同时提供两个
await service.createCharacter(
  timestamps: '1,3',
  url: 'https://example.com/video.mp4',
  fromTask: 'video_123',  // 错误！
);

// ❌ 错误 - 都不提供
await service.createCharacter(
  timestamps: '1,3',
  // 缺少 url 或 fromTask
);
```

### 3. 角色内容限制

```dart
// ✅ 允许的角色类型
- 卡通角色
- 动物
- 虚拟人物
- 机器人
- 幻想生物

// ❌ 不允许的角色类型
- 真人
- 真实人物照片
- 名人肖像
```

### 4. 视频质量要求

**推荐的初始视频设置**：
```dart
final videoResult = await service.generateVideos(
  prompt: '一只橙色猫咪，特写镜头，高清，细节丰富',  // 详细描述
  model: VeoModel.sora2,  // 使用 Sora 2.0
  ratio: '720x1280',
  parameters: {'seconds': 10},  // 足够的时长
);
```

**要点**：
- 使用高质量提示词
- 选择合适的镜头（特写或中景）
- 确保角色在时间段内清晰可见
- 保持角色一致性（避免角度变化过大）

### 5. 角色引用使用

```dart
// 创建角色后的使用
final character = result.data!;

// 方式1：使用 mentionTag
final prompt1 = '让 ${character.mentionTag} 跳舞';  // "让 @catname 跳舞"

// 方式2：直接使用 username
final prompt2 = '让 @${character.username} 睡觉';

// 方式3：组合使用
final prompt3 = '${character.mentionTag} 和朋友们一起玩耍';
```

## 🔍 代码质量

### Linter 检查
- ✅ 无 linter 错误
- ✅ 无 linter 警告
- ✅ 类型安全
- ✅ 代码规范

### 代码统计
- 新增服务方法：1 个（`VeoVideoService.createCharacter()`）
- 新增辅助方法：3 个（`createCharacterFromUrl()`, `createCharacterFromTask()`, `soraCharacterWorkflow()`）
- 新增数据模型：1 个（`SoraCharacter`）
- 文档新增章节：1 个主章节，6 个小节
- 新增代码示例：10+ 个

## 📖 文档完整性

### 新增文档内容

1. **主章节**："7. Sora 角色管理"
2. **小节**：
   - 7.1 创建角色（从视频 URL）
   - 7.2 创建角色（从已完成的任务）
   - 7.3 完整的角色工作流程
   - 7.4 角色数据模型
   - 7.5 使用角色生成视频
   - 7.6 角色创建注意事项
3. **章节编号更新**：原"7. Sora 角色引用"改为"8. Sora 角色引用"
4. **注意事项**：添加第 12 条关于 Sora 角色管理

### 文档统计
- 新增章节/小节：7 个
- 新增代码示例：10+ 个
- 新增数据模型表格：2 个
- 新增对比表格：1 个

## 🎉 完成状态

✅ **核心功能**
- [x] 实现 `VeoVideoService.createCharacter()` 方法
- [x] 实现便捷的角色创建方法（2个）
- [x] 实现完整工作流程方法
- [x] 添加 `SoraCharacter` 数据模型

✅ **代码质量**
- [x] 无 linter 错误
- [x] 类型安全
- [x] 完整的文档注释
- [x] 参数验证

✅ **文档**
- [x] 完整的使用指南
- [x] 多个实际场景示例
- [x] 注意事项和限制说明
- [x] 最佳实践建议

## 🚀 使用建议

### 何时使用角色创建？

**✅ 适合使用角色创建：**
- 需要在多个视频中使用同一角色
- 保持角色一致性
- 创建系列视频内容
- 角色驱动的故事叙述

**❌ 不适合使用角色创建：**
- 一次性视频生成
- 不需要角色一致性
- 角色在视频中不明显
- 视频包含真人

### 推荐工作流程

1. **高质量初始视频**：
   - 使用详细的提示词
   - 选择合适的镜头角度
   - 确保角色清晰可见

2. **精确的时间范围**：
   - 选择角色最清晰的时间段
   - 避免角色移动过快的片段
   - 1-3 秒是黄金范围

3. **有效的角色引用**：
   - 在提示词中使用 `@username`
   - 提供角色的动作描述
   - 保持提示词的连贯性

4. **批量生成**：
   - 一次创建角色
   - 生成多个场景视频
   - 保持角色一致性

## 💡 实际应用场景

### 1. 系列视频创作

```dart
// 创建主角
final hero = await helper.createCharacterFromTask(
  taskId: 'initial_video_id',
  timestamps: '1,3',
);

// 使用主角创建系列剧集
final episodes = [
  '第1集：${hero.data!.mentionTag} 的冒险开始',
  '第2集：${hero.data!.mentionTag} 遇到挑战',
  '第3集：${hero.data!.mentionTag} 取得胜利',
];

for (final episode in episodes) {
  // 生成每一集
}
```

### 2. 角色互动

```dart
// 创建多个角色
final cat = await helper.createCharacterFromUrl(
  videoUrl: 'https://example.com/cat.mp4',
  timestamps: '1,2',
);

final dog = await helper.createCharacterFromUrl(
  videoUrl: 'https://example.com/dog.mp4',
  timestamps: '1,2',
);

// 生成角色互动视频
final interaction = await service.generateVideos(
  prompt: '${cat.data!.mentionTag} 和 ${dog.data!.mentionTag} 一起玩耍',
  model: VeoModel.sora2,
  ratio: '720x1280',
  parameters: {'seconds': 10},
);
```

### 3. 品牌吉祥物

```dart
// 创建品牌吉祥物角色
final mascot = await helper.createCharacterFromUrl(
  videoUrl: 'https://brand.com/mascot-intro.mp4',
  timestamps: '1,3',
);

// 生成营销视频系列
final campaigns = [
  '${mascot.data!.mentionTag} 介绍新产品',
  '${mascot.data!.mentionTag} 庆祝节日',
  '${mascot.data!.mentionTag} 与用户互动',
];

for (final campaign in campaigns) {
  // 生成营销视频
}
```

### 4. 教育内容

```dart
// 创建教学角色
final teacher = await helper.createCharacterFromTask(
  taskId: 'teacher_video_id',
  timestamps: '1,3',
);

// 生成教育视频系列
final lessons = [
  '${teacher.data!.mentionTag} 讲解数学概念',
  '${teacher.data!.mentionTag} 演示科学实验',
  '${teacher.data!.mentionTag} 解答常见问题',
];
```

## 📞 相关功能

### 角色创建 vs 角色引用

| 功能 | API 端点 | 用途 |
|------|---------|------|
| **角色创建** | `/sora/v1/characters` | 从视频提取角色，获取角色 ID 和 username |
| **角色引用** | `/v1/videos` (character_url 参数) | 在生成视频时引用角色 |

**组合使用**：
1. 先使用**角色创建** API 提取角色
2. 获取角色的 `username`
3. 在提示词中使用 `@username` 引用
4. 调用视频生成 API

## 📞 相关文档

- **详细使用指南**: `lib/services/api/providers/VEO_VIDEO_USAGE.md`
- **OpenAPI 规范**: 见本次用户提供的 YAML 文档
- **相关功能**: Sora 角色引用（第 8 章）

## 🔄 版本信息

- **功能版本**: v1.3.0
- **更新日期**: 2026-01-26
- **状态**: ✅ 完成并经过测试
- **依赖**: Sora API v1

---

**实现者**: Claude (Cursor AI)
**实现日期**: 2026-01-26
**完成度**: 100%
