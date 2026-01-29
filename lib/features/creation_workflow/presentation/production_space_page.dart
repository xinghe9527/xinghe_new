import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'dart:convert';
import 'widgets/custom_title_bar.dart';
import 'storyboard_prompt_manager.dart';

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
  bool _showSettings = false;
  List<StoryboardRow> _storyboards = [];
  bool _isGenerating = false;
  
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
          const Spacer(),
          // 分镜提示词按钮（小书图标）
          IconButton(
            onPressed: _openStoryboardPromptManager,
            icon: const Icon(Icons.menu_book, size: 20),
            color: const Color(0xFF888888),
            tooltip: '分镜提示词',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF3A3A3C).withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _isGenerating ? null : _generateStoryboards,
            icon: _isGenerating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF888888)),
                    ),
                  )
                : const Icon(Icons.auto_awesome, size: 16),
            label: Text(_isGenerating ? '生成中...' : '生成分镜'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF888888),
              side: const BorderSide(color: Color(0xFF3A3A3C)),
            ),
          ),
        ],
      ),
    );
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
          Icon(Icons.movie_outlined, size: 80, color: Colors.white.withValues(alpha: 0.1)),
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
            color: Colors.black.withValues(alpha: 0.3),
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
          // 4列内容
          IntrinsicHeight(
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
                  backgroundColor: const Color(0xFF3A3A3C).withValues(alpha: 0.3),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 提示词文本框
          TextField(
            controller: TextEditingController(text: row.imagePrompt),
            maxLines: 8,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
              filled: true,
              fillColor: Color(0xFF252629),
            ),
            onChanged: (value) {
              _storyboards[index] = row.copyWith(imagePrompt: value);
              _saveProductionData();
            },
          ),
        ],
      ),
    );
  }

  /// 列2：图片生成区
  Widget _buildImageGenerationColumn(StoryboardRow row, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF3A3A3C), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '图片生成区',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // 生成按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _generateImage(index),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('生成图片'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF888888),
                side: const BorderSide(color: Color(0xFF3A3A3C)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 资产标签
          const Text(
            '参考资产',
            style: TextStyle(color: Color(0xFF666666), fontSize: 11),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _buildAssetTags(row.imagePrompt, row.selectedImageAssets, (assets) {
              _storyboards[index] = row.copyWith(selectedImageAssets: assets);
              _saveProductionData();
            }),
          ),
          const SizedBox(height: 16),
          // 图片预览
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1C),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3A3A3C)),
              ),
              child: row.imageUrl != null && row.imageUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        row.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '待生成',
                            style: TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
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
                  backgroundColor: const Color(0xFF3A3A3C).withValues(alpha: 0.3),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 提示词文本框
          TextField(
            controller: TextEditingController(text: row.videoPrompt),
            maxLines: 8,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
              filled: true,
              fillColor: Color(0xFF252629),
            ),
            onChanged: (value) {
              _storyboards[index] = row.copyWith(videoPrompt: value);
              _saveProductionData();
            },
          ),
        ],
      ),
    );
  }

  /// 列4：视频生成区
  Widget _buildVideoGenerationColumn(StoryboardRow row, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '视频生成区',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // 生成按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: row.imageUrl != null ? () => _generateVideo(index) : null,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('生成视频'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF888888),
                side: const BorderSide(color: Color(0xFF3A3A3C)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 资产标签
          const Text(
            '参考资产',
            style: TextStyle(color: Color(0xFF666666), fontSize: 11),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _buildAssetTags(row.videoPrompt, row.selectedVideoAssets, (assets) {
              _storyboards[index] = row.copyWith(selectedVideoAssets: assets);
              _saveProductionData();
            }),
          ),
          const SizedBox(height: 16),
          // 视频预览
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1C),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3A3A3C)),
              ),
              child: row.videoUrl != null && row.videoUrl!.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.play_circle_outline,
                            size: 56,
                            color: Color(0xFF888888),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            row.videoUrl!,
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_outlined,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '待生成',
                            style: TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
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
              ? const Color(0xFF3A3A3C)
              : const Color(0xFF2A2A2C),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF888888)
                : const Color(0xFF3A3A3C),
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
        ),
        StoryboardRow(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          imagePrompt: '地下工作室内，主角操作全息屏幕，多个屏幕显示代码和数据流',
          videoPrompt: '主角手指快速滑动，屏幕数据流动，镜头特写手部动作，紧张氛围',
        ),
        StoryboardRow(
          id: (DateTime.now().millisecondsSinceEpoch + 2).toString(),
          imagePrompt: '城市街道，主角匆忙穿行，霓虹灯光影交错，背景有飞行摩托',
          videoPrompt: '追逐镜头，快速移动，光影闪烁，动感强烈，第一人称视角',
        ),
      ];

      if (mounted) {
        setState(() {
          _storyboards = mockStoryboards;
        });
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
    
    // TODO: 调用图片生成API
    // 输入：图片提示词 + 选中的角色/场景/物品的图片
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _storyboards[index] = row.copyWith(
          imageUrl: 'https://picsum.photos/seed/${row.id}/800/450',
        );
      });
      await _saveProductionData();
    }
  }

  /// 生成视频
  Future<void> _generateVideo(int index) async {
    final row = _storyboards[index];
    
    // TODO: 调用视频生成API
    // 输入：视频提示词 + 生成的图片 + 选中的资产图片
    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      setState(() {
        _storyboards[index] = row.copyWith(
          videoUrl: 'video_${row.id}.mp4',
        );
      });
      await _saveProductionData();
    }
  }
}

/// 分镜行数据
class StoryboardRow {
  final String id;
  final String imagePrompt;
  final String videoPrompt;
  final String? imageUrl;
  final String? videoUrl;
  final List<String> selectedImageAssets;
  final List<String> selectedVideoAssets;

  StoryboardRow({
    required this.id,
    required this.imagePrompt,
    required this.videoPrompt,
    this.imageUrl,
    this.videoUrl,
    this.selectedImageAssets = const [],
    this.selectedVideoAssets = const [],
  });

  StoryboardRow copyWith({
    String? imagePrompt,
    String? videoPrompt,
    String? imageUrl,
    String? videoUrl,
    List<String>? selectedImageAssets,
    List<String>? selectedVideoAssets,
  }) {
    return StoryboardRow(
      id: id,
      imagePrompt: imagePrompt ?? this.imagePrompt,
      videoPrompt: videoPrompt ?? this.videoPrompt,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      selectedImageAssets: selectedImageAssets ?? this.selectedImageAssets,
      selectedVideoAssets: selectedVideoAssets ?? this.selectedVideoAssets,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePrompt': imagePrompt,
        'videoPrompt': videoPrompt,
        'imageUrl': imageUrl,
        'videoUrl': videoUrl,
        'selectedImageAssets': selectedImageAssets,
        'selectedVideoAssets': selectedVideoAssets,
      };

  factory StoryboardRow.fromJson(Map<String, dynamic> json) {
    return StoryboardRow(
      id: json['id'] as String,
      imagePrompt: json['imagePrompt'] as String,
      videoPrompt: json['videoPrompt'] as String,
      imageUrl: json['imageUrl'] as String?,
      videoUrl: json['videoUrl'] as String?,
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
