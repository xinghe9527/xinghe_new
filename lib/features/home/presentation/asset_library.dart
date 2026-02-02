import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinghe_new/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/services/upload_queue_manager.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

class AssetLibrary extends StatefulWidget {
  const AssetLibrary({super.key});

  @override
  State<AssetLibrary> createState() => _AssetLibraryState();
}

class _AssetLibraryState extends State<AssetLibrary> with WidgetsBindingObserver, RouteAware {
  int _selectedCategoryIndex = 0; // 0:角色 1:场景 2:物品
  final List<String> _categories = ['角色素材', '场景素材', '物品素材'];
  final List<IconData> _categoryIcons = [
    Icons.person_outline,
    Icons.landscape_outlined,
    Icons.inventory_2_outlined,
  ];
  
  // 服务实例
  final UploadQueueManager _queueManager = UploadQueueManager();
  final SecureStorageManager _storage = SecureStorageManager();
  final LogManager _logger = LogManager();
  late StreamSubscription _uploadSubscription;
  
  // 上传进度显示
  String _uploadStatus = '';  // 显示在界面上的状态
  
  // ✅ 数据更新保护
  DateTime? _lastSaveTime;
  bool _isUpdating = false;

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
      _setupUploadListener();
    });
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }
  
  /// 初始化数据
  Future<void> _initializeData() async {
    try {
      await _loadAssets();
      
      // ✅ 立即检查已完成任务，不等待
      if (mounted) {
        await _checkCompletedTasks();
      }
    } catch (e) {
      _logger.error('初始化数据失败: $e', module: '素材库');
    }
  }
  
  /// 🔍 检查已完成的上传任务
  Future<void> _checkCompletedTasks() async {
    debugPrint('🔍 [素材库] 检查是否有已完成的上传任务...');
    
    final completedTasks = _queueManager.getCompletedTasks();
    if (completedTasks.isEmpty) {
      debugPrint('   没有已完成的任务');
      return;
    }
    
    debugPrint('   找到 ${completedTasks.length} 个已完成的任务');
    
    bool hasUpdate = false;
    for (final task in completedTasks) {
      if (task.characterInfo != null) {
        // ✅ 查找并更新所有匹配路径的素材（不只是第一个）
        int foundCount = 0;
        for (var categoryEntry in _stylesByCategory.entries) {
          for (var style in categoryEntry.value) {
            // ✅ 遍历所有素材，找到所有匹配的
            for (var asset in style.assets) {
              if (asset.path == task.id) {
                foundCount++;
                debugPrint('   ✅ [#$foundCount] 找到匹配的素材: ${asset.name}, 映射代码: ${task.characterInfo}');
                
                if (asset.characterInfo != task.characterInfo) {
                  asset.isUploaded = true;
                  asset.isUploading = false;
                  asset.characterInfo = task.characterInfo;
                  asset.videoUrl = task.videoUrl;
                  hasUpdate = true;
                  debugPrint('      → 已更新映射代码');
                } else {
                  debugPrint('      → 已是最新状态，跳过');
                }
              }
            }
          }
        }
        
        if (foundCount == 0) {
          debugPrint('   ⚠️ 任务 ${task.assetName} 没有找到匹配的素材');
        } else {
          debugPrint('   📊 共找到 $foundCount 个匹配的素材');
        }
      }
    }
    
    if (hasUpdate) {
      debugPrint('   💾 发现新的上传结果，保存数据并更新 UI');
      
      // ✅ 先保存数据
      await _saveAssets();
      
      // ✅ 然后强制刷新 UI
      if (mounted) {
        setState(() {
          debugPrint('   🔄 强制刷新 UI');
        });
      }
    } else {
      debugPrint('   ℹ️ 素材已经是最新状态，无需更新');
    }
  }

  // 设置上传监听器
  void _setupUploadListener() {
    _logger.info('设置上传任务监听器', module: '素材库');
    
    _uploadSubscription = _queueManager.statusStream.listen(
      (task) {
        _logger.info('收到上传通知', module: '素材库', extra: {
          'taskId': task.id,
          'status': task.status.toString(),
        });
        _onUploadStatusChanged(task);
      },
      onError: (error) {
        _logger.error('上传监听器错误: $error', module: '素材库');
      },
    );
  }

  @override
  void dispose() {
    _styleNameController.dispose();
    _styleDescController.dispose();
    _uploadSubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    super.dispose();
  }
  
  /// 🔄 页面重新显示时
  @override
  void didPopNext() {
    debugPrint('📄 [素材库] 页面重新显示');
    if (!_isUpdating) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkCompletedTasks();
        }
      });
    }
  }
  
  @override
  void didPush() {
    debugPrint('📄 [素材库] 页面首次显示');
    // ✅ 页面首次显示时，也检查已完成的任务（可能是从其他页面返回）
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && !_isUpdating) {
        debugPrint('🔍 [didPush] 延迟检查已完成任务');
        _checkCompletedTasks();
      }
    });
  }
  
  @override
  void didPushNext() {
    debugPrint('📄 [素材库] 页面被遮挡');
  }
  
  @override
  void didPop() {
    debugPrint('📄 [素材库] 页面被移除');
  }
  
  /// 🔄 生命周期监听
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 [素材库] 应用返回前台');
      if (!_isUpdating) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _checkCompletedTasks();
          }
        });
      }
    }
  }

  // 上传任务状态变化回调
  void _onUploadStatusChanged(UploadTask task) {
    debugPrint('[素材库] 收到上传状态更新: ${task.id}, 状态: ${task.status}');
    
    // 更新状态显示
    if (task.status == UploadTaskStatus.processing) {
      if (mounted) {
        setState(() {
          _uploadStatus = '正在处理: ${task.assetName}';
        });
      }
    } else if (task.status == UploadTaskStatus.completed && task.characterInfo != null) {
      // ✅ 查找并更新所有匹配路径的素材（不只是第一个）
      int foundCount = 0;
      for (var categoryEntry in _stylesByCategory.entries) {
        for (var style in categoryEntry.value) {
          // ✅ 遍历所有素材，找到所有匹配的
          for (var asset in style.assets) {
            if (asset.path == task.id) {
              foundCount++;
              debugPrint('[素材库] ✅ [#$foundCount] 找到素材: ${asset.name}, 更新映射代码: ${task.characterInfo}');
              
              // ✅ 更新内存数据
              asset.isUploaded = true;
              asset.isUploading = false;
              asset.uploadedId = task.id;
              asset.characterInfo = task.characterInfo;
              asset.videoUrl = task.videoUrl;
              
              debugPrint('[素材库] 📝 已更新素材 #$foundCount: ${asset.name} -> ${asset.characterInfo}');
            }
          }
        }
      }
      
      if (foundCount > 0) {
        debugPrint('[素材库] 📊 共更新了 $foundCount 个重复的素材');
        
        // ✅ 保存数据
        _saveAssets().then((_) {
          debugPrint('[素材库] ✅ 保存完成');
        });
        
        _logger.success('角色创建成功: ${task.characterInfo}', module: '素材库');
        
        // ✅ 强制刷新 UI
        if (mounted) {
          setState(() {
            _uploadStatus = '✅ ${task.assetName}: ${task.characterInfo}';
            debugPrint('[素材库] 🔄 强制刷新 UI');
          });
          
          _showMessage('✅ ${task.assetName}: ${task.characterInfo}', isError: false);
          
          // 3秒后清空状态
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _uploadStatus = '';
              });
            }
          });
        } else {
          debugPrint('⚠️ [素材库] 页面不可见，数据已保存，等待页面返回时刷新');
        }
      } else {
        debugPrint('[素材库] ⚠️ 未找到对应的素材，taskId: ${task.id}');
      }
    } else if (task.status == UploadTaskStatus.failed) {
      if (mounted) {
        setState(() {
          _uploadStatus = '❌ ${task.assetName}: 失败';
        });
        
        _showMessage('❌ ${task.assetName} 上传失败', isError: true);
        
        // 5秒后清空状态
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _uploadStatus = '';
            });
          }
        });
      }
    }
  }

  // 加载保存的素材数据
  Future<void> _loadAssets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assetsJson = prefs.getString('asset_library_data');
      if (assetsJson != null && assetsJson.isNotEmpty && mounted) {
        final data = jsonDecode(assetsJson) as Map<String, dynamic>;
        
        setState(() {
          // 恢复每个分类的风格和素材
          data.forEach((key, value) {
            final categoryIndex = int.parse(key);
            final stylesList = (value as List).map((styleData) {
              return AssetStyle.fromJson(styleData);
            }).toList();
            _stylesByCategory[categoryIndex] = stylesList;
          });
        });
        
        _logger.success('成功加载素材库数据', module: '素材库');
        
        debugPrint('✅ [素材库] 加载数据成功');
        // 打印所有"下载.jpg"素材的信息
        _stylesByCategory.forEach((categoryIndex, styles) {
          for (var style in styles) {
            for (var asset in style.assets) {
              if (asset.name.contains('下载')) {
                debugPrint('   🔎 [${_categories[categoryIndex]}] ${asset.name}:');
                debugPrint('      - path: ${asset.path}');
                debugPrint('      - characterInfo: ${asset.characterInfo}');
                debugPrint('      - isUploaded: ${asset.isUploaded}');
              }
              
              if (asset.characterInfo != null && asset.characterInfo!.isNotEmpty) {
                debugPrint('   - [${_categories[categoryIndex]}] ${asset.name}: ${asset.characterInfo}');
              }
            }
          }
        });
      }
    } catch (e) {
      _logger.error('加载素材库失败: $e', module: '素材库');
      debugPrint('加载素材失败: $e');
    }
  }


  // 保存素材数据
  Future<void> _saveAssets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{};
      
      _stylesByCategory.forEach((key, value) {
        data[key.toString()] = value.map((style) => style.toJson()).toList();
      });
      
      await prefs.setString('asset_library_data', jsonEncode(data));
      
      debugPrint('✅ [素材库] 保存数据成功');
      
      // 打印每个分类已上传的素材
      _stylesByCategory.forEach((categoryIndex, styles) {
        for (var style in styles) {
          for (var asset in style.assets) {
            if (asset.characterInfo != null && asset.characterInfo!.isNotEmpty) {
              debugPrint('   - [${_categories[categoryIndex]}] ${asset.name}: ${asset.characterInfo}');
            }
          }
        }
      });
    } catch (e) {
      debugPrint('⚠️ [素材库] 保存素材失败: $e');
    }
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

    _saveAssets();  // 保存数据
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
        _saveAssets();  // 保存数据
        _showMessage('成功添加 ${result.files.length} 个素材', isError: false);
      }
    } catch (e) {
      _showMessage('添加素材失败: $e', isError: true);
    }
  }

  // 上传素材并创建角色（使用队列）
  Future<void> _uploadAsset(AssetItem asset) async {
    try {
      // 获取 API 配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('upload_provider') ?? 'geeknow';
      final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: 'upload');
      final apiKey = await _storage.getApiKey(provider: provider, modelType: 'upload');
      
      if (baseUrl == null || apiKey == null) {
        _showMessage('未配置视频 API，请先在设置中配置', isError: true);
        return;
      }
      
      final config = ApiConfig(
        provider: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      
      // 创建上传任务并添加到队列
      final task = UploadTask(
        id: asset.path,  // 使用文件路径作为唯一ID
        imageFile: File(asset.path),
        assetName: asset.name,
        apiConfig: config,
      );
      
      // 标记为上传中
      setState(() {
        asset.isUploading = true;
      });
      
      // 添加到队列（后台处理，不阻塞）
      _queueManager.addTask(task);
      
      _logger.info('上传任务已加入队列', module: '素材库', extra: {
        'name': asset.name,
        'queue': _queueManager.getQueueStatus(),
      });
      
    } catch (e) {
      _logger.error('添加上传任务失败: $e', module: '素材库');
      _showMessage('添加任务失败: $e', isError: true);
    }
  }

  // 删除素材
  void _deleteAsset(int index) {
    setState(() {
      _stylesByCategory[_selectedCategoryIndex]![_selectedStyleIndex].assets.removeAt(index);
    });
    _saveAssets();  // 保存数据
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

  // 智能图片显示（区分横屏和竖屏）
  Widget _buildSmartImage(String imagePath) {
    return FutureBuilder<ImageInfo>(
      future: _getImageInfo(imagePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
          final imageInfo = snapshot.data!;
          final width = imageInfo.image.width;
          final height = imageInfo.image.height;
          final isLandscape = width > height;  // 横屏图片
          
          if (isLandscape) {
            // 横屏图片：上下留白，左右填充
            return Container(
              color: AppTheme.inputBackground,
              padding: const EdgeInsets.only(top: 40),  // 上方留白40像素
              child: Image.file(
                File(imagePath),
                width: double.infinity,
                fit: BoxFit.fitWidth,  // 宽度填充，高度自适应
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(Icons.broken_image, color: AppTheme.subTextColor, size: 40),
                  );
                },
              ),
            );
          } else {
            // 竖屏图片：保持原样，填充显示
            return Image.file(
              File(imagePath),
              width: double.infinity,
              fit: BoxFit.cover,  // 填充显示
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: AppTheme.inputBackground,
                  child: Center(
                    child: Icon(Icons.broken_image, color: AppTheme.subTextColor, size: 40),
                  ),
                );
              },
            );
          }
        }
        
        // 加载中或出错时显示默认容器
        return Container(
          color: AppTheme.inputBackground,
          child: Center(
            child: snapshot.hasError
                ? Icon(Icons.broken_image, color: AppTheme.subTextColor, size: 40)
                : CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppTheme.accentColor)),
          ),
        );
      },
    );
  }

  // 获取图片信息（宽高）
  Future<ImageInfo> _getImageInfo(String imagePath) async {
    final completer = Completer<ImageInfo>();
    final img = FileImage(File(imagePath));
    final stream = img.resolve(const ImageConfiguration());
    
    stream.addListener(ImageStreamListener((info, _) {
      if (!completer.isCompleted) {
        completer.complete(info);
      }
    }));
    
    return completer.future;
  }

  // 显示图片预览（放大查看）
  void _showImagePreview(BuildContext context, String imagePath) {
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
                child: Image.file(File(imagePath)),
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
      width: 200,  // 从 280 改为 200（更窄）
      color: AppTheme.scaffoldBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 风格分类标题和添加按钮
          Padding(
            padding: const EdgeInsets.all(16),  // 从 20 改为 16（更紧凑）
            child: Row(
              children: [
                Text(
                  '风格分类',
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 14,  // 从 16 改为 14（更小）
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _isAddingStyle = !_isAddingStyle),
                    child: Container(
                      padding: const EdgeInsets.all(6),  // 从 8 改为 6（更小）
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AF598).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        _isAddingStyle ? Icons.close : Icons.add,
                        color: const Color(0xFF2AF598),
                        size: 16,  // 从 18 改为 16（更小）
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
              padding: const EdgeInsets.symmetric(horizontal: 12),  // 从 16 改为 12
              itemCount: styles.length,
              itemBuilder: (context, index) {
                final style = styles[index];
                final isSelected = _selectedStyleIndex == index;
                
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedStyleIndex = index),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),  // 从 8 改为 6
                      padding: const EdgeInsets.all(12),  // 从 16 改为 12（更紧凑）
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
                                width: 6,  // 从 8 改为 6
                                height: 6,
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF2AF598) : AppTheme.subTextColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),  // 从 8 改为 6
                              Expanded(
                                child: Text(
                                  style.name,
                                  style: TextStyle(
                                    color: AppTheme.textColor,
                                    fontSize: 12,  // 从 14 改为 12（更小）
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (style.description.isNotEmpty) ...[
                            const SizedBox(height: 4),  // 从 6 改为 4
                            Text(
                              style.description,
                              style: TextStyle(color: AppTheme.subTextColor, fontSize: 10),  // 从 11 改为 10
                            ),
                          ],
                          const SizedBox(height: 6),  // 从 8 改为 6
                          Text(
                            '${style.assets.length} 个素材',
                            style: TextStyle(color: AppTheme.subTextColor, fontSize: 10),  // 从 11 改为 10
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
                const SizedBox(width: 16),
                // 上传状态显示
                if (_uploadStatus.isNotEmpty)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(AppTheme.accentColor),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _uploadStatus,
                              style: TextStyle(
                                color: AppTheme.accentColor,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
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
                      crossAxisCount: 6,  // 从 4 列改为 6 列（图片更小）
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
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
    // ✅ 调试：打印素材信息
    if (asset.name == '下载.jpg') {
      debugPrint('📦 [素材卡片] 构建素材: ${asset.name}');
      debugPrint('   - characterInfo: ${asset.characterInfo}');
      debugPrint('   - isUploaded: ${asset.isUploaded}');
      debugPrint('   - 是否显示映射代码: ${asset.characterInfo != null}');
    }
    
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
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showImagePreview(context, asset.path),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: _buildSmartImage(asset.path),  // 使用智能图片显示
                    ),
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
                        child: const Icon(Icons.close, color: Colors.white, size: 16),  // 改为 ❌ 图标
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
                // 文件名/角色信息
                if (asset.characterInfo != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          asset.characterInfo!,
                          style: TextStyle(
                            color: AppTheme.accentColor,
                            fontSize: 10,  // 字体改小
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 复制按钮
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: asset.characterInfo!));
                            _showMessage('已复制: ${asset.characterInfo}', isError: false);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.copy,
                              size: 12,
                              color: AppTheme.accentColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    asset.isUploaded ? asset.uploadedId! : asset.name,
                    style: TextStyle(
                      color: AppTheme.textColor,
                      fontSize: 10,  // 统一字体大小
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

  // 从 JSON 恢复
  factory AssetStyle.fromJson(Map<String, dynamic> json) {
    return AssetStyle(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      assets: (json['assets'] as List<dynamic>?)
          ?.map((e) => AssetItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'assets': assets.map((e) => e.toJson()).toList(),
    };
  }
}

// 素材项数据模型
class AssetItem {
  final String path;
  final String name;
  bool isUploaded;
  bool isUploading;
  String? uploadedId;
  String? characterInfo;  // 角色信息（格式：@username,）
  String? videoUrl;       // Supabase 视频 URL

  AssetItem({
    required this.path,
    required this.name,
    this.isUploaded = false,
    this.isUploading = false,
    this.uploadedId,
    this.characterInfo,
    this.videoUrl,
  });

  // 从 JSON 恢复
  factory AssetItem.fromJson(Map<String, dynamic> json) {
    return AssetItem(
      path: json['path'] as String,
      name: json['name'] as String,
      isUploaded: json['isUploaded'] as bool? ?? false,
      isUploading: false,  // 加载时总是 false
      uploadedId: json['uploadedId'] as String?,
      characterInfo: json['characterInfo'] as String?,
      videoUrl: json['videoUrl'] as String?,
    );
  }

  // 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'isUploaded': isUploaded,
      'uploadedId': uploadedId,
      'characterInfo': characterInfo,
      'videoUrl': videoUrl,
    };
  }
}
