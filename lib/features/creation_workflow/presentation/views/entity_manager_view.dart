import 'package:flutter/material.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/project.dart';
import '../workflow_controller.dart';

/// 第2步：实体与资产管理（角色、场景）
class EntityManagerView extends StatelessWidget {
  final WorkflowController controller;

  const EntityManagerView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161618),
      child: Column(
        children: [
          _buildToolbar(context),
          Expanded(
            child: ValueListenableBuilder<Project>(
              valueListenable: controller.projectNotifier,
              builder: (context, project, _) {
                if (project.entities.isEmpty) {
                  return _buildEmptyState(context);
                }
                return _buildEntityGrid(context, project.entities);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 工具栏
  Widget _buildToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1C),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A2C), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            '实体管理',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // 从剧本提取按钮
          ElevatedButton.icon(
            onPressed: controller.extractEntities,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('从剧本提取'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF888888),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 手动添加按钮
          OutlinedButton.icon(
            onPressed: () => _showAddEntityDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('手动添加'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF3A3A3C)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 100,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          const Text(
            '还没有角色或场景',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '点击"从剧本提取"自动识别，或手动添加',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 实体网格
  Widget _buildEntityGrid(BuildContext context, List<Entity> entities) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        childAspectRatio: 1.5,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: entities.length,
      itemBuilder: (context, index) {
        return _buildEntityCard(context, entities[index]);
      },
    );
  }

  /// 实体卡片
  Widget _buildEntityCard(BuildContext context, Entity entity) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entity.isLocked
              ? const Color(0xFF888888)
              : const Color(0xFF2A2A2C),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：类型和锁定开关
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: entity.type == EntityType.character
                  ? const Color(0xFF888888).withOpacity(0.1)
                  : const Color(0xFF009EFD).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                // 类型图标
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: entity.type == EntityType.character
                        ? const Color(0xFF888888).withOpacity(0.2)
                        : const Color(0xFF009EFD).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    entity.type == EntityType.character
                        ? Icons.person
                        : Icons.landscape,
                    color: entity.type == EntityType.character
                        ? const Color(0xFF888888)
                        : const Color(0xFF009EFD),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // 名称
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entity.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        entity.type.displayName,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // 锁定开关
                Column(
                  children: [
                    Switch(
                      value: entity.isLocked,
                      onChanged: (_) => controller.toggleEntityLock(entity.id),
                      activeColor: const Color(0xFF888888),
                    ),
                    Text(
                      entity.isLocked ? '已锁定' : '未锁定',
                      style: TextStyle(
                        color: entity.isLocked
                            ? const Color(0xFF888888)
                            : const Color(0xFF666666),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 固定描述词
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '固定形象描述',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (entity.isLocked)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF888888).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '锁定生效',
                            style: TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: entity.fixedPrompt),
                      maxLines: null,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '例如：银发，红瞳，机能风外套',
                        hintStyle: TextStyle(color: Color(0xFF666666)),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                      ),
                      onChanged: (value) {
                        controller.updateEntity(
                          entity.id,
                          entity.copyWith(fixedPrompt: value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 操作按钮
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFF2A2A2C), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => controller.deleteEntity(entity.id),
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 添加实体对话框
  void _showAddEntityDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddEntityDialog(
        onAdd: (entity) => controller.addEntity(entity),
      ),
    );
  }
}

/// 添加实体对话框
class _AddEntityDialog extends StatefulWidget {
  final Function(Entity) onAdd;

  const _AddEntityDialog({required this.onAdd});

  @override
  State<_AddEntityDialog> createState() => _AddEntityDialogState();
}

class _AddEntityDialogState extends State<_AddEntityDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  EntityType _selectedType = EntityType.character;

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E20),
      title: const Text('添加实体', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 类型选择
            Row(
              children: [
                const Text('类型：', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 12),
                ...EntityType.values.map((type) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ChoiceChip(
                      label: Text(type.displayName),
                      selected: _selectedType == type,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedType = type);
                        }
                      },
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),
            // 名称
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：主角、未来都市',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // 固定描述
            TextField(
              controller: _promptController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '固定描述',
                hintText: '例如：银发，红瞳，机能风外套',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF888888),
            foregroundColor: Colors.black,
          ),
          child: const Text('添加'),
        ),
      ],
    );
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      return;
    }

    final entity = Entity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: _selectedType,
      name: _nameController.text.trim(),
      fixedPrompt: _promptController.text.trim(),
    );

    widget.onAdd(entity);
    Navigator.pop(context);
  }
}
