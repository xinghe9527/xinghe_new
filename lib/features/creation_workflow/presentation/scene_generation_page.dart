import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
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
  String _imageRatio = '16:9';  // ✅ 图片比例，默认 16:9
  List<SceneData> _scenes = [];
  bool _isInferring = false;
  final ApiRepository _apiRepository = ApiRepository();
  final Set<int> _generatingImages = {};

  final List<String> _ratios = ['1:1', '9:16', '16:9', '4:3', '3:4'];  // ✅ 比例选项

  @override
  void initState() {
    super.initState();
    _loadSceneData();
    _loadImageRatio();  // 加载保存的比例设置
  }

  /// 加载图片比例设置
  Future<void> _loadImageRatio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRatio = prefs.getString('scene_image_ratio');
      if (savedRatio != null && _ratios.contains(savedRatio)) {
        if (mounted) {
          setState(() => _imageRatio = savedRatio);
        }
        debugPrint('✅ 加载场景图片比例: $savedRatio');
      }
    } catch (e) {
      debugPrint('⚠️ 加载场景图片比例失败: $e');
    }
  }

  /// 保存图片比例设置
  Future<void> _saveImageRatio(String ratio) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('scene_image_ratio', ratio);
      debugPrint('✅ 保存场景图片比例: $ratio');
    } catch (e) {
      debugPrint('⚠️ 保存场景图片比例失败: $e');
    }
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
                        // 比例选择器（样式与其他按钮一致）
                        PopupMenuButton<String>(
                          offset: const Offset(0, 40),
                          tooltip: '选择图片比例',
                          color: const Color(0xFF2A2A2C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFF3A3A3C)),
                          ),
                          itemBuilder: (context) {
                            return _ratios.map((ratio) {
                              final isSelected = ratio == _imageRatio;
                              return PopupMenuItem<String>(
                                value: ratio,
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check : Icons.crop_square,
                                      size: 16,
                                      color: isSelected ? const Color(0xFF4A9EFF) : Colors.transparent,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      ratio,
                                      style: TextStyle(
                                        color: isSelected ? const Color(0xFF4A9EFF) : const Color(0xFF888888),
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList();
                          },
                          onSelected: (v) {
                            setState(() => _imageRatio = v);
                            _saveImageRatio(v);  // 保存选择的比例
                          },
                          child: OutlinedButton.icon(
                            onPressed: null,  // 点击由 PopupMenuButton 处理
                            icon: const Icon(Icons.aspect_ratio, size: 16),
                            label: Text(_imageRatio),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF888888),
                              side: const BorderSide(color: Color(0xFF3A3A3C)),
                              disabledForegroundColor: const Color(0xFF888888),  // 禁用状态下保持颜色
                            ),
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
                      // 场景名称和操作按钮
                      Row(
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
                          const SizedBox(width: 8),
                          // 生成图片按钮（单个）
                          IconButton(
                            onPressed: _generatingImages.contains(index) ? null : () => _generateSingleScene(index),
                            icon: _generatingImages.contains(index)
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF888888))),
                                  )
                                : const Icon(Icons.image, size: 16),
                            tooltip: '生成图片',
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF3A3A3C),
                              foregroundColor: const Color(0xFF888888),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                          // 删除按钮
                          IconButton(
                            onPressed: () => _deleteScene(index),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            tooltip: '删除场景',
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF3A3A3C),
                              foregroundColor: const Color(0xFF888888),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                        ],
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
      
      String fullPrompt = '';
      
      if (_selectedPromptContent.isNotEmpty) {
        // ✅ 如果用户设置了提示词预设，完全使用用户的预设（不添加干扰性指令）
        fullPrompt = _selectedPromptContent.replaceAll('{{小说原文}}', widget.scriptContent)
            .replaceAll('{{推文文案}}', widget.scriptContent)
            .replaceAll('{{故事情节}}', widget.scriptContent);
        
        print('✅ 使用用户自定义提示词预设（完整控制输出格式）');
      } else {
        // ✅ 如果没有预设，使用简单的基础格式
        fullPrompt = '''请从以下剧本中提取所有场景。

剧本：
${widget.scriptContent}

输出格式：
每个场景一行，格式为：
场景名称 | 场景描述

示例：
未来都市天台 | 高楼天台，夜晚，霓虹灯闪烁，俯瞰整个城市。
地下工作室 | 多个全息屏幕，服务器机架，暗色调，科技感十足。

现在开始提取：''';
        
        print('⚠️ 未设置提示词预设，使用默认简单格式');
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
        
        // ✅ 智能解析场景（支持 JSON 格式和简单格式）
        final sceneList = <SceneData>[];
        
        try {
          // 尝试解析 JSON 格式
          try {
            // 清理文本：移除可能的 markdown 代码块标记
            String cleanText = responseText.trim();
            if (cleanText.startsWith('```json')) {
              cleanText = cleanText.replaceFirst('```json', '').trim();
            }
            if (cleanText.startsWith('```')) {
              cleanText = cleanText.replaceFirst('```', '').trim();
            }
            if (cleanText.endsWith('```')) {
              cleanText = cleanText.substring(0, cleanText.lastIndexOf('```')).trim();
            }
            
            // 尝试找到 JSON 数组
            final startIndex = cleanText.indexOf('[');
            final endIndex = cleanText.lastIndexOf(']');
            
            if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
              final jsonStr = cleanText.substring(startIndex, endIndex + 1);
              final List<dynamic> jsonList = jsonDecode(jsonStr);
              
              print('✅ JSON 解析成功，找到 ${jsonList.length} 个场景');
              
              for (final item in jsonList) {
                if (item is Map<String, dynamic>) {
                  final name = item['name']?.toString() ?? '未命名';
                  final description = item['description']?.toString() ?? '';
                  
                  sceneList.add(SceneData(
                    id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + sceneList.length.toString(),
                    name: name,
                    description: description,
                  ));
                  
                  print('   - 场景: $name (描述长度: ${description.length})');
                }
              }
            } else {
              throw Exception('未找到有效的 JSON 数组标记');
            }
          } catch (jsonError) {
            print('⚠️ JSON 格式解析失败: $jsonError');
            throw jsonError;
          }
        } catch (e) {
          // JSON 解析失败，尝试简单格式（场景名称 | 场景描述）
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          print('⚠️ 尝试简单格式解析（场景名称 | 场景描述）');
          
          final lines = responseText.split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            
            // 跳过明显的注释或说明行
            if (trimmed.startsWith('#') || 
                trimmed.startsWith('//') || 
                trimmed.startsWith('根据') ||
                trimmed.startsWith('```')) {
              continue;
            }
            
            if (trimmed.contains('|')) {
              final parts = trimmed.split('|');
              if (parts.length >= 2) {
                final name = parts[0].trim();
                final description = parts.sublist(1).join('|').trim();
                
                if (name.isNotEmpty && description.isNotEmpty) {
                  sceneList.add(SceneData(
                    id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + sceneList.length.toString(),
                    name: name,
                    description: description,
                  ));
                  
                  print('   - 场景: $name (描述长度: ${description.length})');
                }
              }
            }
          }
          
          print('✅ 简单格式解析完成，找到 ${sceneList.length} 个场景');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        }
        
        if (sceneList.isEmpty) {
          // 如果所有解析都失败，将整个文本作为一个场景
          print('⚠️ 所有格式解析失败，使用原始文本作为单个场景');
          sceneList.add(SceneData(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: '推理结果',
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

  /// 生成单个场景图片
  Future<void> _generateSingleScene(int index) async {
    final scene = _scenes[index];
    
    setState(() {
      _generatingImages.add(index);
    });
    
    print('\n🎨 生成单个场景图片');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('场景: ${scene.name}');
    print('比例: $_imageRatio');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    try {
      // 读取图片 API 配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('image_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final baseUrl = await storage.getBaseUrl(provider: provider, modelType: 'image');
      final apiKey = await storage.getApiKey(provider: provider, modelType: 'image');
      final model = await storage.getModel(provider: provider, modelType: 'image');

      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置图片 API');
      }

      // 构建完整的提示词（只用于图片生成，不使用推理预设）
      String fullPrompt = scene.description;
      
      // ✅ 添加风格参考说明
      if (_styleReferenceText.isNotEmpty) {
        fullPrompt = '$_styleReferenceText, $fullPrompt';
      }
      
      // ✅ 如果有风格参考图片，在提示词中明确说明
      final hasStyleImage = _styleReferenceImage != null && _styleReferenceImage!.isNotEmpty;
      if (hasStyleImage) {
        fullPrompt = '参考图片的艺术风格、色彩和构图风格，但不要融合图片内容。$fullPrompt';
      }
      
      print('   📝 生成提示词: ${fullPrompt.substring(0, fullPrompt.length > 100 ? 100 : fullPrompt.length)}...');
      print('   🎨 风格参考图片: ${hasStyleImage ? "是" : "否"}');

      // 准备参考图片
      final referenceImages = <String>[];
      if (hasStyleImage) {
        referenceImages.add(_styleReferenceImage!);
        print('   📸 添加风格参考图片');
      }

      // 调用 API
      final response = await _apiRepository.generateImages(
        provider: provider,
        prompt: fullPrompt,
        model: model,
        referenceImages: referenceImages.isEmpty ? null : referenceImages,
        parameters: {
          'size': _imageRatio,
          'quality': '1K',
        },
      );

      if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
        final imageUrl = response.data!.first.imageUrl;
        if (mounted) {
          setState(() {
            _scenes[index] = _scenes[index].copyWith(imageUrl: imageUrl);
          });
        }
        await _saveSceneData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 场景"${scene.name}"图片生成成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
        print('   ✅ 生成成功');
      } else {
        throw Exception(response.error ?? '生成失败');
      }
    } catch (e) {
      print('   💥 生成异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 生成失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _generatingImages.remove(index));
      }
    }
  }

  /// 删除场景
  Future<void> _deleteScene(int index) async {
    final scene = _scenes[index];
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要删除场景"${scene.name}"吗？',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _scenes.removeAt(index);
      });
      await _saveSceneData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已删除场景"${scene.name}"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  /// 批量生成所有场景图片
  Future<void> _generateImages() async {
    if (_scenes.isEmpty) return;

    print('\n🎨 场景空间 - 批量生成图片');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('   场景数量: ${_scenes.length}');
    print('   比例: $_imageRatio');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    int successCount = 0;
    int failCount = 0;

    for (var i = 0; i < _scenes.length; i++) {
      if (_generatingImages.contains(i)) continue;

      setState(() => _generatingImages.add(i));

      try {
        print('📷 生成第 ${i + 1}/${_scenes.length} 个场景图片');
        
        // 读取图片 API 配置
        final prefs = await SharedPreferences.getInstance();
        final provider = prefs.getString('image_provider') ?? 'geeknow';
        final storage = SecureStorageManager();
        final baseUrl = await storage.getBaseUrl(provider: provider, modelType: 'image');
        final apiKey = await storage.getApiKey(provider: provider, modelType: 'image');
        final model = await storage.getModel(provider: provider, modelType: 'image');

        if (baseUrl == null || apiKey == null) {
          throw Exception('未配置图片 API');
        }

        // 构建完整的提示词（只用于图片生成，不使用推理预设）
        String fullPrompt = _scenes[i].description;
        
        // ✅ 添加风格参考说明
        if (_styleReferenceText.isNotEmpty) {
          fullPrompt = '$_styleReferenceText, $fullPrompt';
        }
        
        // ✅ 如果有风格参考图片，在提示词中明确说明
        final hasStyleImage = _styleReferenceImage != null && _styleReferenceImage!.isNotEmpty;
        if (hasStyleImage) {
          fullPrompt = '参考图片的艺术风格、色彩和构图风格，但不要融合图片内容。$fullPrompt';
        }
        
        print('   📝 生成提示词: ${fullPrompt.substring(0, fullPrompt.length > 100 ? 100 : fullPrompt.length)}...');
        print('   🎨 风格参考图片: ${hasStyleImage ? "是" : "否"}');

        // 准备参考图片
        final referenceImages = <String>[];
        if (hasStyleImage) {
          referenceImages.add(_styleReferenceImage!);
          print('   📸 添加风格参考图片');
        }

        // 调用 API
        final response = await _apiRepository.generateImages(
          provider: provider,
          prompt: fullPrompt,
          model: model,
          referenceImages: referenceImages.isEmpty ? null : referenceImages,
          parameters: {
            'size': _imageRatio,
            'quality': '1K',
          },
        );

        if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
          final imageUrl = response.data!.first.imageUrl;
          if (mounted) {
            setState(() {
              _scenes[i] = _scenes[i].copyWith(imageUrl: imageUrl);
            });
          }
          await _saveSceneData();
          successCount++;
          print('   ✅ 场景 ${i + 1} 生成成功');
        } else {
          failCount++;
          print('   ❌ 场景 ${i + 1} 生成失败: ${response.error}');
        }
      } catch (e) {
        failCount++;
        print('   💥 场景 ${i + 1} 生成异常: $e');
      } finally {
        if (mounted) {
          setState(() => _generatingImages.remove(i));
        }
      }

      // 避免请求过快
      if (i < _scenes.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 生成完成: 成功 $successCount, 失败 $failCount'),
          backgroundColor: successCount > 0 ? Colors.green : Colors.red,
        ),
      );
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
