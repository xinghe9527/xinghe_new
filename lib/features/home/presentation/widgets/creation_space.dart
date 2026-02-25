import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../../../../main.dart';  // ✅ 导入主题管理
import '../../../creation_workflow/presentation/creation_mode_selector.dart';
import '../../../creation_workflow/presentation/workspace_page.dart';
import '../../../creation_workflow/presentation/story_input_page.dart';  // ✅ 导入故事输入页

class CreationSpace extends StatefulWidget {
  const CreationSpace({super.key});

  @override
  State<CreationSpace> createState() => _CreationSpaceState();
}

class _CreationSpaceState extends State<CreationSpace> {
  final List<Work> _works = [];  // 作品列表（初始为空）
  String? _defaultCoverImage;  // 全局默认封面

  @override
  void initState() {
    super.initState();
    _loadWorks();  // 启动时加载作品
    _loadDefaultCover();  // 加载默认封面
  }

  /// 加载默认封面
  Future<void> _loadDefaultCover() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final coverPath = prefs.getString('default_work_cover');
      if (coverPath != null && coverPath.isNotEmpty) {
        setState(() {
          _defaultCoverImage = coverPath;
        });
        debugPrint('✅ 加载默认封面: $coverPath');
      }
    } catch (e) {
      debugPrint('⚠️ 加载默认封面失败: $e');
    }
  }

  /// 设置默认封面
  Future<void> _setDefaultCover() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final imagePath = result.files.first.path!;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('default_work_cover', imagePath);
        
        setState(() {
          _defaultCoverImage = imagePath;
        });
        
        debugPrint('✅ 设置默认封面: $imagePath');
      }
    } catch (e) {
      debugPrint('⚠️ 设置默认封面失败: $e');
    }
  }

  /// 加载保存的作品
  Future<void> _loadWorks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final worksJson = prefs.getString('creation_works');
      
      if (worksJson != null && worksJson.isNotEmpty) {
        final worksList = jsonDecode(worksJson) as List;
        setState(() {
          _works.clear();
          _works.addAll(worksList.map((json) => Work.fromJson(json)).toList());
        });
        debugPrint('✅ 加载 ${_works.length} 个作品');
      }
    } catch (e) {
      debugPrint('⚠️ 加载作品失败: $e');
    }
  }

  /// 保存作品到本地存储
  Future<void> _saveWorks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('creation_works', jsonEncode(_works.map((w) => w.toJson()).toList()));
      debugPrint('✅ 保存 ${_works.length} 个作品');
    } catch (e) {
      debugPrint('⚠️ 保存作品失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, theme, child) {
        return Container(
          color: AppTheme.scaffoldBackground,  // ✅ 使用主题背景色
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一部分：顶部 Hero 横幅（紧贴标题栏）
              _buildHeroBanner(),
              
              // 第二部分：作品画廊区域（可滚动）
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: _buildGallerySection(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 顶部 Hero 横幅
  Widget _buildHeroBanner() {
    return Transform.translate(
      offset: const Offset(0, 0),  // 先恢复到自然位置，不上移
      child: SizedBox(
        height: 340,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. 本地图片资源
            Image.asset(
              'assets/images/banner_creation.jpg',
              fit: BoxFit.cover,
            ),
            // 2. 底部渐变遮罩 (让图片和下方背景自然融合)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppTheme.scaffoldBackground, // ✅ 使用主题背景色
                  ],
                  stops: const [0.6, 1.0], // 图片下半部分开始渐变
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 作品画廊区域
  Widget _buildGallerySection() {
    return Container(
      color: AppTheme.scaffoldBackground,  // ✅ 使用主题背景色
      child: Column(
        children: [
          // A. 画廊标题栏与操作区
          _buildGalleryHeader(),
          
          // B. 作品网格
          _buildWorksGrid(),
        ],
      ),
    );
  }

  /// 画廊标题栏与操作区
  Widget _buildGalleryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),  // 顶部改为20px，与其他空间保持一致
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧：标题 + 默认封面设置按钮
          Row(
            children: [
              const Text(
                '我的作品集',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              // 默认封面设置按钮（只显示图标，灰色）
              Tooltip(
                message: '切换封面',
                waitDuration: const Duration(milliseconds: 500),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _setDefaultCover,
                    child: Container(
                      padding: const EdgeInsets.all(4),  // 从 6 缩小到 4
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),  // 统一灰色
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),  // 统一灰色
                        ),
                      ),
                      child: Icon(
                        Icons.photo_library_outlined,
                        size: 12,  // 从 16 缩小到 12
                        color: Colors.white.withOpacity(0.5),  // 统一灰色
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // 右侧：创建作品按钮（青蓝渐变机甲风格）
          _buildNewWorkButton(),
        ],
      ),
    );
  }

  /// 创建作品按钮（紧凑型机甲风格）
  Widget _buildNewWorkButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _createNewWork,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2AF598).withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.auto_awesome, color: Colors.white, size: 18),  // 星星图标，和封面统一
              SizedBox(width: 6),
              Text(
                '创建作品',
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
    );
  }

  /// 创建新作品 - 先命名再选择方式
  Future<void> _createNewWork() async {
    // 1. 弹出输入框，让用户输入作品名称和选择继承源
    final result = await _showWorkNameDialog();
    if (result == null) return;
    
    final workName = result['name'] as String;
    final sourceWorkId = result['sourceWorkId'] as String?;
    
    if (workName.isEmpty) return;

    // 2. 立即创建作品并添加到列表
    final workId = DateTime.now().millisecondsSinceEpoch.toString();
    final newWork = Work(
      id: workId,
      title: workName,
      createdAt: DateTime.now(),
      coverImage: _defaultCoverImage,
    );
    
    if (!mounted) return;
    setState(() {
      _works.add(newWork);
    });
    await _saveWorks();
    debugPrint('✅ 创建新作品：$workName (ID: $workId)');
    
    // 3. 如果选择了继承源，复制资产
    if (sourceWorkId != null) {
      await _inheritAssets(sourceWorkId, workId);
    }

    // 4. 打开创作模式选择界面
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreationModeSelector(
          workId: workId,
          workName: workName,
        ),
        fullscreenDialog: true,
      ),
    );
    
    // 5. 返回后重新加载作品列表
    if (mounted) {
      _loadWorks();
    }
  }
  
  /// 继承资产（从源作品复制到新作品）
  Future<void> _inheritAssets(String sourceWorkId, String targetWorkId) async {
    try {
      debugPrint('========== 开始继承资产 ==========');
      debugPrint('源作品ID: $sourceWorkId');
      debugPrint('目标作品ID: $targetWorkId');
      
      final prefs = await SharedPreferences.getInstance();
      
      // 复制角色（注意：key 格式是 characters_{workId}，不是 work_{workId}_characters）
      final charactersKey = 'characters_$sourceWorkId';
      debugPrint('查找角色数据，Key: $charactersKey');
      final charactersJson = prefs.getString(charactersKey);
      debugPrint('角色数据: ${charactersJson != null ? "找到" : "未找到"}');
      
      if (charactersJson != null) {
        final Map<String, dynamic> sourceData = jsonDecode(charactersJson);
        final List<dynamic> sourceList = sourceData['characters'] as List<dynamic>;
        debugPrint('源作品有 ${sourceList.length} 个角色');
        
        final inheritedList = sourceList.asMap().entries.map((entry) {
          final index = entry.key;
          final json = Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
          // 生成新ID，标记为继承
          json['id'] = '${DateTime.now().millisecondsSinceEpoch}_char_$index';
          json['isInherited'] = true;
          json['sourceWorkId'] = sourceWorkId;
          debugPrint('  - 继承角色: ${json['name']}');
          return json;
        }).toList();
        
        final targetKey = 'characters_$targetWorkId';
        final targetData = {
          'characters': inheritedList,
          'selectedPromptName': sourceData['selectedPromptName'] ?? '默认',
          'selectedPromptContent': sourceData['selectedPromptContent'] ?? '',
          'styleReferenceImage': sourceData['styleReferenceImage'],
        };
        await prefs.setString(targetKey, jsonEncode(targetData));
        debugPrint('✅ 继承了 ${inheritedList.length} 个角色到 $targetKey');
      } else {
        debugPrint('⚠️ 源作品没有角色数据');
      }
      
      // 复制场景（key 格式是 scenes_{workId}）
      final scenesKey = 'scenes_$sourceWorkId';
      debugPrint('查找场景数据，Key: $scenesKey');
      final scenesJson = prefs.getString(scenesKey);
      debugPrint('场景数据: ${scenesJson != null ? "找到" : "未找到"}');
      
      if (scenesJson != null) {
        final Map<String, dynamic> sourceData = jsonDecode(scenesJson);
        final List<dynamic> sourceList = sourceData['scenes'] as List<dynamic>;
        debugPrint('源作品有 ${sourceList.length} 个场景');
        
        final inheritedList = sourceList.asMap().entries.map((entry) {
          final index = entry.key;
          final json = Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
          json['id'] = '${DateTime.now().millisecondsSinceEpoch}_scene_$index';
          json['isInherited'] = true;
          json['sourceWorkId'] = sourceWorkId;
          debugPrint('  - 继承场景: ${json['name']}');
          return json;
        }).toList();
        
        final targetKey = 'scenes_$targetWorkId';
        final targetData = {
          'scenes': inheritedList,
          'selectedPromptName': sourceData['selectedPromptName'] ?? '默认',
          'selectedPromptContent': sourceData['selectedPromptContent'] ?? '',
          'styleReferenceImage': sourceData['styleReferenceImage'],
        };
        await prefs.setString(targetKey, jsonEncode(targetData));
        debugPrint('✅ 继承了 ${inheritedList.length} 个场景到 $targetKey');
      } else {
        debugPrint('⚠️ 源作品没有场景数据');
      }
      
      // 复制物品（key 格式是 items_{workId}）
      final itemsKey = 'items_$sourceWorkId';
      debugPrint('查找物品数据，Key: $itemsKey');
      final itemsJson = prefs.getString(itemsKey);
      debugPrint('物品数据: ${itemsJson != null ? "找到" : "未找到"}');
      
      if (itemsJson != null) {
        final Map<String, dynamic> sourceData = jsonDecode(itemsJson);
        final List<dynamic> sourceList = sourceData['items'] as List<dynamic>;
        debugPrint('源作品有 ${sourceList.length} 个物品');
        
        final inheritedList = sourceList.asMap().entries.map((entry) {
          final index = entry.key;
          final json = Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
          json['id'] = '${DateTime.now().millisecondsSinceEpoch}_item_$index';
          json['isInherited'] = true;
          json['sourceWorkId'] = sourceWorkId;
          debugPrint('  - 继承物品: ${json['name']}');
          return json;
        }).toList();
        
        final targetKey = 'items_$targetWorkId';
        final targetData = {
          'items': inheritedList,
          'selectedPromptName': sourceData['selectedPromptName'] ?? '默认',
          'selectedPromptContent': sourceData['selectedPromptContent'] ?? '',
          'styleReferenceImage': sourceData['styleReferenceImage'],
        };
        await prefs.setString(targetKey, jsonEncode(targetData));
        debugPrint('✅ 继承了 ${inheritedList.length} 个物品到 $targetKey');
      } else {
        debugPrint('⚠️ 源作品没有物品数据');
      }
      
      debugPrint('========== 资产继承完成 ==========');
    } catch (e, stackTrace) {
      debugPrint('❌ 资产继承失败: $e');
      debugPrint('堆栈: $stackTrace');
    }
  }

  /// 显示作品命名对话框（带资产继承选项）
  Future<Map<String, dynamic>?> _showWorkNameDialog() async {
    final controller = TextEditingController(text: '作品 ${_works.length + 1}');
    String? selectedSourceWorkId;
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 380,  // ✅ 从480缩小到380
            decoration: BoxDecoration(
              color: AppTheme.surfaceBackground,
              borderRadius: BorderRadius.circular(16),  // ✅ 从20缩小到16
              border: Border.all(
                color: AppTheme.dividerColor,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 24,  // ✅ 从30缩小到24
                  offset: const Offset(0, 8),  // ✅ 从10缩小到8
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题区域
                Container(
                  padding: const EdgeInsets.all(20),  // ✅ 从24缩小到20
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '创建新作品',
                        style: TextStyle(
                          color: AppTheme.textColor,
                          fontSize: 20,  // ✅ 从24缩小到20
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,  // ✅ 从0.5缩小到0.3
                        ),
                      ),
                      const SizedBox(height: 6),  // ✅ 从8缩小到6
                      Text(
                        '开始你的创作之旅',
                        style: TextStyle(
                          color: AppTheme.subTextColor,
                          fontSize: 13,  // ✅ 从14缩小到13
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 分隔线
                Divider(color: AppTheme.dividerColor, height: 1),
                
                // 内容区域
                Padding(
                  padding: const EdgeInsets.all(20),  // ✅ 从24缩小到20
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 作品名称输入
                      Text(
                        '作品名称',
                        style: TextStyle(
                          color: AppTheme.textColor,
                          fontSize: 13,  // ✅ 从14缩小到13
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),  // ✅ 从12缩小到10
                      TextField(
                        controller: controller,
                        autofocus: true,
                        style: TextStyle(color: AppTheme.textColor, fontSize: 14),  // ✅ 从15缩小到14
                        decoration: InputDecoration(
                          hintText: '输入作品名称',
                          hintStyle: TextStyle(color: AppTheme.subTextColor, fontSize: 14),
                          filled: true,
                          fillColor: AppTheme.inputBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),  // ✅ 从12缩小到10
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppTheme.dividerColor,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppTheme.accentColor,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),  // ✅ 从16,14缩小到14,12
                        ),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            Navigator.pop(context, {
                              'name': value.trim(),
                              'sourceWorkId': selectedSourceWorkId,
                            });
                          }
                        },
                      ),
                      
                      const SizedBox(height: 20),  // ✅ 从24缩小到20
                      
                      // 继承资产选项
                      Text(
                        '继承资产（可选）',
                        style: TextStyle(
                          color: AppTheme.textColor,
                          fontSize: 13,  // ✅ 从14缩小到13
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),  // ✅ 从12缩小到10
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.inputBackground,
                          borderRadius: BorderRadius.circular(10),  // ✅ 从12缩小到10
                          border: Border.all(
                            color: AppTheme.dividerColor,
                            width: 1,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: selectedSourceWorkId,
                            isExpanded: true,
                            dropdownColor: AppTheme.surfaceBackground,
                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.subTextColor, size: 20),  // ✅ 从24缩小到20
                            hint: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),  // ✅ 从16缩小到14
                              child: Text(
                                '不继承（从零开始）',
                                style: TextStyle(color: AppTheme.subTextColor, fontSize: 14),  // ✅ 从15缩小到14
                              ),
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: Row(
                                    children: [
                                      Icon(Icons.fiber_new_rounded, size: 16, color: AppTheme.subTextColor),  // ✅ 从18缩小到16
                                      const SizedBox(width: 8),  // ✅ 从10缩小到8
                                      Text(
                                        '不继承（从零开始）',
                                        style: TextStyle(color: AppTheme.textColor, fontSize: 14),  // ✅ 从15缩小到14
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              ..._works.map((work) => DropdownMenuItem<String?>(
                                value: work.id,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.folder_outlined,  // ✅ 使用文件夹图标，和素材库一样
                                        size: 16,
                                        color: AppTheme.subTextColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          work.title,
                                          style: TextStyle(
                                            color: AppTheme.textColor,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedSourceWorkId = value;
                              });
                            },
                          ),
                        ),
                      ),
                      
                      if (selectedSourceWorkId != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.inputBackground,  // ✅ 暗灰色背景
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.dividerColor,  // ✅ 灰色边框
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '将复制所有角色、场景、物品到新作品',
                            style: TextStyle(
                              color: AppTheme.subTextColor,  // ✅ 灰色字体
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // 底部按钮区域
                Container(
                  padding: const EdgeInsets.all(20),  // ✅ 从24缩小到20
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppTheme.dividerColor, width: 1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 取消按钮
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.subTextColor,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),  // ✅ 从24,12缩小到20,10
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),  // ✅ 从10缩小到8
                          ),
                        ),
                        child: const Text('取消', style: TextStyle(fontSize: 14)),  // ✅ 从15缩小到14
                      ),
                      const SizedBox(width: 10),  // ✅ 从12缩小到10
                      // 确定按钮（渐变）
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),  // ✅ 从10缩小到8
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2AF598).withOpacity(0.3),
                              blurRadius: 10,  // ✅ 从12缩小到10
                              offset: const Offset(0, 3),  // ✅ 从4缩小到3
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            final name = controller.text.trim();
                            if (name.isNotEmpty) {
                              Navigator.pop(context, {
                                'name': name,
                                'sourceWorkId': selectedSourceWorkId,
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),  // ✅ 从10缩小到8
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),  // ✅ 从32,12缩小到24,10
                          ),
                          child: const Text('创建作品', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),  // ✅ 从15缩小到14
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 作品网格
  Widget _buildWorksGrid() {
    // 如果没有作品，显示空状态
    if (_works.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 64,
                color: Colors.white.withOpacity(0.1),
              ),
              const SizedBox(height: 16),
              Text(
                '还没有作品',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '点击"创建作品"开始您的创作之旅',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.2),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,  // 从 6 改为 8（再缩小三分之一）
          childAspectRatio: 0.75,
          mainAxisSpacing: 10,  // 间距再缩小
          crossAxisSpacing: 10,
        ),
        itemCount: _works.length,
        itemBuilder: (context, index) {
          return _buildWorkCard(_works[index], index);
        },
      ),
    );
  }

  /// 作品卡片
  Widget _buildWorkCard(Work work, int index) {
    // 获取作品的渐变色（基于索引）
    final gradient = _getGradientForIndex(index);
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openManualMode(work),
        onSecondaryTapDown: (details) => _showWorkContextMenu(context, details, work),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
            ),
          ),
          child: Stack(
            children: [
              // 封面区域（铺满整个卡片）
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: work.coverImage != null
                      // 显示自定义封面图片
                      ? Image.file(
                          File(work.coverImage!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            // 如果图片加载失败，显示渐变
                            return Container(
                              decoration: BoxDecoration(gradient: gradient),
                              child: Center(
                                child: Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white.withOpacity(0.6),
                                  size: 24,
                                ),
                              ),
                            );
                          },
                        )
                      // 显示默认渐变
                      : Container(
                          decoration: BoxDecoration(gradient: gradient),
                          child: Center(
                            child: Icon(
                              Icons.auto_awesome,
                              color: Colors.white.withOpacity(0.6),
                              size: 24,
                            ),
                          ),
                        ),
                ),
              ),
              
              // 标题区域（浮在底部，半透明背景）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBackground.withOpacity(0.85),  // ✅ 使用主题表面色，85% 不透明度
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work.title,
                        style: TextStyle(
                          color: AppTheme.textColor,  // ✅ 使用主题文字色
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '创建于 ${_formatDate(work.createdAt)}',
                        style: TextStyle(
                          color: AppTheme.subTextColor,  // ✅ 使用主题次要文字色
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开作品空间
  Future<void> _openManualMode(Work work) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workJson = prefs.getString('work_${work.id}');
      
      String? currentPage;
      String? sourceType;
      
      if (workJson != null && workJson.isNotEmpty) {
        final data = jsonDecode(workJson) as Map<String, dynamic>;
        currentPage = data['currentPage'] as String?;
        sourceType = data['sourceType'] as String?;
      }
      
      if (!mounted) return;
      
      debugPrint('📖 打开作品: ${work.title}');
      debugPrint('   currentPage: $currentPage');
      debugPrint('   sourceType: $sourceType');
      
      // ✅ 根据 currentPage 决定打开哪个页面
      if (currentPage == 'story_input') {
        // 还在故事输入阶段，返回故事输入页
        debugPrint('   → 打开故事输入页');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StoryInputPage(
              workId: work.id,
              workName: work.title,
            ),
            fullscreenDialog: true,
          ),
        );
      } else if (currentPage == 'workspace' || sourceType != null) {
        // 已进入剧本空间，或有任何保存数据，打开剧本空间
        debugPrint('   → 打开剧本空间');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => WorkspacePage(
              initialScript: '',  // 从保存的数据加载
              sourceType: '已有作品',
              workId: work.id,
              workName: work.title,
            ),
            fullscreenDialog: true,
          ),
        );
      } else {
        // 全新作品，打开创作模式选择器
        debugPrint('   → 打开创作模式选择器');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CreationModeSelector(
              workId: work.id,
              workName: work.title,
            ),
            fullscreenDialog: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('打开作品失败: $e');
    }
    
    // 返回后重新加载作品列表（可能有更新）
    if (mounted) {
      _loadWorks();
    }
  }


  /// 显示作品右键菜单
  void _showWorkContextMenu(BuildContext context, TapDownDetails details, Work work) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final menuPosition = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    
    showMenu(
      context: context,
      position: menuPosition,
      color: const Color(0xFF1E1E20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        const PopupMenuItem(
          value: 'cover',
          child: Row(
            children: [
              Icon(Icons.photo_outlined, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text('设置封面', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text('重命名', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'cover') {
        _setCoverImage(work);
      } else if (value == 'rename') {
        _renameWork(work);
      } else if (value == 'delete') {
        _deleteWork(work);
      }
    });
  }

  /// 设置封面图片
  Future<void> _setCoverImage(Work work) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final imagePath = result.files.first.path!;
        
        setState(() {
          final index = _works.indexWhere((w) => w.id == work.id);
          if (index != -1) {
            _works[index] = Work(
              id: work.id,
              title: work.title,
              createdAt: work.createdAt,
              coverImage: imagePath,
            );
          }
        });
        _saveWorks();  // 自动保存
        debugPrint('设置封面: ${work.title} → $imagePath');
      }
    } catch (e) {
      debugPrint('⚠️ 选择封面失败: $e');
    }
  }

  /// 重命名作品
  void _renameWork(Work work) {
    final controller = TextEditingController(text: work.title);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('重命名作品', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '输入新名称',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2AF598)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  final index = _works.indexWhere((w) => w.id == work.id);
                  if (index != -1) {
                    _works[index] = Work(
                      id: work.id,
                      title: controller.text.trim(),
                      createdAt: work.createdAt,
                    );
                  }
                });
                _saveWorks();  // 自动保存
                debugPrint('重命名作品: ${work.title} → ${controller.text}');
              }
              Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: Color(0xFF2AF598))),
          ),
        ],
      ),
    );
  }

  /// 删除作品
  void _deleteWork(Work work) {
    setState(() {
      _works.removeWhere((w) => w.id == work.id);
    });
    _saveWorks();  // 自动保存
    debugPrint('删除作品: ${work.title}，剩余作品数：${_works.length}');
  }

  /// 获取作品封面渐变色（基于索引循环）
  LinearGradient _getGradientForIndex(int index) {
    final gradients = [
      // 青蓝渐变
      const LinearGradient(
        colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      // 紫粉渐变
      const LinearGradient(
        colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      // 橙黄渐变
      const LinearGradient(
        colors: [Color(0xFFFF9800), Color(0xFFF44336)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      // 蓝紫渐变
      const LinearGradient(
        colors: [Color(0xFF3F51B5), Color(0xFF00BCD4)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      // 绿青渐变
      const LinearGradient(
        colors: [Color(0xFF4CAF50), Color(0xFF00BCD4)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      // 粉紫渐变
      const LinearGradient(
        colors: [Color(0xFFFF4081), Color(0xFF7C4DFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ];
    
    return gradients[index % gradients.length];
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// 作品数据模型
class Work {
  final String id;
  final String title;
  final DateTime createdAt;
  final String? coverImage;  // 封面图片路径（可选）

  Work({
    required this.id,
    required this.title,
    required this.createdAt,
    this.coverImage,
  });

  /// 从 JSON 恢复
  factory Work.fromJson(Map<String, dynamic> json) {
    return Work(
      id: json['id'] as String,
      title: json['title'] as String? ?? '未命名作品',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      coverImage: json['coverImage'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.millisecondsSinceEpoch,
      if (coverImage != null) 'coverImage': coverImage,
    };
  }
}

/// 手动模式界面
class ManualModeScreen extends StatelessWidget {
  final Work work;

  const ManualModeScreen({super.key, required this.work});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161618),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E20),
        title: Text(work.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.edit_note,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '手动模式 - ${work.title}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '这里将是独立的手动创作界面',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'ID: ${work.id}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
