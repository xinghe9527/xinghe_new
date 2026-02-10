import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'dart:io';

/// 可拖动的媒体项（视频/音频）- 使用独立拖拽手柄
/// 支持拖动到外部应用（如剪映）
class DraggableMediaItem extends StatelessWidget {
  final String filePath;
  final Widget child;
  final String? dragPreviewText;
  final String? coverUrl;  // ✅ 新增：封面图片 URL

  const DraggableMediaItem({
    super.key,
    required this.filePath,
    required this.child,
    this.dragPreviewText,
    this.coverUrl,
  });

  /// 构建封面图片（支持本地文件和网络 URL）
  Widget _buildCoverImage(String coverUrl) {
    final isLocalFile = !coverUrl.startsWith('http');
    
    if (isLocalFile) {
      return Image.file(
        File(coverUrl),
        width: 120,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultDragPreview(context);
        },
      );
    } else {
      return Image.network(
        coverUrl,
        width: 120,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultDragPreview(context);
        },
      );
    }
  }

  /// 构建默认的拖拽预览（无封面图时使用）
  Widget _buildDefaultDragPreview(BuildContext context) {
    return Container(
      width: 120,
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor.withValues(alpha: 0.9),
            Theme.of(context).primaryColor.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.video_file_rounded,
            color: Colors.white,
            size: 36,
          ),
          const SizedBox(height: 6),
          if (dragPreviewText != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                dragPreviewText!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 2,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 原始内容（不被拖动包裹，保持原有交互）
        child,
        
        // ✅ 独立的拖拽手柄（左下角）
        Positioned(
          left: 4,
          bottom: 4,
          child: DragItemWidget(
            // 允许复制操作
            allowedOperations: () {
              debugPrint('🎯 [拖动] 允许的操作: copy');
              return [DropOperation.copy];
            },
            
            // 提供拖动数据
            dragItemProvider: (request) async {
              try {
                final item = DragItem();
                
                // 添加文件 URI（这样剪映等应用可以接收）
                final file = File(filePath);
                if (await file.exists()) {
                  final uri = Uri.file(file.absolute.path);
                  debugPrint('🎯 [拖动] 准备拖动文件: ${file.absolute.path}');
                  debugPrint('🎯 [拖动] URI: $uri');
                  
                  // ✅ 添加文件 URI 格式
                  item.add(Formats.fileUri(uri));
                  
                  // ✅ 尝试添加纯文本格式（某些应用可能需要）
                  try {
                    item.add(Formats.plainText(file.absolute.path));
                    debugPrint('🎯 [拖动] 已添加纯文本格式');
                  } catch (e) {
                    debugPrint('⚠️ [拖动] 添加纯文本格式失败: $e');
                  }
                } else {
                  debugPrint('❌ [拖动] 文件不存在: $filePath');
                }
                
                return item;
              } catch (e, stackTrace) {
                debugPrint('❌ [拖动] 创建拖动项失败: $e');
                debugPrint('❌ [拖动] 堆栈: $stackTrace');
                return DragItem();
              }
            },
            
            // 拖动开始回调
            canAddItemToExistingSession: false,
            
            // 拖动时的预览
            dragBuilder: (context, child) {
              // ✅ 如果有封面图，显示图片预览
              if (coverUrl != null && coverUrl!.isNotEmpty) {
                return Opacity(
                  opacity: 0.5,  // 50% 透明度，幽灵效果
                  child: Container(
                    width: 120,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildCoverImage(coverUrl!),
                    ),
                  ),
                );
              }
              
              // ✅ 没有封面图时，显示美化的图标预览
              return Opacity(
                opacity: 0.7,  // 70% 透明度
                child: _buildDefaultDragPreview(context),
              );
            },
            
            // ✅ 关键修复：必须使用 DraggableWidget 包裹拖拽手柄！
            child: DraggableWidget(
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.open_with_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
