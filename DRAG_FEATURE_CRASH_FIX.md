# 🔧 拖动功能崩溃修复

## 问题描述

用户点击场景空间或物品空间时软件崩溃。

## 问题原因

在 `_buildImageWidget` 方法中，代码逻辑有多个问题：

### 问题 1：文件检查顺序错误

```dart
// ❌ 错误的代码
Widget _buildImageWidget(String imageUrl) {
  final imageWidget = imageUrl.startsWith('http')
      ? Image.network(imageUrl, fit: BoxFit.cover)
      : Image.file(File(imageUrl), fit: BoxFit.cover);  // 这里会立即创建 Image.file
  
  // 后面才检查文件是否存在
  if (!imageUrl.startsWith('http')) {
    final file = File(imageUrl);
    if (file.existsSync()) {
      // ...
    }
  }
  
  return imageWidget;
}
```

### 问题 2：缺少错误处理

- `Image.network` 和 `Image.file` 没有 `errorBuilder`
- 创建 `DraggableMediaItem` 时没有 try-catch 保护

## 解决方案

### 修复 1：调整代码逻辑顺序

先检查文件类型和存在性，再创建 Widget：

```dart
Widget _buildImageWidget(String imageUrl) {
  // 如果是网络图片，直接返回
  if (imageUrl.startsWith('http')) {
    return Image.network(
      imageUrl, 
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Icon(Icons.broken_image, color: Color(0xFF888888)),
        );
      },
    );
  }
  
  // 本地文件：先检查文件是否存在
  final file = File(imageUrl);
  final imageWidget = Image.file(
    file, 
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) {
      return const Center(
        child: Icon(Icons.broken_image, color: Color(0xFF888888)),
      );
    },
  );
  
  // 如果文件存在，添加拖动功能
  if (file.existsSync()) {
    try {
      return DraggableMediaItem(
        filePath: imageUrl,
        dragPreviewText: path.basename(imageUrl),
        coverUrl: imageUrl,
        child: imageWidget,
      );
    } catch (e) {
      debugPrint('⚠️ 创建拖动组件失败: $e');
      return imageWidget;
    }
  }
  
  // 文件不存在，直接返回图片组件（会显示错误图标）
  return imageWidget;
}
```

### 修复 2：添加错误处理

- 为 `Image.network` 和 `Image.file` 添加 `errorBuilder`
- 用 try-catch 包裹 `DraggableMediaItem` 的创建
- 添加 `debugPrint` 输出错误信息

## 修复的文件

1. `lib/features/creation_workflow/presentation/scene_generation_page.dart`
2. `lib/features/creation_workflow/presentation/item_generation_page.dart`

## 修复后的行为

- 网络图片：显示图片，加载失败显示错误图标
- 本地文件存在：显示图片 + 拖动功能
- 本地文件不存在：显示错误图标
- 拖动组件创建失败：降级为普通图片显示

## 测试建议

1. 打开场景空间，确认不再崩溃
2. 打开物品空间，确认不再崩溃
3. 在场景和物品之间切换，确认不崩溃
4. 生成新的场景图片，确认拖动功能正常
5. 生成新的物品图片，确认拖动功能正常
6. 测试网络图片加载失败的情况
7. 测试本地文件不存在的情况

---

**修复时间**：2026-02-25  
**状态**：✅ 已修复  
**影响范围**：场景生成、物品生成
