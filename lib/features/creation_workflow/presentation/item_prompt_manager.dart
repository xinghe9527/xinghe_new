import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 物品提示词管理器
class ItemPromptManager extends StatefulWidget {
  final String? currentPresetName;

  const ItemPromptManager({super.key, this.currentPresetName});

  @override
  State<ItemPromptManager> createState() => _ItemPromptManagerState();
}

class _ItemPromptManagerState extends State<ItemPromptManager> {
  List<Map<String, String>> _presets = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetsJson = prefs.getString('item_prompt_presets');
      
      if (presetsJson != null && presetsJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(presetsJson);
        setState(() {
          _presets = list.map((e) => Map<String, String>.from(e)).toList();
          if (widget.currentPresetName != null) {
            _selectedIndex = _presets.indexWhere((p) => p['name'] == widget.currentPresetName);
            if (_selectedIndex == -1) _selectedIndex = 0;
          }
        });
      } else {
        _presets = [
          {
            'name': '默认',
            'content': '请从以下剧本中提取所有重要物品和道具，并提供详细的外观描述。包括：形状、颜色、材质、功能、特殊标记。',
          },
          {
            'name': '科幻道具',
            'content': '请提取物品并以科幻风格描述。重点：科技感、LED灯效、金属材质、未来设计、功能性。',
          },
          {
            'name': '魔法物品',
            'content': '请提取物品并以魔法/奇幻风格描述。重点：魔法光效、符文、宝石、神秘感、魔力属性。',
          },
        ];
        await _savePresets();
      }
    } catch (e) {
      debugPrint('加载物品提示词失败: $e');
    }
  }

  Future<void> _savePresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('item_prompt_presets', jsonEncode(_presets));
      
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已保存'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      debugPrint('保存物品提示词失败: $e');
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
            Row(
              children: [
                const Text(
                  '物品提示词',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
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
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 200, child: _buildPresetList()),
                  const SizedBox(width: 24),
                  Expanded(child: _buildPresetEditor()),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
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
          return ListTile(
            title: Text(
              _presets[index]['name'] ?? '',
              style: TextStyle(
                color: index == _selectedIndex ? Colors.white : const Color(0xFF888888),
                fontWeight: index == _selectedIndex ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: index == _selectedIndex,
            selectedTileColor: const Color(0xFF3A3A3C),
            onTap: () => setState(() => _selectedIndex = index),
          );
        },
      ),
    );
  }

  Widget _buildPresetEditor() {
    if (_presets.isEmpty) {
      return const Center(child: Text('请先创建一个预设', style: TextStyle(color: Color(0xFF666666))));
    }

    if (_selectedIndex >= _presets.length) _selectedIndex = 0;
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
          Row(
            children: [
              const Text('名称：', style: TextStyle(color: Color(0xFF888888))),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: preset['name']),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) {
                    _presets[_selectedIndex]['name'] = value;
                    _savePresets();
                  },
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.save, size: 20),
                color: const Color(0xFF888888),
                onPressed: _savePresets,
                tooltip: '保存',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                color: const Color(0xFF888888),
                onPressed: _deletePreset,
                tooltip: '删除',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('提示词内容：', style: TextStyle(color: Color(0xFF888888))),
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
      _presets.add({'name': '新预设 ${_presets.length + 1}', 'content': ''});
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
      if (_selectedIndex >= _presets.length) _selectedIndex = _presets.length - 1;
    });
    _savePresets();
  }

  void _confirmSelection() {
    if (_presets.isEmpty) return;
    Navigator.pop(context, _presets[_selectedIndex]);
  }
}
