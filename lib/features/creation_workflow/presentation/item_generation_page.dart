import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'dart:convert';
import 'widgets/custom_title_bar.dart';
import 'item_prompt_manager.dart';
import 'style_reference_dialog.dart';

/// 物品生成页面
class ItemGenerationPage extends StatefulWidget {
  final String workId;
  final String workName;
  final String scriptContent;

  const ItemGenerationPage({
    super.key,
    required this.workId,
    required this.workName,
    required this.scriptContent,
  });

  @override
  State<ItemGenerationPage> createState() => _ItemGenerationPageState();
}

class _ItemGenerationPageState extends State<ItemGenerationPage> {
  bool _showSettings = false;
  String _selectedPromptName = '默认';
  String _selectedPromptContent = '';
  String _styleReferenceText = '';
  String? _styleReferenceImage;
  List<ItemData> _items = [];
  bool _isInferring = false;

  @override
  void initState() {
    super.initState();
    _loadItemData();
  }

  Future<void> _loadItemData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'items_${widget.workId}';
      final dataJson = prefs.getString(key);
      
      if (dataJson != null && dataJson.isNotEmpty) {
        final data = jsonDecode(dataJson) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _selectedPromptName = data['selectedPromptName'] ?? '默认';
            _selectedPromptContent = data['selectedPromptContent'] ?? '';
            _styleReferenceText = data['styleReferenceText'] ?? '';
            _styleReferenceImage = data['styleReferenceImage'];
            
            final itemList = data['items'] as List<dynamic>?;
            if (itemList != null) {
              _items = itemList
                  .map((e) => ItemData.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('加载物品数据失败: $e');
    }
  }

  Future<void> _saveItemData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'items_${widget.workId}';
      final data = {
        'selectedPromptName': _selectedPromptName,
        'selectedPromptContent': _selectedPromptContent,
        'styleReferenceText': _styleReferenceText,
        'styleReferenceImage': _styleReferenceImage,
        'items': _items.map((e) => e.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      debugPrint('保存物品数据失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: CustomTitleBar(
        subtitle: widget.workName,
        onBack: () => Navigator.pop(context),
        onSettings: () => setState(() => _showSettings = true),
      ),
      body: _showSettings
          ? SettingsPage(onBack: () => setState(() => _showSettings = false))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.category, color: Color(0xFF888888), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '物品生成',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A2C), height: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text(
                          '待生成区',
                          style: TextStyle(color: Color(0xFF666666), fontSize: 14),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          onPressed: _openItemPromptManager,
                          icon: const Icon(Icons.menu_book, size: 20),
                          color: const Color(0xFF888888),
                          tooltip: '物品提示词（当前：$_selectedPromptName）',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF3A3A3C).withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _isInferring ? null : _inferItems,
                          icon: _isInferring
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Color(0xFF888888)),
                                  ),
                                )
                              : const Icon(Icons.psychology, size: 16),
                          label: Text(_isInferring ? '推理中...' : '推理'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF888888),
                            side: const BorderSide(color: Color(0xFF3A3A3C)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _openStyleReference,
                          icon: const Icon(Icons.palette, size: 16),
                          label: const Text('风格参考'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF888888),
                            side: const BorderSide(color: Color(0xFF3A3A3C)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _items.isEmpty ? null : _generateImages,
                          icon: const Icon(Icons.image, size: 16),
                          label: const Text('生成图片'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF888888),
                            side: const BorderSide(color: Color(0xFF3A3A3C)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _items.isEmpty ? _buildEmptyState() : _buildItemList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.category_outlined, size: 80, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 24),
          const Text('还没有物品', style: TextStyle(color: Color(0xFF666666), fontSize: 16)),
          const SizedBox(height: 12),
          const Text(
            '点击"推理"按钮，AI将从剧本中提取物品',
            style: TextStyle(color: Color(0xFF555555), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF252629),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3C),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: TextEditingController(text: item.description),
                        maxLines: 6,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(12),
                        ),
                        onChanged: (value) {
                          _items[index] = item.copyWith(description: value);
                          _saveItemData();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  height: 250,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E20),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          child: Image.network(
                            item.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildImagePlaceholder();
                            },
                          ),
                        )
                      : _buildImagePlaceholder(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 60, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          const Text('待生成', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
        ],
      ),
    );
  }

  void _openItemPromptManager() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => ItemPromptManager(currentPresetName: _selectedPromptName),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedPromptName = result['name'] ?? '默认';
        _selectedPromptContent = result['content'] ?? '';
      });
      await _saveItemData();
    }
  }

  Future<void> _inferItems() async {
    if (widget.scriptContent.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剧本内容为空，无法推理')),
      );
      return;
    }

    setState(() => _isInferring = true);

    try {
      await Future.delayed(const Duration(seconds: 2));

      final mockItems = [
        ItemData(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '全息通讯器',
          description: '手腕式全息投影通讯设备，蓝色光效，可显示3D影像和数据。',
        ),
        ItemData(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          name: '数据解码器',
          description: '便携式黑客工具，黑色金属外壳，带有多个接口和闪烁的LED指示灯。',
        ),
        ItemData(
          id: (DateTime.now().millisecondsSinceEpoch + 2).toString(),
          name: '飞行摩托',
          description: '单人飞行载具，流线型设计，霓虹蓝色灯带，可悬浮和高速飞行。',
        ),
      ];

      if (mounted) {
        setState(() {
          _items = mockItems;
        });
        await _saveItemData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 推理完成，识别到 3 个物品')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('推理失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInferring = false);
      }
    }
  }

  void _openStyleReference() async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => StyleReferenceDialog(
        initialText: _styleReferenceText,
        initialImage: _styleReferenceImage,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _styleReferenceText = result['text'] ?? '';
        _styleReferenceImage = result['image'];
      });
      await _saveItemData();
    }
  }

  Future<void> _generateImages() async {
    if (_items.isEmpty) return;

    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          _items[i] = _items[i].copyWith(
            imageUrl: 'https://picsum.photos/seed/${_items[i].id}/500/500',
          );
        }
      });
      await _saveItemData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已为 ${_items.length} 个物品生成图片')),
        );
      }
    }
  }
}

class ItemData {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;

  ItemData({
    required this.id,
    required this.name,
    required this.description,
    this.imageUrl,
  });

  ItemData copyWith({String? name, String? description, String? imageUrl}) {
    return ItemData(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
      };

  factory ItemData.fromJson(Map<String, dynamic> json) {
    return ItemData(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}
