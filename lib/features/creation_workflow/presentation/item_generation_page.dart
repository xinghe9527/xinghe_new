import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'widgets/custom_title_bar.dart';
import 'item_prompt_manager.dart';
import 'style_reference_dialog.dart';
import 'asset_library_selector.dart';
import '../../../services/api/api_repository.dart';
import '../../../services/api/secure_storage_manager.dart';
import '../../../services/upload_queue_manager.dart';
import '../../../services/api/base/api_config.dart';
import 'widgets/draggable_media_item.dart';  // ✅ 导入拖动组件

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

class _ItemGenerationPageState extends State<ItemGenerationPage> with WidgetsBindingObserver, RouteAware {
  bool _showSettings = false;
  String _selectedPromptName = '默认';
  String _selectedPromptContent = '';
  String _styleReferenceText = '';
  String? _styleReferenceImage;
  String _imageRatio = '16:9';  // ✅ 图片比例，默认 16:9
  List<ItemData> _items = [];
  bool _isInferring = false;
  String _inferenceMode = 'preserve';  // ✅ 推理模式：'preserve' = 保留现有，'overwrite' = 覆盖全部
  final ApiRepository _apiRepository = ApiRepository();
  final Set<int> _generatingImages = {};
  final UploadQueueManager _uploadQueue = UploadQueueManager();
  late StreamSubscription _uploadSubscription;
  DateTime? _lastSaveTime;  // ✅ 记录最后保存时间
  bool _isUpdating = false;  // ✅ 标记是否正在更新数据

  final List<String> _ratios = ['1:1', '9:16', '16:9', '4:3', '3:4'];  // ✅ 比例选项

  @override
  void initState() {
    super.initState();
    _initializeData();  // ✅ 异步初始化数据
    _loadImageRatio();
    _setupUploadListener();
    WidgetsBinding.instance.addObserver(this);  // ✅ 添加生命周期监听
  }
  
  /// 初始化数据（先加载数据，再检查已完成任务）
  Future<void> _initializeData() async {
    await _loadItemData();  // ✅ 等待数据加载完成
    await _checkCompletedTasks();  // ✅ 然后检查已完成的任务
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ 注册路由监听
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }
  
  @override
  void dispose() {
    _uploadSubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);  // ✅ 移除生命周期监听
    routeObserver.unsubscribe(this);  // ✅ 取消路由监听
    super.dispose();
  }
  
  /// 🔄 生命周期监听：当应用从后台返回前台时重新加载数据
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 应用返回前台（不自动加载，避免覆盖）');
      if (!_isUpdating) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _checkCompletedTasks();
          }
        });
      }
    }
  }
  
  /// 🔄 页面重新显示时（从其他页面返回）
  @override
  void didPopNext() {
    debugPrint('📄 物品页面重新显示');
    // ✅ 不自动重新加载数据，避免覆盖正在编辑的内容
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_isUpdating) {
        _checkCompletedTasks();
      }
    });
  }
  
  /// 🔄 页面首次显示时
  @override
  void didPush() {
    debugPrint('📄 物品页面首次显示');
  }
  
  /// 🔄 页面被遮挡时
  @override
  void didPushNext() {
    debugPrint('📄 物品页面被遮挡');
  }
  
  /// 🔄 页面被移除时
  @override
  void didPop() {
    debugPrint('📄 物品页面被移除');
  }
  
  /// 🔍 检查已完成的上传任务（页面初始化时调用）
  Future<void> _checkCompletedTasks() async {
    debugPrint('🔍 [物品] 检查是否有已完成的上传任务...');
    
    final completedTasks = _uploadQueue.getCompletedTasks();
    if (completedTasks.isEmpty) {
      debugPrint('   没有已完成的任务');
      return;
    }
    
    debugPrint('   找到 ${completedTasks.length} 个已完成的任务');
    
    bool hasUpdate = false;
    for (final task in completedTasks) {
      if (task.characterInfo != null) {
        bool found = false;
        for (var i = 0; i < _items.length; i++) {
          if (_items[i].imageUrl == task.id || 
              _items[i].imageUrl == task.imageFile.path) {
            debugPrint('   ✅ 找到匹配的物品: ${_items[i].name}, 映射代码: ${task.characterInfo}');
            found = true;
            
            if (_items[i].mappingCode != task.characterInfo) {
              _items[i] = _items[i].copyWith(
                mappingCode: task.characterInfo,
                isUploaded: true,
                description: '${task.characterInfo}${_items[i].name}',
              );
              hasUpdate = true;
            }
            break;
          }
        }
        
        if (!found) {
          debugPrint('   ⚠️ 任务 ${task.assetName} 没有找到匹配的物品');
        }
      }
    }
    
    if (hasUpdate) {
      debugPrint('   💾 发现新的上传结果，保存数据并更新 UI');
      await _saveItemData();
      if (mounted) {
        setState(() {});
      }
    }
  }
  
  void _setupUploadListener() {
    _uploadSubscription = _uploadQueue.statusStream.listen((task) {
      debugPrint('📥 [物品] 收到上传状态: ${task.id}, ${task.status}, ${task.characterInfo}');
      
      if (task.status == UploadTaskStatus.completed && task.characterInfo != null) {
        for (var i = 0; i < _items.length; i++) {
          if (_items[i].imageUrl == task.id || _items[i].imageUrl == task.imageFile.path) {
            debugPrint('✅ 找到匹配的物品: ${_items[i].name}');
            
            _items[i] = _items[i].copyWith(
              mappingCode: task.characterInfo,
              isUploaded: true,
              description: '${task.characterInfo}${_items[i].name}',
            );
            
            _saveItemData();
            
            if (mounted) {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ ${_items[i].name} 上传成功\n映射代码: ${task.characterInfo}'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            } else {
              debugPrint('⚠️ 页面不可见，数据已保存，等待页面返回时刷新');
            }
            break;
          }
        }
      } else if (task.status == UploadTaskStatus.failed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('上传失败: ${task.error ?? "未知错误"}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  /// 加载图片比例设置
  Future<void> _loadImageRatio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRatio = prefs.getString('item_image_ratio');
      if (savedRatio != null && _ratios.contains(savedRatio)) {
        if (mounted) {
          setState(() => _imageRatio = savedRatio);
        }
        debugPrint('✅ 加载物品图片比例: $savedRatio');
      }
    } catch (e) {
      debugPrint('⚠️ 加载物品图片比例失败: $e');
    }
  }

  /// 保存图片比例设置
  Future<void> _saveImageRatio(String ratio) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('item_image_ratio', ratio);
      debugPrint('✅ 保存物品图片比例: $ratio');
    } catch (e) {
      debugPrint('⚠️ 保存物品图片比例失败: $e');
    }
  }

  Future<void> _loadItemData() async {
    try {
      // ✅ 如果正在更新数据，跳过加载
      if (_isUpdating) {
        debugPrint('⏭️ [物品] 跳过加载（正在更新数据中）');
        return;
      }
      
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
                            backgroundColor: const Color(0xFF3A3A3C).withOpacity( 0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 推理模式选择器
                        PopupMenuButton<String>(
                          offset: const Offset(0, 40),
                          tooltip: '推理模式',
                          color: const Color(0xFF2A2A2C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFF3A3A3C)),
                          ),
                          itemBuilder: (context) {
                            return [
                              PopupMenuItem<String>(
                                value: 'preserve',
                                child: Row(
                                  children: [
                                    Icon(
                                      _inferenceMode == 'preserve' ? Icons.check : Icons.shield_outlined,
                                      size: 16,
                                      color: _inferenceMode == 'preserve' ? const Color(0xFF4A9EFF) : const Color(0xFF888888),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '保留现有',
                                      style: TextStyle(
                                        color: _inferenceMode == 'preserve' ? const Color(0xFF4A9EFF) : const Color(0xFF888888),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'overwrite',
                                child: Row(
                                  children: [
                                    Icon(
                                      _inferenceMode == 'overwrite' ? Icons.check : Icons.refresh,
                                      size: 16,
                                      color: _inferenceMode == 'overwrite' ? const Color(0xFF4A9EFF) : const Color(0xFF888888),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '覆盖全部',
                                      style: TextStyle(
                                        color: _inferenceMode == 'overwrite' ? const Color(0xFF4A9EFF) : const Color(0xFF888888),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ];
                          },
                          onSelected: (value) {
                            setState(() {
                              _inferenceMode = value;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFF3A3A3C)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _inferenceMode == 'preserve' ? Icons.shield_outlined : Icons.refresh,
                                  size: 16,
                                  color: const Color(0xFF888888),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _inferenceMode == 'preserve' ? '保留现有' : '覆盖全部',
                                  style: const TextStyle(
                                    color: Color(0xFF888888),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  size: 18,
                                  color: Color(0xFF888888),
                                ),
                              ],
                            ),
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
                          onPressed: _items.isEmpty ? null : _generateImages,
                          icon: const Icon(Icons.collections, size: 16),
                          label: const Text('批量生成'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF888888),
                            side: const BorderSide(color: Color(0xFF3A3A3C)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 清空按钮
                        OutlinedButton.icon(
                          onPressed: _items.isEmpty ? null : _clearAll,
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
          Icon(Icons.category_outlined, size: 80, color: Colors.white.withOpacity( 0.1)),
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
                      // 物品名称和操作按钮
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A3A3C),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item.isInherited)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.folder_copy,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    color: item.isInherited 
                                        ? Colors.white  // ✅ 继承的资产：白色
                                        : const Color(0xFF888888),  // 新创建的：灰色
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 生成图片按钮（单个）
                          IconButton(
                            onPressed: _generatingImages.contains(index) ? null : () => _generateSingleItem(index),
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
                          // ✅ 上传按钮
                          IconButton(
                            onPressed: item.imageUrl != null && !item.isUploaded ? () => _uploadItem(index) : null,
                            icon: Icon(item.isUploaded ? Icons.cloud_done : Icons.cloud_upload, size: 16),
                            tooltip: item.isUploaded ? '已上传' : '上传获取映射代码',
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF3A3A3C),
                              foregroundColor: item.isUploaded ? const Color(0xFF4A9EFF) : const Color(0xFF888888),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                          // 删除按钮
                          IconButton(
                            onPressed: () => _deleteItem(index),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            tooltip: '删除物品',
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
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? GestureDetector(
                                onTap: () => _viewImage(item.imageUrl!),
                                onSecondaryTapDown: (details) => _showImageContextMenu(context, details, item.imageUrl!),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                  child: _buildImageWidget(item.imageUrl!),
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

  /// 推理物品（调用真实 LLM API）
  Future<void> _inferItems() async {
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
      
      print('\n🧠 开始推理物品');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔧 Provider: $provider');
      print('🎯 Model: ${model ?? "未设置"}');
      print('📋 物品提示词预设: $_selectedPromptContent');
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
        fullPrompt = '''请从以下剧本中提取所有重要物品。

剧本：
${widget.scriptContent}

输出格式：
每个物品一行，格式为：
物品名称 | 物品描述

示例：
全息通讯器 | 手腕式全息投影通讯设备，蓝色光效。
飞行摩托 | 单人飞行载具，流线型设计，霓虹灯带。

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
        
        print('📄 API 返回物品列表:');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print(responseText);
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
        
        // ✅ 智能解析物品（支持 JSON 格式和简单格式）
        final itemList = <ItemData>[];
        
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
              
              print('✅ JSON 解析成功，找到 ${jsonList.length} 个物品');
              
              for (final item in jsonList) {
                if (item is Map<String, dynamic>) {
                  final name = item['name']?.toString() ?? '未命名';
                  final description = item['description']?.toString() ?? '';
                  
                  itemList.add(ItemData(
                    id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + itemList.length.toString(),
                    name: name,
                    description: description,
                  ));
                  
                  print('   - 物品: $name (描述长度: ${description.length})');
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
          // JSON 解析失败，尝试简单格式（物品名称 | 物品描述）
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          print('⚠️ 尝试简单格式解析（物品名称 | 物品描述）');
          
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
                  itemList.add(ItemData(
                    id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + itemList.length.toString(),
                    name: name,
                    description: description,
                  ));
                  
                  print('   - 物品: $name (描述长度: ${description.length})');
                }
              }
            }
          }
          
          print('✅ 简单格式解析完成，找到 ${itemList.length} 个物品');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        }
        
        if (itemList.isEmpty) {
          // 如果所有解析都失败
          print('⚠️ 所有格式解析失败');
          
          // 在保留现有模式下，解析失败应该报错，而不是创建无用的"推理结果"
          if (_inferenceMode == 'preserve') {
            throw Exception('无法解析推理结果，请检查提示词设置或LLM返回格式');
          } else {
            // 覆盖全部模式下，将整个文本作为一个物品（向后兼容）
            itemList.add(ItemData(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: '推理结果',
              description: responseText,
            ));
          }
        }
        
        // ✅ 根据推理模式处理物品列表
        if (_inferenceMode == 'preserve') {
          // 保留现有模式：只添加不存在的物品
          final existingNames = _items.map((i) => i.name).toSet();
          final newItems = itemList.where((i) => !existingNames.contains(i.name)).toList();
          
          print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          print('🔍 推理模式: 保留现有');
          print('📊 现有物品: ${_items.length} 个');
          print('📊 推理物品: ${itemList.length} 个');
          print('📊 新增物品: ${newItems.length} 个');
          
          if (newItems.isNotEmpty) {
            print('✅ 新增物品列表:');
            for (final item in newItems) {
              print('   - ${item.name}');
            }
          } else {
            print('⚠️ 没有新物品需要添加');
          }
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
          
          if (mounted) {
            setState(() {
              _items.addAll(newItems);
            });
            await _saveItemData();
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(newItems.isEmpty 
                    ? '✅ 推理完成，没有新物品需要添加' 
                    : '✅ 推理完成，新增 ${newItems.length} 个物品'),
                  backgroundColor: newItems.isEmpty ? const Color(0xFF888888) : Colors.green,
                ),
              );
            }
          }
        } else {
          // 覆盖全部模式：替换所有物品
          print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          print('🔄 推理模式: 覆盖全部');
          print('📊 原有物品: ${_items.length} 个');
          print('📊 新物品: ${itemList.length} 个');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
          
          if (mounted) {
            setState(() {
              _items = itemList;
            });
            await _saveItemData();
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ 推理完成，识别到 ${itemList.length} 个物品'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        }
      } else {
        throw Exception(response.error ?? '推理失败');
      }
    } catch (e) {
      print('❌ 推理物品失败: $e');
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
      await _saveItemData();
    }
  }

  /// 清空所有物品
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
          '确定要清空所有物品吗？\n\n此操作不可恢复，已生成的物品和图片都将被删除。',
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
        _items.clear();
      });
      await _saveItemData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 已清空所有物品'),
            backgroundColor: Color(0xFF888888),
          ),
        );
      }
    }
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
            
            debugPrint('✅ 物品图片已保存: $filePath');
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

  /// 生成单个物品图片
  Future<void> _generateSingleItem(int index) async {
    final item = _items[index];
    
    setState(() {
      _generatingImages.add(index);
    });
    
    print('\n🎨 生成单个物品图片');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('物品: ${item.name}');
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
      String fullPrompt = item.description;
      
      // ✅ 添加风格参考说明
      if (_styleReferenceText.isNotEmpty) {
        fullPrompt = '$_styleReferenceText, $fullPrompt';
      }
      
      // ✅ 如果有风格参考图片，在提示词中明确说明
      final hasStyleImage = _styleReferenceImage != null && _styleReferenceImage!.isNotEmpty;
      if (hasStyleImage) {
        fullPrompt = '参考图片的艺术风格、色彩和构图风格，但不要融合图片内容。只生成物品本身，不要有人物、手、脸等元素。$fullPrompt';
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
        
        print('✅ 图片生成成功: $imageUrl');
        print('💾 下载并保存到本地...');
        
        // ✅ 下载并保存图片到本地
        final savedPath = await _downloadAndSaveImage(imageUrl, 'item_${item.name}');
        
        print('✅ 保存完成（使用本地路径）');
        
        if (mounted) {
          setState(() {
            _items[index] = _items[index].copyWith(imageUrl: savedPath);
          });
        }
        await _saveItemData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 物品"${item.name}"图片生成成功'),
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

  /// 删除物品
  Future<void> _deleteItem(int index) async {
    final item = _items[index];
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要删除物品"${item.name}"吗？',
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
        _items.removeAt(index);
      });
      await _saveItemData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已删除物品"${item.name}"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  /// 上传物品
  Future<void> _uploadItem(int index) async {
    final item = _items[index];
    if (item.imageUrl == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('upload_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final baseUrl = await storage.getBaseUrl(provider: provider, modelType: 'upload');
      final apiKey = await storage.getApiKey(provider: provider, modelType: 'upload');
      
      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置上传API');
      }
      
      final config = ApiConfig(provider: provider, baseUrl: baseUrl, apiKey: apiKey);
      final task = UploadTask(
        id: item.imageUrl!,
        imageFile: File(item.imageUrl!),
        assetName: item.name,
        apiConfig: config,
      );
      
      _uploadQueue.addTask(task);
      debugPrint('✅ ${item.name} 上传任务已加入队列');
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 批量生成所有物品图片
  Future<void> _generateImages() async {
    if (_items.isEmpty) return;

    print('\n🎨 物品空间 - 批量生成图片');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('   物品数量: ${_items.length}');
    print('   比例: $_imageRatio');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    int successCount = 0;
    int failCount = 0;
    
    // ✅ 读取图片 API 配置（一次性读取）
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('image_provider') ?? 'geeknow';
    final storage = SecureStorageManager();
    final model = await storage.getModel(provider: provider, modelType: 'image');

    // ✅ 并发生成（每批 3 个，避免API限流）
    for (var batchStart = 0; batchStart < _items.length; batchStart += 3) {
      final batchEnd = (batchStart + 3 > _items.length) ? _items.length : batchStart + 3;
      final batchIndices = List.generate(batchEnd - batchStart, (i) => batchStart + i);
      
      print('📦 批次 ${batchStart ~/ 3 + 1}: 生成 ${batchIndices.length} 个物品');
      
      // 并发生成当前批次
      final futures = batchIndices.map((i) async {
        if (_generatingImages.contains(i)) return false;
        
        setState(() => _generatingImages.add(i));
        
        try {
          final item = _items[i];
          
          // 构建完整的提示词
          String fullPrompt = item.description;
          if (_styleReferenceText.isNotEmpty) {
            fullPrompt = '$_styleReferenceText, $fullPrompt';
          }
          
          final hasStyleImage = _styleReferenceImage != null && _styleReferenceImage!.isNotEmpty;
          if (hasStyleImage) {
            fullPrompt = '参考图片的艺术风格、色彩和构图风格，但不要融合图片内容。只生成物品本身，不要有人物、手、脸等元素。$fullPrompt';
          }
          
          print('   📸 [${i + 1}/${_items.length}] ${item.name}');
          
          // 准备参考图片
          final referenceImages = <String>[];
          if (hasStyleImage) {
            referenceImages.add(_styleReferenceImage!);
          }
          
          // 调用 API（独立请求）
          _apiRepository.clearCache();
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
                _items[i] = _items[i].copyWith(imageUrl: imageUrl);
              });
            }
            
            print('      ✅ 成功\n');
            return true;
          } else {
            print('      ❌ 失败: ${response.error}\n');
            return false;
          }
        } catch (e) {
          print('      ❌ 异常: $e\n');
          return false;
        } finally {
          if (mounted) {
            setState(() => _generatingImages.remove(i));
          }
        }
      });
      
      // 等待当前批次完成
      final results = await Future.wait(futures);
      successCount += results.where((r) => r == true).length;
      failCount += results.where((r) => r == false).length;
      
      // 保存当前批次的结果
      await _saveItemData();
      
      print('✅ 批次完成: 成功 ${results.where((r) => r).length}, 失败 ${results.where((r) => !r).length}\n');
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
              Text('物品素材库', style: TextStyle(color: Color(0xFF888888))),
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
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AssetLibrarySelector(
        category: AssetCategory.item,  // 只显示物品素材
      ),
    );

    if (result != null && mounted) {
      final selectedPath = result['path'] as String?;
      final characterInfo = result['characterInfo'] as String?;
      
      if (selectedPath != null) {
        _isUpdating = true;
        _lastSaveTime = DateTime.now();
        
        try {
          // ✅ 直接创建新对象，同时设置映射代码
          String newDescription = _items[index].description.replaceAll(RegExp(r'@\w+,'), '').trim();
          
          // ✅ 如果素材已上传，使用素材的映射代码
          if (characterInfo != null && characterInfo.isNotEmpty) {
            newDescription = '$characterInfo${_items[index].name}';
          }
          
          _items[index] = ItemData(
            id: _items[index].id,
            name: _items[index].name,
            description: newDescription,
            imageUrl: selectedPath,
            mappingCode: characterInfo,
            isUploaded: characterInfo != null && characterInfo.isNotEmpty,
          );
          
          await _saveItemData();
          
          debugPrint('✅ 已从素材库选择物品图片');
          debugPrint('   - 映射代码: $characterInfo');
          
          if (mounted) {
            setState(() {});
            
            final message = characterInfo != null && characterInfo.isNotEmpty
                ? '✅ 已选择图片并设置映射代码'
                : '✅ 已选择图片（未上传的素材）';
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        } finally {
          Future.delayed(const Duration(seconds: 2), () {
            _isUpdating = false;
          });
        }
      }
    }
  }

  Future<void> _insertLocalImage(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty && mounted) {
      _isUpdating = true;
      _lastSaveTime = DateTime.now();
      
      try {
        final filePath = result.files.first.path!;
        
        _items[index] = ItemData(
          id: _items[index].id,
          name: _items[index].name,
          description: _items[index].description.replaceAll(RegExp(r'@\w+,'), '').trim(),
          imageUrl: filePath,
          mappingCode: null,
          isUploaded: false,
        );
        
        await _saveItemData();
        
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 已插入图片')),
          );
        }
      } finally {
        Future.delayed(const Duration(seconds: 2), () {
          _isUpdating = false;
        });
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF3A3A3C)),
      ),
      items: const [
        PopupMenuItem(
          value: 'locate_file',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('定位文件', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete_image',
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
      if (value == 'locate_file') {
        _locateFile(imageUrl);
      } else if (value == 'delete_image') {
        _deleteImage(imageUrl);
      }
    });
  }
  
  /// 删除图片
  Future<void> _deleteImage(String imageUrl) async {
    final index = _items.indexWhere((i) => i.imageUrl == imageUrl);
    if (index == -1) return;
    
    final item = _items[index];
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要删除"${item.name}"的图片吗？',
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

    if (confirm == true) {
      _isUpdating = true;
      _lastSaveTime = DateTime.now();
      
      try {
        // 删除本地文件
        if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
          try {
            final file = File(imageUrl);
            if (await file.exists()) {
              await file.delete();
              debugPrint('✅ 已删除本地文件: $imageUrl');
            }
          } catch (e) {
            debugPrint('⚠️ 删除本地文件失败: $e');
          }
        }
        
        // 清除物品的图片URL
        _items[index] = ItemData(
          id: _items[index].id,
          name: _items[index].name,
          description: _items[index].description.replaceAll(RegExp(r'@\w+,'), '').trim(),
          imageUrl: null,
          mappingCode: null,
          isUploaded: false,
        );
        
        await _saveItemData();
        
        debugPrint('✅ 已删除物品图片: ${item.name}');
        
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 已删除"${item.name}"的图片'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } finally {
        Future.delayed(const Duration(seconds: 2), () {
          _isUpdating = false;
        });
      }
    }
  }

  void _locateFile(String imageUrl) async {
    // 检查是否为本地文件
    if (imageUrl.isEmpty || imageUrl.startsWith('http')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('只能定位本地文件')),
        );
      }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在')),
          );
        }
      }
    } catch (e) {
      debugPrint('定位文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定位文件失败: $e')),
        );
      }
    }
  }

  Widget _buildImageWidget(String imageUrl) {
    // ✅ 如果是网络图片，直接返回
    if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl, 
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.broken_image, color: Color(0xFF888888)),
          );
        },
      );
    }
    
    // ✅ 本地文件：先检查文件是否存在
    final file = File(imageUrl);
    final imageWidget = Image.file(
      file, 
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Icon(Icons.broken_image, color: Color(0xFF888888)),
        );
      },
    );
    
    // ✅ 如果文件存在，添加拖动功能
    if (file.existsSync()) {
      try {
        return DraggableMediaItem(
          filePath: imageUrl,
          dragPreviewText: path.basename(imageUrl),
          coverUrl: imageUrl,
          child: imageWidget,
        );
      } catch (e) {
        debugPrint('⚠️ 创建拖动组件失败: $e');
        return imageWidget;
      }
    }
    
    // ✅ 文件不存在，直接返回图片组件（会显示错误图标）
    return imageWidget;
  }
}

class ItemData {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;
  final String? mappingCode;
  final bool isUploaded;
  final bool isInherited;      // ✅ 是否继承自其他作品
  final String? sourceWorkId;  // ✅ 来源作品ID

  ItemData({
    required this.id,
    required this.name,
    required this.description,
    this.imageUrl,
    this.mappingCode,
    this.isUploaded = false,
    this.isInherited = false,
    this.sourceWorkId,
  });

  ItemData copyWith({
    String? name, 
    String? description, 
    String? imageUrl, 
    String? mappingCode, 
    bool? isUploaded,
    bool? isInherited,
    String? sourceWorkId,
  }) {
    return ItemData(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      mappingCode: mappingCode ?? this.mappingCode,
      isUploaded: isUploaded ?? this.isUploaded,
      isInherited: isInherited ?? this.isInherited,
      sourceWorkId: sourceWorkId ?? this.sourceWorkId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'mappingCode': mappingCode,
        'isUploaded': isUploaded,
        'isInherited': isInherited,
        'sourceWorkId': sourceWorkId,
      };

  factory ItemData.fromJson(Map<String, dynamic> json) {
    final sourceWorkId = json['sourceWorkId'] as String?;
    return ItemData(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      imageUrl: json['imageUrl'] as String?,
      mappingCode: json['mappingCode'] as String?,
      isUploaded: json['isUploaded'] as bool? ?? false,
      isInherited: json['isInherited'] as bool? ?? false,
      sourceWorkId: (sourceWorkId == null || sourceWorkId.isEmpty) ? null : sourceWorkId,
    );
  }
}
