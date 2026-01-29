import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

/// 素材库选择对话框
class AssetLibrarySelector extends StatefulWidget {
  final AssetCategory category;  // 素材分类（角色/场景/物品）

  const AssetLibrarySelector({
    super.key,
    required this.category,
  });

  @override
  State<AssetLibrarySelector> createState() => _AssetLibrarySelectorState();
}

class _AssetLibrarySelectorState extends State<AssetLibrarySelector> {
  List<AssetStyle> _styles = [];
  int _selectedStyleIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  /// 加载素材
  Future<void> _loadAssets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assetsJson = prefs.getString('asset_library_data');
      
      if (assetsJson != null && assetsJson.isNotEmpty) {
        final data = jsonDecode(assetsJson) as Map<String, dynamic>;
        final categoryIndex = widget.category.index;
        final categoryKey = categoryIndex.toString();
        
        if (data.containsKey(categoryKey)) {
          final stylesList = data[categoryKey] as List<dynamic>;
          if (mounted) {
            setState(() {
              _styles = stylesList
                  .map((e) => AssetStyle.fromJson(e as Map<String, dynamic>))
                  .toList();
            });
            debugPrint('✅ 加载${widget.category.displayName}素材: ${_styles.length}个风格');
          }
        } else {
          debugPrint('⚠️ 未找到${widget.category.displayName}素材数据');
        }
      } else {
        debugPrint('⚠️ 素材库数据为空');
      }
    } catch (e) {
      debugPrint('❌ 加载素材失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E20),
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(
                  widget.category == AssetCategory.character
                      ? Icons.person
                      : widget.category == AssetCategory.scene
                          ? Icons.landscape
                          : Icons.category,
                  color: const Color(0xFF888888),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '${widget.category.displayName}素材库',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 风格选择
            if (_styles.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _styles.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedStyleIndex == index;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: OutlinedButton(
                        onPressed: () => setState(() => _selectedStyleIndex = index),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isSelected ? Colors.white : const Color(0xFF888888),
                          backgroundColor: isSelected ? const Color(0xFF3A3A3C) : Colors.transparent,
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF888888) : const Color(0xFF3A3A3C),
                          ),
                        ),
                        child: Text(_styles[index].name),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            // 素材网格
            Expanded(
              child: _buildAssetGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetGrid() {
    try {
      if (_styles.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_outlined,
                size: 80,
                color: Colors.white.withOpacity( 0.1),
              ),
              const SizedBox(height: 16),
              Text(
                '${widget.category.displayName}素材库为空',
                style: const TextStyle(color: Color(0xFF666666), fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                '请在素材库页面添加素材',
                style: TextStyle(color: Color(0xFF555555), fontSize: 13),
              ),
            ],
          ),
        );
      }

      if (_selectedStyleIndex >= _styles.length) {
        _selectedStyleIndex = 0;
      }

      final currentStyle = _styles[_selectedStyleIndex];
      if (currentStyle.assets.isEmpty) {
        return const Center(
          child: Text(
            '当前风格没有素材',
            style: TextStyle(color: Color(0xFF666666)),
          ),
        );
      }

      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: currentStyle.assets.length,
        itemBuilder: (context, index) {
          try {
            final asset = currentStyle.assets[index];
            return _buildAssetCard(asset);
          } catch (e) {
            debugPrint('构建素材卡片失败: $e');
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF252629),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.error, color: Color(0xFF666666)),
              ),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('构建素材网格失败: $e');
      return Center(
        child: Text(
          '加载素材失败: $e',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
  }

  Widget _buildAssetCard(AssetItem asset) {
    return GestureDetector(
      onTap: () {
        try {
          Navigator.pop(context, asset.path);
        } catch (e) {
          debugPrint('选择素材失败: $e');
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF252629),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3A3A3C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 图片预览
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                child: _buildImagePreview(asset.path),
              ),
            ),
            // 素材名称
            Container(
              padding: const EdgeInsets.all(8),
              child: Text(
                asset.name,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建图片预览（安全版本）
  Widget _buildImagePreview(String imagePath) {
    try {
      final file = File(imagePath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorPlaceholder();
          },
        );
      } else {
        return _buildErrorPlaceholder();
      }
    } catch (e) {
      debugPrint('图片加载失败: $imagePath, 错误: $e');
      return _buildErrorPlaceholder();
    }
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A1C),
      child: const Center(
        child: Icon(
          Icons.image_not_supported,
          color: Color(0xFF666666),
          size: 32,
        ),
      ),
    );
  }
}

/// 素材分类枚举
enum AssetCategory {
  character,  // 角色
  scene,      // 场景
  item,       // 物品
}

extension AssetCategoryExt on AssetCategory {
  String get displayName {
    switch (this) {
      case AssetCategory.character:
        return '角色';
      case AssetCategory.scene:
        return '场景';
      case AssetCategory.item:
        return '物品';
    }
  }
}

/// 风格数据模型（从素材库复制）
class AssetStyle {
  final String name;
  final String description;
  final List<AssetItem> assets;

  AssetStyle({
    required this.name,
    this.description = '',
    List<AssetItem>? assets,
  }) : assets = assets ?? [];

  factory AssetStyle.fromJson(Map<String, dynamic> json) {
    return AssetStyle(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      assets: (json['assets'] as List<dynamic>?)
              ?.map((e) => AssetItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'assets': assets.map((e) => e.toJson()).toList(),
    };
  }
}

/// 素材项数据模型（从素材库复制）
class AssetItem {
  final String path;
  final String name;
  bool isUploaded;
  bool isUploading;
  String? uploadedId;
  String? characterInfo;
  String? videoUrl;

  AssetItem({
    required this.path,
    required this.name,
    this.isUploaded = false,
    this.isUploading = false,
    this.uploadedId,
    this.characterInfo,
    this.videoUrl,
  });

  factory AssetItem.fromJson(Map<String, dynamic> json) {
    return AssetItem(
      path: json['path'] as String,
      name: json['name'] as String,
      isUploaded: json['isUploaded'] as bool? ?? false,
      isUploading: json['isUploading'] as bool? ?? false,
      uploadedId: json['uploadedId'] as String?,
      characterInfo: json['characterInfo'] as String?,
      videoUrl: json['videoUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'isUploaded': isUploaded,
      'isUploading': isUploading,
      'uploadedId': uploadedId,
      'characterInfo': characterInfo,
      'videoUrl': videoUrl,
    };
  }
}
