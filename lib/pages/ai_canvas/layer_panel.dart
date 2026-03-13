import 'package:flutter/material.dart';
import 'canvas_models.dart';

/// 图层面板 — 显示在画布右侧，管理所有图层
class LayerPanel extends StatefulWidget {
  final List<CanvasLayer> layers;
  final String? selectedLayerId;
  final Set<String> selectedLayerIds;
  final ValueChanged<String?> onSelectLayer;
  final VoidCallback onLayersChanged; // 图层数据变化时回调

  const LayerPanel({
    super.key,
    required this.layers,
    required this.selectedLayerId,
    required this.selectedLayerIds,
    required this.onSelectLayer,
    required this.onLayersChanged,
  });

  @override
  State<LayerPanel> createState() => _LayerPanelState();
}

class _LayerPanelState extends State<LayerPanel> {
  static const Color _accentBlue = Color(0xFF3B82F6);
  static const Color _borderColor = Color(0xFFE5E7EB);

  /// 按 zIndex 降序排列的图层（最上面的图层显示在列表最前面）
  List<CanvasLayer> get _sortedLayers {
    final sorted = List<CanvasLayer>.from(widget.layers);
    sorted.sort((a, b) => b.zIndex.compareTo(a.zIndex));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedLayers;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: _borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 标题栏
          _buildHeader(),
          const Divider(height: 1, color: _borderColor),
          // 图层列表
          Expanded(
            child: sorted.isEmpty
                ? _buildEmptyState()
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: sorted.length,
                    onReorder: (oldIndex, newIndex) {
                      _reorderLayers(sorted, oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final layer = sorted[index];
                      return _buildLayerItem(layer, index, key: ValueKey(layer.id));
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.layers, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          const Text(
            '图层',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          // 全部显示/隐藏
          _buildHeaderAction(
            icon: Icons.visibility,
            tooltip: '全部显示/隐藏',
            onTap: _toggleAllVisibility,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: Colors.black45),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.layers_clear, size: 32, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            '暂无图层',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerItem(CanvasLayer layer, int index, {required Key key}) {
    final isSelected = widget.selectedLayerId == layer.id ||
        widget.selectedLayerIds.contains(layer.id);

    return ReorderableDragStartListener(
      key: key,
      index: index,
      child: GestureDetector(
        onTap: () => widget.onSelectLayer(layer.id),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? _accentBlue.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: _borderColor.withValues(alpha: 0.5)),
              left: isSelected
                  ? BorderSide(color: _accentBlue, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              // 图层类型图标
              Icon(
                layer.icon,
                size: 16,
                color: layer.visible
                    ? (isSelected ? _accentBlue : Colors.black54)
                    : Colors.black26,
              ),
              const SizedBox(width: 8),
              // 图层名称
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () => _renameLayer(layer),
                  child: Text(
                    layer.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: layer.visible ? Colors.black87 : Colors.black38,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      decoration: layer.visible
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              // 锁定按钮
              _buildLayerAction(
                icon: layer.locked ? Icons.lock : Icons.lock_open,
                isActive: layer.locked,
                tooltip: layer.locked ? '解锁' : '锁定',
                onTap: () {
                  setState(() => layer.locked = !layer.locked);
                  widget.onLayersChanged();
                },
              ),
              // 可见性按钮
              _buildLayerAction(
                icon: layer.visible ? Icons.visibility : Icons.visibility_off,
                isActive: !layer.visible,
                tooltip: layer.visible ? '隐藏' : '显示',
                onTap: () {
                  setState(() => layer.visible = !layer.visible);
                  widget.onLayersChanged();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayerAction({
    required IconData icon,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 14,
            color: isActive ? Colors.black38 : Colors.black54,
          ),
        ),
      ),
    );
  }

  /// 重命名图层
  void _renameLayer(CanvasLayer layer) {
    final controller = TextEditingController(text: layer.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('重命名图层', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入图层名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              setState(() => layer.name = value.trim());
              widget.onLayersChanged();
            }
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                setState(() => layer.name = value);
                widget.onLayersChanged();
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  /// 拖拽重排图层
  void _reorderLayers(
      List<CanvasLayer> sorted, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final layer = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, layer);

    // 重新分配 zIndex（列表第一个 = 最高层级）
    for (int i = 0; i < sorted.length; i++) {
      sorted[i].zIndex = sorted.length - 1 - i;
    }
    widget.onLayersChanged();
  }

  /// 切换全部图层可见性
  void _toggleAllVisibility() {
    final allVisible = widget.layers.every((l) => l.visible);
    setState(() {
      for (var layer in widget.layers) {
        layer.visible = !allVisible;
      }
    });
    widget.onLayersChanged();
  }
}
