import 'package:flutter/material.dart';
import '../../domain/models/script_line.dart';
import '../../domain/models/project.dart';
import '../workflow_controller.dart';

/// 第1步：智能剧本编辑器（Excel风格）
class ScriptEditorView extends StatefulWidget {
  final WorkflowController controller;

  const ScriptEditorView({super.key, required this.controller});

  @override
  State<ScriptEditorView> createState() => _ScriptEditorViewState();
}

class _ScriptEditorViewState extends State<ScriptEditorView> {
  final TextEditingController _themeController = TextEditingController();

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161618),
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: ValueListenableBuilder<Project>(
              valueListenable: widget.controller.projectNotifier,
              builder: (context, project, _) {
                if (project.scriptLines.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildScriptTable(project.scriptLines);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 工具栏
  Widget _buildToolbar() {
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
          // AI生成剧本输入框
          Expanded(
            child: TextField(
              controller: _themeController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '输入主题，让AI生成剧本（例如：赛博朋克世界的冒险故事）',
                hintStyle: const TextStyle(color: Color(0xFF666666)),
                filled: true,
                fillColor: const Color(0xFF252629),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // AI生成按钮
          ElevatedButton.icon(
            onPressed: _generateScript,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI 生成'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF888888),
              foregroundColor: const Color(0xFF888888),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 添加空行按钮
          OutlinedButton.icon(
            onPressed: _addEmptyLine,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加空行'),
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
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 100,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          const Text(
            '还没有剧本内容',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '在上方输入主题，让AI为你生成剧本',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 剧本表格（Excel风格）
  Widget _buildScriptTable(List<ScriptLine> lines) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        return Column(
          children: [
            _buildScriptRow(lines[index], index),
            _buildInsertButton(index + 1),
          ],
        );
      },
    );
  }

  /// 剧本行
  Widget _buildScriptRow(ScriptLine line, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF2A2A2C),
          width: 1,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 序号
            Container(
              width: 50,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF252629),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // 类型标签
            Container(
              width: 80,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: line.type == ScriptLineType.action
                    ? const Color(0xFF888888).withOpacity(0.1)
                    : const Color(0xFF009EFD).withOpacity(0.1),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: line.type == ScriptLineType.action
                        ? const Color(0xFF888888).withOpacity(0.2)
                        : const Color(0xFF009EFD).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    line.type.displayName,
                    style: TextStyle(
                      color: line.type == ScriptLineType.action
                          ? const Color(0xFF888888)
                          : const Color(0xFF009EFD),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            // 内容
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (line.hasContextMemory)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF888888).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF888888).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.memory,
                                    color: Color(0xFF888888),
                                    size: 12,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '上下文记忆已激活',
                                    style: TextStyle(
                                      color: Color(0xFF888888),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // AI提示词
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1C),
                ),
                child: Text(
                  line.aiPrompt.isEmpty ? '(待生成)' : line.aiPrompt,
                  style: TextStyle(
                    color: line.aiPrompt.isEmpty
                        ? const Color(0xFF666666)
                        : const Color(0xFFCCCCCC),
                    fontSize: 13,
                    height: 1.5,
                    fontStyle: line.aiPrompt.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            ),
            // 操作按钮
            Container(
              width: 100,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    color: const Color(0xFF888888),
                    onPressed: () => _editLine(line),
                    tooltip: '编辑',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    color: Colors.red.withOpacity(0.7),
                    onPressed: () => widget.controller.deleteScriptLine(line.id),
                    tooltip: '删除',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 插入按钮（在两行之间）
  Widget _buildInsertButton(int insertAt) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _insertLine(insertAt),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.transparent,
              width: 1,
            ),
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF888888).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFF888888),
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '插入一行 / AI扩写',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// AI生成剧本
  void _generateScript() {
    final theme = _themeController.text.trim();
    if (theme.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入主题')),
      );
      return;
    }
    widget.controller.generateScript(theme);
  }

  /// 添加空行
  void _addEmptyLine() {
    final line = ScriptLine(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: '',
      type: ScriptLineType.action,
    );
    widget.controller.addScriptLine(line);
  }

  /// 编辑行
  void _editLine(ScriptLine line) {
    // TODO: 打开编辑对话框
    showDialog(
      context: context,
      builder: (context) => _EditLineDialog(
        line: line,
        onSave: (updated) => widget.controller.updateScriptLine(line.id, updated),
      ),
    );
  }

  /// 插入行（AI扩写）
  void _insertLine(int insertAt) {
    widget.controller.expandScript(insertAt);
  }
}

/// 编辑剧本行对话框
class _EditLineDialog extends StatefulWidget {
  final ScriptLine line;
  final Function(ScriptLine) onSave;

  const _EditLineDialog({required this.line, required this.onSave});

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  late TextEditingController _contentController;
  late ScriptLineType _selectedType;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.line.content);
    _selectedType = widget.line.type;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E20),
      title: const Text('编辑剧本行', style: TextStyle(color: Colors.white)),
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
                ...ScriptLineType.values.map((type) {
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
            // 内容输入
            TextField(
              controller: _contentController,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '输入剧本内容',
                hintStyle: TextStyle(color: Color(0xFF666666)),
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
            foregroundColor: const Color(0xFF888888),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _save() {
    final updated = widget.line.copyWith(
      content: _contentController.text,
      type: _selectedType,
    );
    widget.onSave(updated);
    Navigator.pop(context);
  }
}
