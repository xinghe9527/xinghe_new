import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'widgets/custom_title_bar.dart';
import 'scene_prompt_manager.dart';
import 'style_reference_dialog.dart';
import 'asset_library_selector.dart';
import '../../../services/api/api_repository.dart';
import '../../../services/api/secure_storage_manager.dart';

/// 场景生成页面
class SceneGenerationPage extends StatefulWidget {
  final String workId;
  final String workName;
  final String scriptContent;

  const SceneGenerationPage({
    super.key,
    required this.workId,
    required this.workName,
    required this.scriptContent,
  });

  @override
  State<SceneGenerationPage> createState() => _SceneGenerationPageState();
}

class _SceneGenerationPageState extends State<SceneGenerationPage> {
  bool _showSettings = false;
  String _selectedPromptName = '默认';
  String _selectedPromptContent = '';
  String _styleReferenceText = '';
  String? _styleReferenceImage;
  List<SceneData> _scenes = [];
  bool _isInferring = false;
  final ApiRepository _apiRepository = ApiRepository();

  @override
  void initState() {
    super.initState();
    _loadSceneData();
  }

  Future<void> _loadSceneData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'scenes_${widget.workId}';
      final dataJson = prefs.getString(key);
      
      if (dataJson != null && dataJson.isNotEmpty) {
        final data = jsonDecode(dataJson) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _selectedPromptName = data['selectedPromptName'] ?? '默认';
            _selectedPromptContent = data['selectedPromptContent'] ?? '';
            _styleReferenceText = data['styleReferenceText'] ?? '';
            _styleReferenceImage = data['styleReferenceImage'];
            
            final sceneList = data['scenes'] as List<dynamic>?;
            if (sceneList != null) {
              _scenes = sceneList
                  .map((e) => SceneData.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('加载场景数据失败: $e');
    }
  }

  Future<void> _saveSceneData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'scenes_${widget.workId}';
      final data = {
        'selectedPromptName': _selectedPromptName,
        'selectedPromptContent': _selectedPromptContent,
        'styleReferenceText': _styleReferenceText,
        'styleReferenceImage': _styleReferenceImage,
        'scenes': _scenes.map((e) => e.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      debugPrint('保存场景数据失败: $e');
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
                  const Icon(Icons.landscape, color: Color(0xFF888888), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '场景生成',
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
                          onPressed: _openScenePromptManager,
                          icon: const Icon(Icons.menu_book, size: 20),
                          color: const Color(0xFF888888),
                          tooltip: '场景提示词（当前：$_selectedPromptName）',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF3A3A3C).withOpacity( 0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _isInferring ? null : _inferScenes,
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
                          onPressed: _scenes.isEmpty ? null : _generateImages,
                          icon: const Icon(Icons.image, size: 16),
                          label: const Text('生成图片'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF888888),
                            side: const BorderSide(color: Color(0xFF3A3A3C)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 清空按钮
                        OutlinedButton.icon(
                          onPressed: _scenes.isEmpty ? null : _clearAll,
                          icon: const Icon(Icons.delete_sweep, size: 16),
                          label: const Text('清空'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF6B6B),
                            side: BorderSide(color: const Color(0xFFFF6B6B).withOpacity(0.3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _scenes.isEmpty
                        ? _buildEmptyState()
                        : _buildSceneList(),
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
          Icon(Icons.landscape_outlined, size: 80, color: Colors.white.withOpacity( 0.1)),
          const SizedBox(height: 24),
          const Text('还没有场景', style: TextStyle(color: Color(0xFF666666), fontSize: 16)),
          const SizedBox(height: 12),
          const Text(
            '点击"推理"按钮，AI将从剧本中提取场景',
            style: TextStyle(color: Color(0xFF555555), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSceneList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _scenes.length,
      itemBuilder: (context, index) {
        final scene = _scenes[index];
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
                          scene.name,
                          style: const TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: TextEditingController(text: scene.description),
                        maxLines: 6,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(12),
                        ),
                        onChanged: (value) {
                          _scenes[index] = scene.copyWith(description: value);
                          _saveSceneData();
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
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: scene.imageUrl != null && scene.imageUrl!.isNotEmpty
                            ? GestureDetector(
                                onTap: () => _viewImage(scene.imageUrl!),
                                onSecondaryTapDown: (details) => _showImageContextMenu(context, details, scene.imageUrl!),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                  child: _buildImageWidget(scene.imageUrl!),
                                ),
                              )
                            : _buildImagePlaceholder(),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.add_photo_alternate, size: 20),
                          color: const Color(0xFF888888),
                          onPressed: () => _showImageSourceMenu(context, index),
                          tooltip: '添加图片',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity( 0.6),
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
      },
    );
  }

  Widget _buildImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 60, color: Colors.white.withOpacity( 0.1)),
          const SizedBox(height: 12),
          const Text('待生成', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
        ],
      ),
    );
  }

  void _openScenePromptManager() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => ScenePromptManager(currentPresetName: _selectedPromptName),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedPromptName = result['name'] ?? '默认';
        _selectedPromptContent = result['content'] ?? '';
      });
      await _saveSceneData();
    }
  }

  /// 推理场景（调用真实 LLM API）
  Future<void> _inferScenes() async {
    if (widget.scriptContent.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剧本内容为空，无法推理')),
      );
      return;
    }

    setState(() => _isInferring = true);

    try {
      // ✅ 读取 LLM 完整配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('llm_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final model = await storage.getModel(provider: provider, modelType: 'llm');
      
      print('\n🧠 开始推理场景');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔧 Provider: $provider');
      print('🎯 Model: ${model ?? "未设置"}');
      print('📋 场景提示词预设: $_selectedPromptContent');
      print('📝 剧本长度: ${widget.scriptContent.length} 字符');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // ✅ 构建 messages
      final messages = <Map<String, String>>[];
      
      final basePrompt = '''请从以下剧本中提取所有场景。

剧本：
${widget.scriptContent}

输出格式：
每个场景一行，格式为：
场景名称 | 场景描述

示例：
未来都市天台 | 高楼天台，夜晚，霓虹灯闪烁，俯瞰整个城市。
地下工作室 | 多个全息屏幕，服务器机架，暗色调，科技感十足。

现在开始提取：''';
      
      String fullPrompt = '';
      if (_selectedPromptContent.isNotEmpty) {
        fullPrompt = '''【重要指令 - 必须严格遵守】
$_selectedPromptContent

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$basePrompt''';
      } else {
        fullPrompt = basePrompt;
      }
      
      messages.add({'role': 'user', 'content': fullPrompt});
      
      // ✅ 调用真实 LLM API
      _apiRepository.clearCache();
      final response = await _apiRepository.generateTextWithMessages(
        provider: provider,
        messages: messages,
        model: model,
        parameters: {
          'temperature': 0.5,
          'max_tokens': 2000,
        },
      );
      
      if (response.isSuccess && response.data != null) {
        final responseText = response.data!.text;
        
        print('📄 API 返回场景列表:');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print(responseText);
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
        
        // ✅ 解析场景
        final sceneList = <SceneData>[];
        final lines = responseText.split('\n');
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          if (line.contains('|')) {
            final parts = line.split('|');
            if (parts.length >= 2) {
              sceneList.add(SceneData(
                id: DateTime.now().millisecondsSinceEpoch.toString() + sceneList.length.toString(),
                name: parts[0].trim(),
                description: parts[1].trim(),
              ));
            }
          }
        }
        
        if (sceneList.isEmpty) {
          sceneList.add(SceneData(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: '场景列表',
            description: responseText,
          ));
        }
        
        if (mounted) {
          setState(() {
            _scenes = sceneList;
          });
          await _saveSceneData();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ 推理完成，识别到 ${sceneList.length} 个场景'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception(response.error ?? '推理失败');
      }
    } catch (e) {
      print('❌ 推理场景失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('推理失败：$e'),
            backgroundColor: Colors.red,
          ),
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
      await _saveSceneData();
    }
  }

  /// 清空所有场景
  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Color(0xFFFFA726), size: 28),
            SizedBox(width: 12),
            Text('确认清空', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          '确定要清空所有场景吗？\n\n此操作不可恢复，已生成的场景和图片都将被删除。',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定清空', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _scenes.clear();
      });
      await _saveSceneData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 已清空所有场景'),
            backgroundColor: Color(0xFF888888),
          ),
        );
      }
    }
  }

  Future<void> _generateImages() async {
    if (_scenes.isEmpty) return;

    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      setState(() {
        for (var i = 0; i < _scenes.length; i++) {
          final imageUrl = 'https://picsum.photos/seed/${_scenes[i].id}/800/450';
          _scenes[i] = _scenes[i].copyWith(imageUrl: imageUrl);
          _saveImageToLocal(imageUrl, 'scene_${_scenes[i].id}');
        }
      });
      await _saveSceneData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已为 ${_scenes.length} 个场景生成图片')),
        );
      }
    }
  }

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
              Text('场景素材库', style: TextStyle(color: Color(0xFF888888))),
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

  Future<void> _selectFromLibrary(int index) async {
    final selectedPath = await showDialog<String>(
      context: context,
      builder: (context) => const AssetLibrarySelector(
        category: AssetCategory.scene,  // 只显示场景素材
      ),
    );

    if (selectedPath != null && mounted) {
      setState(() {
        _scenes[index] = _scenes[index].copyWith(imageUrl: selectedPath);
      });
      await _saveSceneData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已从素材库选择图片')),
        );
      }
    }
  }

  Future<void> _insertLocalImage(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty && mounted) {
      final filePath = result.files.first.path!;
      setState(() {
        _scenes[index] = _scenes[index].copyWith(imageUrl: filePath);
      });
      await _saveSceneData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已插入图片')),
        );
      }
    }
  }

  Future<void> _saveImageToLocal(String imageUrl, String filename) async {
    try {
      final savePath = imageSavePathNotifier.value;
      if (savePath == '未设置' || savePath.isEmpty) return;
      debugPrint('保存图片到: $savePath/$filename.png');
    } catch (e) {
      debugPrint('保存图片失败: $e');
    }
  }

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

  void _showImageContextMenu(BuildContext context, TapDownDetails details, String imageUrl) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中配置图片保存路径')),
        );
      }
    }
  }

  Widget _buildImageWidget(String imageUrl) {
    if (imageUrl.startsWith('http')) {
      return Image.network(imageUrl, fit: BoxFit.cover);
    } else {
      return Image.file(File(imageUrl), fit: BoxFit.cover);
    }
  }
}

class SceneData {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;

  SceneData({
    required this.id,
    required this.name,
    required this.description,
    this.imageUrl,
  });

  SceneData copyWith({String? name, String? description, String? imageUrl}) {
    return SceneData(
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

  factory SceneData.fromJson(Map<String, dynamic> json) {
    return SceneData(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}
