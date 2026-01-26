import 'package:flutter/material.dart';
import 'package:xinghe_new/main.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class AssetLibrary extends StatefulWidget {
  const AssetLibrary({super.key});

  @override
  State<AssetLibrary> createState() => _AssetLibraryState();
}

class _AssetLibraryState extends State<AssetLibrary> {
  int _selectedCategoryIndex = 0; // 0:角色 1:场景 2:物品
  final List<String> _categories = ['角色素材', '场景素材', '物品素材'];
  final List<IconData> _categoryIcons = [
    Icons.person_outline,
    Icons.landscape_outlined,
    Icons.inventory_2_outlined,
  ];

  // 每个分类的风格列表
  final Map<int, List<AssetStyle>> _stylesByCategory = {
    0: [AssetStyle(name: '仙侠风格', description: '修仙玄幻仙气')],
    1: [AssetStyle(name: '都市风格', description: '现代都市生活')],
    2: [AssetStyle(name: '古风物品', description: '古风东方韵味')],
  };

  int _selectedStyleIndex = 0;
  bool _isAddingStyle = false;
  final TextEditingController _styleNameController = TextEditingController();
  final TextEditingController _styleDescController = TextEditingController();

  @override
  void dispose() {
    _styleNameController.dispose();
    _styleDescController.dispose();
    super.dispose();
  }

  // 添加新风格
  void _addNewStyle() {
    if (_styleNameController.text.trim().isEmpty) {
      _showMessage('请输入风格名称', isError: true);
      return;
    }

    setState(() {
      _stylesByCategory[_selectedCategoryIndex]!.add(
        AssetStyle(
          name: _styleNameController.text.trim(),
          description: _styleDescController.text.trim(),
        ),
      );
      _styleNameController.clear();
      _styleDescController.clear();
      _isAddingStyle = false;
    });

    _showMessage('风格添加成功', isError: false);
  }

  // 添加素材到当前风格
  Future<void> _addAssets() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        dialogTitle: '选择素材图片',
      );

      if (result != null) {
        setState(() {
          final currentStyle = _stylesByCategory[_selectedCategoryIndex]![_selectedStyleIndex];
          for (var file in result.files) {
            if (file.path != null) {
              currentStyle.assets.add(
                AssetItem(
                  path: file.path!,
                  name: file.name,
                  isUploaded: false,
                ),
              );
            }
          }
        });
        _showMessage('成功添加 ${result.files.length} 个素材', isError: false);
      }
    } catch (e) {
      _showMessage('添加素材失败: $e', isError: true);
    }
  }

  // 上传素材
  Future<void> _uploadAsset(AssetItem asset) async {
    setState(() => asset.isUploading = true);

    try {
      // TODO: 实际调用上传API
      await Future.delayed(const Duration(seconds: 2));
      
      setState(() {
        asset.isUploaded = true;
        asset.uploadedId = 'char_${DateTime.now().millisecondsSinceEpoch}';
        asset.isUploading = false;
      });
      
      _showMessage('上传成功', isError: false);
    } catch (e) {
      setState(() => asset.isUploading = false);
      _showMessage('上传失败: $e', isError: true);
    }
  }

  // 删除素材
  void _deleteAsset(int index) {
    setState(() {
      _stylesByCategory[_selectedCategoryIndex]![_selectedStyleIndex].assets.removeAt(index);
    });
    _showMessage('素材已删除', isError: false);
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF2AF598),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, themeIndex, _) {
        return Container(
          color: AppTheme.scaffoldBackground,
          child: Column(
            children: [
              // 顶部分类Tab
              _buildTopCategories(),
              
              Expanded(
                child: Row(
                  children: [
                    // 左侧风格列表
                    _buildStyleList(),
                    
                    VerticalDivider(width: 1, color: AppTheme.dividerColor),
                    
                    // 右侧素材展示区
                    Expanded(child: _buildAssetGrid()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 顶部分类Tab
  Widget _buildTopCategories() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: List.generate(_categories.length, (index) {
          final isSelected = _selectedCategoryIndex == index;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategoryIndex = index;
                  _selectedStyleIndex = 0;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)])
                      : null,
                  color: isSelected ? null : AppTheme.inputBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _categoryIcons[index],
                      color: isSelected ? Colors.white : AppTheme.textColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _categories[index],
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textColor,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // 左侧风格列表
  Widget _buildStyleList() {
    final styles = _stylesByCategory[_selectedCategoryIndex] ?? [];
    
    return Container(
      width: 280,
      color: AppTheme.scaffoldBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 风格分类标题和添加按钮
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  '风格分类',
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _isAddingStyle = !_isAddingStyle),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AF598).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        _isAddingStyle ? Icons.close : Icons.add,
                        color: const Color(0xFF2AF598),
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 添加风格表单
          if (_isAddingStyle) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('风格名称', style: TextStyle(color: AppTheme.subTextColor, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _styleNameController,
                    style: TextStyle(color: AppTheme.textColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '例如: 赛博朋克',
                      hintStyle: TextStyle(color: AppTheme.subTextColor.withOpacity(0.5)),
                      filled: true,
                      fillColor: AppTheme.inputBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('描述', style: TextStyle(color: AppTheme.subTextColor, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _styleDescController,
                    style: TextStyle(color: AppTheme.textColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '可选',
                      hintStyle: TextStyle(color: AppTheme.subTextColor.withOpacity(0.5)),
                      filled: true,
                      fillColor: AppTheme.inputBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _addNewStyle,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text('添加风格', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // 风格列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: styles.length,
              itemBuilder: (context, index) {
                final style = styles[index];
                final isSelected = _selectedStyleIndex == index;
                
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedStyleIndex = index),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.sideBarItemHover : AppTheme.surfaceBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF2AF598).withOpacity(0.3) : AppTheme.dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF2AF598) : AppTheme.subTextColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  style.name,
                                  style: TextStyle(
                                    color: AppTheme.textColor,
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (style.description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              style.description,
                              style: TextStyle(color: AppTheme.subTextColor, fontSize: 11),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '${style.assets.length} 个素材',
                            style: TextStyle(color: AppTheme.subTextColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 右侧素材网格展示
  Widget _buildAssetGrid() {
    final styles = _stylesByCategory[_selectedCategoryIndex] ?? [];
    if (styles.isEmpty) {
      return Center(
        child: Text('请先添加风格分类', style: TextStyle(color: AppTheme.subTextColor)),
      );
    }
    
    final currentStyle = styles[_selectedStyleIndex];
    
    return Container(
      color: AppTheme.scaffoldBackground,
      child: Column(
        children: [
          // 顶部操作栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Text(
                  '${currentStyle.name} (${currentStyle.assets.length})',
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _addAssets,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.add, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('添加', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 素材网格
          Expanded(
            child: currentStyle.assets.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_outlined, color: AppTheme.subTextColor.withOpacity(0.3), size: 64),
                        const SizedBox(height: 16),
                        Text('暂无素材', style: TextStyle(color: AppTheme.subTextColor)),
                        const SizedBox(height: 8),
                        Text('点击右上角"添加"按钮添加素材', style: TextStyle(color: AppTheme.subTextColor.withOpacity(0.7), fontSize: 12)),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: currentStyle.assets.length,
                    itemBuilder: (context, index) {
                      return _buildAssetCard(currentStyle.assets[index], index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // 素材卡片
  Widget _buildAssetCard(AssetItem asset, int index) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图片预览
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Image.file(
                    File(asset.path),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: AppTheme.inputBackground,
                        child: Center(
                          child: Icon(Icons.broken_image, color: AppTheme.subTextColor, size: 40),
                        ),
                      );
                    },
                  ),
                ),
                // 已上传标识
                if (asset.isUploaded)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AF598),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.check, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text('已上传', style: TextStyle(color: Colors.white, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                // 删除按钮
                Positioned(
                  top: 8,
                  right: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _deleteAsset(index),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 信息和操作区
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 文件名/ID
                Text(
                  asset.isUploaded ? asset.uploadedId! : asset.name,
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                
                // 上传按钮
                if (!asset.isUploaded)
                  SizedBox(
                    width: double.infinity,
                    child: MouseRegion(
                      cursor: asset.isUploading ? SystemMouseCursors.wait : SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: asset.isUploading ? null : () => _uploadAsset(asset),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.textColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: asset.isUploading
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.cloud_upload_outlined, color: AppTheme.accentColor, size: 14),
                                      const SizedBox(width: 4),
                                      Text('上传', style: TextStyle(color: AppTheme.accentColor, fontSize: 11)),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 风格数据模型
class AssetStyle {
  final String name;
  final String description;
  final List<AssetItem> assets;

  AssetStyle({
    required this.name,
    this.description = '',
    List<AssetItem>? assets,
  }) : assets = assets ?? [];
}

// 素材项数据模型
class AssetItem {
  final String path;
  final String name;
  bool isUploaded;
  bool isUploading;
  String? uploadedId;

  AssetItem({
    required this.path,
    required this.name,
    this.isUploaded = false,
    this.isUploading = false,
    this.uploadedId,
  });
}
