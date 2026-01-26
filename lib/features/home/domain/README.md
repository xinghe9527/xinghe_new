# 领域模型 (Domain Models)

## DrawingTask - 绘图任务模型

### 数据结构

```dart
class DrawingTask {
  String id;              // 唯一标识
  String model;           // AI模型
  String ratio;           // 比例 (1:1, 16:9等)
  String quality;         // 清晰度 (1K, 2K, 4K)
  int batchCount;         // 批量生成数量
  String prompt;          // 提示词
  List<String> referenceImages;  // 参考图片路径
  List<String> generatedImages;  // 生成结果路径
  TaskStatus status;      // 任务状态
}
```

### 状态枚举

```dart
enum TaskStatus {
  idle,       // 等待中
  generating, // 生成中
  completed,  // 已完成
  failed,     // 失败
}
```

### 使用示例

```dart
// 创建新任务
final task = DrawingTask.create();

// 更新参数
final updatedTask = task.copyWith(
  model: 'DALL-E 3',
  ratio: '16:9',
  batchCount: 4,
);

// 保存到JSON
final json = task.toJson();

// 从JSON恢复
final restoredTask = DrawingTask.fromJson(json);
```

### 持久化

任务列表通过 `SharedPreferences` 自动保存：
- 键名: `drawing_tasks`
- 格式: JSON数组
- 保存时机: 任务创建、更新、删除时自动保存

### 扩展性

未来可以添加更多字段：
- `createdAt`: 创建时间
- `tags`: 标签分类
- `favorite`: 收藏状态
- `exportPath`: 导出路径
