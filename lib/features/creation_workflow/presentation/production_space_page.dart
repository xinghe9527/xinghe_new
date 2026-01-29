import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'dart:convert';
import 'dart:io';
import 'storyboard_prompt_manager.dart';
import 'character_generation_page.dart';
import 'scene_generation_page.dart';
import 'item_generation_page.dart';
import '../data/real_ai_service.dart';

/// 分镜空间页面（分镜生成和管理 - Excel风格）
class ProductionSpacePage extends StatefulWidget {
  final String workId;
  final String workName;
  final String scriptContent;
  final String storyboardPromptContent;
  final String storyboardPromptName;
  final Function(String name, String content)? onPromptChanged;

  const ProductionSpacePage({
    super.key,
    required this.workId,
    required this.workName,
    required this.scriptContent,
    required this.storyboardPromptContent,
    required this.storyboardPromptName,
    this.onPromptChanged,
  });

  @override
  State<ProductionSpacePage> createState() => _ProductionSpacePageState();
}

class _ProductionSpacePageState extends State<ProductionSpacePage> {
  List<StoryboardRow> _storyboards = [];
  bool _isGenerating = false;
  final RealAIService _aiService = RealAIService(); // ✅ 真实 AI 服务
  
  // 全局主题提示词
  String _globalImageTheme = '';  // 图片全局主题
  String _globalVideoTheme = '';  // 视频全局主题
  
  // 角色、场景、物品数据（用于显示标签）
  List<AssetReference> _characters = [];
  List<AssetReference> _scenes = [];
  List<AssetReference> _items = [];

  @override
  void initState() {
    super.initState();
    _loadProductionData();
    _initMockAssets();  // 初始化Mock资产用于演示
  }

  /// 初始化Mock资产（用于演示）
  void _initMockAssets() {
    if (_characters.isEmpty) {
      _characters = [
        AssetReference(
          id: 'char_001',
          name: '主角',
          imageUrl: 'https://picsum.photos/200/300',
          type: AssetType.character,
        ),
      ];
    }
    if (_scenes.isEmpty) {
      _scenes = [
        AssetReference(
          id: 'scene_001',
          name: '天台',
          imageUrl: 'https://picsum.photos/400/300',
          type: AssetType.scene,
        ),
        AssetReference(
          id: 'scene_002',
          name: '工作室',
          imageUrl: 'https://picsum.photos/400/301',
          type: AssetType.scene,
        ),
        AssetReference(
          id: 'scene_003',
          name: '街道',
          imageUrl: 'https://picsum.photos/400/302',
          type: AssetType.scene,
        ),
      ];
    }
    if (_items.isEmpty) {
      _items = [
        AssetReference(
          id: 'item_001',
          name: '飞行摩托',
          imageUrl: 'https://picsum.photos/200/200',
          type: AssetType.item,
        ),
      ];
    }
  }

  /// 加载分镜数据
  Future<void> _loadProductionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载分镜数据
      final storyboardsJson = prefs.getString('storyboards_${widget.workId}');
      if (storyboardsJson != null && storyboardsJson.isNotEmpty) {
        final data = jsonDecode(storyboardsJson) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _globalImageTheme = data['globalImageTheme'] ?? '';
            _globalVideoTheme = data['globalVideoTheme'] ?? '';
            final list = data['storyboards'] as List<dynamic>?;
            if (list != null) {
              _storyboards = list
                  .map((e) => StoryboardRow.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          });
        }
      }
      
      // 加载角色、场景、物品数据
      await _loadAssetReferences();
    } catch (e) {
      debugPrint('加载分镜数据失败: $e');
    }
  }

  /// 加载角色、场景、物品引用
  Future<void> _loadAssetReferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载角色
      final charactersJson = prefs.getString('characters_${widget.workId}');
      if (charactersJson != null && charactersJson.isNotEmpty) {
        final data = jsonDecode(charactersJson) as Map<String, dynamic>;
        final charList = data['characters'] as List<dynamic>?;
        if (charList != null) {
          _characters = charList.map((e) {
            return AssetReference(
              id: e['id'] as String,
              name: e['name'] as String,
              imageUrl: e['imageUrl'] as String?,
              type: AssetType.character,
            );
          }).toList();
        }
      }
      
      // 加载场景
      final scenesJson = prefs.getString('scenes_${widget.workId}');
      if (scenesJson != null && scenesJson.isNotEmpty) {
        final data = jsonDecode(scenesJson) as Map<String, dynamic>;
        final sceneList = data['scenes'] as List<dynamic>?;
        if (sceneList != null) {
          _scenes = sceneList.map((e) {
            return AssetReference(
              id: e['id'] as String,
              name: e['name'] as String,
              imageUrl: e['imageUrl'] as String?,
              type: AssetType.scene,
            );
          }).toList();
        }
      }
      
      // 加载物品
      final itemsJson = prefs.getString('items_${widget.workId}');
      if (itemsJson != null && itemsJson.isNotEmpty) {
        final data = jsonDecode(itemsJson) as Map<String, dynamic>;
        final itemList = data['items'] as List<dynamic>?;
        if (itemList != null) {
          _items = itemList.map((e) {
            return AssetReference(
              id: e['id'] as String,
              name: e['name'] as String,
              imageUrl: e['imageUrl'] as String?,
              type: AssetType.item,
            );
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('加载资产引用失败: $e');
    }
  }

  /// 保存分镜数据
  Future<void> _saveProductionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'globalImageTheme': _globalImageTheme,
        'globalVideoTheme': _globalVideoTheme,
        'storyboards': _storyboards.map((e) => e.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('storyboards_${widget.workId}', jsonEncode(data));
      debugPrint('✅ 保存分镜数据');
    } catch (e) {
      debugPrint('⚠️ 保存分镜数据失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 直接返回内容，不需要 Scaffold（因为已经在 workspace_page 中了）
    return Column(
      children: [
        // 顶部工具栏
        _buildToolbar(),
        // Excel风格表格
        Expanded(
          child: _storyboards.isEmpty
              ? _buildEmptyState()
              : _buildStoryboardTable(),
        ),
      ],
    );
  }

  /// 工具栏
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E20),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A2C))),
      ),
      child: Row(
        children: [
          const Icon(Icons.grid_on, color: Color(0xFF888888), size: 20),
          const SizedBox(width: 8),
          const Text(
            '分镜空间',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 24),
          // 角色按钮 - 浅色渐变
          _buildLightGradientButton(
            icon: Icons.person,
            label: '角色',
            onTap: _openCharacterGeneration,
          ),
          const SizedBox(width: 8),
          // 场景按钮 - 浅色渐变
          _buildLightGradientButton(
            icon: Icons.landscape,
            label: '场景',
            onTap: _openSceneGeneration,
          ),
          const SizedBox(width: 8),
          // 物品按钮 - 浅色渐变
          _buildLightGradientButton(
            icon: Icons.category,
            label: '物品',
            onTap: _openItemGeneration,
          ),
          const Spacer(),
          // 分镜提示词按钮（小书图标）
          IconButton(
            onPressed: _openStoryboardPromptManager,
            icon: const Icon(Icons.menu_book, size: 20),
            color: const Color(0xFF888888),
            tooltip: '分镜提示词',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF3A3A3C).withOpacity( 0.3),
            ),
          ),
          const SizedBox(width: 12),
          // 批量图片生成按钮 - 浅色渐变
          _buildLightGradientButton(
            icon: Icons.collections,
            label: '批量图片',
            onTap: _isGenerating ? null : _batchGenerateImages,
          ),
          const SizedBox(width: 8),
          // 批量视频生成按钮 - 浅色渐变
          _buildLightGradientButton(
            icon: Icons.video_library,
            label: '批量视频',
            onTap: _isGenerating ? null : _batchGenerateVideos,
          ),
          const SizedBox(width: 8),
          // 生成分镜按钮 - 主题渐变色
          _buildPrimaryGradientButton(
            icon: _isGenerating ? null : Icons.auto_awesome,
            label: _isGenerating ? '生成中...' : '生成分镜',
            onTap: _isGenerating ? null : _generateStoryboards,
            isLoading: _isGenerating,
          ),
        ],
      ),
    );
  }

  /// 工具按钮（旧版本，保留备用）
  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF888888),
        side: const BorderSide(color: Color(0xFF3A3A3C)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  /// 浅色渐变按钮（角色、场景、物品、批量操作）
  Widget _buildLightGradientButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: onTap != null
                  ? [
                      const Color(0xFFE0E0E0).withOpacity(0.15),
                      const Color(0xFFBDBDBD).withOpacity(0.1),
                    ]
                  : [
                      const Color(0xFF555555).withOpacity(0.1),
                      const Color(0xFF444444).withOpacity(0.05),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: onTap != null 
                  ? const Color(0xFFFFFFFF).withOpacity(0.1)
                  : const Color(0xFF555555).withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: onTap != null 
                    ? const Color(0xFFCCCCCC)
                    : const Color(0xFF666666),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: onTap != null 
                      ? const Color(0xFFCCCCCC)
                      : const Color(0xFF666666),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 主题渐变色按钮（生成分镜）
  Widget _buildPrimaryGradientButton({
    IconData? icon,
    required String label,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: onTap != null
                  ? [
                      const Color(0xFF2AFADF), // 青绿色
                      const Color(0xFF4C83FF), // 蓝色
                    ]
                  : [
                      const Color(0xFF555555),
                      const Color(0xFF444444),
                    ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: onTap != null
                ? [
                    BoxShadow(
                      color: const Color(0xFF2AFADF).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: 16,
                  color: Colors.white,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开角色生成页面
  Future<void> _openCharacterGeneration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CharacterGenerationPage(
          workId: widget.workId,
          workName: widget.workName,
          scriptContent: widget.scriptContent,  // 使用剧本内容
        ),
        fullscreenDialog: true,
      ),
    );
    // 返回后重新加载资产
    if (mounted) {
      await _loadAssetReferences();
      setState(() {});
    }
  }

  /// 打开场景生成页面
  Future<void> _openSceneGeneration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SceneGenerationPage(
          workId: widget.workId,
          workName: widget.workName,
          scriptContent: widget.scriptContent,  // 使用剧本内容
        ),
        fullscreenDialog: true,
      ),
    );
    // 返回后重新加载资产
    if (mounted) {
      await _loadAssetReferences();
      setState(() {});
    }
  }

  /// 打开物品生成页面
  Future<void> _openItemGeneration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ItemGenerationPage(
          workId: widget.workId,
          workName: widget.workName,
          scriptContent: widget.scriptContent,  // 使用剧本内容
        ),
        fullscreenDialog: true,
      ),
    );
    // 返回后重新加载资产
    if (mounted) {
      await _loadAssetReferences();
      setState(() {});
    }
  }

  /// 打开分镜提示词管理器
  Future<void> _openStoryboardPromptManager() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StoryboardPromptManager(
        currentPresetName: widget.storyboardPromptName,
      ),
    );

    if (result != null && widget.onPromptChanged != null && mounted) {
      final name = result['name'] ?? '默认';
      final content = result['content'] ?? '';
      widget.onPromptChanged!(name, content);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已选择分镜提示词: $name')),
        );
      }
    }
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_outlined, size: 80, color: Colors.white.withOpacity( 0.1)),
          const SizedBox(height: 24),
          const Text('还没有分镜', style: TextStyle(color: Color(0xFF666666), fontSize: 16)),
          const SizedBox(height: 12),
          const Text(
            '点击"生成分镜"按钮，AI将根据剧本生成分镜',
            style: TextStyle(color: Color(0xFF555555), fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// 分镜表格（横向4列布局）
  Widget _buildStoryboardTable() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _storyboards.length,
      itemBuilder: (context, index) {
        return _buildStoryboardRow(_storyboards[index], index);
      },
    );
  }

  /// 分镜行（横向4列：图片提示词 | 图片生成区 | 视频提示词 | 视频生成区）
  Widget _buildStoryboardRow(StoryboardRow row, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3C), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity( 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 行头（缩小版）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF252629),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3C),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '分镜 ${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 资产标签（检测所有提示词中的资产）
                ...(() {
                  final combinedPrompt = '${row.imagePrompt} ${row.videoPrompt}';
                  // 自动收集当前分镜涉及的所有资产ID
                  final autoDetectedAssets = <String>[];
                  
                  // 检测角色
                  for (final char in _characters) {
                    if (combinedPrompt.contains(char.name)) {
                      autoDetectedAssets.add(char.id);
                    }
                  }
                  // 检测场景
                  for (final scene in _scenes) {
                    if (combinedPrompt.contains(scene.name)) {
                      autoDetectedAssets.add(scene.id);
                    }
                  }
                  // 检测物品
                  for (final item in _items) {
                    if (combinedPrompt.contains(item.name)) {
                      autoDetectedAssets.add(item.id);
                    }
                  }
                  
                  // 如果selectedAssets为空，自动选中所有检测到的资产
                  final currentSelected = row.selectedImageAssets.isEmpty && row.selectedVideoAssets.isEmpty
                      ? autoDetectedAssets
                      : [...row.selectedImageAssets, ...row.selectedVideoAssets].toSet().toList();
                  
                  final tags = <Widget>[];
                  
                  // 生成角色标签
                  for (final char in _characters) {
                    if (combinedPrompt.contains(char.name)) {
                      final isSelected = currentSelected.contains(char.id);
                      tags.add(_buildAssetTag(
                        char.name,
                        char.type,
                        isSelected,
                        () {
                          final newSelected = List<String>.from(currentSelected);
                          if (newSelected.contains(char.id)) {
                            newSelected.remove(char.id);
                          } else {
                            newSelected.add(char.id);
                          }
                          setState(() {
                            _storyboards[index] = row.copyWith(
                              selectedImageAssets: newSelected,
                              selectedVideoAssets: newSelected,
                            );
                          });
                          _saveProductionData();
                        },
                      ));
                    }
                  }
                  
                  // 生成场景标签
                  for (final scene in _scenes) {
                    if (combinedPrompt.contains(scene.name)) {
                      final isSelected = currentSelected.contains(scene.id);
                      tags.add(_buildAssetTag(
                        scene.name,
                        scene.type,
                        isSelected,
                        () {
                          final newSelected = List<String>.from(currentSelected);
                          if (newSelected.contains(scene.id)) {
                            newSelected.remove(scene.id);
                          } else {
                            newSelected.add(scene.id);
                          }
                          setState(() {
                            _storyboards[index] = row.copyWith(
                              selectedImageAssets: newSelected,
                              selectedVideoAssets: newSelected,
                            );
                          });
                          _saveProductionData();
                        },
                      ));
                    }
                  }
                  
                  // 生成物品标签
                  for (final item in _items) {
                    if (combinedPrompt.contains(item.name)) {
                      final isSelected = currentSelected.contains(item.id);
                      tags.add(_buildAssetTag(
                        item.name,
                        item.type,
                        isSelected,
                        () {
                          final newSelected = List<String>.from(currentSelected);
                          if (newSelected.contains(item.id)) {
                            newSelected.remove(item.id);
                          } else {
                            newSelected.add(item.id);
                          }
                          setState(() {
                            _storyboards[index] = row.copyWith(
                              selectedImageAssets: newSelected,
                              selectedVideoAssets: newSelected,
                            );
                          });
                          _saveProductionData();
                        },
                      ));
                    }
                  }
                  
                  // 如果自动检测到资产但未选中，自动选中它们
                  if (autoDetectedAssets.isNotEmpty && currentSelected.isEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _storyboards[index] = row.copyWith(
                            selectedImageAssets: autoDetectedAssets,
                            selectedVideoAssets: autoDetectedAssets,
                          );
                        });
                        _saveProductionData();
                      }
                    });
                  }
                  
                  return tags;
                })(),
                const Spacer(),
                // 插入按钮（向上插入）
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  color: const Color(0xFF888888),
                  onPressed: () => _insertEmptyStoryboard(index),
                  tooltip: '在上方插入分镜',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                  ),
                ),
                const SizedBox(width: 4),
                // 删除按钮
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: const Color(0xFF888888),
                  onPressed: () => _deleteStoryboard(index),
                  tooltip: '删除此分镜',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                  ),
                ),
              ],
            ),
          ),
          // 4列内容（固定高度）
          SizedBox(
            height: 270,  // 缩小三分之一（400 → 270）
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 列1：图片提示词
                Expanded(
                  flex: 3,
                  child: _buildImagePromptColumn(row, index),
                ),
                // 列2：图片生成区
                Expanded(
                  flex: 2,
                  child: _buildImageGenerationColumn(row, index),
                ),
                // 列3：视频提示词
                Expanded(
                  flex: 3,
                  child: _buildVideoPromptColumn(row, index),
                ),
                // 列4：视频生成区
                Expanded(
                  flex: 2,
                  child: _buildVideoGenerationColumn(row, index),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 列1：图片提示词
  Widget _buildImagePromptColumn(StoryboardRow row, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF3A3A3C), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主题提示词 + 推理按钮（全局绑定）
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: _globalImageTheme),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '主题风格...',
                    hintStyle: TextStyle(color: Color(0xFF666666)),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xFF2A2A2C),
                  ),
                  onChanged: (value) {
                    setState(() => _globalImageTheme = value);
                    _saveProductionData();
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => _reinferImagePrompt(index),
                icon: const Icon(Icons.psychology, size: 16),
                color: const Color(0xFF888888),
                tooltip: '推理',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF3A3A3C).withOpacity( 0.3),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 提示词文本框（可滚动，独立滚动）
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF3A3A3C)),
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF252629),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),  // 阻止滚动冒泡
                child: TextField(
                  controller: TextEditingController(text: row.imagePrompt),
                  maxLines: null,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                  onChanged: (value) {
                    _storyboards[index] = row.copyWith(imagePrompt: value);
                    _saveProductionData();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 列2：图片生成区（四宫格）
  Widget _buildImageGenerationColumn(StoryboardRow row, int index) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF3A3A3C), width: 1)),
      ),
      child: Stack(
        children: [
          // 四宫格布局
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: 4,
            itemBuilder: (context, gridIndex) {
              final hasImage = gridIndex < row.imageUrls.length;
              final imageUrl = hasImage ? row.imageUrls[gridIndex] : null;
              final isSelected = row.selectedImageIndex == gridIndex;
              
              return GestureDetector(
                onTap: () {
                  // 所有格子都可以选中（包括空白格子）
                  setState(() {
                    _storyboards[index] = row.copyWith(selectedImageIndex: gridIndex);
                  });
                  _saveProductionData();
                  
                  // 提示用户当前选择
                  final mode = hasImage ? '图生视频' : '文生视频';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已选择格子${gridIndex + 1}（$mode模式）'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                onSecondaryTapDown: hasImage ? (details) => _showImageContextMenu(
                  context, details, imageUrl!, index, gridIndex,
                ) : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF888888) : const Color(0xFF3A3A3C),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: hasImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(Icons.error, color: Color(0xFF666666)),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 24,
                            color: Colors.white.withOpacity( 0.1),
                          ),
                        ),
                ),
              );
            },
          ),
          // 右上角生成按钮
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: () => _generateImage(index),
              icon: const Icon(Icons.auto_awesome, size: 14),
              color: const Color(0xFF888888),
              tooltip: '生成图片',
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withOpacity( 0.7),
                padding: const EdgeInsets.all(6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示图片右键菜单
  void _showImageContextMenu(BuildContext context, TapDownDetails details, String imageUrl, int storyboardIndex, int gridIndex) {
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
          value: 'folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('打开文件夹', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('删除图片', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'folder') {
        _openImageFolder();
      } else if (value == 'delete') {
        _deleteImage(storyboardIndex, gridIndex);
      }
    });
  }

  void _openImageFolder() {
    final savePath = imageSavePathNotifier.value;
    if (savePath != '未设置' && savePath.isNotEmpty) {
      try {
        if (Platform.isWindows) {
          Process.run('explorer', [savePath]);
        }
      } catch (e) {
        debugPrint('打开文件夹失败: $e');
      }
    }
  }

  void _deleteImage(int storyboardIndex, int gridIndex) {
    setState(() {
      final row = _storyboards[storyboardIndex];
      final newUrls = List<String>.from(row.imageUrls);
      newUrls.removeAt(gridIndex);
      _storyboards[storyboardIndex] = row.copyWith(
        imageUrls: newUrls,
        selectedImageIndex: 0,
      );
    });
    _saveProductionData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 已删除图片')),
    );
  }

  /// 列3：视频提示词
  Widget _buildVideoPromptColumn(StoryboardRow row, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF3A3A3C), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主题提示词 + 推理按钮（全局绑定）
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: _globalVideoTheme),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '主题风格...',
                    hintStyle: TextStyle(color: Color(0xFF666666)),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xFF2A2A2C),
                  ),
                  onChanged: (value) {
                    setState(() => _globalVideoTheme = value);
                    _saveProductionData();
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => _reinferVideoPrompt(index),
                icon: const Icon(Icons.psychology, size: 16),
                color: const Color(0xFF888888),
                tooltip: '推理',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF3A3A3C).withOpacity( 0.3),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 提示词文本框（可滚动，独立滚动）
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF3A3A3C)),
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF252629),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),  // 阻止滚动冒泡
                child: TextField(
                  controller: TextEditingController(text: row.videoPrompt),
                  maxLines: null,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                  onChanged: (value) {
                    _storyboards[index] = row.copyWith(videoPrompt: value);
                    _saveProductionData();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 列4：视频生成区（四宫格）
  Widget _buildVideoGenerationColumn(StoryboardRow row, int index) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          // 四宫格布局
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: 4,
            itemBuilder: (context, gridIndex) {
              final hasVideo = gridIndex < row.videoUrls.length;
              final videoUrl = hasVideo ? row.videoUrls[gridIndex] : null;
              
              return GestureDetector(
                onTap: hasVideo ? () => _playVideo(videoUrl!) : null,
                onSecondaryTapDown: hasVideo ? (details) => _showVideoContextMenu(
                  context, details, videoUrl!, index, gridIndex,
                ) : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF3A3A3C)),
                  ),
                  child: hasVideo
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.play_circle_outline,
                                size: 32,
                                color: Color(0xFF888888),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                videoUrl!.split('/').last,
                                style: const TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 9,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.videocam_outlined,
                            size: 24,
                            color: Colors.white.withOpacity( 0.1),
                          ),
                        ),
                ),
              );
            },
          ),
          // 右上角生成按钮
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: row.selectedImageIndex < row.imageUrls.length 
                  ? () => _generateVideo(index) 
                  : null,
              icon: const Icon(Icons.auto_awesome, size: 14),
              color: const Color(0xFF888888),
              tooltip: '生成视频',
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withOpacity( 0.7),
                padding: const EdgeInsets.all(6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVideoContextMenu(BuildContext context, TapDownDetails details, String videoUrl, int storyboardIndex, int gridIndex) {
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
          value: 'folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('打开文件夹', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('删除视频', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'folder') {
        _openVideoFolder();
      } else if (value == 'delete') {
        _deleteVideo(storyboardIndex, gridIndex);
      }
    });
  }

  void _playVideo(String videoUrl) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('播放视频: $videoUrl')),
    );
  }

  void _openVideoFolder() {
    final savePath = videoSavePathNotifier.value;
    if (savePath != '未设置' && savePath.isNotEmpty) {
      try {
        if (Platform.isWindows) {
          Process.run('explorer', [savePath]);
        }
      } catch (e) {
        debugPrint('打开视频文件夹失败: $e');
      }
    }
  }

  void _deleteVideo(int storyboardIndex, int gridIndex) {
    setState(() {
      final row = _storyboards[storyboardIndex];
      final newUrls = List<String>.from(row.videoUrls);
      newUrls.removeAt(gridIndex);
      _storyboards[storyboardIndex] = row.copyWith(videoUrls: newUrls);
    });
    _saveProductionData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 已删除视频')),
    );
  }

  /// 构建资产标签按钮
  List<Widget> _buildAssetTags(
    String prompt,
    List<String> selectedAssets,
    Function(List<String>) onChanged,
  ) {
    final tags = <Widget>[];
    
    // 检查角色
    for (final char in _characters) {
      if (prompt.contains(char.name)) {
        tags.add(_buildAssetTag(
          char.name,
          char.type,
          selectedAssets.contains(char.id),
          () {
            final newSelected = List<String>.from(selectedAssets);
            if (newSelected.contains(char.id)) {
              newSelected.remove(char.id);
            } else {
              newSelected.add(char.id);
            }
            onChanged(newSelected);
          },
        ));
      }
    }
    
    // 检查场景
    for (final scene in _scenes) {
      if (prompt.contains(scene.name)) {
        tags.add(_buildAssetTag(
          scene.name,
          scene.type,
          selectedAssets.contains(scene.id),
          () {
            final newSelected = List<String>.from(selectedAssets);
            if (newSelected.contains(scene.id)) {
              newSelected.remove(scene.id);
            } else {
              newSelected.add(scene.id);
            }
            onChanged(newSelected);
          },
        ));
      }
    }
    
    // 检查物品
    for (final item in _items) {
      if (prompt.contains(item.name)) {
        tags.add(_buildAssetTag(
          item.name,
          item.type,
          selectedAssets.contains(item.id),
          () {
            final newSelected = List<String>.from(selectedAssets);
            if (newSelected.contains(item.id)) {
              newSelected.remove(item.id);
            } else {
              newSelected.add(item.id);
            }
            onChanged(newSelected);
          },
        ));
      }
    }
    
    return tags;
  }

  /// 资产标签按钮
  Widget _buildAssetTag(String name, AssetType type, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3A3A3C)  // 选中：灰色背景
              : const Color(0xFF1A1A1C),  // 未选中：黑色背景
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF888888)  // 选中：灰色边框
                : const Color(0xFF2A2A2C),  // 未选中：深黑边框
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type == AssetType.character
                  ? Icons.person
                  : type == AssetType.scene
                      ? Icons.landscape
                      : Icons.category,
              size: 12,
              color: isSelected ? const Color(0xFF888888) : const Color(0xFF666666),
            ),
            const SizedBox(width: 4),
            Text(
              name,
              style: TextStyle(
                color: isSelected ? const Color(0xFF888888) : const Color(0xFF666666),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 生成分镜（使用上下文记忆）
  Future<void> _generateStoryboards() async {
    if (widget.scriptContent.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剧本内容为空')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // TODO: 调用LLM使用分镜提示词 + 剧本内容 + 上下文记忆生成分镜
      // 提示词应该包含：
      // 1. 用户选择的分镜提示词
      // 2. 完整的剧本内容
      // 3. 已有的分镜（如果有）作为上下文
      await Future.delayed(const Duration(seconds: 3));

      final mockStoryboards = [
        StoryboardRow(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          imagePrompt: '主角站在未来都市天台，俯瞰城市，夜景，霓虹灯闪烁。主角的银白短发在风中飘动。',
          videoPrompt: '主角转身眺望，镜头从远景推进到中景，展现城市全貌和主角的背影',
          selectedImageAssets: ['char_001', 'scene_001'],  // 默认选中：主角、天台
          selectedVideoAssets: ['char_001', 'scene_001'],
        ),
        StoryboardRow(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          imagePrompt: '地下工作室内，主角操作全息屏幕，多个屏幕显示代码和数据流',
          videoPrompt: '主角手指快速滑动，屏幕数据流动，镜头特写手部动作，紧张氛围',
          selectedImageAssets: ['char_001', 'scene_002'],  // 默认选中：主角、工作室
          selectedVideoAssets: ['char_001', 'scene_002'],
        ),
        StoryboardRow(
          id: (DateTime.now().millisecondsSinceEpoch + 2).toString(),
          imagePrompt: '城市街道，主角匆忙穿行，霓虹灯光影交错，背景有飞行摩托',
          videoPrompt: '追逐镜头，快速移动，光影闪烁，动感强烈，第一人称视角',
          selectedImageAssets: ['char_001', 'scene_003', 'item_001'],  // 默认选中：主角、街道、飞行摩托
          selectedVideoAssets: ['char_001', 'scene_003', 'item_001'],
        ),
      ];

      if (mounted) {
        setState(() {
          _storyboards = mockStoryboards;
        });
        
        // 自动为每个分镜选中检测到的资产
        _autoSelectAssets();
        
        await _saveProductionData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ 生成 ${_storyboards.length} 个分镜（含上下文记忆）')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  /// 🔥 批量生成所有分镜的图片
  Future<void> _batchGenerateImages() async {
    if (_storyboards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先生成分镜')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    
    int successCount = 0;
    int failCount = 0;
    
    try {
      // 找出所有还没有图片的分镜
      final storyboardsToGenerate = _storyboards.where((sb) => sb.imageUrls.isEmpty).toList();
      
      if (storyboardsToGenerate.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('所有分镜都已生成图片')),
          );
        }
        return;
      }
      
      // 并发生成图片（每批 3 个）
      for (int i = 0; i < storyboardsToGenerate.length; i += 3) {
        final batch = storyboardsToGenerate.skip(i).take(3).toList();
        final futures = batch.map((sb) async {
          try {
            // 构建完整提示词（包含全局主题）
            String fullPrompt = sb.imagePrompt;
            if (_globalImageTheme.isNotEmpty) {
              fullPrompt = '$_globalImageTheme, $fullPrompt';
            }
            
            // 调用 API 生成图片
            final imageUrl = await _aiService.generateStoryboardImage(prompt: fullPrompt);
            
            // 更新分镜数据
            final index = _storyboards.indexWhere((s) => s.id == sb.id);
            if (index != -1) {
              setState(() {
                _storyboards[index] = _storyboards[index].copyWith(
                  imageUrls: [imageUrl],
                  selectedImageIndex: 0,
                );
              });
            }
            
            successCount++;
          } catch (e) {
            failCount++;
            debugPrint('生成图片失败 [${sb.id}]: $e');
          }
        });
        
        await Future.wait(futures);
        
        // 每批完成后保存
        await _saveProductionData();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 批量图片生成完成：成功 $successCount 个，失败 $failCount 个'),
            backgroundColor: successCount > 0 ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 批量生成失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  /// 🔥 批量生成所有分镜的视频
  Future<void> _batchGenerateVideos() async {
    if (_storyboards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先生成分镜')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    
    int successCount = 0;
    int failCount = 0;
    
    try {
      // 找出所有有图片但没有视频的分镜
      final storyboardsToGenerate = _storyboards.where((sb) {
        return sb.imageUrls.isNotEmpty && sb.videoUrls.isEmpty;
      }).toList();
      
      if (storyboardsToGenerate.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可生成视频的分镜（需要先生成图片）')),
          );
        }
        return;
      }
      
      // 并发生成视频（每批 2 个，因为视频生成较慢）
      for (int i = 0; i < storyboardsToGenerate.length; i += 2) {
        final batch = storyboardsToGenerate.skip(i).take(2).toList();
        final futures = batch.map((sb) async {
          try {
            // 构建完整提示词（包含全局主题）
            String fullPrompt = sb.videoPrompt.isNotEmpty ? sb.videoPrompt : sb.imagePrompt;
            if (_globalVideoTheme.isNotEmpty) {
              fullPrompt = '$_globalVideoTheme, $fullPrompt';
            }
            
            // 获取参考图片
            final referenceImage = sb.imageUrls.isNotEmpty ? sb.imageUrls[sb.selectedImageIndex] : null;
            
            // 调用 API 生成视频
            final videoUrl = await _aiService.generateVideoClip(
              prompt: fullPrompt,
              imageUrl: referenceImage,
            );
            
            // 更新分镜数据
            final index = _storyboards.indexWhere((s) => s.id == sb.id);
            if (index != -1) {
              setState(() {
                _storyboards[index] = _storyboards[index].copyWith(
                  videoUrls: [videoUrl],
                );
              });
            }
            
            successCount++;
          } catch (e) {
            failCount++;
            debugPrint('生成视频失败 [${sb.id}]: $e');
          }
        });
        
        await Future.wait(futures);
        
        // 每批完成后保存
        await _saveProductionData();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 批量视频生成完成：成功 $successCount 个，失败 $failCount 个'),
            backgroundColor: successCount > 0 ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 批量生成失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  /// 自动为所有分镜选中检测到的资产
  void _autoSelectAssets() {
    for (int i = 0; i < _storyboards.length; i++) {
      final row = _storyboards[i];
      final combinedPrompt = '${row.imagePrompt} ${row.videoPrompt}';
      final detectedAssets = <String>[];
      
      // 检测所有资产
      for (final char in _characters) {
        if (combinedPrompt.contains(char.name)) {
          detectedAssets.add(char.id);
        }
      }
      for (final scene in _scenes) {
        if (combinedPrompt.contains(scene.name)) {
          detectedAssets.add(scene.id);
        }
      }
      for (final item in _items) {
        if (combinedPrompt.contains(item.name)) {
          detectedAssets.add(item.id);
        }
      }
      
      // 自动选中检测到的资产
      if (detectedAssets.isNotEmpty) {
        _storyboards[i] = row.copyWith(
          selectedImageAssets: detectedAssets,
          selectedVideoAssets: detectedAssets,
        );
      }
    }
    
    debugPrint('✅ 自动选中资产完成');
  }

  /// 插入空白分镜（向上插入）
  void _insertEmptyStoryboard(int currentIndex) {
    final newStoryboard = StoryboardRow(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imagePrompt: '',
      videoPrompt: '',
    );

    setState(() {
      _storyboards.insert(currentIndex, newStoryboard);
    });
    _saveProductionData();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ 已在分镜 ${currentIndex + 1} 上方插入空白分镜')),
    );
  }

  /// 重新推理图片提示词
  void _reinferImagePrompt(int index) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: Text('推理图片提示词 - 分镜${index + 1}', style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '输入额外要求（可选），AI将结合上下文记忆推理',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 3,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: '例如：增加光影效果、特写镜头...',
                  hintStyle: TextStyle(color: Color(0xFF666666)),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
          ),
          OutlinedButton.icon(
            onPressed: () {
              final requirement = controller.text.trim();
              Navigator.pop(context);
              _executeImageReinfer(index, requirement);
            },
            icon: const Icon(Icons.psychology, size: 16),
            label: const Text('推理'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF888888),
              side: const BorderSide(color: Color(0xFF3A3A3C)),
            ),
          ),
        ],
      ),
    );
  }

  /// 执行图片提示词推理
  Future<void> _executeImageReinfer(int index, String requirement) async {
    try {
      // TODO: 调用LLM推理
      // 输入：全局图片主题 + 剧本上下文 + 前后分镜 + 用户要求
      await Future.delayed(const Duration(seconds: 2));

      final row = _storyboards[index];
      final themePrefix = _globalImageTheme.isNotEmpty ? '$_globalImageTheme。' : '';
      final updatedPrompt = requirement.isNotEmpty
          ? '$themePrefix根据要求"$requirement"重新推理的画面描述'
          : '$themePrefix${row.imagePrompt}';

      if (mounted) {
        setState(() {
          _storyboards[index] = row.copyWith(imagePrompt: updatedPrompt);
        });
        await _saveProductionData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 已推理图片提示词')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('推理失败：$e')),
        );
      }
    }
  }

  /// 重新推理视频提示词
  void _reinferVideoPrompt(int index) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: Text('推理视频提示词 - 分镜${index + 1}', style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '输入额外要求（可选），AI将结合上下文记忆推理',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 3,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: '例如：慢镜头、第一人称视角...',
                  hintStyle: TextStyle(color: Color(0xFF666666)),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
          ),
          OutlinedButton.icon(
            onPressed: () {
              final requirement = controller.text.trim();
              Navigator.pop(context);
              _executeVideoReinfer(index, requirement);
            },
            icon: const Icon(Icons.psychology, size: 16),
            label: const Text('推理'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF888888),
              side: const BorderSide(color: Color(0xFF3A3A3C)),
            ),
          ),
        ],
      ),
    );
  }

  /// 执行视频提示词推理
  Future<void> _executeVideoReinfer(int index, String requirement) async {
    try {
      // TODO: 调用LLM推理
      // 输入：全局视频主题 + 剧本上下文 + 前后分镜 + 用户要求
      await Future.delayed(const Duration(seconds: 2));

      final row = _storyboards[index];
      final themePrefix = _globalVideoTheme.isNotEmpty ? '$_globalVideoTheme。' : '';
      final updatedPrompt = requirement.isNotEmpty
          ? '$themePrefix根据要求"$requirement"重新推理的运镜描述'
          : '$themePrefix${row.videoPrompt}';

      if (mounted) {
        setState(() {
          _storyboards[index] = row.copyWith(videoPrompt: updatedPrompt);
        });
        await _saveProductionData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 已推理视频提示词')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('推理失败：$e')),
        );
      }
    }
  }

  /// 删除分镜
  void _deleteStoryboard(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要删除分镜 ${index + 1} 吗？\n\n删除后可重新生成分镜，上下文记忆将保持连贯性。',
          style: const TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _storyboards.removeAt(index);
              });
              _saveProductionData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ 已删除分镜')),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF888888),
              side: const BorderSide(color: Color(0xFF3A3A3C)),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 生成图片
  Future<void> _generateImage(int index) async {
    final row = _storyboards[index];
    
    if (row.imageUrls.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多生成4张图片')),
      );
      return;
    }
    
    // TODO: 调用图片生成API
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      final newImageUrl = 'https://picsum.photos/seed/${row.id}_${row.imageUrls.length}/800/450';
      setState(() {
        final newUrls = List<String>.from(row.imageUrls)..add(newImageUrl);
        _storyboards[index] = row.copyWith(imageUrls: newUrls);
      });
      await _saveProductionData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已生成图片 ${row.imageUrls.length + 1}/4')),
        );
      }
    }
  }

  /// 生成视频
  Future<void> _generateVideo(int index) async {
    final row = _storyboards[index];
    
    if (row.videoUrls.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多生成4个视频')),
      );
      return;
    }
    
    // 检查选中的格子
    final selectedImageUrl = row.selectedImageIndex < row.imageUrls.length
        ? row.imageUrls[row.selectedImageIndex]
        : null;
    
    final mode = selectedImageUrl != null ? '图生视频' : '文生视频';
    
    // TODO: 调用视频生成API
    // 如果 selectedImageUrl 不为null：图生视频（使用图片作为参考）
    // 如果 selectedImageUrl 为null：文生视频（只使用提示词）
    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      final newVideoUrl = 'video_${row.id}_${row.videoUrls.length}_$mode.mp4';
      setState(() {
        final newUrls = List<String>.from(row.videoUrls)..add(newVideoUrl);
        _storyboards[index] = row.copyWith(videoUrls: newUrls);
      });
      await _saveProductionData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已生成视频 ${row.videoUrls.length + 1}/4（$mode）')),
        );
      }
    }
  }
}

/// 分镜行数据
class StoryboardRow {
  final String id;
  final String imagePrompt;
  final String videoPrompt;
  final List<String> imageUrls;         // 多个图片URL（最多4个）
  final List<String> videoUrls;         // 多个视频URL（最多4个）
  final int selectedImageIndex;         // 选中的图片索引
  final List<String> selectedImageAssets;
  final List<String> selectedVideoAssets;

  StoryboardRow({
    required this.id,
    required this.imagePrompt,
    required this.videoPrompt,
    this.imageUrls = const [],
    this.videoUrls = const [],
    this.selectedImageIndex = 0,
    this.selectedImageAssets = const [],
    this.selectedVideoAssets = const [],
  });

  // 兼容旧数据
  String? get imageUrl => imageUrls.isNotEmpty ? imageUrls[selectedImageIndex] : null;
  String? get videoUrl => videoUrls.isNotEmpty ? videoUrls.first : null;

  StoryboardRow copyWith({
    String? imagePrompt,
    String? videoPrompt,
    List<String>? imageUrls,
    List<String>? videoUrls,
    int? selectedImageIndex,
    List<String>? selectedImageAssets,
    List<String>? selectedVideoAssets,
  }) {
    return StoryboardRow(
      id: id,
      imagePrompt: imagePrompt ?? this.imagePrompt,
      videoPrompt: videoPrompt ?? this.videoPrompt,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      selectedImageIndex: selectedImageIndex ?? this.selectedImageIndex,
      selectedImageAssets: selectedImageAssets ?? this.selectedImageAssets,
      selectedVideoAssets: selectedVideoAssets ?? this.selectedVideoAssets,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePrompt': imagePrompt,
        'videoPrompt': videoPrompt,
        'imageUrls': imageUrls,
        'videoUrls': videoUrls,
        'selectedImageIndex': selectedImageIndex,
        'selectedImageAssets': selectedImageAssets,
        'selectedVideoAssets': selectedVideoAssets,
      };

  factory StoryboardRow.fromJson(Map<String, dynamic> json) {
    return StoryboardRow(
      id: json['id'] as String,
      imagePrompt: json['imagePrompt'] as String,
      videoPrompt: json['videoPrompt'] as String,
      imageUrls: (json['imageUrls'] as List<dynamic>?)?.cast<String>() ?? 
                 (json['imageUrl'] != null ? [json['imageUrl'] as String] : []),  // 兼容旧数据
      videoUrls: (json['videoUrls'] as List<dynamic>?)?.cast<String>() ?? 
                 (json['videoUrl'] != null ? [json['videoUrl'] as String] : []),  // 兼容旧数据
      selectedImageIndex: json['selectedImageIndex'] as int? ?? 0,
      selectedImageAssets: (json['selectedImageAssets'] as List<dynamic>?)?.cast<String>() ?? [],
      selectedVideoAssets: (json['selectedVideoAssets'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// 资产引用
class AssetReference {
  final String id;
  final String name;
  final String? imageUrl;
  final AssetType type;

  AssetReference({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.type,
  });
}

enum AssetType {
  character,
  scene,
  item,
}
