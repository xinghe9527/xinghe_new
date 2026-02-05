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
import 'character_prompt_manager.dart';
import 'style_reference_dialog.dart';
import 'asset_library_selector.dart';
import '../../../services/api/api_repository.dart';
import '../../../services/api/secure_storage_manager.dart';
import '../../../services/api/base/api_config.dart';
import '../../../services/api/base/api_response.dart';
import '../../../services/upload_queue_manager.dart';  // ✅ 上传队列管理器
import '../../../services/api/providers/geeknow_service.dart';  // ✅ 直接导入服务

/// 角色生成页面
class CharacterGenerationPage extends StatefulWidget {
  final String workId;
  final String workName;
  final String scriptContent;  // 剧本内容，用于推理

  const CharacterGenerationPage({
    super.key,
    required this.workId,
    required this.workName,
    required this.scriptContent,
  });

  @override
  State<CharacterGenerationPage> createState() => _CharacterGenerationPageState();
}

class _CharacterGenerationPageState extends State<CharacterGenerationPage> with WidgetsBindingObserver, RouteAware {
  bool _showSettings = false;
  String _selectedPromptName = '默认';
  String _selectedPromptContent = '';
  String _styleReferenceText = '';
  String? _styleReferenceImage;
  String _imageRatio = '16:9';  // ✅ 图片比例，默认 16:9
  List<CharacterData> _characters = [];
  bool _isInferring = false;
  final ApiRepository _apiRepository = ApiRepository();
  final Set<int> _generatingImages = {};
  final UploadQueueManager _uploadQueue = UploadQueueManager();  // ✅ 上传队列
  late StreamSubscription _uploadSubscription;  // ✅ 上传监听
  DateTime? _lastSaveTime;  // ✅ 记录最后保存时间
  bool _isUpdating = false;  // ✅ 标记是否正在更新数据

  final List<String> _ratios = ['1:1', '9:16', '16:9', '4:3', '3:4'];  // ✅ 比例选项

  @override
  void initState() {
    super.initState();
    _loadImageRatio();  // 加载保存的比例设置
    _setupUploadListener();  // ✅ 设置上传监听
    WidgetsBinding.instance.addObserver(this);  // ✅ 添加生命周期监听
    
    // ✅ 使用 Future.microtask 确保在下一个事件循环执行
    Future.microtask(() => _initializeData());
  }
  
  /// 初始化数据（先加载数据，再检查已完成任务）
  Future<void> _initializeData() async {
    try {
      await _loadCharacterData();  // ✅ 等待数据加载完成
      
      // ✅ 延迟检查已完成任务，确保页面已经构建完成
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _checkCompletedTasks();  // ✅ 然后检查已完成的任务
        }
      });
    } catch (e) {
      debugPrint('❌ 初始化数据失败: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('数据加载失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    _uploadSubscription.cancel();  // ✅ 取消监听器，避免内存泄漏
    WidgetsBinding.instance.removeObserver(this);  // ✅ 移除生命周期监听
    routeObserver.unsubscribe(this);  // ✅ 取消路由监听
    super.dispose();
  }
  
  /// 🔄 生命周期监听：当应用从后台返回前台时重新加载数据
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ✅ 不自动重新加载，避免覆盖数据
      debugPrint('📱 应用返回前台（不自动加载，避免覆盖）');
      
      // 只检查已完成的上传任务
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
    debugPrint('📄 页面重新显示');
    // ✅ 不自动重新加载数据，避免覆盖正在编辑的内容
    // 只在必要时（如上传完成）通过监听器更新
    
    // 只检查已完成的上传任务
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_isUpdating) {
        _checkCompletedTasks();
      }
    });
  }
  
  /// 🔄 页面首次显示时
  @override
  void didPush() {
    debugPrint('📄 页面首次显示');
  }
  
  /// 🔄 页面被遮挡时
  @override
  void didPushNext() {
    debugPrint('📄 页面被遮挡');
  }
  
  /// 🔄 页面被移除时
  @override
  void didPop() {
    debugPrint('📄 页面被移除');
  }
  
  /// 🔍 检查已完成的上传任务（页面初始化时调用）
  Future<void> _checkCompletedTasks() async {
    debugPrint('🔍 检查是否有已完成的上传任务...');
    
    final completedTasks = _uploadQueue.getCompletedTasks();
    if (completedTasks.isEmpty) {
      debugPrint('   没有已完成的任务');
      return;
    }
    
    debugPrint('   找到 ${completedTasks.length} 个已完成的任务');
    
    bool hasUpdate = false;
    for (final task in completedTasks) {
      debugPrint('   🔎 检查任务:');
      debugPrint('      - task.id: ${task.id}');
      debugPrint('      - task.imageFile.path: ${task.imageFile.path}');
      debugPrint('      - task.characterInfo: ${task.characterInfo}');
      debugPrint('      - task.assetName: ${task.assetName}');
      
      if (task.characterInfo != null) {
        // 查找对应的角色并更新
        bool found = false;
        for (var i = 0; i < _characters.length; i++) {
          debugPrint('      🔎 比对角色: ${_characters[i].name}');
          debugPrint('         - imageUrl: ${_characters[i].imageUrl}');
          
          if (_characters[i].imageUrl == task.id || 
              _characters[i].imageUrl == task.imageFile.path) {
            debugPrint('      ✅ 找到匹配的角色: ${_characters[i].name}, 映射代码: ${task.characterInfo}');
            found = true;
            
            // 检查是否已经更新过
            if (_characters[i].mappingCode != task.characterInfo) {
              _characters[i] = _characters[i].copyWith(
                mappingCode: task.characterInfo,
                isUploaded: true,
                description: '${task.characterInfo}${_characters[i].name}',
              );
              hasUpdate = true;
            }
            break;
          }
        }
        
        if (!found) {
          debugPrint('      ❌ 没有找到匹配的角色');
        }
      } else {
        debugPrint('      ⚠️ 任务没有 characterInfo');
      }
    }
    
    if (hasUpdate) {
      debugPrint('   💾 发现新的上传结果，保存数据并更新 UI');
      await _saveCharacterData();
      if (mounted) {
        setState(() {});
      }
    } else {
      debugPrint('   ℹ️ 没有需要更新的数据');
    }
  }
  
  /// 设置上传监听
  void _setupUploadListener() {
    _uploadSubscription = _uploadQueue.statusStream.listen((task) {
      debugPrint('📥 收到上传状态: ${task.id}, ${task.status}, ${task.characterInfo}');
      
      if (task.status == UploadTaskStatus.completed && task.characterInfo != null) {
        // 查找对应的角色并更新
        for (var i = 0; i < _characters.length; i++) {
          if (_characters[i].imageUrl == task.id || 
              _characters[i].imageUrl == task.imageFile.path) {
            debugPrint('✅ 找到匹配的角色: ${_characters[i].name}');
            
            // ✅ 先更新内存中的数据
            _characters[i] = _characters[i].copyWith(
              mappingCode: task.characterInfo,
              isUploaded: true,
              description: '${task.characterInfo}${_characters[i].name}',  // @username,名字
            );
            
            // ✅ 保存到本地存储
            _saveCharacterData();
            
            // ✅ 只有在页面可见时才更新 UI
            if (mounted) {
              setState(() {});  // 触发重建
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ ${_characters[i].name} 上传成功\n映射代码: ${task.characterInfo}'),
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
        debugPrint('❌ 上传失败: ${task.error}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('上传失败: ${task.error}'),
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
      final savedRatio = prefs.getString('character_image_ratio');
      if (savedRatio != null && _ratios.contains(savedRatio)) {
        if (mounted) {
          setState(() => _imageRatio = savedRatio);
        }
        debugPrint('✅ 加载图片比例: $savedRatio');
      }
    } catch (e) {
      debugPrint('⚠️ 加载图片比例失败: $e');
    }
  }

  /// 保存图片比例设置
  Future<void> _saveImageRatio(String ratio) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('character_image_ratio', ratio);
      debugPrint('✅ 保存图片比例: $ratio');
    } catch (e) {
      debugPrint('⚠️ 保存图片比例失败: $e');
    }
  }

  /// 加载角色数据
  Future<void> _loadCharacterData() async {
    try {
      // ✅ 如果正在更新数据，跳过加载
      if (_isUpdating) {
        debugPrint('⏭️ 跳过加载（正在更新数据中）');
        return;
      }
      
      // ✅ 如果刚刚保存过（5秒内），跳过加载，避免覆盖
      if (_lastSaveTime != null && 
          DateTime.now().difference(_lastSaveTime!).inSeconds < 5) {
        debugPrint('⏭️ 跳过加载（${DateTime.now().difference(_lastSaveTime!).inSeconds}秒前刚保存过）');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final key = 'characters_${widget.workId}';
      final dataJson = prefs.getString(key);
      
      if (dataJson != null && dataJson.isNotEmpty) {
        final data = jsonDecode(dataJson) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _selectedPromptName = data['selectedPromptName'] ?? '默认';
            _selectedPromptContent = data['selectedPromptContent'] ?? '';
            _styleReferenceText = data['styleReferenceText'] ?? '';
            _styleReferenceImage = data['styleReferenceImage'];
            
            final charList = data['characters'] as List<dynamic>?;
            if (charList != null) {
              _characters = charList
                  .map((e) => CharacterData.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          });
          
          debugPrint('✅ 加载角色数据成功 (${_characters.length} 个角色)');
          // 打印每个角色的映射代码，方便调试
          for (var char in _characters) {
            debugPrint('   - ${char.name}: ${char.mappingCode ?? "无"}');
          }
        }
      } else {
        debugPrint('⚠️ 没有找到保存的角色数据');
      }
    } catch (e) {
      debugPrint('❌ 加载角色数据失败: $e');
    }
  }

  /// 保存角色数据
  Future<void> _saveCharacterData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'characters_${widget.workId}';
      final data = {
        'selectedPromptName': _selectedPromptName,
        'selectedPromptContent': _selectedPromptContent,
        'styleReferenceText': _styleReferenceText,
        'styleReferenceImage': _styleReferenceImage,
        'characters': _characters.map((e) => e.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(data));
      _lastSaveTime = DateTime.now();  // ✅ 记录保存时间
      
      debugPrint('✅ 保存角色数据成功 (${_characters.length} 个角色)');
      
      // 打印每个角色的映射代码，方便调试
      for (var char in _characters) {
        if (char.mappingCode != null && char.mappingCode!.isNotEmpty) {
          debugPrint('   - ${char.name}: ${char.mappingCode}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ 保存角色数据失败: $e');
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
            // 顶部工具栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Color(0xFF888888), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '角色生成',
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
            // 待生成区
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 操作按钮栏
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text(
                          '待生成区',
                          style: TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 提示词按钮（小书图标）
                        IconButton(
                          onPressed: _openCharacterPromptManager,
                          icon: const Icon(Icons.menu_book, size: 20),
                          color: const Color(0xFF888888),
                          tooltip: '角色提示词（当前：$_selectedPromptName）',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF3A3A3C).withOpacity(0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 推理按钮
                        OutlinedButton.icon(
                          onPressed: _isInferring ? null : _inferCharacters,
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
                        // 风格参考按钮
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
                        // 批量生成按钮
                        OutlinedButton.icon(
                          onPressed: _characters.isEmpty ? null : _generateImages,
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
                          onPressed: _characters.isEmpty ? null : _clearAll,
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
                  // 角色列表
                  Expanded(
                    child: _characters.isEmpty
                        ? _buildEmptyState()
                        : _buildCharacterList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_outline,
            size: 80,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          const Text(
            '还没有角色',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '点击"推理"按钮，AI将从剧本中提取角色',
            style: TextStyle(
              color: Color(0xFF555555),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 角色列表
  Widget _buildCharacterList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _characters.length,
      itemBuilder: (context, index) {
        return _buildCharacterCard(_characters[index], index);
      },
    );
  }

  /// 角色卡片
  Widget _buildCharacterCard(CharacterData character, int index) {
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
          // 左边：角色信息
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 角色名称和操作按钮
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3C),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          character.name,
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
                        onPressed: () => _generateSingleImage(index),
                        icon: const Icon(Icons.image, size: 16),
                        tooltip: '生成图片',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF3A3A3C),
                          foregroundColor: const Color(0xFF888888),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                      // ✅ 上传按钮（获取映射代码）
                      IconButton(
                        onPressed: character.imageUrl != null && 
                                   character.imageUrl!.isNotEmpty && 
                                   !character.isUploaded
                            ? () => _uploadCharacter(index)
                            : null,
                        icon: Icon(
                          character.isUploaded ? Icons.cloud_done : Icons.cloud_upload,
                          size: 16,
                        ),
                        tooltip: character.isUploaded ? '已上传' : '上传获取映射代码',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF3A3A3C),
                          foregroundColor: character.isUploaded 
                              ? const Color(0xFF4A9EFF)
                              : const Color(0xFF888888),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                      // 删除按钮
                      IconButton(
                        onPressed: () => _deleteCharacter(index),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        tooltip: '删除角色',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF3A3A3C),
                          foregroundColor: const Color(0xFF888888),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 角色描述（可编辑）
                  TextField(
                    controller: TextEditingController(text: character.description),
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(12),
                    ),
                    onChanged: (value) {
                      _characters[index] = character.copyWith(description: value);
                      _saveCharacterData();
                    },
                  ),
                ],
              ),
            ),
          ),
          // 右边：图片生成区
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
                  // 图片显示区
                  Positioned.fill(
                    child: _generatingImages.contains(index)
                        // ✅ 显示"生成中"状态
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                                  ),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  '生成中...',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : character.imageUrl != null && character.imageUrl!.isNotEmpty
                        // 显示已生成的图片
                        ? GestureDetector(
                            onTap: () => _viewImage(character.imageUrl!),
                            onSecondaryTapDown: (details) => _showImageContextMenu(context, details, character.imageUrl!),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                              ),
                              child: _buildImageWidget(character.imageUrl!),
                            ),
                          )
                        // 显示"待生成"占位符
                        : _buildImagePlaceholder(),
                  ),
                  // 右上角插入按钮
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.add_photo_alternate, size: 20),
                          color: const Color(0xFF888888),
                          onPressed: () => _showImageSourceMenu(context, index),
                          tooltip: '添加图片',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.6),
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
  }

  /// 图片占位符
  Widget _buildImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 60,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 12),
          const Text(
            '待生成',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// 打开角色提示词管理器
  void _openCharacterPromptManager() async {
    if (!mounted) return;
    
    try {
      final result = await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => CharacterPromptManager(
          currentPresetName: _selectedPromptName,
        ),
      );

      if (!mounted) return;
      
      if (result != null) {
        setState(() {
          _selectedPromptName = result['name'] ?? '默认';
          _selectedPromptContent = result['content'] ?? '';
        });
        await _saveCharacterData();
        debugPrint('✅ 作品 ${widget.workName} 选择角色提示词: $_selectedPromptName');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 打开角色提示词管理器失败: $e');
      debugPrint('堆栈: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    }
  }

  /// 推理角色（调用真实 LLM API）
  Future<void> _inferCharacters() async {
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
      
      // ✅ 读取用户配置的模型（关键！）
      final storage = SecureStorageManager();
      final model = await storage.getModel(provider: provider, modelType: 'llm');
      
      print('\n🧠 开始推理角色');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔧 Provider: $provider');
      print('🎯 Model: ${model ?? "未设置"}');  // ← 显示实际使用的模型
      print('📋 角色提示词预设: $_selectedPromptContent');
      print('📝 剧本长度: ${widget.scriptContent.length} 字符');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // ✅ 构建 messages（参考最佳实践）
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
        fullPrompt = '''请从以下剧本中提取所有角色。

剧本：
${widget.scriptContent}

输出格式：
每个角色一行，格式为：
角色名称 | 角色描述

示例：
主角 | 20岁左右的年轻人，银白色短发，蓝色眼睛，身穿黑色机能风外套。
神秘人 | 身份不明的神秘角色，总是戴着面具。

现在开始提取：''';
        
        print('⚠️ 未设置提示词预设，使用默认简单格式');
      }
      
      messages.add({'role': 'user', 'content': fullPrompt});
      
      // ✅ 调用真实 LLM API（使用用户配置的模型）
      _apiRepository.clearCache();
      final response = await _apiRepository.generateTextWithMessages(
        provider: provider,
        messages: messages,
        model: model,  // ✅ 使用用户在设置中配置的模型
        parameters: {
          'temperature': 0.5,
          'max_tokens': 2000,
        },
      );
      
      if (response.isSuccess && response.data != null) {
        final responseText = response.data!.text;
        
        print('📄 API 返回角色列表:');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print(responseText);
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
        
        // ✅ 智能解析角色（支持 JSON 格式和简单格式）
        final characterList = <CharacterData>[];
        
        try {
          // 方法1：尝试直接解析整个文本为 JSON（最可靠）
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
              
              print('✅ JSON 解析成功，找到 ${jsonList.length} 个角色');
              
              for (final item in jsonList) {
                if (item is Map<String, dynamic>) {
                  final name = item['name']?.toString() ?? '未命名';
                  final description = item['description']?.toString() ?? '';
                  
                  characterList.add(CharacterData(
                    id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + characterList.length.toString(),
                    name: name,
                    description: description,
                  ));
                  
                  print('   - 角色: $name (描述长度: ${description.length})');
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
          // JSON 解析失败，尝试简单格式（角色名称 | 角色描述）
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          print('⚠️ 尝试简单格式解析（角色名称 | 角色描述）');
          
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
                  characterList.add(CharacterData(
                    id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + characterList.length.toString(),
                    name: name,
                    description: description,
                  ));
                  
                  print('   - 角色: $name (描述长度: ${description.length})');
                }
              }
            }
          }
          
          print('✅ 简单格式解析完成，找到 ${characterList.length} 个角色');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        }
        
        if (characterList.isEmpty) {
          // 如果所有解析都失败，将整个文本作为一个角色
          print('⚠️ 所有格式解析失败，使用原始文本作为单个角色');
          characterList.add(CharacterData(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: '推理结果',
            description: responseText,
          ));
        }
        
        if (mounted) {
          setState(() {
            _characters = characterList;
          });
          await _saveCharacterData();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ 推理完成，识别到 ${characterList.length} 个角色'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception(response.error ?? '推理失败');
      }
    } catch (e) {
      print('❌ 推理角色失败: $e');
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

  /// 打开风格参考对话框
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
      await _saveCharacterData();
    }
  }

  /// 生成角色图片
  /// 清空所有角色
  Future<void> _clearAll() async {
    // 显示确认对话框
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
          '确定要清空所有角色吗？\n\n此操作不可恢复，已生成的角色和图片都将被删除。',
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
        _characters.clear();
      });
      await _saveCharacterData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 已清空所有角色'),
            backgroundColor: Color(0xFF888888),
          ),
        );
      }
    }
  }

  /// 生成单个角色的图片
  Future<void> _generateSingleImage(int index) async {
    final character = _characters[index];
    
    // ✅ 显示"生成中"状态
    setState(() {
      _generatingImages.add(index);
    });
    
    // ✅ 读取图片 API 配置
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('image_provider') ?? 'geeknow';
    final storage = SecureStorageManager();
    final model = await storage.getModel(provider: provider, modelType: 'image');
    
    print('\n🎨 生成单个角色图片');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('角色: ${character.name}');
    print('Provider: $provider');
    print('Model: ${model ?? "未设置"}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    try {
      // ✅ 构建完整提示词
      String prompt = character.description;
      if (_styleReferenceText.isNotEmpty) {
        prompt = '$_styleReferenceText, $prompt';
      }
      
      // ✅ 如果有风格参考图片，在提示词中明确说明
      final hasStyleImage = _styleReferenceImage != null && _styleReferenceImage!.isNotEmpty;
      if (hasStyleImage) {
        prompt = '参考图片的艺术风格、色彩和构图风格，但不要融合图片内容。$prompt';
      }
      
      // ✅ 读取完整 API 配置
      final baseUrl = await storage.getBaseUrl(provider: provider, modelType: 'image');
      final apiKey = await storage.getApiKey(provider: provider, modelType: 'image');
      
      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置图片 API');
      }
      
      print('   BaseURL: $baseUrl');
      print('   API Key: ${apiKey.substring(0, 10)}...');
      print('   🎨 风格参考图片: ${hasStyleImage ? "是" : "否"}\n');
      
      // ✅ 使用 ApiRepository 调用（自动使用配置的服务商）
      print('   比例: $_imageRatio');
      print('   调用 ApiRepository.generateImages...');
      
      // ✅ 准备参考图片
      final referenceImages = <String>[];
      if (hasStyleImage) {
        referenceImages.add(_styleReferenceImage!);
        print('   📸 添加风格参考图片');
      }
      
      // ✅ 通过 ApiRepository 调用（会自动使用 ComfyUI 或其他配置的服务商）
      _apiRepository.clearCache();
      final response = await _apiRepository.generateImages(
        provider: provider,
        prompt: prompt,
        model: model,
        referenceImages: referenceImages.isNotEmpty ? referenceImages : null,
        parameters: {
          'size': _imageRatio,
          'quality': 'standard',
        },
      );
      
      print('   ✅ API 调用返回');
      print('   Success: ${response.isSuccess}');
      print('   HasData: ${response.data != null}');
      
      if (response.isSuccess && response.data != null) {
        // ✅ 兼容不同的返回类型
        final imageUrls = response.data is List
            ? (response.data as List).map((img) => img.imageUrl as String).toList()
            : [];
        
        print('   图片数量: ${imageUrls.length}');
        
        if (imageUrls.isEmpty) {
          throw Exception('API 返回成功但没有图片');
        }
        
        final imageUrl = imageUrls.first;
        
        print('🖼️ 图片 URL: $imageUrl');
        print('💾 下载并保存到本地...');
        
        // ✅ 下载并保存图片到本地
        final savedPath = await _downloadAndSaveImage(imageUrl, 'character_${character.name}');
        
        print('✅ 更新 State（使用本地路径）...\n');
        
        if (mounted) {
          setState(() {
            _characters[index] = _characters[index].copyWith(imageUrl: savedPath);
            _generatingImages.remove(index);  // ✅ 清除生成中状态
          });
          await _saveCharacterData();
          
          print('✅ State 已更新，图片应该显示了');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${character.name} 的图片生成成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('❌ 响应成功但没有图片数据');
        print('   Data: ${response.data}');
        print('   Error: ${response.error}');
        throw Exception(response.error ?? '未返回图片数据');
      }
    } catch (e) {
      print('💥 生成异常: $e\n');
      
      if (mounted) {
        setState(() {
          _generatingImages.remove(index);  // ✅ 清除生成中状态
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 生成失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 删除单个角色
  Future<void> _deleteCharacter(int index) async {
    final character = _characters[index];
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要删除角色"${character.name}"吗？',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFF888888))),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _characters.removeAt(index);
      });
      await _saveCharacterData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已删除角色"${character.name}"'),
            backgroundColor: const Color(0xFF888888),
          ),
        );
      }
    }
  }

  /// 上传角色获取映射代码
  Future<void> _uploadCharacter(int index) async {
    final character = _characters[index];
    
    if (character.imageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先生成图片')),
      );
      return;
    }
    
    try {
      // 读取上传API配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('upload_provider') ?? 'geeknow';
      final storage = SecureStorageManager();
      final baseUrl = await storage.getBaseUrl(provider: provider, modelType: 'upload');
      final apiKey = await storage.getApiKey(provider: provider, modelType: 'upload');
      
      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置上传API，请在设置中配置');
      }
      
      final config = ApiConfig(
        provider: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      
      // ✅ 使用上传队列管理器
      final task = UploadTask(
        id: character.imageUrl!,
        imageFile: File(character.imageUrl!),
        assetName: character.name,
        apiConfig: config,
      );
      
      // 标记为上传中
      setState(() {
        _characters[index] = character.copyWith(isUploaded: false);
      });
      
      // 添加到队列
      _uploadQueue.addTask(task);
      
      debugPrint('✅ ${character.name} 上传任务已加入队列');
      
    } catch (e) {
      debugPrint('❌ 添加上传任务失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 生成角色图片（调用真实图片 API）
  Future<void> _generateImages() async {
    if (_characters.isEmpty) return;

    // ✅ 读取图片 API 配置
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('image_provider') ?? 'geeknow';
    final storage = SecureStorageManager();
    final model = await storage.getModel(provider: provider, modelType: 'image');
    
    print('\n🎨 开始生成角色图片');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔧 Provider: $provider');
    print('🎯 Model: ${model ?? "未设置"}');
    print('📝 风格参考文字: ${_styleReferenceText.isNotEmpty ? _styleReferenceText : "无"}');
    print('🖼️ 风格参考图片: ${_styleReferenceImage != null ? "有" : "无"}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    int successCount = 0;
    int failCount = 0;

    // ✅ 并发生成（每批 3 个，避免API限流）
    for (var batchStart = 0; batchStart < _characters.length; batchStart += 3) {
      final batchEnd = (batchStart + 3 > _characters.length) ? _characters.length : batchStart + 3;
      final batch = _characters.sublist(batchStart, batchEnd);
      
      print('📦 批次 ${batchStart ~/ 3 + 1}: 生成 ${batch.length} 个角色');
      
      // ✅ 并发生成当前批次的所有角色
      final futures = batch.asMap().entries.map((entry) async {
        final localIndex = entry.key;
        final globalIndex = batchStart + localIndex;
        final character = entry.value;
        
        try {
          // ✅ 构建完整提示词（风格参考 + 角色描述）
          String prompt = character.description;
          if (_styleReferenceText.isNotEmpty) {
            prompt = '$_styleReferenceText, $prompt';
          }
          
          // ✅ 如果有风格参考图片，在提示词中明确说明
          final hasStyleImage = _styleReferenceImage != null && _styleReferenceImage!.isNotEmpty;
          if (hasStyleImage) {
            prompt = '参考图片的艺术风格、色彩和构图风格，但不要融合图片内容。$prompt';
          }
          
          print('   📸 [${globalIndex + 1}/${_characters.length}] ${character.name}');
          
          // ✅ 准备参考图片
          final referenceImages = <String>[];
          if (hasStyleImage) {
            referenceImages.add(_styleReferenceImage!);
          }
          
          // ✅ 调用真实图片 API（独立请求）
          _apiRepository.clearCache();
          final response = await _apiRepository.generateImages(
            provider: provider,
            prompt: prompt,
            model: model,
            count: 1,
            referenceImages: referenceImages.isNotEmpty ? referenceImages : null,
            parameters: {
              'quality': 'standard',
              'size': _imageRatio,  // 使用用户选择的比例
            },
          );
          
          if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
            final imageUrl = response.data!.first.imageUrl;
            
            // 下载并保存到本地
            final savedPath = await _downloadAndSaveImage(imageUrl, 'character_${character.name}');
            
            if (mounted) {
              setState(() {
                _characters[globalIndex] = _characters[globalIndex].copyWith(imageUrl: savedPath);
              });
            }
            
            print('      ✅ 成功\n');
            return true;  // 成功
          } else {
            print('      ❌ 失败: ${response.error}\n');
            return false;  // 失败
          }
        } catch (e) {
          print('      ❌ 异常: $e\n');
          return false;  // 失败
        }
      });
      
      // 等待当前批次所有请求完成
      final results = await Future.wait(futures);
      successCount += results.where((r) => r == true).length;
      failCount += results.where((r) => r == false).length;
      
      // 保存当前批次的结果
      await _saveCharacterData();
      
      print('✅ 批次完成: 成功 ${results.where((r) => r).length}, 失败 ${results.where((r) => !r).length}\n');
    }

    await _saveCharacterData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 角色图片生成完成：成功 $successCount 个，失败 $failCount 个'),
          backgroundColor: successCount > 0 ? Colors.green : Colors.red,
        ),
      );
    }
  }

  /// 显示图片来源选择菜单
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
              Text('角色素材库', style: TextStyle(color: Color(0xFF888888))),
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

  /// 从素材库选择
  Future<void> _selectFromLibrary(int index) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AssetLibrarySelector(
        category: AssetCategory.character,  // 只显示角色素材
      ),
    );

    if (result != null && mounted) {
      final selectedPath = result['path'] as String?;
      final characterInfo = result['characterInfo'] as String?;
      
      if (selectedPath != null) {
        // ✅ 设置更新标志，阻止并发的重新加载
        _isUpdating = true;
        _lastSaveTime = DateTime.now();
        
        try {
          final oldChar = _characters[index];
          debugPrint('📝 准备更新角色 ${oldChar.name}:');
          debugPrint('   - 旧图片: ${oldChar.imageUrl}');
          debugPrint('   - 新图片: $selectedPath');
          debugPrint('   - 旧映射代码: ${oldChar.mappingCode}');
          debugPrint('   - 新映射代码: $characterInfo');
          
          // ✅ 直接创建新对象，同时设置映射代码
          String newDescription = _characters[index].description.replaceAll(RegExp(r'@\w+,'), '').trim();
          
          // ✅ 如果素材已上传，使用素材的映射代码
          if (characterInfo != null && characterInfo.isNotEmpty) {
            newDescription = '$characterInfo${_characters[index].name}';
          }
          
          _characters[index] = CharacterData(
            id: _characters[index].id,
            name: _characters[index].name,
            description: newDescription,
            imageUrl: selectedPath,
            mappingCode: characterInfo,  // ✅ 使用素材的映射代码
            isUploaded: characterInfo != null && characterInfo.isNotEmpty,  // ✅ 如果有映射代码，标记为已上传
          );
          
          debugPrint('✅ 已更新内存中的数据:');
          debugPrint('   - 新图片: ${_characters[index].imageUrl}');
          debugPrint('   - 新描述: ${_characters[index].description}');
          debugPrint('   - 新映射代码: ${_characters[index].mappingCode}');
          debugPrint('   - 已上传: ${_characters[index].isUploaded}');
          
          // ✅ 先保存数据
          await _saveCharacterData();
          
          debugPrint('✅ 已从素材库选择图片并保存');
          
          // ✅ 然后更新 UI
          if (mounted) {
            setState(() {});
          }
        } finally {
          // ✅ 延迟重置更新标志，确保保存完成
          Future.delayed(const Duration(seconds: 2), () {
            _isUpdating = false;
            debugPrint('🔓 解除更新锁');
          });
        }
        
        if (mounted) {
          final message = characterInfo != null && characterInfo.isNotEmpty
              ? '✅ 已选择图片并设置映射代码'
              : '✅ 已选择图片（未上传的素材）';
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    }
  }

  /// 插入本地图片
  Future<void> _insertLocalImage(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty && mounted) {
      // ✅ 立即设置保护时间，防止其他地方重新加载数据
      _lastSaveTime = DateTime.now();
      
      final filePath = result.files.first.path!;
      setState(() {
        // ✅ 直接创建新对象，确保 imageUrl 被更新，并重置上传状态
        _characters[index] = CharacterData(
          id: _characters[index].id,
          name: _characters[index].name,
          description: _characters[index].description.replaceAll(RegExp(r'@\w+,'), '').trim(),  // ✅ 移除旧的映射代码
          imageUrl: filePath,
          mappingCode: null,  // ✅ 清除旧的映射代码
          isUploaded: false,  // ✅ 重置上传状态，允许重新上传
        );
      });
      await _saveCharacterData();
      
      debugPrint('✅ 已更新角色图片: ${_characters[index].name} -> $filePath');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已插入图片')),
        );
      }
    }
  }

  /// 保存图片到本地
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
            
            debugPrint('✅ 图片已保存: $filePath');
            return filePath;  // 返回本地路径
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
      return imageUrl;  // 下载失败，返回原 URL
    } catch (e) {
      debugPrint('💥 保存图片失败: $e');
      return imageUrl;
    }
  }

  /// 查看图片（放大）
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

  /// 显示图片右键菜单
  void _showImageContextMenu(BuildContext context, TapDownDetails details, String imageUrl) {
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
      items: [
        const PopupMenuItem(
          value: 'locate_file',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 8),
              Text('定位文件', style: TextStyle(color: Color(0xFF888888))),
            ],
          ),
        ),
        const PopupMenuItem(
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
    // 查找包含该图片的角色
    final index = _characters.indexWhere((c) => c.imageUrl == imageUrl);
    if (index == -1) return;
    
    final character = _characters[index];
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要删除"${character.name}"的图片吗？',
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
      // 删除本地文件（如果是本地路径且不为空）
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
      
      // 清除角色的图片URL
      // ⚠️ 注意：由于 copyWith 使用 ?? 运算符，无法直接设置为 null
      // 所以我们需要创建一个新的 CharacterData 对象
      if (mounted) {
        // ✅ 立即设置保护时间，防止其他地方重新加载数据
        _lastSaveTime = DateTime.now();
        
        setState(() {
          _characters[index] = CharacterData(
            id: _characters[index].id,
            name: _characters[index].name,
            description: _characters[index].description.replaceAll(RegExp(r'@\w+,'), '').trim(),  // ✅ 移除映射代码
            imageUrl: null,  // ✅ 设置为 null
            mappingCode: null,  // ✅ 清除映射代码
            isUploaded: false,  // ✅ 清除上传状态
          );
        });
        await _saveCharacterData();
        
        debugPrint('✅ 已删除角色图片: ${character.name}');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已删除"${character.name}"的图片'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  /// 定位文件
  void _locateFile(String imageUrl) async {
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

  /// 构建图片Widget（支持网络和本地）
  Widget _buildImageWidget(String imageUrl) {
    // ✅ 检查空字符串
    if (imageUrl.isEmpty) {
      return const Center(
        child: Icon(Icons.image_not_supported, color: Color(0xFF888888)),
      );
    }
    
    try {
      if (imageUrl.startsWith('http')) {
        return Image.network(
          imageUrl, 
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('⚠️ 网络图片加载失败: $error');
            return const Center(
              child: Icon(Icons.broken_image, color: Color(0xFF888888)),
            );
          },
        );
      } else {
        final file = File(imageUrl);
        return Image.file(
          file, 
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('⚠️ 本地图片加载失败: $error');
            return const Center(
              child: Icon(Icons.broken_image, color: Color(0xFF888888)),
            );
          },
        );
      }
    } catch (e) {
      debugPrint('⚠️ 构建图片 Widget 失败: $e');
      return const Center(
        child: Icon(Icons.error, color: Colors.red),
      );
    }
  }
}

/// 角色数据模型
class CharacterData {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;
  final String? mappingCode;  // ✅ 上传后的@代码
  final bool isUploaded;       // ✅ 是否已上传

  CharacterData({
    required this.id,
    required this.name,
    required this.description,
    this.imageUrl,
    this.mappingCode,
    this.isUploaded = false,
  });

  CharacterData copyWith({
    String? name,
    String? description,
    String? imageUrl,
    String? mappingCode,
    bool? isUploaded,
  }) {
    return CharacterData(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      mappingCode: mappingCode ?? this.mappingCode,
      isUploaded: isUploaded ?? this.isUploaded,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'mappingCode': mappingCode,
      'isUploaded': isUploaded,
    };
  }

  factory CharacterData.fromJson(Map<String, dynamic> json) {
    // ✅ 将空字符串转换为 null，避免问题
    final imageUrl = json['imageUrl'] as String?;
    final mappingCode = json['mappingCode'] as String?;
    
    return CharacterData(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      imageUrl: (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl,
      mappingCode: (mappingCode == null || mappingCode.isEmpty) ? null : mappingCode,
      isUploaded: json['isUploaded'] as bool? ?? false,
    );
  }
}
