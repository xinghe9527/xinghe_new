import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 角色提示词管理器（独立且通用）
class CharacterPromptManager extends StatefulWidget {
  final String? currentPresetName;

  const CharacterPromptManager({
    super.key,
    this.currentPresetName,
  });

  @override
  State<CharacterPromptManager> createState() => _CharacterPromptManagerState();
}

class _CharacterPromptManagerState extends State<CharacterPromptManager> {
  List<Map<String, String>> _presets = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  /// 加载角色提示词预设
  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetsJson = prefs.getString('character_prompt_presets');
      
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
            'content': '请从以下剧本中提取所有出现的角色，并为每个角色提供详细的外貌描述。格式要求：\n角色名称：[名字]\n外貌描述：[详细的外貌特征]\n性格特点：[简要性格]',
          },
          {
            'name': '动漫风格',
            'content': '请从剧本中提取角色，并以动漫/漫画风格描述他们的外貌。重点包括：发型、发色、眼睛颜色、服装风格、配饰等视觉元素。',
          },
          {
            'name': '写实风格',
            'content': '请从剧本中提取角色，并以写实风格描述他们的外貌。包括：年龄、身高、体型、面部特征、穿着打扮等。',
          },
        ];
        await _savePresets();
      }
    } catch (e) {
      debugPrint('加载角色提示词预设失败: $e');
    }
  }

  /// 保存预设
  Future<void> _savePresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'character_prompt_presets',
        jsonEncode(_presets),
      );
    } catch (e) {
      debugPrint('保存角色提示词预设失败: $e');
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
                  '角色提示词',
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

  void _confirmSelection() {
    if (_presets.isEmpty) return;
    
    final selected = _presets[_selectedIndex];
    Navigator.pop(context, selected);
  }
}
