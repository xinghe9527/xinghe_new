import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'widgets/custom_title_bar.dart';
import 'character_prompt_manager.dart';
import 'style_reference_dialog.dart';
import 'asset_library_selector.dart';

/// 角色生成页面
class CharacterGenerationPage extends StatefulWidget {
  final String workId;
  final String workName;
  final String scriptContent;  // 剧本内容，用于推理

  const CharacterGenerationPage({
    super.key,
    required this.workId,
    required this.workName,
    required this.scriptContent,
  });

  @override
  State<CharacterGenerationPage> createState() => _CharacterGenerationPageState();
}

class _CharacterGenerationPageState extends State<CharacterGenerationPage> {
  bool _showSettings = false;
  String _selectedPromptName = '默认';
  String _selectedPromptContent = '';
  String _styleReferenceText = '';
  String? _styleReferenceImage;
  List<CharacterData> _characters = [];
  bool _isInferring = false;

  @override
  void initState() {
    super.initState();
    _loadCharacterData();
  }

  /// 加载角色数据
  Future<void> _loadCharacterData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'characters_${widget.workId}';
      final dataJson = prefs.getString(key);
      
      if (dataJson != null && dataJson.isNotEmpty) {
        final data = jsonDecode(dataJson) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _selectedPromptName = data['selectedPromptName'] ?? '默认';
            _selectedPromptContent = data['selectedPromptContent'] ?? '';
            _styleReferenceText = data['styleReferenceText'] ?? '';
            _styleReferenceImage = data['styleReferenceImage'];
            
            final charList = data['characters'] as List<dynamic>?;
            if (charList != null) {
              _characters = charList
                  .map((e) => CharacterData.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('加载角色数据失败: $e');
    }
  }

  /// 保存角色数据
  Future<void> _saveCharacterData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'characters_${widget.workId}';
      final data = {
        'selectedPromptName': _selectedPromptName,
        'selectedPromptContent': _selectedPromptContent,
        'styleReferenceText': _styleReferenceText,
        'styleReferenceImage': _styleReferenceImage,
        'characters': _characters.map((e) => e.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(data));
      debugPrint('✅ 保存角色数据');
    } catch (e) {
      debugPrint('⚠️ 保存角色数据失败: $e');
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
            // 顶部工具栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Color(0xFF888888), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '角色生成',
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
            // 待生成区
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 操作按钮栏
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text(
                          '待生成区',
                          style: TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 提示词按钮（小书图标）
                        IconButton(
                          onPressed: _openCharacterPromptManager,
                          icon: const Icon(Icons.menu_book, size: 20),
                          color: const Color(0xFF888888),
                          tooltip: '角色提示词（当前：$_selectedPromptName）',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF3A3A3C).withOpacity(0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 推理按钮
                        OutlinedButton.icon(
                          onPressed: _isInferring ? null : _inferCharacters,
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
                        // 风格参考按钮
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
                        // 生成图片按钮
                        OutlinedButton.icon(
                          onPressed: _characters.isEmpty ? null : _generateImages,
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
                  // 角色列表
                  Expanded(
                    child: _characters.isEmpty
                        ? _buildEmptyState()
                        : _buildCharacterList(),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            Icons.person_outline,
            size: 80,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          const Text(
            '还没有角色',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '点击"推理"按钮，AI将从剧本中提取角色',
            style: TextStyle(
              color: Color(0xFF555555),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 角色列表
  Widget _buildCharacterList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _characters.length,
      itemBuilder: (context, index) {
        return _buildCharacterCard(_characters[index], index);
      },
    );
  }

  /// 角色卡片
  Widget _buildCharacterCard(CharacterData character, int index) {
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
          // 左边：角色信息
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 角色名称
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3C),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          character.name,
                          style: const TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 角色描述（可编辑）
                  TextField(
                    controller: TextEditingController(text: character.description),
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(12),
                    ),
                    onChanged: (value) {
                      _characters[index] = character.copyWith(description: value);
                      _saveCharacterData();
                    },
                  ),
                ],
              ),
            ),
          ),
          // 右边：图片生成区
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
              child: Stack(
                children: [
                  // 图片显示区
                  Positioned.fill(
                    child: character.imageUrl != null && character.imageUrl!.isNotEmpty
                        ? GestureDetector(
                            onTap: () => _viewImage(character.imageUrl!),
                            onSecondaryTapDown: (details) => _showImageContextMenu(context, details, character.imageUrl!),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                              ),
                              child: _buildImageWidget(character.imageUrl!),
                            ),
                          )
                        : _buildImagePlaceholder(),
                  ),
                  // 右上角插入按钮
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.add_photo_alternate, size: 20),
                          color: const Color(0xFF888888),
                          onPressed: () => _showImageSourceMenu(context, index),
                          tooltip: '添加图片',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.6),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 图片占位符
  Widget _buildImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 60,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 12),
          const Text(
            '待生成',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// 打开角色提示词管理器
  void _openCharacterPromptManager() async {
    if (!mounted) return;
    
    try {
      final result = await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => CharacterPromptManager(
          currentPresetName: _selectedPromptName,
        ),
      );

      if (!mounted) return;
      
      if (result != null) {
        setState(() {
          _selectedPromptName = result['name'] ?? '默认';
          _selectedPromptContent = result['content'] ?? '';
        });
        await _saveCharacterData();
        debugPrint('✅ 作品 ${widget.workName} 选择角色提示词: $_selectedPromptName');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 打开角色提示词管理器失败: $e');
      debugPrint('堆栈: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    }
  }

  /// 推理角色
  Future<void> _inferCharacters() async {
    if (widget.scriptContent.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剧本内容为空，无法推理')),
      );
      return;
    }

    setState(() => _isInferring = true);

    try {
      // TODO: 调用LLM API推理角色
      // 使用选择的角色提示词 + 剧本内容
      await Future.delayed(const Duration(seconds: 2));

      // Mock数据：推理出的角色
      final mockCharacters = [
        CharacterData(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '主角',
          description: '20岁左右的年轻人，银白色短发，蓝色眼睛，身穿黑色机能风外套。性格沉稳，擅长黑客技术。',
        ),
        CharacterData(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          name: '神秘人',
          description: '身份不明的神秘角色，总是戴着面具，穿着长风衣。声音低沉，似乎知道很多秘密。',
        ),
        CharacterData(
          id: (DateTime.now().millisecondsSinceEpoch + 2).toString(),
          name: 'AI助手',
          description: '全息投影形态的人工智能，外观为半透明的蓝色光影。能够提供信息支持和战术建议。',
        ),
      ];

      if (mounted) {
        setState(() {
          _characters = mockCharacters;
        });
        await _saveCharacterData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 推理完成，识别到 3 个角色')),
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

  /// 打开风格参考对话框
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
      await _saveCharacterData();
    }
  }

  /// 生成角色图片
  Future<void> _generateImages() async {
    if (_characters.isEmpty) return;

    // TODO: 为每个角色生成图片
    // 使用：角色描述 + 风格参考文字 + 风格参考图片
    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      setState(() {
        for (var i = 0; i < _characters.length; i++) {
          // Mock图片URL
          final imageUrl = 'https://picsum.photos/seed/${_characters[i].id}/400/600';
          _characters[i] = _characters[i].copyWith(imageUrl: imageUrl);
          // 保存到本地
          _saveImageToLocal(imageUrl, 'character_${_characters[i].id}');
        }
      });
      await _saveCharacterData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已为 ${_characters.length} 个角色生成图片')),
        );
      }
    }
  }

  /// 显示图片来源选择菜单
  void _showImageSourceMenu(BuildContext context, int index) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 100, 0, 0),
      items: const [
        PopupMenuItem(
          value: 'library',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('角色素材库', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'local',
          child: Row(
            children: [
              Icon(Icons.file_upload, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('本地图片', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'library') {
        _selectFromLibrary(index);
      } else if (value == 'local') {
        _insertLocalImage(index);
      }
    });
  }

  /// 从素材库选择
  Future<void> _selectFromLibrary(int index) async {
    final selectedPath = await showDialog<String>(
      context: context,
      builder: (context) => const AssetLibrarySelector(
        category: AssetCategory.character,  // 只显示角色素材
      ),
    );

    if (selectedPath != null && mounted) {
      setState(() {
        _characters[index] = _characters[index].copyWith(imageUrl: selectedPath);
      });
      await _saveCharacterData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已从素材库选择图片')),
        );
      }
    }
  }

  /// 插入本地图片
  Future<void> _insertLocalImage(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty && mounted) {
      final filePath = result.files.first.path!;
      setState(() {
        _characters[index] = _characters[index].copyWith(imageUrl: filePath);
      });
      await _saveCharacterData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已插入图片')),
        );
      }
    }
  }

  /// 保存图片到本地
  Future<void> _saveImageToLocal(String imageUrl, String filename) async {
    try {
      final savePath = imageSavePathNotifier.value;
      if (savePath == '未设置' || savePath.isEmpty) return;
      
      // TODO: 下载并保存图片到本地
      debugPrint('保存图片到: $savePath/$filename.png');
    } catch (e) {
      debugPrint('保存图片失败: $e');
    }
  }

  /// 查看图片（放大）
  void _viewImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: _buildImageWidget(imageUrl),
          ),
        ),
      ),
    );
  }

  /// 显示图片右键菜单
  void _showImageContextMenu(BuildContext context, TapDownDetails details, String imageUrl) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('打开文件夹', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'open_folder') {
        _openSaveFolder();
      }
    });
  }

  /// 打开保存文件夹
  void _openSaveFolder() async {
    final savePath = imageSavePathNotifier.value;
    if (savePath != '未设置' && savePath.isNotEmpty) {
      try {
        if (Platform.isWindows) {
          Process.run('explorer', [savePath]);
        } else if (Platform.isMacOS) {
          Process.run('open', [savePath]);
        } else if (Platform.isLinux) {
          Process.run('xdg-open', [savePath]);
        }
      } catch (e) {
        debugPrint('打开文件夹失败: $e');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置图片保存路径')),
      );
    }
  }

  /// 构建图片Widget（支持网络和本地）
  Widget _buildImageWidget(String imageUrl) {
    if (imageUrl.startsWith('http')) {
      return Image.network(imageUrl, fit: BoxFit.cover);
    } else {
      return Image.file(File(imageUrl), fit: BoxFit.cover);
    }
  }
}

/// 角色数据模型
class CharacterData {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;

  CharacterData({
    required this.id,
    required this.name,
    required this.description,
    this.imageUrl,
  });

  CharacterData copyWith({
    String? name,
    String? description,
    String? imageUrl,
  }) {
    return CharacterData(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
    };
  }

  factory CharacterData.fromJson(Map<String, dynamic> json) {
    return CharacterData(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}
