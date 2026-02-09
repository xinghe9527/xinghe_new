import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:xinghe_new/main.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'storyboard_prompt_manager.dart';
import 'character_generation_page.dart';
import 'scene_generation_page.dart';
import 'item_generation_page.dart';
import 'widgets/voice_generation_dialog.dart';
import 'widgets/video_audio_editor_dialog.dart';
import '../../../services/api/api_repository.dart';
import '../../../services/api/secure_storage_manager.dart';
import '../../../services/ffmpeg_service.dart';

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
  bool _showScriptColumn = false;  // ✅ 控制剧本列的显示/隐藏
  Set<int> _selectedStoryboards = {};  // ✅ 选中的分镜索引（用于合并）
  final ApiRepository _apiRepository = ApiRepository();  // ✅ API Repository
  
  // 全局主题提示词
  String _globalImageTheme = '';  // 图片全局主题
  String _globalVideoTheme = '';  // 视频全局主题
  
  // 角色、场景、物品数据（用于显示标签）
  List<AssetReference> _characters = [];
  List<AssetReference> _scenes = [];
  List<AssetReference> _items = [];

  AudioPlayer? _voiceAudioPlayer;
  bool _voiceUseSystemPlayer = false;

  @override
  void initState() {
    super.initState();
    _loadProductionData();
    _initMockAssets();  // 初始化Mock资产用于演示
    _loadScriptColumnState();  // ✅ 加载剧本列显示状态
  }

  @override
  void dispose() {
    _voiceAudioPlayer?.dispose();
    super.dispose();
  }
  
  /// 加载剧本列显示状态
  Future<void> _loadScriptColumnState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final showScript = prefs.getBool('show_script_column_${widget.workId}') ?? false;
      if (mounted) {
        setState(() {
          _showScriptColumn = showScript;
        });
      }
      debugPrint('✅ 加载剧本列显示状态: $showScript');
    } catch (e) {
      debugPrint('⚠️ 加载剧本列状态失败: $e');
    }
  }
  
  /// 保存剧本列显示状态
  Future<void> _saveScriptColumnState(bool show) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_script_column_${widget.workId}', show);
      debugPrint('✅ 保存剧本列显示状态: $show');
    } catch (e) {
      debugPrint('⚠️ 保存剧本列状态失败: $e');
    }
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
              mappingCode: e['mappingCode'] as String?,  // ✅ 加载映射代码
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
              mappingCode: e['mappingCode'] as String?,  // ✅ 加载映射代码
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
              mappingCode: e['mappingCode'] as String?,  // ✅ 加载映射代码
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
          // ✅ 显示剧本按钮 - 浅色渐变
          _buildLightGradientButton(
            icon: Icons.menu_book,
            label: '剧本',
            onTap: () {
              final newState = !_showScriptColumn;
              setState(() {
                _showScriptColumn = newState;
              });
              _saveScriptColumnState(newState);  // ✅ 保存状态
            },
          ),
          const SizedBox(width: 8),
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
          // ✅ 合并按钮（选中多个分镜时显示）
          if (_selectedStoryboards.length >= 2)
            _buildLightGradientButton(
              icon: Icons.merge,
              label: '合并(${_selectedStoryboards.length})',
              onTap: _mergeSelectedStoryboards,
            ),
          if (_selectedStoryboards.length >= 2)
            const SizedBox(width: 12),
          // 清空分镜按钮（小巧，无文字）
          IconButton(
            onPressed: _storyboards.isEmpty ? null : _clearAllStoryboards,
            icon: const Icon(Icons.delete_sweep, size: 18),
            color: const Color(0xFF888888),
            tooltip: '清空所有分镜',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF3A3A3C).withOpacity(0.3),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(width: 8),
          // 分镜提示词按钮（小书图标）
          IconButton(
            onPressed: _openStoryboardPromptManager,
            icon: const Icon(Icons.menu_book, size: 20),
            color: const Color(0xFF888888),
            tooltip: '分镜提示词（当前：${widget.storyboardPromptName}）',
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

  /// 分镜行（可选显示左侧剧本列）
  Widget _buildStoryboardRow(StoryboardRow row, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3C), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✅ 剧本列（左侧，可选显示）
            if (_showScriptColumn)
              Container(
                width: 250,
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1C),
                  border: Border(right: BorderSide(color: Color(0xFF3A3A3C), width: 2)),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF252629),
                        border: Border(bottom: BorderSide(color: Color(0xFF3A3A3C))),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(10)),
                      ),
                    child: Row(
                      children: [
                        const Icon(Icons.article, color: Color(0xFF888888), size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            row.isUserCreated ? '用户自定义' : '剧本片段',
                            style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // ✅ 拆分按钮
                        if (row.scriptSegment.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.call_split, size: 14),
                            color: const Color(0xFF888888),
                            onPressed: () => _showSplitDialog(index),
                            tooltip: '拆分分镜',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(4),
                            ),
                          ),
                        if (!row.isUserCreated && row.startIndex >= 0)
                          Text(
                            '${row.startIndex}-${row.endIndex}',
                            style: const TextStyle(color: Color(0xFF666666), fontSize: 9),
                          ),
                      ],
                    ),
                    ),
                    // 内容
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          row.scriptSegment.isEmpty ? '（未提供剧本片段）' : row.scriptSegment,
                          style: TextStyle(
                            color: row.scriptSegment.isEmpty ? const Color(0xFF666666) : const Color(0xFFCCCCCC),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    // ✅ 配音按钮区域
                    if (row.scriptSegment.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Color(0xFF3A3A3C))),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!row.hasVoice)
                              // 未配音状态
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => _openVoiceGenerationDialog(index),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.mic, color: Colors.white, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          '配音',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            else
                              // 已配音状态（点击可进入修改，橙色渐变）
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => _openVoiceGenerationDialog(index),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFF9A56), Color(0xFFFF6B6B)],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.white, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          '已配音',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            // 分镜内容（右侧，原有内容）
            Expanded(
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
                        // ✅ 勾选框（用于合并）
                        Checkbox(
                          value: _selectedStoryboards.contains(index),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedStoryboards.add(index);
                              } else {
                                _selectedStoryboards.remove(index);
                              }
                            });
                          },
                          fillColor: WidgetStateProperty.all(const Color(0xFF3A3A3C)),
                          checkColor: const Color(0xFF4A9EFF),
                        ),
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
                        const SizedBox(width: 6),
                // ➕ 手动添加资产按钮
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showAddAssetDialog(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3C).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: const Color(0xFF555555),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 14,
                        color: Color(0xFF888888),
                      ),
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
                  
                  // ✅ 直接使用用户的选择，不自动覆盖
                  // 自动选中只在生成分镜时执行一次（_autoSelectAssets 方法）
                  final currentSelected = [...row.selectedImageAssets, ...row.selectedVideoAssets].toSet().toList();
                  
                  final tags = <Widget>[];
                  
                  // ✅ 显示所有已选中的资产（无论提示词中是否包含）
                  // 同时也显示提示词中检测到但未选中的资产
                  
                  // 生成角色标签
                  for (final char in _characters) {
                    final isSelected = currentSelected.contains(char.id);
                    final isDetected = combinedPrompt.contains(char.name);
                    
                    // 如果已选中或被检测到，就显示标签
                    if (isSelected || isDetected) {
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
                    final isSelected = currentSelected.contains(scene.id);
                    final isDetected = combinedPrompt.contains(scene.name);
                    
                    // 如果已选中或被检测到，就显示标签
                    if (isSelected || isDetected) {
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
                    final isSelected = currentSelected.contains(item.id);
                    final isDetected = combinedPrompt.contains(item.name);
                    
                    // 如果已选中或被检测到，就显示标签
                    if (isSelected || isDetected) {
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
                  
                  // ✅ 移除自动选中逻辑，允许用户自由控制
                  // 自动选中只在生成分镜时执行一次（_autoSelectAssets 方法）
                  // 不在 build 方法中重复执行，避免用户无法取消选择
                  
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
            ),
          ],
        ),
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
                          child: imageUrl!.startsWith('http')
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => const Icon(Icons.error, color: Color(0xFF666666)),
                                )
                              : Image.file(
                                  File(imageUrl),
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
      color: const Color(0xFF2A2A2C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF3A3A3C)),
      ),
      items: const [
        PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.zoom_in, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('放大查看', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('定位文件', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('删除图片', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'view') {
        _viewImage(imageUrl);
      } else if (value == 'folder') {
        _locateImageFile(imageUrl);
      } else if (value == 'delete') {
        _deleteImage(storyboardIndex, gridIndex);
      }
    });
  }

  /// 放大查看图片
  void _viewImage(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: imageUrl.startsWith('http')
                    ? Image.network(imageUrl)
                    : Image.file(File(imageUrl)),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _locateImageFile(String imageUrl) async {
    // 检查是否为本地文件
    if (imageUrl.isEmpty || imageUrl.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只能定位本地文件')),
      );
      return;
    }
    
    try {
      final file = File(imageUrl);
      if (await file.exists()) {
        if (Platform.isWindows) {
          await Process.run('explorer', ['/select,', imageUrl]);
          debugPrint('✅ 已定位文件: $imageUrl');
        } else if (Platform.isMacOS) {
          await Process.run('open', ['-R', imageUrl]);
        } else if (Platform.isLinux) {
          // Linux 上定位到文件所在文件夹
          final directory = file.parent.path;
          await Process.run('xdg-open', [directory]);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
      }
    } catch (e) {
      debugPrint('定位文件失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('定位文件失败: $e')),
      );
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

  /// 列4：视频生成区（四宫格+合成按钮）
  Widget _buildVideoGenerationColumn(StoryboardRow row, int index) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // 四宫格布局
          Expanded(
            child: Stack(
              children: [
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
              final isSelectedVideo = row.selectedVideoIndex == gridIndex;
              
              return GestureDetector(
                // ✅ 左键选择视频（用于语音合成）
                onTap: () {
                  setState(() {
                    _storyboards[index] = row.copyWith(selectedVideoIndex: gridIndex);
                  });
                  _saveProductionData();
                  
                  final message = hasVideo 
                      ? '已选择视频${gridIndex + 1}（用于语音合成）' 
                      : '已选择空格子${gridIndex + 1}（用于语音合成）';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                // ✅ 右键显示菜单（播放视频、定位文件、删除视频）
                onSecondaryTapDown: hasVideo ? (details) {
                  _showVideoContextMenuDirect(context, videoUrl!, index, gridIndex, details);
                } : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelectedVideo ? const Color(0xFF667EEA) : const Color(0xFF3A3A3C),
                      width: isSelectedVideo ? 2 : 1,
                    ),
                  ),
                  child: hasVideo
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            // 视频缩略图（首帧）
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: _buildVideoThumbnail(videoUrl!),
                            ),
                            // 播放按钮
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
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
          ),
          
          // ✅ 合成按钮（只在有配音和视频时显示，样式参考配音按钮）
          if (row.voiceDialogues.isNotEmpty && row.videoUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showVideoAudioMergeDialog(row, index),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.merge_type, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        '合成语音',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ✅ 右键显示视频操作菜单（参考图片右键菜单样式）
  void _showVideoContextMenuDirect(BuildContext context, String videoUrl, int storyboardIndex, int gridIndex, TapDownDetails details) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      color: const Color(0xFF2A2A2C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF3A3A3C)),
      ),
      items: const [
        PopupMenuItem(
          value: 'play',
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('播放视频', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('定位文件', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('删除视频', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'play') {
        _playVideo(videoUrl);
      } else if (value == 'folder') {
        _locateVideoFile(videoUrl);
      } else if (value == 'delete') {
        _deleteVideo(storyboardIndex, gridIndex);
      }
    });
  }
  
  /// ✅ 显示语音视频合成对话框
  void _showVideoAudioMergeDialog(StoryboardRow row, int index) {
    if (row.voiceDialogues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该分镜还没有配音，请先生成配音')),
      );
      return;
    }
    
    if (row.videoUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该分镜还没有视频，请先生成视频')),
      );
      return;
    }
    
    // 获取选中的视频
    final selectedVideoIndex = row.selectedVideoIndex;
    if (selectedVideoIndex >= row.videoUrls.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('选中的格子没有视频，请选择有视频的格子')),
      );
      return;
    }
    
    final selectedVideoUrl = row.videoUrls[selectedVideoIndex];
    
    // ✅ 解析对话音频映射
    Map<String, String> dialogueAudioMap = {};
    if (row.dialogueAudioMapJson != null && row.dialogueAudioMapJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(row.dialogueAudioMapJson!) as Map<String, dynamic>;
        dialogueAudioMap = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (e) {
        print('[视频合成] 解析音频映射失败: $e');
      }
    }
    
    // 检查是否有音频文件
    if (dialogueAudioMap.isEmpty && (row.generatedAudioPath == null || !File(row.generatedAudioPath!).existsSync())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配音文件不存在，请重新生成配音')),
      );
      return;
    }
    
    // 显示完整版编辑器对话框
    showDialog(
      context: context,
      builder: (context) => VideoAudioEditorDialog(
        videoPath: selectedVideoUrl,
        dialogues: row.voiceDialogues,
        dialogueAudioMap: dialogueAudioMap,
        videoIndex: selectedVideoIndex + 1,
        storyboardIndex: index + 1,
        onMerge: (dialogueTimings) async {
          // 执行合成（多条音频）
          await _mergeVideoWithMultipleAudios(row, index, selectedVideoUrl, dialogueTimings);
        },
      ),
    );
  }
  
  /// ✅ 合成视频和多条音频
  Future<void> _mergeVideoWithMultipleAudios(StoryboardRow row, int index, String videoPath, Map<String, double> dialogueTimings) async {
    try {
      final ffmpegService = FFmpegService();
      
      // TODO: 实现多音频合并（先简化为使用第一个音频）
      final firstAudioPath = row.generatedAudioPath;
      final firstStartTime = dialogueTimings.values.isNotEmpty ? dialogueTimings.values.first : 0.0;
      
      // 生成输出路径
      final videoDir = path.dirname(videoPath);
      final videoBasename = path.basenameWithoutExtension(videoPath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = path.join(videoDir, '${videoBasename}_voiced_$timestamp.mp4');
      
      // 使用 FFmpeg 合成
      final mergedPath = await ffmpegService.mergeVideoAudioWithTiming(
        videoPath: videoPath,
        audioPath: firstAudioPath!,
        audioStartTime: firstStartTime,
        outputPath: outputPath,
        isPreview: false,
      );
      
      if (mergedPath != null) {
        // 更新分镜，添加新视频
        setState(() {
          final newUrls = List<String>.from(row.videoUrls)..add(mergedPath);
          _storyboards[index] = row.copyWith(
            videoUrls: newUrls,
            voiceStartTime: firstStartTime,
          );
        });
        await _saveProductionData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 合成完成！新视频已添加 (${row.videoUrls.length + 1}/4)'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: '播放',
                onPressed: () => _playVideo(mergedPath),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 合成失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 构建视频缩略图（显示首帧）
  Widget _buildVideoThumbnail(String videoUrl) {
    final isLocalFile = !videoUrl.startsWith('http');
    
    if (isLocalFile) {
      // 本地视频：检查是否有对应的首帧图片
      final thumbnailPath = videoUrl.replaceAll('.mp4', '.jpg');
      final thumbnailFile = File(thumbnailPath);
      
      return FutureBuilder<bool>(
        key: ValueKey(thumbnailPath),  // ✅ 添加 key，确保每次都重新检查
        future: thumbnailFile.exists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 加载中
            return Container(
              color: const Color(0xFF1A1A1C),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF888888)),
                ),
              ),
            );
          }
          
          if (snapshot.data == true) {
            // 显示首帧图片
            debugPrint('📷 显示首帧: $thumbnailPath');
            return Image.file(
              thumbnailFile,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('⚠️ 首帧加载失败: $error');
                return Container(
                  color: const Color(0xFF1A1A1C),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 32,
                    ),
                  ),
                );
              },
            );
          } else {
            // 首帧不存在，显示默认图标
            debugPrint('⚠️ 首帧不存在: $thumbnailPath');
            return Container(
              color: const Color(0xFF1A1A1C),
              child: const Center(
                child: Icon(
                  Icons.videocam,
                  color: Color(0xFF888888),
                  size: 32,
                ),
              ),
            );
          }
        },
      );
    } else {
      // 在线 URL：显示默认图标
      return Container(
        color: const Color(0xFF1A1A1C),
        child: const Center(
          child: Icon(
            Icons.videocam,
            color: Color(0xFF888888),
            size: 32,
          ),
        ),
      );
    }
  }

  Future<void> _playVideo(String videoUrl) async {
    try {
      // 检查是否是本地文件
      final isLocalFile = !videoUrl.startsWith('http');
      
      if (isLocalFile) {
        // 本地文件：检查是否存在
        final file = File(videoUrl);
        if (await file.exists()) {
          // Windows: 使用 cmd /c start 打开（兼容性最好）
          final result = await Process.run(
            'cmd',
            ['/c', 'start', '', videoUrl],
            runInShell: true,
          );
          
          if (result.exitCode == 0) {
            debugPrint('✅ 已用默认播放器打开视频: $videoUrl');
          } else {
            debugPrint('❌ 打开视频失败: exitCode=${result.exitCode}');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('打开视频失败')),
              );
            }
          }
        } else {
          debugPrint('❌ 视频文件不存在: $videoUrl');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('视频文件不存在')),
            );
          }
        }
      } else {
        // 网络 URL：用默认浏览器打开
        await Process.run(
          'cmd',
          ['/c', 'start', '', videoUrl],
          runInShell: true,
        );
        debugPrint('✅ 已在浏览器中打开: $videoUrl');
      }
    } catch (e) {
      debugPrint('❌ 打开视频失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开视频失败: $e')),
        );
      }
    }
  }

  void _locateVideoFile(String videoUrl) async {
    // 检查是否为本地文件
    if (videoUrl.isEmpty || videoUrl.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只能定位本地文件')),
      );
      return;
    }
    
    try {
      final file = File(videoUrl);
      if (await file.exists()) {
        if (Platform.isWindows) {
          await Process.run('explorer', ['/select,', videoUrl]);
          debugPrint('✅ 已定位文件: $videoUrl');
        } else if (Platform.isMacOS) {
          await Process.run('open', ['-R', videoUrl]);
        } else if (Platform.isLinux) {
          // Linux 上定位到文件所在文件夹
          final directory = file.parent.path;
          await Process.run('xdg-open', [directory]);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
      }
    } catch (e) {
      debugPrint('定位文件失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('定位文件失败: $e')),
      );
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
        const SnackBar(content: Text('剧本内容为空，无法生成分镜')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // ✅ 读取 LLM 完整配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('llm_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final model = await storage.getModel(provider: provider, modelType: 'llm');
      
      print('\n🎬 开始推理分镜');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔧 Provider: $provider');
      print('🎯 Model: ${model ?? "未设置"}');
      print('📋 分镜提示词预设: ${widget.storyboardPromptName}');
      print('📝 剧本长度: ${widget.scriptContent.length} 字符');
      print('🎞️ 已有分镜数量: ${_storyboards.length}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // ✅ 构建 messages
      final messages = <Map<String, String>>[];
      
      String fullPrompt = '';
      
      if (widget.storyboardPromptContent.isNotEmpty) {
        // ✅ 如果用户设置了提示词预设，使用预设并强调生成完整分镜
        final userPrompt = widget.storyboardPromptContent
            .replaceAll('{{小说原文}}', widget.scriptContent)
            .replaceAll('{{推文文案}}', widget.scriptContent)
            .replaceAll('{{故事情节}}', widget.scriptContent)
            .replaceAll('{{剧本内容}}', widget.scriptContent);
        
        // ✅ 纯粹使用用户的提示词预设，不添加任何额外要求
        // 用户的预设中应该包含剧本拆分和分镜生成的所有规则
        fullPrompt = userPrompt;
        
        print('✅ 使用用户自定义分镜提示词预设（纯净模式）');
      } else {
        // ✅ 如果没有预设，使用简单的基础格式
        fullPrompt = '''请根据以下剧本内容生成分镜脚本。

剧本：
${widget.scriptContent}

输出格式：
每个分镜一行，格式为：
分镜序号 | 图片提示词 | 视频提示词

示例：
1 | 主角站在未来都市天台，俯瞰城市，夜景，霓虹灯闪烁 | 主角转身眺望，镜头从远景推进到中景
2 | 地下工作室内，主角操作全息屏幕，多个屏幕显示代码 | 主角手指快速滑动，屏幕数据流动

现在开始生成：''';
        
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
          'temperature': 0.7,
          'max_tokens': 30000,  // ✅ 30000（阿里云上限是32768）
        },
      );
      
      if (response.isSuccess && response.data != null) {
        final responseText = response.data!.text;
        
        print('📄 API 返回分镜列表:');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print(responseText);
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
        
        // ✅ 智能解析分镜（支持多种格式）
        final storyboardList = <StoryboardRow>[];
        
        try {
          // 方法1：检测特殊格式标记（_::~OUTPUT_START::~_ ... _::~OUTPUT_END::~_）
          if (responseText.contains('_::~OUTPUT_START::~_') && responseText.contains('_::~OUTPUT_END::~_')) {
            print('🔍 检测到特殊输出格式标记');
            
            // ✅ 提取所有输出块（每个块是一个分镜）
            final outputPattern = RegExp(r'_::~OUTPUT_START::~_(.*?)_::~OUTPUT_END::~_', dotAll: true);
            final matches = outputPattern.allMatches(responseText);
            
            print('📦 找到 ${matches.length} 个输出块');
            
            for (final match in matches) {
              final content = match.group(1)?.trim() ?? '';
              if (content.isEmpty) continue;
              
              // ✅ 使用正则表达式匹配所有的 "内容===内容" 对
              // 改进：使用贪婪匹配直到遇到独立的 === 或结尾
              final storyboardPattern = RegExp(
                r'([\s\S]+?)===\s*([\s\S]+?)(?=\s*===\s*[\s\S]+?===|$)',
                dotAll: true,
                multiLine: true,
              );
              
              final storyboards = storyboardPattern.allMatches(content);
              
              print('   正则匹配到 ${storyboards.length} 个分镜段落');
              
              int currentScriptPosition = 0;  // 当前在原剧本中的位置
              
              for (final sb in storyboards) {
                var imagePrompt = sb.group(1)?.trim() ?? '';
                var videoPrompt = sb.group(2)?.trim() ?? '';
                
                // ✅ 尝试提取剧本片段（如果有）
                String scriptSegment = '';
                int startIndex = -1;
                int endIndex = -1;
                
                // 检查图片提示词中是否包含【剧本片段】标记
                final scriptPattern = RegExp(r'【剧本片段】(.*?)【图片提示词】', dotAll: true);
                final scriptMatch = scriptPattern.firstMatch(imagePrompt);
                
                if (scriptMatch != null) {
                  scriptSegment = scriptMatch.group(1)?.trim() ?? '';
                  // 移除【剧本片段】部分，保留纯粹的图片提示词
                  imagePrompt = imagePrompt.replaceFirst(scriptPattern, '').trim();
                  
                  // ✅ 在原剧本中查找该片段的位置
                  final foundIndex = widget.scriptContent.indexOf(scriptSegment, currentScriptPosition);
                  if (foundIndex != -1) {
                    startIndex = foundIndex;
                    endIndex = foundIndex + scriptSegment.length;
                    currentScriptPosition = endIndex;  // 下次从这里开始找
                  }
                  
                  print('   📖 剧本片段: ${scriptSegment.substring(0, scriptSegment.length > 40 ? 40 : scriptSegment.length)}...');
                  print('      位置: $startIndex - $endIndex');
                }
                
                if (imagePrompt.isNotEmpty || videoPrompt.isNotEmpty) {
                  storyboardList.add(StoryboardRow(
                    id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + storyboardList.length.toString(),
                    scriptSegment: scriptSegment,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    isUserCreated: false,
                    imagePrompt: imagePrompt,
                    videoPrompt: videoPrompt,
                    selectedImageAssets: [],
                    selectedVideoAssets: [],
                  ));
                  
                  print('   ✅ 分镜 ${storyboardList.length}');
                  print('      图片: ${imagePrompt.substring(0, imagePrompt.length > 50 ? 50 : imagePrompt.length)}...');
                  print('      视频: ${videoPrompt.substring(0, videoPrompt.length > 50 ? 50 : videoPrompt.length)}...');
                }
              }
            }
            
            print('✅ 特殊格式解析完成，找到 ${storyboardList.length} 个分镜');
          } else {
            // 方法2：尝试 JSON 格式
            try {
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
              
              final startIndex = cleanText.indexOf('[');
              final endIndex = cleanText.lastIndexOf(']');
              
              if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
                final jsonStr = cleanText.substring(startIndex, endIndex + 1);
                final List<dynamic> jsonList = jsonDecode(jsonStr);
                
                print('✅ JSON 解析成功，找到 ${jsonList.length} 个分镜');
                
                for (final item in jsonList) {
                  if (item is Map<String, dynamic>) {
                    storyboardList.add(StoryboardRow(
                      id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + storyboardList.length.toString(),
                      imagePrompt: item['imagePrompt']?.toString() ?? item['image_prompt']?.toString() ?? '',
                      videoPrompt: item['videoPrompt']?.toString() ?? item['video_prompt']?.toString() ?? '',
                      selectedImageAssets: [],
                      selectedVideoAssets: [],
                    ));
                    
                    print('   - 分镜 ${storyboardList.length}');
                  }
                }
              } else {
                throw Exception('未找到有效的 JSON 数组');
              }
            } catch (jsonError) {
              print('⚠️ JSON 格式解析失败: $jsonError');
              
              // 方法3：简单格式（序号 | 图片提示词 | 视频提示词）
              print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
              print('⚠️ 尝试简单格式解析（序号 | 图片提示词 | 视频提示词）');
              
              final lines = responseText.split('\n');
              for (final line in lines) {
                final trimmed = line.trim();
                if (trimmed.isEmpty) continue;
                
                // 跳过注释行
                if (trimmed.startsWith('#') || 
                    trimmed.startsWith('//') || 
                    trimmed.startsWith('根据') ||
                    trimmed.startsWith('```')) {
                  continue;
                }
                
                if (trimmed.contains('|')) {
                  final parts = trimmed.split('|');
                  if (parts.length >= 3) {
                    storyboardList.add(StoryboardRow(
                      id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + storyboardList.length.toString(),
                      imagePrompt: parts[1].trim(),
                      videoPrompt: parts[2].trim(),
                      selectedImageAssets: [],
                      selectedVideoAssets: [],
                    ));
                    
                    print('   - 分镜 ${storyboardList.length}');
                  }
                }
              }
              
              print('✅ 简单格式解析完成，找到 ${storyboardList.length} 个分镜');
              print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            }
          }
        } catch (e) {
          print('⚠️ 所有格式解析尝试失败: $e');
        }
        
        if (storyboardList.isEmpty) {
          throw Exception('未能解析出任何分镜，请检查提示词预设或 LLM 响应格式');
        }
        
        if (mounted) {
          setState(() {
            _storyboards = storyboardList;
          });
          
          // 自动为每个分镜选中检测到的资产
          _autoSelectAssets();
          
          // ✅ 替换视频提示词中的占位符为实际映射代码
          _replacePlaceholdersWithMappingCodes();
          
          await _saveProductionData();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ 推理完成，生成 ${storyboardList.length} 个分镜'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception(response.error ?? '推理失败');
      }
    } catch (e) {
      print('❌ 生成分镜失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成失败：$e'),
            backgroundColor: Colors.red,
          ),
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
      // ✅ 找出所有还有空格子的分镜（<4张图片）
      final storyboardsToGenerate = _storyboards.where((sb) => sb.imageUrls.length < 4).toList();
      
      if (storyboardsToGenerate.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('所有分镜的四宫格都已填满')),
          );
        }
        return;
      }
      
      print('   待生成分镜数量: ${storyboardsToGenerate.length}');
      for (var sb in storyboardsToGenerate) {
        final idx = _storyboards.indexWhere((s) => s.id == sb.id);
        print('   - 分镜${idx + 1}: 当前 ${sb.imageUrls.length}/4 张');
      }
      
      // ✅ 读取图片 API 配置（一次性读取）
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('image_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final model = await storage.getModel(provider: provider, modelType: 'image');
      
      print('\n🎨 批量生成分镜图片');
      print('   待生成数量: ${storyboardsToGenerate.length}');
      print('   Provider: $provider');
      print('   Model: ${model ?? "未设置"}\n');
      
      // ✅ 一次性并发生成所有分镜的图片（API 支持 100 条并发）
      print('🚀 开始并发生成 ${storyboardsToGenerate.length} 个分镜图片\n');
      
      final futures = storyboardsToGenerate.map((sb) async {
        try {
          final storyboardIndex = _storyboards.indexWhere((s) => s.id == sb.id);
          
          // 构建完整提示词（包含全局主题）
          String fullPrompt = sb.imagePrompt;
          if (_globalImageTheme.isNotEmpty) {
            fullPrompt = '$_globalImageTheme。$fullPrompt';
          }
          
          // ✅ 收集选中资产的图片作为参考图片
          final referenceImages = <String>[];
          final selectedAssetIds = [...sb.selectedImageAssets, ...sb.selectedVideoAssets].toSet().toList();
          
          for (final assetId in selectedAssetIds) {
            // 查找角色、场景、物品的图片
            final char = _characters.firstWhere((c) => c.id == assetId, orElse: () => AssetReference(id: '', name: '', type: AssetType.character));
            if (char.id.isNotEmpty && char.imageUrl != null && char.imageUrl!.isNotEmpty) {
              referenceImages.add(char.imageUrl!);
            }
            
            final scene = _scenes.firstWhere((s) => s.id == assetId, orElse: () => AssetReference(id: '', name: '', type: AssetType.scene));
            if (scene.id.isNotEmpty && scene.imageUrl != null && scene.imageUrl!.isNotEmpty) {
              referenceImages.add(scene.imageUrl!);
            }
            
            final item = _items.firstWhere((it) => it.id == assetId, orElse: () => AssetReference(id: '', name: '', type: AssetType.item));
            if (item.id.isNotEmpty && item.imageUrl != null && item.imageUrl!.isNotEmpty) {
              referenceImages.add(item.imageUrl!);
            }
          }
          
          print('   📸 [${storyboardIndex + 1}] 开始生成...');
          
          // ✅ 调用真实图片 API（独立请求）
          final response = await _apiRepository.generateImages(
            provider: provider,
            prompt: fullPrompt,
            model: model,
            referenceImages: referenceImages.isNotEmpty ? referenceImages : null,
            parameters: {
              'size': '16:9',
              'quality': '1K',
            },
          );
          
          if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
            final imageUrl = response.data!.first.imageUrl;
            
            // ✅ 下载并保存图片到本地
            final savedPath = await _downloadAndSaveImage(imageUrl, 'storyboard_${storyboardIndex + 1}');
            
            // ✅ 更新分镜数据（追加到现有图片列表，占用下一个格子）
            if (storyboardIndex != -1 && mounted) {
              setState(() {
                final newUrls = List<String>.from(_storyboards[storyboardIndex].imageUrls)..add(savedPath);
                _storyboards[storyboardIndex] = _storyboards[storyboardIndex].copyWith(
                  imageUrls: newUrls,
                  // 如果是第一张图片，设置为选中状态
                  selectedImageIndex: newUrls.length == 1 ? 0 : _storyboards[storyboardIndex].selectedImageIndex,
                );
              });
            }
            
            print('      ✅ [${storyboardIndex + 1}] 成功');
            return true;
          } else {
            print('      ❌ [${storyboardIndex + 1}] 失败: ${response.error}');
            return false;
          }
        } catch (e) {
          final storyboardIndex = _storyboards.indexWhere((s) => s.id == sb.id);
          print('      ❌ [${storyboardIndex + 1}] 异常: $e');
          return false;
        }
      });
      
      // ✅ 等待所有请求完成
      print('⏳ 等待所有图片生成完成...\n');
      final results = await Future.wait(futures);
      successCount = results.where((r) => r == true).length;
      failCount = results.where((r) => r == false).length;
      
      // 保存所有结果
      await _saveProductionData();
      
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
      // ✅ 找出所有有图片且还有空格子的分镜（需要先有图片，且视频<4个）
      final storyboardsToGenerate = _storyboards.where((sb) {
        return sb.imageUrls.isNotEmpty && sb.videoUrls.length < 4;
      }).toList();
      
      if (storyboardsToGenerate.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            _storyboards.any((sb) => sb.imageUrls.isEmpty)
                ? const SnackBar(content: Text('请先生成图片'))
                : const SnackBar(content: Text('所有分镜的视频四宫格都已填满')),
          );
        }
        return;
      }
      
      print('   待生成分镜数量: ${storyboardsToGenerate.length}');
      for (var sb in storyboardsToGenerate) {
        final idx = _storyboards.indexWhere((s) => s.id == sb.id);
        print('   - 分镜${idx + 1}: 当前 ${sb.videoUrls.length}/4 个视频');
      }
      
      // ✅ 读取视频 API 配置（一次性读取）
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final model = await storage.getModel(provider: provider, modelType: 'video');
      
      print('\n🎬 批量生成分镜视频');
      print('   待生成数量: ${storyboardsToGenerate.length}');
      print('   Provider: $provider');
      print('   Model: ${model ?? "未设置"}\n');
      
      // ✅ 一次性并发生成所有分镜的视频（API 支持 100 条并发）
      print('🚀 开始并发生成 ${storyboardsToGenerate.length} 个分镜视频\n');
      
      final futures = storyboardsToGenerate.map((sb) async {
        try {
          final storyboardIndex = _storyboards.indexWhere((s) => s.id == sb.id);
          
          // 构建完整提示词（包含全局主题）
          String fullPrompt = sb.videoPrompt.isNotEmpty ? sb.videoPrompt : sb.imagePrompt;
          if (_globalVideoTheme.isNotEmpty) {
            fullPrompt = '$_globalVideoTheme, $fullPrompt';
          }
          
          // 获取参考图片
          final referenceImage = sb.imageUrls.isNotEmpty ? sb.imageUrls[sb.selectedImageIndex] : null;
          final mode = referenceImage != null ? '图生视频' : '文生视频';
          
          print('   🎬 [${storyboardIndex + 1}] $mode 开始生成...');
          
          // ✅ 调用真实视频 API（独立请求）
          final response = await _apiRepository.generateVideos(
            provider: provider,
            prompt: fullPrompt,
            model: model,
            referenceImages: referenceImage != null ? [referenceImage] : null,
            parameters: {
              'ratio': '16:9',
              'seconds': 8,
            },
          );
          
          if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
            final videoUrl = response.data!.first.videoUrl;
            
            // ✅ 下载并保存视频到本地
            final savedPath = await _downloadAndSaveVideo(videoUrl, 'storyboard_${storyboardIndex + 1}');
            
            // ✅ 更新分镜数据（追加到现有视频列表，占用下一个格子）
            if (storyboardIndex != -1 && mounted) {
              setState(() {
                final newUrls = List<String>.from(_storyboards[storyboardIndex].videoUrls)..add(savedPath);
                _storyboards[storyboardIndex] = _storyboards[storyboardIndex].copyWith(
                  videoUrls: newUrls,
                );
              });
            }
            
            print('      ✅ [${storyboardIndex + 1}] 成功');
            return true;
          } else {
            print('      ❌ [${storyboardIndex + 1}] 失败: ${response.error}');
            return false;
          }
        } catch (e) {
          final storyboardIndex = _storyboards.indexWhere((s) => s.id == sb.id);
          print('      ❌ [${storyboardIndex + 1}] 异常: $e');
          return false;
        }
      });
      
      // ✅ 等待所有请求完成
      print('⏳ 等待所有视频生成完成...\n');
      final results = await Future.wait(futures);
      successCount = results.where((r) => r == true).length;
      failCount = results.where((r) => r == false).length;
      
      // 保存所有结果
      await _saveProductionData();
      
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

  /// 替换视频提示词中的占位符为实际映射代码
  void _replacePlaceholdersWithMappingCodes() {
    debugPrint('\n🔄 替换视频提示词中的占位符');
    
    for (var i = 0; i < _storyboards.length; i++) {
      var videoPrompt = _storyboards[i].videoPrompt;
      var replacedCount = 0;
      
      // 替换角色占位符
      for (final char in _characters) {
        if (char.mappingCode != null && char.mappingCode!.isNotEmpty) {
          // 查找类似 @characterXXX 角色名 的模式
          final pattern = RegExp(r'@character\d+\s+' + RegExp.escape(char.name));
          if (videoPrompt.contains(pattern)) {
            videoPrompt = videoPrompt.replaceAll(pattern, '${char.mappingCode}${char.name}');
            replacedCount++;
            debugPrint('   ✅ 分镜${i+1}: 替换 @character → ${char.mappingCode}${char.name}');
          }
        }
      }
      
      // 替换场景占位符
      for (final scene in _scenes) {
        if (scene.mappingCode != null && scene.mappingCode!.isNotEmpty) {
          final pattern = RegExp(r'@scene\d+\s+' + RegExp.escape(scene.name));
          if (videoPrompt.contains(pattern)) {
            videoPrompt = videoPrompt.replaceAll(pattern, '${scene.mappingCode}${scene.name}');
            replacedCount++;
          }
        }
      }
      
      // 替换物品占位符
      for (final item in _items) {
        if (item.mappingCode != null && item.mappingCode!.isNotEmpty) {
          final pattern = RegExp(r'@(item|asset)\d+\s+' + RegExp.escape(item.name));
          if (videoPrompt.contains(pattern)) {
            videoPrompt = videoPrompt.replaceAll(pattern, '${item.mappingCode}${item.name}');
            replacedCount++;
          }
        }
      }
      
      // 如果有替换，更新分镜
      if (replacedCount > 0) {
        _storyboards[i] = _storyboards[i].copyWith(videoPrompt: videoPrompt);
        debugPrint('   📝 分镜${i+1}: 替换了 $replacedCount 个占位符');
      }
    }
    
    debugPrint('✅ 占位符替换完成\n');
  }

  /// 自动为所有分镜选中检测到的资产
  void _autoSelectAssets() {
    print('\n🔍 开始自动选中资产');
    print('   可用角色: ${_characters.length} 个');
    print('   可用场景: ${_scenes.length} 个');
    print('   可用物品: ${_items.length} 个\n');
    
    for (int i = 0; i < _storyboards.length; i++) {
      final row = _storyboards[i];
      final combinedPrompt = '${row.imagePrompt} ${row.videoPrompt}';
      final detectedAssets = <String>[];
      
      print('📋 分镜${i + 1} 资产检测:');
      
      // ✅ 检测角色（精确匹配）
      for (final char in _characters) {
        if (combinedPrompt.contains(char.name)) {
          detectedAssets.add(char.id);
          print('   ✅ 角色: ${char.name}');
        }
      }
      
      // ✅ 检测场景（智能模糊匹配）
      for (final scene in _scenes) {
        // 方法1：完整名称匹配
        if (combinedPrompt.contains(scene.name)) {
          detectedAssets.add(scene.id);
          print('   ✅ 场景: ${scene.name} (完整匹配)');
        } else {
          // 方法2：提取场景名称的关键词进行模糊匹配
          // 例如："青竹村晨雾村口场景" → 关键词："青竹村", "村口"
          final sceneKeywords = _extractSceneKeywords(scene.name);
          var matchCount = 0;
          for (final keyword in sceneKeywords) {
            if (keyword.length >= 2 && combinedPrompt.contains(keyword)) {
              matchCount++;
            }
          }
          // 如果匹配到50%以上的关键词，认为是匹配
          if (matchCount >= sceneKeywords.length * 0.5 && matchCount > 0) {
            if (!detectedAssets.contains(scene.id)) {
              detectedAssets.add(scene.id);
              print('   ✅ 场景: ${scene.name} (模糊匹配, 关键词: ${sceneKeywords.join(", ")})');
            }
          }
        }
      }
      
      // ✅ 检测物品（精确匹配）
      for (final item in _items) {
        if (combinedPrompt.contains(item.name)) {
          detectedAssets.add(item.id);
          print('   ✅ 物品: ${item.name}');
        }
      }
      
      print('   📊 总计检测到 ${detectedAssets.length} 个资产\n');
      
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
  
  /// 提取场景名称的关键词
  List<String> _extractSceneKeywords(String sceneName) {
    // 移除常见的后缀词
    String cleaned = sceneName
        .replaceAll('场景', '')
        .replaceAll('内部', '')
        .replaceAll('外部', '')
        .replaceAll('内景', '')
        .replaceAll('外景', '')
        .trim();
    
    // 按常见分隔符拆分
    final keywords = <String>[];
    
    // 拆分策略：按空格、顿号、逗号等分隔
    final separators = [' ', '、', '，', ','];
    var parts = [cleaned];
    
    for (final sep in separators) {
      final newParts = <String>[];
      for (final part in parts) {
        newParts.addAll(part.split(sep));
      }
      parts = newParts;
    }
    
    // 过滤并返回
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.length >= 2) {
        keywords.add(trimmed);
      }
    }
    
    return keywords.isEmpty ? [cleaned] : keywords;
  }

  /// 清空所有分镜
  Future<void> _clearAllStoryboards() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('确认清空', style: TextStyle(color: Colors.white)),
        content: const Text(
          '确定要清空所有分镜吗？此操作不可恢复。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: Color(0xFF888888))),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final count = _storyboards.length;
      setState(() {
        _storyboards.clear();
      });
      await _saveProductionData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已清空 $count 个分镜'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  /// 显示添加资产对话框
  void _showAddAssetDialog(int storyboardIndex) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E20),
            title: Text('添加资产到分镜 ${storyboardIndex + 1}', style: const TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_characters.isNotEmpty) ...[
                      const Text('角色', style: TextStyle(color: Color(0xFF888888), fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _characters.map((char) {
                          final isSelected = _storyboards[storyboardIndex].selectedImageAssets.contains(char.id);
                          return _buildSelectableAssetChip(char.name, char.type, isSelected, () {
                            setDialogState(() {
                              _toggleAssetSelection(storyboardIndex, char.id);
                            });
                          });
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_scenes.isNotEmpty) ...[
                      const Text('场景', style: TextStyle(color: Color(0xFF888888), fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _scenes.map((scene) {
                          final isSelected = _storyboards[storyboardIndex].selectedImageAssets.contains(scene.id);
                          return _buildSelectableAssetChip(scene.name, scene.type, isSelected, () {
                            setDialogState(() {
                              _toggleAssetSelection(storyboardIndex, scene.id);
                            });
                          });
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_items.isNotEmpty) ...[
                      const Text('物品', style: TextStyle(color: Color(0xFF888888), fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _items.map((item) {
                          final isSelected = _storyboards[storyboardIndex].selectedImageAssets.contains(item.id);
                          return _buildSelectableAssetChip(item.name, item.type, isSelected, () {
                            setDialogState(() {
                              _toggleAssetSelection(storyboardIndex, item.id);
                            });
                          });
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成', style: TextStyle(color: Color(0xFF888888))),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 切换资产选择状态
  void _toggleAssetSelection(int storyboardIndex, String assetId) {
    final row = _storyboards[storyboardIndex];
    final currentSelected = [...row.selectedImageAssets, ...row.selectedVideoAssets].toSet().toList();
    final newSelected = List<String>.from(currentSelected);
    
    if (newSelected.contains(assetId)) {
      newSelected.remove(assetId);
      // TODO: 从视频提示词中移除映射代码（可选）
    } else {
      newSelected.add(assetId);
      
      // ✅ 添加资产时，自动在视频提示词前插入映射代码
      final asset = _findAssetById(assetId);
      if (asset != null && asset['mappingCode'] != null) {
        final code = asset['mappingCode'];
        final name = asset['name'];
        final insertText = '$code,$name\n';
        
        final currentVideoPrompt = row.videoPrompt;
        final newVideoPrompt = insertText + currentVideoPrompt;
        
        setState(() {
          _storyboards[storyboardIndex] = row.copyWith(
            selectedImageAssets: newSelected,
            selectedVideoAssets: newSelected,
            videoPrompt: newVideoPrompt,  // 更新视频提示词
          );
        });
        _saveProductionData();
        return;
      }
    }
    
    setState(() {
      _storyboards[storyboardIndex] = row.copyWith(
        selectedImageAssets: newSelected,
        selectedVideoAssets: newSelected,
      );
    });
    _saveProductionData();
  }
  
  /// 根据ID查找资产
  Map<String, dynamic>? _findAssetById(String assetId) {
    // 查找角色
    for (final char in _characters) {
      if (char.id == assetId) {
        return {
          'id': char.id,
          'name': char.name,
          'mappingCode': char.mappingCode,  // ✅ 使用 mappingCode
          'type': 'character',
        };
      }
    }
    // 查找场景
    for (final scene in _scenes) {
      if (scene.id == assetId) {
        return {
          'id': scene.id,
          'name': scene.name,
          'mappingCode': scene.mappingCode,
          'type': 'scene',
        };
      }
    }
    // 查找物品
    for (final item in _items) {
      if (item.id == assetId) {
        return {
          'id': item.id,
          'name': item.name,
          'mappingCode': item.mappingCode,
          'type': 'item',
        };
      }
    }
    return null;
  }

  /// 构建可选择的资产芯片
  Widget _buildSelectableAssetChip(String name, AssetType type, bool isSelected, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3A3A3C) : const Color(0xFF1A1A1C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF888888) : const Color(0xFF2A2A2C),
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
                size: 14,
                color: isSelected ? const Color(0xFF888888) : const Color(0xFF555555),
              ),
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF888888) : const Color(0xFF555555),
                  fontSize: 12,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check, size: 14, color: Color(0xFF4A9EFF)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 下载并保存单张图片到本地
  Future<String> _downloadAndSaveImage(String imageUrl, String prefix) async {
    try {
      // ✅ 优先使用作品保存路径，如果没设置则使用图片保存路径
      final workPath = workSavePathNotifier.value;
      final imagePath = imageSavePathNotifier.value;
      
      String savePath;
      if (workPath != '未设置' && workPath.isNotEmpty) {
        // 使用作品路径 + 作品名称
        savePath = path.join(workPath, widget.workName);
        debugPrint('📁 使用作品保存路径: $savePath');
      } else if (imagePath != '未设置' && imagePath.isNotEmpty) {
        // 使用图片保存路径
        savePath = imagePath;
        debugPrint('📁 使用图片保存路径: $savePath');
      } else {
        debugPrint('⚠️ 未设置保存路径，使用在线 URL');
        return imageUrl;
      }
      
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
        debugPrint('✅ 创建目录: $savePath');
      }
      
      // 重试最多3次下载图片
      for (var retry = 0; retry < 3; retry++) {
        try {
          final response = await http.get(
            Uri.parse(imageUrl),
            headers: {'Connection': 'keep-alive'},
          ).timeout(const Duration(seconds: 30));
          
          if (response.statusCode == 200) {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = '${prefix}_$timestamp.png';
            final filePath = path.join(savePath, fileName);
            
            final file = File(filePath);
            await file.writeAsBytes(response.bodyBytes);
            
            debugPrint('✅ 分镜图片已保存: $filePath');
            return filePath;
          } else {
            debugPrint('⚠️ 下载失败 (重试 $retry/3): HTTP ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('⚠️ 下载异常 (重试 $retry/3): $e');
          if (retry < 2) {
            await Future.delayed(Duration(seconds: retry + 1));
          }
        }
      }
      
      debugPrint('❌ 下载失败，使用在线 URL');
      return imageUrl;
    } catch (e) {
      debugPrint('💥 保存图片失败: $e');
      return imageUrl;
    }
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

  /// 执行图片提示词推理（带上下文记忆）
  Future<void> _executeImageReinfer(int index, String requirement) async {
    try {
      // ✅ 读取 LLM 配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('llm_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final model = await storage.getModel(provider: provider, modelType: 'llm');
      
      print('\n🎬 重新推理图片提示词 - 分镜 ${index + 1}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔧 Provider: $provider');
      print('🎯 Model: ${model ?? "未设置"}');
      print('📝 用户要求: ${requirement.isNotEmpty ? requirement : "无"}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // ✅ 构建上下文信息
      final contextInfo = StringBuffer();
      
      // 全局图片主题
      if (_globalImageTheme.isNotEmpty) {
        contextInfo.writeln('【全局图片风格主题】');
        contextInfo.writeln(_globalImageTheme);
        contextInfo.writeln();
      }
      
      // 前面的分镜（上下文）
      if (index > 0) {
        contextInfo.writeln('【前面的分镜（上下文参考）】');
        final prevCount = index > 2 ? 2 : index;  // 最多显示前2个分镜
        for (var i = index - prevCount; i < index; i++) {
          contextInfo.writeln('分镜${i + 1}:');
          contextInfo.writeln('  图片: ${_storyboards[i].imagePrompt}');
          contextInfo.writeln('  视频: ${_storyboards[i].videoPrompt}');
          contextInfo.writeln();
        }
      }
      
      // 当前分镜的现有内容
      contextInfo.writeln('【当前分镜（需要推理）】');
      contextInfo.writeln('分镜${index + 1}:');
      if (_storyboards[index].imagePrompt.isNotEmpty) {
        contextInfo.writeln('  当前图片提示词: ${_storyboards[index].imagePrompt}');
      }
      if (_storyboards[index].videoPrompt.isNotEmpty) {
        contextInfo.writeln('  视频提示词: ${_storyboards[index].videoPrompt}');
      }
      contextInfo.writeln();
      
      // 后面的分镜（上下文）
      if (index < _storyboards.length - 1) {
        contextInfo.writeln('【后面的分镜（上下文参考）】');
        final nextCount = index < _storyboards.length - 3 ? 2 : _storyboards.length - index - 1;
        for (var i = index + 1; i <= index + nextCount; i++) {
          contextInfo.writeln('分镜${i + 1}:');
          contextInfo.writeln('  图片: ${_storyboards[i].imagePrompt}');
          contextInfo.writeln('  视频: ${_storyboards[i].videoPrompt}');
          contextInfo.writeln();
        }
      }
      
      // 构建完整提示词
      String fullPrompt = '''请根据以下信息，为分镜${index + 1}推理一个详细的图片提示词。

$contextInfo

【剧本内容（节选相关部分）】
${widget.scriptContent.substring(0, widget.scriptContent.length > 1000 ? 1000 : widget.scriptContent.length)}...

${requirement.isNotEmpty ? '【用户额外要求】\n$requirement\n\n' : ''}
【任务】
基于上述上下文，为分镜${index + 1}生成一个详细的图片提示词，要求：
1. 与前后分镜保持连贯性
2. 符合全局图片风格主题
3. 包含人物、场景、镜头景别、氛围等元素
4. 直接输出提示词文本，不要其他格式

图片提示词：''';
      
      final messages = <Map<String, String>>[
        {'role': 'user', 'content': fullPrompt}
      ];
      
      // 调用 LLM API
      _apiRepository.clearCache();
      final response = await _apiRepository.generateTextWithMessages(
        provider: provider,
        messages: messages,
        model: model,
        parameters: {
          'temperature': 0.7,
          'max_tokens': 500,
        },
      );
      
      if (response.isSuccess && response.data != null) {
        var updatedPrompt = response.data!.text.trim();
        
        // ✅ 移除可能的前缀文字（如"图片提示词："等）
        updatedPrompt = updatedPrompt
            .replaceFirst('图片提示词：', '')
            .replaceFirst('图片提示词:', '')
            .replaceFirst('图片：', '')
            .replaceFirst('图片:', '')
            .trim();
        
        print('✅ 推理成功');
        print('📝 新提示词: ${updatedPrompt.substring(0, updatedPrompt.length > 100 ? 100 : updatedPrompt.length)}...\n');
        
        if (mounted) {
          setState(() {
            _storyboards[index] = _storyboards[index].copyWith(imagePrompt: updatedPrompt);
          });
          await _saveProductionData();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ 分镜${index + 1}的图片提示词已更新'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception(response.error ?? '推理失败');
      }
    } catch (e) {
      print('❌ 推理失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('推理失败：$e'),
            backgroundColor: Colors.red,
          ),
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

  /// 执行视频提示词推理（带上下文记忆）
  Future<void> _executeVideoReinfer(int index, String requirement) async {
    try {
      // ✅ 读取 LLM 配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('llm_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final model = await storage.getModel(provider: provider, modelType: 'llm');
      
      print('\n🎬 重新推理视频提示词 - 分镜 ${index + 1}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔧 Provider: $provider');
      print('🎯 Model: ${model ?? "未设置"}');
      print('📝 用户要求: ${requirement.isNotEmpty ? requirement : "无"}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // ✅ 构建上下文信息
      final contextInfo = StringBuffer();
      
      // 全局视频主题
      if (_globalVideoTheme.isNotEmpty) {
        contextInfo.writeln('【全局视频风格主题】');
        contextInfo.writeln(_globalVideoTheme);
        contextInfo.writeln();
      }
      
      // 前面的分镜（上下文）
      if (index > 0) {
        contextInfo.writeln('【前面的分镜（上下文参考）】');
        final prevCount = index > 2 ? 2 : index;
        for (var i = index - prevCount; i < index; i++) {
          contextInfo.writeln('分镜${i + 1}:');
          contextInfo.writeln('  图片: ${_storyboards[i].imagePrompt}');
          contextInfo.writeln('  视频: ${_storyboards[i].videoPrompt}');
          contextInfo.writeln();
        }
      }
      
      // 当前分镜的现有内容
      contextInfo.writeln('【当前分镜（需要推理）】');
      contextInfo.writeln('分镜${index + 1}:');
      contextInfo.writeln('  图片提示词: ${_storyboards[index].imagePrompt}');
      if (_storyboards[index].videoPrompt.isNotEmpty) {
        contextInfo.writeln('  当前视频提示词: ${_storyboards[index].videoPrompt}');
      }
      contextInfo.writeln();
      
      // 后面的分镜（上下文）
      if (index < _storyboards.length - 1) {
        contextInfo.writeln('【后面的分镜（上下文参考）】');
        final nextCount = index < _storyboards.length - 3 ? 2 : _storyboards.length - index - 1;
        for (var i = index + 1; i <= index + nextCount; i++) {
          contextInfo.writeln('分镜${i + 1}:');
          contextInfo.writeln('  图片: ${_storyboards[i].imagePrompt}');
          contextInfo.writeln('  视频: ${_storyboards[i].videoPrompt}');
          contextInfo.writeln();
        }
      }
      
      // 构建完整提示词
      String fullPrompt = '''请根据以下信息，为分镜${index + 1}推理一个详细的视频运镜描述。

$contextInfo

【剧本内容（节选相关部分）】
${widget.scriptContent.substring(0, widget.scriptContent.length > 1000 ? 1000 : widget.scriptContent.length)}...

${requirement.isNotEmpty ? '【用户额外要求】\n$requirement\n\n' : ''}
【任务】
基于上述上下文和当前分镜的图片内容，为分镜${index + 1}生成一个详细的视频运镜描述，要求：
1. 与前后分镜保持连贯性和节奏感
2. 符合全局视频风格主题
3. 描述镜头运动、节奏、视角、转场等
4. 确保视频能够承接前一个分镜，并过渡到下一个分镜
5. 直接输出视频提示词文本，不要其他格式

视频提示词：''';
      
      final messages = <Map<String, String>>[
        {'role': 'user', 'content': fullPrompt}
      ];
      
      // 调用 LLM API
      _apiRepository.clearCache();
      final response = await _apiRepository.generateTextWithMessages(
        provider: provider,
        messages: messages,
        model: model,
        parameters: {
          'temperature': 0.7,
          'max_tokens': 500,
        },
      );
      
      if (response.isSuccess && response.data != null) {
        var updatedPrompt = response.data!.text.trim();
        
        // ✅ 移除可能的前缀文字（如"视频提示词："等）
        updatedPrompt = updatedPrompt
            .replaceFirst('视频提示词：', '')
            .replaceFirst('视频提示词:', '')
            .replaceFirst('视频：', '')
            .replaceFirst('视频:', '')
            .replaceFirst('运镜描述：', '')
            .replaceFirst('运镜描述:', '')
            .trim();
        
        print('✅ 推理成功');
        print('📝 新提示词: ${updatedPrompt.substring(0, updatedPrompt.length > 100 ? 100 : updatedPrompt.length)}...\n');
        
        if (mounted) {
          setState(() {
            _storyboards[index] = _storyboards[index].copyWith(videoPrompt: updatedPrompt);
          });
          await _saveProductionData();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ 分镜${index + 1}的视频提示词已更新'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception(response.error ?? '推理失败');
      }
    } catch (e) {
      print('❌ 推理失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('推理失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 显示拆分对话框（手动选择位置）
  void _showSplitDialog(int index) {
    final row = _storyboards[index];
    if (row.scriptSegment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此分镜没有剧本片段，无法拆分')),
      );
      return;
    }
    
    if (row.scriptSegment.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剧本片段太短，无法拆分')),
      );
      return;
    }
    
    int? selectedPosition;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 预览拆分结果
          final preview1 = selectedPosition != null 
              ? row.scriptSegment.substring(0, selectedPosition!)
              : '';
          final preview2 = selectedPosition != null
              ? row.scriptSegment.substring(selectedPosition!)
              : '';
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E20),
            title: Text('拆分分镜 ${index + 1}', style: const TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 700,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '点击文本中的位置作为拆分点',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  // ✅ 可点击的文本（每个字符可点击）
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252629),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3A3A3C)),
                    ),
                    child: SingleChildScrollView(
                      child: Wrap(
                        children: row.scriptSegment.split('').asMap().entries.map((entry) {
                          final i = entry.key;
                          final char = entry.value;
                          
                          if (i == 0 || i == row.scriptSegment.length - 1) {
                            // 第一个和最后一个字符不能作为拆分点
                            return Text(char, style: const TextStyle(color: Color(0xFF666666), fontSize: 14));
                          }
                          
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedPosition = i;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: i == selectedPosition 
                                    ? const Color(0xFF4A9EFF).withOpacity(0.3)
                                    : Colors.transparent,
                                border: i == selectedPosition 
                                    ? const Border(right: BorderSide(color: Color(0xFF4A9EFF), width: 2))
                                    : null,
                              ),
                              child: Text(
                                char,
                                style: TextStyle(
                                  color: i == selectedPosition ? const Color(0xFF4A9EFF) : const Color(0xFFCCCCCC),
                                  fontSize: 14,
                                  fontWeight: i == selectedPosition ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (selectedPosition != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '拆分位置：第 ${selectedPosition!} 字',
                      style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    const Text('预览：', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1C),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF3A3A3C)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('片段1（前${preview1.length}字）：', style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 11)),
                          Text(
                            preview1.substring(0, preview1.length > 100 ? 100 : preview1.length) + (preview1.length > 100 ? '...' : ''),
                            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          Text('片段2（后${preview2.length}字）：', style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 11)),
                          Text(
                            preview2.substring(0, preview2.length > 100 ? 100 : preview2.length) + (preview2.length > 100 ? '...' : ''),
                            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: selectedPosition != null
                    ? () {
                        Navigator.pop(context);
                        _executeSplitAtPosition(index, selectedPosition!);
                      }
                    : null,
                child: const Text('确认拆分', style: TextStyle(color: Color(0xFF4A9EFF))),
              ),
            ],
          );
        },
      ),
    );
  }
  
  /// 执行拆分（在指定位置）
  Future<void> _executeSplitAtPosition(int index, int position) async {
    final row = _storyboards[index];
    
    // 在指定位置拆分
    final part1Text = row.scriptSegment.substring(0, position);
    final part2Text = row.scriptSegment.substring(position);
    
    // 计算新的位置
    final part1Start = row.startIndex;
    final part1End = row.startIndex + part1Text.length;
    final part2Start = part1End;
    final part2End = row.endIndex;
    
    // 创建两个新分镜
    final storyboard1 = StoryboardRow(
      id: '${DateTime.now().millisecondsSinceEpoch}_1',
      scriptSegment: part1Text,
      startIndex: part1Start,
      endIndex: part1End,
      isUserCreated: false,
      imagePrompt: '',  // 需要重新推理
      videoPrompt: '',
    );
    
    final storyboard2 = StoryboardRow(
      id: '${DateTime.now().millisecondsSinceEpoch}_2',
      scriptSegment: part2Text,
      startIndex: part2Start,
      endIndex: part2End,
      isUserCreated: false,
      imagePrompt: '',
      videoPrompt: '',
    );
    
    // 替换原分镜
    setState(() {
      _storyboards[index] = storyboard1;
      _storyboards.insert(index + 1, storyboard2);
    });
    
    await _saveProductionData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 已拆分为分镜 ${index + 1} 和 ${index + 2}\n请分别推理各自的提示词'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// 打开语音生成对话框
  void _openVoiceGenerationDialog(int index) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => VoiceGenerationDialog(
        storyboard: _storyboards[index],
        storyboardIndex: index,
        onComplete: (updatedStoryboard) {
          setState(() {
            _storyboards[index] = updatedStoryboard;
          });
          _saveProductionData();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 分镜 ${index + 1} 配音已保存'),
              backgroundColor: const Color(0xFF2AF598),
            ),
          );
        },
      ),
    );
  }

  /// 播放配音（废弃，已改为点击"已配音"进入向导试听）
  Future<void> _playVoiceAudio(StoryboardRow row) async {
    if (row.generatedAudioPath == null) return;
    final path = row.generatedAudioPath!;
    
    try {
      final audioFile = File(path);
      if (!await audioFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('配音文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      if (_voiceUseSystemPlayer) {
        await Process.run('cmd', ['/c', 'start', '', path]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('正在播放配音...'), backgroundColor: Color(0xFF2AF598), duration: Duration(seconds: 1)),
          );
        }
        return;
      }
      try {
        _voiceAudioPlayer ??= AudioPlayer();
        await _voiceAudioPlayer!.stop();
        await _voiceAudioPlayer!.play(DeviceFileSource(path));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('正在播放配音...'), backgroundColor: Color(0xFF2AF598), duration: Duration(seconds: 1)),
          );
        }
      } on MissingPluginException catch (_) {
        _voiceUseSystemPlayer = true;
        await Process.run('cmd', ['/c', 'start', '', path]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('正在播放配音...'), backgroundColor: Color(0xFF2AF598), duration: Duration(seconds: 1)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 小按钮辅助方法
  Widget _buildSmallButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A3C),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFCCCCCC), size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 合并选中的分镜
  Future<void> _mergeSelectedStoryboards() async {
    if (_selectedStoryboards.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择2个分镜进行合并')),
      );
      return;
    }
    
    final indices = _selectedStoryboards.toList()..sort();
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('确认合并', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要合并 ${indices.length} 个分镜吗？\n'
          '分镜 ${indices.map((i) => i + 1).join(", ")}\n\n'
          '合并后需要重新推理提示词。',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('合并', style: TextStyle(color: Color(0xFF4A9EFF))),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // 合并剧本片段
    final mergedScriptSegments = <String>[];
    int mergedStartIndex = -1;
    int mergedEndIndex = -1;
    
    for (final i in indices) {
      final row = _storyboards[i];
      if (row.scriptSegment.isNotEmpty) {
        mergedScriptSegments.add(row.scriptSegment);
        if (mergedStartIndex == -1 || row.startIndex < mergedStartIndex) {
          mergedStartIndex = row.startIndex;
        }
        if (row.endIndex > mergedEndIndex) {
          mergedEndIndex = row.endIndex;
        }
      }
    }
    
    final mergedScript = mergedScriptSegments.join('');
    
    // 创建新分镜
    final mergedStoryboard = StoryboardRow(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      scriptSegment: mergedScript,
      startIndex: mergedStartIndex,
      endIndex: mergedEndIndex,
      isUserCreated: false,
      imagePrompt: '',  // 需要重新推理
      videoPrompt: '',
    );
    
    // 替换：删除所有选中的，在第一个位置插入新的
    setState(() {
      // 从后往前删除，避免索引变化
      for (final i in indices.reversed) {
        _storyboards.removeAt(i);
      }
      // 在原来第一个的位置插入合并后的分镜
      _storyboards.insert(indices.first, mergedStoryboard);
      _selectedStoryboards.clear();  // 清空选中状态
    });
    
    await _saveProductionData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 已合并为分镜 ${indices.first + 1}\n请推理新的提示词'),
          backgroundColor: Colors.green,
        ),
      );
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
    
    print('\n🎨 生成分镜图片 - 分镜 ${index + 1}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    try {
      // ✅ 读取图片 API 配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('image_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final baseUrl = await storage.getBaseUrl(provider: provider, modelType: 'image');
      final apiKey = await storage.getApiKey(provider: provider, modelType: 'image');
      final model = await storage.getModel(provider: provider, modelType: 'image');
      
      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置图片 API');
      }
      
      print('🔧 Provider: $provider');
      print('🎯 Model: ${model ?? "未设置"}');
      print('📝 图片提示词: ${row.imagePrompt.substring(0, row.imagePrompt.length > 100 ? 100 : row.imagePrompt.length)}...');
      
      // ✅ 构建完整提示词（添加全局主题）
      String fullPrompt = row.imagePrompt;
      if (_globalImageTheme.isNotEmpty) {
        fullPrompt = '$_globalImageTheme。$fullPrompt';
        print('🎨 全局主题: $_globalImageTheme');
      }
      
      // ✅ 收集选中资产的图片作为参考图片
      final referenceImages = <String>[];
      final selectedAssetIds = [...row.selectedImageAssets, ...row.selectedVideoAssets].toSet().toList();
      
      print('📦 选中的资产: ${selectedAssetIds.length} 个');
      
      for (final assetId in selectedAssetIds) {
        // 查找角色资产
        final char = _characters.firstWhere(
          (c) => c.id == assetId,
          orElse: () => AssetReference(id: '', name: '', type: AssetType.character),
        );
        if (char.id.isNotEmpty && char.imageUrl != null && char.imageUrl!.isNotEmpty) {
          referenceImages.add(char.imageUrl!);
          print('   ✅ 角色图片: ${char.name}');
        }
        
        // 查找场景资产
        final scene = _scenes.firstWhere(
          (s) => s.id == assetId,
          orElse: () => AssetReference(id: '', name: '', type: AssetType.scene),
        );
        if (scene.id.isNotEmpty && scene.imageUrl != null && scene.imageUrl!.isNotEmpty) {
          referenceImages.add(scene.imageUrl!);
          print('   ✅ 场景图片: ${scene.name}');
        }
        
        // 查找物品资产
        final item = _items.firstWhere(
          (i) => i.id == assetId,
          orElse: () => AssetReference(id: '', name: '', type: AssetType.item),
        );
        if (item.id.isNotEmpty && item.imageUrl != null && item.imageUrl!.isNotEmpty) {
          referenceImages.add(item.imageUrl!);
          print('   ✅ 物品图片: ${item.name}');
        }
      }
      
      print('🖼️ 参考图片总数: ${referenceImages.length} 张');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // ✅ 调用真实图片 API
      final response = await _apiRepository.generateImages(
        provider: provider,
        prompt: fullPrompt,
        model: model,
        referenceImages: referenceImages.isNotEmpty ? referenceImages : null,
        parameters: {
          'size': '16:9',
          'quality': '1K',
        },
      );
      
      if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
        final imageUrl = response.data!.first.imageUrl;
        
        print('✅ 图片生成成功: $imageUrl');
        print('💾 下载并保存到本地...');
        
        // ✅ 下载并保存图片到本地
        final savedPath = await _downloadAndSaveImage(imageUrl, 'storyboard_${index + 1}');
        
        print('✅ 保存完成（使用本地路径）\n');
        
        if (mounted) {
          setState(() {
            final newUrls = List<String>.from(row.imageUrls)..add(savedPath);
            _storyboards[index] = row.copyWith(imageUrls: newUrls);
          });
          await _saveProductionData();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ 分镜${index + 1}图片生成成功 (${row.imageUrls.length + 1}/4)'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception(response.error ?? '生成失败');
      }
    } catch (e) {
      print('❌ 图片生成失败: $e\n');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 图片生成失败: $e'),
            backgroundColor: Colors.red,
          ),
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
    
    print('\n🎬 生成分镜视频 - 分镜 ${index + 1}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    try {
      // ✅ 读取视频 API 配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final model = await storage.getModel(provider: provider, modelType: 'video');
      
      // 检查选中的图片
      final selectedImageUrl = row.selectedImageIndex < row.imageUrls.length
          ? row.imageUrls[row.selectedImageIndex]
          : null;
      
      final mode = selectedImageUrl != null ? '图生视频' : '文生视频';
      
      print('🔧 Provider: $provider');
      print('🎯 Model: ${model ?? "未设置"}');
      print('📝 模式: $mode');
      print('📝 视频提示词: ${row.videoPrompt.substring(0, row.videoPrompt.length > 100 ? 100 : row.videoPrompt.length)}...');
      
      // 构建完整提示词
      String fullPrompt = row.videoPrompt.isNotEmpty ? row.videoPrompt : row.imagePrompt;
      if (_globalVideoTheme.isNotEmpty) {
        fullPrompt = '$_globalVideoTheme, $fullPrompt';
        print('🎨 全局主题: $_globalVideoTheme');
      }
      
      if (selectedImageUrl != null) {
        print('🖼️ 参考图片: $selectedImageUrl');
      }
      
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // ✅ 调用真实视频 API
      final response = await _apiRepository.generateVideos(
        provider: provider,
        prompt: fullPrompt,
        model: model,
        referenceImages: selectedImageUrl != null ? [selectedImageUrl] : null,
        parameters: {
          'ratio': '16:9',
          'seconds': 8,
        },
      );
      
      if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
        final videoUrl = response.data!.first.videoUrl;
        
        print('✅ 视频生成成功: $videoUrl');
        print('💾 下载并保存到本地...');
        
        // ✅ 下载并保存视频到本地（包括首帧提取）
        final savedPath = await _downloadAndSaveVideo(videoUrl, 'storyboard_${index + 1}');
        
        print('✅ 保存完成（使用本地路径）\n');
        
        if (mounted) {
          setState(() {
            final newUrls = List<String>.from(row.videoUrls)..add(savedPath);
            _storyboards[index] = row.copyWith(videoUrls: newUrls);
          });
          await _saveProductionData();
          
          // ✅ 延迟一下，确保首帧文件系统写入完成，然后再次刷新界面
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            setState(() {});  // 再次刷新，显示首帧
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ 分镜${index + 1}视频生成成功 (${row.videoUrls.length + 1}/4) - $mode'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception(response.error ?? '生成失败');
      }
    } catch (e) {
      print('❌ 视频生成失败: $e\n');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 视频生成失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 下载并保存视频到本地
  Future<String> _downloadAndSaveVideo(String videoUrl, String prefix) async {
    try {
      // ✅ 优先使用作品保存路径，如果没设置则使用视频保存路径
      final workPath = workSavePathNotifier.value;
      final videoPath = videoSavePathNotifier.value;
      
      String savePath;
      if (workPath != '未设置' && workPath.isNotEmpty) {
        // 使用作品路径 + 作品名称
        savePath = path.join(workPath, widget.workName);
        debugPrint('📁 使用作品保存路径: $savePath');
      } else if (videoPath != '未设置' && videoPath.isNotEmpty) {
        // 使用视频保存路径
        savePath = videoPath;
        debugPrint('📁 使用视频保存路径: $savePath');
      } else {
        debugPrint('⚠️ 未设置保存路径，使用在线 URL');
        return videoUrl;
      }
      
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
        debugPrint('✅ 创建目录: $savePath');
      }
      
      // 重试最多3次下载视频
      for (var retry = 0; retry < 3; retry++) {
        try {
          final response = await http.get(
            Uri.parse(videoUrl),
            headers: {'Connection': 'keep-alive'},
          ).timeout(const Duration(seconds: 120));  // 视频较大，超时时间longer
          
          if (response.statusCode == 200) {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = '${prefix}_$timestamp.mp4';
            final filePath = path.join(savePath, fileName);
            
            final file = File(filePath);
            await file.writeAsBytes(response.bodyBytes);
            
            debugPrint('✅ 视频已保存: $filePath');
            
            // ✅ 提取视频首帧
            try {
              debugPrint('📸 开始提取视频首帧...');
              final ffmpegService = FFmpegService();
              final thumbnailPath = filePath.replaceAll('.mp4', '.jpg');
              debugPrint('   视频路径: $filePath');
              debugPrint('   首帧路径: $thumbnailPath');
              
              final success = await ffmpegService.extractFrame(
                videoPath: filePath,
                outputPath: thumbnailPath,
              );
              
              if (success) {
                debugPrint('✅ 视频首帧提取成功: $thumbnailPath');
                // 验证文件是否真的存在
                final thumbnailFile = File(thumbnailPath);
                if (await thumbnailFile.exists()) {
                  final fileSize = await thumbnailFile.length();
                  debugPrint('✅ 首帧文件已确认存在，大小: ${fileSize} 字节');
                } else {
                  debugPrint('⚠️ 首帧文件不存在！');
                }
              } else {
                debugPrint('⚠️ 提取首帧失败: success = false');
              }
            } catch (e, stackTrace) {
              debugPrint('⚠️ 提取首帧失败: $e');
              debugPrint('堆栈: $stackTrace');
            }
            
            return filePath;
          } else {
            debugPrint('⚠️ 下载失败 (重试 $retry/3): HTTP ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('⚠️ 下载异常 (重试 $retry/3): $e');
          if (retry < 2) {
            await Future.delayed(Duration(seconds: (retry + 1) * 2));  // 等待更长时间
          }
        }
      }
      
      debugPrint('❌ 下载失败，使用在线 URL');
      return videoUrl;
    } catch (e) {
      debugPrint('💥 保存视频失败: $e');
      return videoUrl;
    }
  }
}

/// 分镜行数据
class StoryboardRow {
  final String id;
  final String scriptSegment;           // ✅ 剧本片段文本
  final int startIndex;                 // ✅ 在原剧本中的起始位置
  final int endIndex;                   // ✅ 在原剧本中的结束位置
  final bool isUserCreated;             // ✅ 是否用户手动创建
  final String imagePrompt;
  final String videoPrompt;
  final List<String> imageUrls;         // 多个图片URL（最多4个）
  final List<String> videoUrls;         // 多个视频URL（最多4个）
  final int selectedImageIndex;         // 选中的图片索引
  final List<String> selectedImageAssets;
  final List<String> selectedVideoAssets;
  
  // ✅ 语音合成相关字段
  final List<VoiceDialogue> voiceDialogues;  // 对话列表
  final String? generatedAudioPath;          // 生成的配音路径
  final double voiceStartTime;               // 配音起始时间（秒）
  final bool hasVoice;                       // 是否已生成配音
  
  // ✅ 配音向导状态（用于恢复）
  final int voiceWizardStep;                 // 向导当前步骤 (0-2)
  final int currentDialogueIndex;            // 当前正在配音的对话索引
  final String? dialogueAudioMapJson;        // 对话音频映射（JSON格式：{dialogueId: audioPath}）
  final int selectedVideoIndex;              // 选中的视频索引（用于语音合成）

  StoryboardRow({
    required this.id,
    this.scriptSegment = '',             // ✅ 默认空
    this.startIndex = -1,                // ✅ -1 表示未定位
    this.endIndex = -1,
    this.isUserCreated = false,
    required this.imagePrompt,
    required this.videoPrompt,
    this.imageUrls = const [],
    this.videoUrls = const [],
    this.selectedImageIndex = 0,
    this.selectedImageAssets = const [],
    this.selectedVideoAssets = const [],
    this.voiceDialogues = const [],      // ✅ 默认空对话列表
    this.generatedAudioPath,             // ✅ 默认无配音
    this.voiceStartTime = 0.0,           // ✅ 默认从0秒开始
    this.hasVoice = false,               // ✅ 默认未生成
    this.voiceWizardStep = 0,            // ✅ 默认第一步
    this.currentDialogueIndex = 0,       // ✅ 默认第一个对话
    this.dialogueAudioMapJson,           // ✅ 默认无音频
    this.selectedVideoIndex = 0,         // ✅ 默认选择第一个视频
  });

  // 兼容旧数据
  String? get imageUrl => imageUrls.isNotEmpty ? imageUrls[selectedImageIndex] : null;
  String? get videoUrl => videoUrls.isNotEmpty ? videoUrls.first : null;

  StoryboardRow copyWith({
    String? scriptSegment,
    int? startIndex,
    int? endIndex,
    bool? isUserCreated,
    String? imagePrompt,
    String? videoPrompt,
    List<String>? imageUrls,
    List<String>? videoUrls,
    int? selectedImageIndex,
    List<String>? selectedImageAssets,
    List<String>? selectedVideoAssets,
    List<VoiceDialogue>? voiceDialogues,
    String? generatedAudioPath,
    double? voiceStartTime,
    bool? hasVoice,
    int? voiceWizardStep,
    int? currentDialogueIndex,
    String? dialogueAudioMapJson,
    int? selectedVideoIndex,
  }) {
    return StoryboardRow(
      id: id,
      scriptSegment: scriptSegment ?? this.scriptSegment,
      startIndex: startIndex ?? this.startIndex,
      endIndex: endIndex ?? this.endIndex,
      isUserCreated: isUserCreated ?? this.isUserCreated,
      imagePrompt: imagePrompt ?? this.imagePrompt,
      videoPrompt: videoPrompt ?? this.videoPrompt,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      selectedImageIndex: selectedImageIndex ?? this.selectedImageIndex,
      selectedImageAssets: selectedImageAssets ?? this.selectedImageAssets,
      selectedVideoAssets: selectedVideoAssets ?? this.selectedVideoAssets,
      voiceDialogues: voiceDialogues ?? this.voiceDialogues,
      generatedAudioPath: generatedAudioPath ?? this.generatedAudioPath,
      voiceStartTime: voiceStartTime ?? this.voiceStartTime,
      hasVoice: hasVoice ?? this.hasVoice,
      voiceWizardStep: voiceWizardStep ?? this.voiceWizardStep,
      currentDialogueIndex: currentDialogueIndex ?? this.currentDialogueIndex,
      dialogueAudioMapJson: dialogueAudioMapJson ?? this.dialogueAudioMapJson,
      selectedVideoIndex: selectedVideoIndex ?? this.selectedVideoIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scriptSegment': scriptSegment,
        'startIndex': startIndex,
        'endIndex': endIndex,
        'isUserCreated': isUserCreated,
        'imagePrompt': imagePrompt,
        'videoPrompt': videoPrompt,
        'imageUrls': imageUrls,
        'videoUrls': videoUrls,
        'selectedImageIndex': selectedImageIndex,
        'selectedImageAssets': selectedImageAssets,
        'selectedVideoAssets': selectedVideoAssets,
        'voiceDialogues': voiceDialogues.map((d) => d.toJson()).toList(),
        'generatedAudioPath': generatedAudioPath,
        'voiceStartTime': voiceStartTime,
        'hasVoice': hasVoice,
        'voiceWizardStep': voiceWizardStep,
        'currentDialogueIndex': currentDialogueIndex,
        'dialogueAudioMapJson': dialogueAudioMapJson,
        'selectedVideoIndex': selectedVideoIndex,
      };

  factory StoryboardRow.fromJson(Map<String, dynamic> json) {
    return StoryboardRow(
      id: json['id'] as String,
      scriptSegment: json['scriptSegment'] as String? ?? '',  // ✅ 兼容旧数据
      startIndex: json['startIndex'] as int? ?? -1,
      endIndex: json['endIndex'] as int? ?? -1,
      isUserCreated: json['isUserCreated'] as bool? ?? false,
      imagePrompt: json['imagePrompt'] as String,
      videoPrompt: json['videoPrompt'] as String,
      imageUrls: (json['imageUrls'] as List<dynamic>?)?.cast<String>() ?? 
                 (json['imageUrl'] != null ? [json['imageUrl'] as String] : []),  // 兼容旧数据
      videoUrls: (json['videoUrls'] as List<dynamic>?)?.cast<String>() ?? 
                 (json['videoUrl'] != null ? [json['videoUrl'] as String] : []),  // 兼容旧数据
      selectedImageIndex: json['selectedImageIndex'] as int? ?? 0,
      selectedImageAssets: (json['selectedImageAssets'] as List<dynamic>?)?.cast<String>() ?? [],
      selectedVideoAssets: (json['selectedVideoAssets'] as List<dynamic>?)?.cast<String>() ?? [],
      voiceDialogues: (json['voiceDialogues'] as List<dynamic>?)
          ?.map((d) => VoiceDialogue.fromJson(d as Map<String, dynamic>))
          .toList() ?? [],
      generatedAudioPath: json['generatedAudioPath'] as String?,
      voiceStartTime: (json['voiceStartTime'] as num?)?.toDouble() ?? 0.0,
      hasVoice: json['hasVoice'] as bool? ?? false,
      voiceWizardStep: json['voiceWizardStep'] as int? ?? 0,
      currentDialogueIndex: json['currentDialogueIndex'] as int? ?? 0,
      dialogueAudioMapJson: json['dialogueAudioMapJson'] as String?,
      selectedVideoIndex: json['selectedVideoIndex'] as int? ?? 0,
    );
  }
}

/// 资产引用
class AssetReference {
  final String id;
  final String name;
  final String? imageUrl;
  final String? mappingCode;  // ✅ 上传后的映射代码
  final AssetType type;

  AssetReference({
    required this.id,
    required this.name,
    this.imageUrl,
    this.mappingCode,
    required this.type,
  });
}

enum AssetType {
  character,
  scene,
  item,
}

/// 语音对话数据模型
class VoiceDialogue {
  final String id;
  final String character;     // 角色名称
  final String emotion;       // 情感（开心、悲伤等）
  final String dialogue;      // 台词内容

  VoiceDialogue({
    required this.id,
    required this.character,
    required this.emotion,
    required this.dialogue,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'character': character,
    'emotion': emotion,
    'dialogue': dialogue,
  };

  factory VoiceDialogue.fromJson(Map<String, dynamic> json) {
    return VoiceDialogue(
      id: json['id'] as String,
      character: json['character'] as String,
      emotion: json['emotion'] as String,
      dialogue: json['dialogue'] as String,
    );
  }

  VoiceDialogue copyWith({
    String? character,
    String? emotion,
    String? dialogue,
  }) {
    return VoiceDialogue(
      id: id,
      character: character ?? this.character,
      emotion: emotion ?? this.emotion,
      dialogue: dialogue ?? this.dialogue,
    );
  }
}

