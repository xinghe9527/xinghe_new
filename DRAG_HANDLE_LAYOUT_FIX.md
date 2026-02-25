# 🔧 拖动手柄布局修复

## 问题描述

在分镜空间的四宫格图片区域，拖动手柄显示在图片外面的左下角，导致图片被挤压变小。

## 问题原因

`DraggableMediaItem` 组件使用了 `Stack` 布局，拖动手柄通过 `Positioned` 定位在左下角。

默认情况下，`Stack` 的大小会包含所有 `Positioned` 子组件的位置，即使它们超出了主要内容的边界。这导致：

```dart
// ❌ 问题代码
Stack(
  children: [
    child,  // 图片内容
    Positioned(
      left: 4,
      bottom: 4,
      child: DragHandle(),  // 拖动手柄
    ),
  ],
)
```

在这种情况下：
1. Stack 的大小 = max(child 的大小, Positioned 子组件的边界)
2. 拖动手柄在 (left: 4, bottom: 4) 位置
3. Stack 会扩展以包含拖动手柄
4. 在四宫格布局中，这会挤压图片

## 解决方案

使用 `Stack` 的 `clipBehavior` 和 `fit` 属性来控制布局行为：

```dart
// ✅ 修复后的代码
Stack(
  clipBehavior: Clip.none,  // 允许子组件超出边界
  fit: StackFit.passthrough,  // Stack 大小由 child 决定，不受 Positioned 影响
  children: [
    child,  // 图片内容
    Positioned(
      left: 4,
      bottom: 4,
      child: DragHandle(),  // 拖动手柄
    ),
  ],
)
```

### 关键属性说明

1. **`clipBehavior: Clip.none`**
   - 允许子组件超出 Stack 的边界
   - 拖动手柄可以显示在图片外面，不会被裁剪

2. **`fit: StackFit.passthrough`**
   - Stack 的大小由非 Positioned 子组件（即 `child`）决定
   - Positioned 子组件不影响 Stack 的大小
   - 这样拖动手柄就不会挤压图片

## 修复的文件

- `lib/features/creation_workflow/presentation/widgets/draggable_media_item.dart`

## 修复后的效果

- 图片保持原始大小，不被挤压
- 拖动手柄显示在图片内部的左下角
- 拖动手柄可以部分超出图片边界（如果需要）
- 不影响其他使用 `DraggableMediaItem` 的地方（视频空间、绘图空间等）

## 影响范围

此修复影响所有使用 `DraggableMediaItem` 组件的地方：
- 视频空间
- 绘图空间
- AI 画布
- 分镜空间
- 角色生成
- 场景生成
- 物品生成

## 测试建议

1. **分镜空间测试**：
   - 生成四宫格图片
   - 确认图片不被挤压
   - 确认拖动手柄在图片左下角
   - 测试拖动功能是否正常

2. **其他空间测试**：
   - 视频空间：确认视频卡片布局正常
   - 绘图空间：确认图片布局正常
   - AI 画布：确认画布节点布局正常

3. **边界情况测试**：
   - 小尺寸图片：拖动手柄是否正常显示
   - 大尺寸图片：拖动手柄是否正常显示
   - 不同宽高比的图片：布局是否正常

## 技术细节

### Stack 的布局行为

Flutter 的 `Stack` 组件有两种布局模式：

1. **默认模式**（`fit: StackFit.loose`）：
   - Stack 的大小 = max(所有子组件的边界)
   - Positioned 子组件会影响 Stack 的大小

2. **Passthrough 模式**（`fit: StackFit.passthrough`）：
   - Stack 的大小 = 非 Positioned 子组件的大小
   - Positioned 子组件不影响 Stack 的大小

### clipBehavior 的作用

- `Clip.none`：不裁剪，子组件可以超出边界
- `Clip.hardEdge`：硬裁剪，超出边界的部分被裁掉
- `Clip.antiAlias`：抗锯齿裁剪
- `Clip.antiAliasWithSaveLayer`：抗锯齿裁剪 + 保存图层

---

**修复时间**：2026-02-25  
**状态**：✅ 已修复  
**影响范围**：所有使用 DraggableMediaItem 的地方
