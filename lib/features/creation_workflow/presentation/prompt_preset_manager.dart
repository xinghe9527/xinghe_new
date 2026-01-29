import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 提示词预设管理器
class PromptPresetManager extends StatefulWidget {
  final String? currentPresetName;  // 当前选择的预设名称

  const PromptPresetManager({
    super.key,
    this.currentPresetName,
  });

  @override
  State<PromptPresetManager> createState() => _PromptPresetManagerState();
}

class _PromptPresetManagerState extends State<PromptPresetManager> {
  List<Map<String, String>> _presets = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  /// 加载提示词预设
  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetsJson = prefs.getString('prompt_presets');
      
      if (presetsJson != null && presetsJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(presetsJson);
        setState(() {
          _presets = list.map((e) => Map<String, String>.from(e)).toList();
          // 恢复当前选择的预设
          if (widget.currentPresetName != null) {
            _selectedIndex = _presets.indexWhere(
              (p) => p['name'] == widget.currentPresetName,
            );
            if (_selectedIndex == -1) _selectedIndex = 0;
          }
        });
      } else {
        // 默认预设
        _presets = [
          {
            'name': '默认',
            'content': '请根据以下故事内容，生成一个详细的剧本。要求：\n1. 保留故事的核心情节\n2. 添加场景描述\n3. 包含角色对白\n4. 标注场景切换',
          },
          {
            'name': '简洁版',
            'content': '请将以下故事转换为简洁的剧本格式，突出关键情节和对话。',
          },
          {
            'name': '详细版',
            'content': '请根据以下故事，创作一个详细的剧本。要求：\n1. 详细的场景描述（光线、氛围、环境）\n2. 人物动作和表情\n3. 丰富的对白\n4. 镜头提示\n5. 音效和背景音乐建议',
          },
        ];
        await _savePresets();
      }
    } catch (e) {
      debugPrint('加载提示词预设失败: $e');
    }
  }

  /// 保存提示词预设
  Future<void> _savePresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('prompt_presets', jsonEncode(_presets));
    } catch (e) {
      debugPrint('保存提示词预设失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E20),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Text(
                  '剧本提示词',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // 新建按钮
                OutlinedButton.icon(
                  onPressed: _addPreset,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF888888),
                    side: const BorderSide(color: Color(0xFF3A3A3C)),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 内容区域
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左边：预设列表
                  SizedBox(
                    width: 200,
                    child: _buildPresetList(),
                  ),
                  const SizedBox(width: 24),
                  // 右边：预设内容编辑
                  Expanded(
                    child: _buildPresetEditor(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Color(0xFF888888)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _confirmSelection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3A3A3C),
                    foregroundColor: const Color(0xFF888888),
                  ),
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 预设列表
  Widget _buildPresetList() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252629),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A2C)),
      ),
      child: ListView.builder(
        itemCount: _presets.length,
        itemBuilder: (context, index) {
          final preset = _presets[index];
          final isSelected = index == _selectedIndex;
          
          return ListTile(
            title: Text(
              preset['name'] ?? '',
              style: TextStyle(
                color: isSelected ? const Color(0xFF888888) : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedTileColor: const Color(0xFF3A3A3C),
            onTap: () => setState(() => _selectedIndex = index),
          );
        },
      ),
    );
  }

  /// 预设编辑器
  Widget _buildPresetEditor() {
    if (_presets.isEmpty) {
      return const Center(
        child: Text(
          '请先创建一个预设',
          style: TextStyle(color: Color(0xFF666666)),
        ),
      );
    }

    final preset = _presets[_selectedIndex];
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252629),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A2C)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 名称编辑
          Row(
            children: [
              const Text(
                '名称：',
                style: TextStyle(color: Color(0xFF888888)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: preset['name']),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) {
                    _presets[_selectedIndex]['name'] = value;
                    _savePresets();
                  },
                ),
              ),
              const SizedBox(width: 12),
              // 删除按钮
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _deletePreset,
                tooltip: '删除此预设',
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 内容编辑
          const Text(
            '提示词内容：',
            style: TextStyle(color: Color(0xFF888888)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: preset['content']),
              maxLines: null,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
              onChanged: (value) {
                _presets[_selectedIndex]['content'] = value;
                _savePresets();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 新建预设
  void _addPreset() {
    setState(() {
      _presets.add({
        'name': '新预设 ${_presets.length + 1}',
        'content': '',
      });
      _selectedIndex = _presets.length - 1;
    });
    _savePresets();
  }

  /// 删除预设
  void _deletePreset() {
    if (_presets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个预设')),
      );
      return;
    }

    setState(() {
      _presets.removeAt(_selectedIndex);
      if (_selectedIndex >= _presets.length) {
        _selectedIndex = _presets.length - 1;
      }
    });
    _savePresets();
  }

  /// 确认选择
  void _confirmSelection() {
    if (_presets.isEmpty) return;
    
    final selected = _presets[_selectedIndex];
    Navigator.pop(context, selected);
  }
}
