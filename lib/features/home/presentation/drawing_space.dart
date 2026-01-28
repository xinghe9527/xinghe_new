import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinghe_new/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/services/api/providers/openai_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import '../domain/drawing_task.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';

/// GeekNow 图片模型列表（与设置界面保持一致）
class GeekNowImageModels {
  static const List<String> models = [
    // OpenAI 系列
    'gpt-4o', 'gpt-4-turbo', 'dall-e-3', 'dall-e-2',
    // Gemini 图像生成系列
    'gemini-3-pro-image-preview', 'gemini-3-pro-image-preview-lite', 
    'gemini-2.5-flash-image-preview', 'gemini-2.5-flash-image', 'gemini-pro-vision',
    // Stable Diffusion 系列
    'stable-diffusion-xl', 'stable-diffusion-3',
    // Midjourney 风格
    'midjourney-v6', 'midjourney-niji',
  ];
}

class DrawingSpace extends StatefulWidget {
  const DrawingSpace({super.key});

  @override
  State<DrawingSpace> createState() => _DrawingSpaceState();
}

class _DrawingSpaceState extends State<DrawingSpace> {
  final List<DrawingTask> _tasks = [DrawingTask.create()];
  final LogManager _logger = LogManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTasks());
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('drawing_tasks');
      if (tasksJson != null && tasksJson.isNotEmpty && mounted) {
        final tasksList = jsonDecode(tasksJson) as List;
        setState(() {
          _tasks.clear();
          _tasks.addAll(tasksList.map((json) => DrawingTask.fromJson(json)).toList());
        });
        _logger.success('成功加载 ${_tasks.length} 个绘图任务', module: '绘图空间');
      }
    } catch (e) {
      debugPrint('加载任务失败: $e');
      _logger.error('加载绘图任务失败: $e', module: '绘图空间');
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('drawing_tasks', jsonEncode(_tasks.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('保存任务失败: $e');
    }
  }

  void _addNewTask() {
    if (mounted) {
      // 如果有现有任务，从最新任务复制设置
      final newTask = _tasks.isEmpty 
          ? DrawingTask.create()
          : DrawingTask.create().copyWith(
              model: _tasks.first.model,
              ratio: _tasks.first.ratio,
              quality: _tasks.first.quality,
              batchCount: _tasks.first.batchCount,
            );
      setState(() => _tasks.insert(0, newTask));
      _saveTasks();
      _logger.success('创建新的绘图任务', module: '绘图空间', extra: {
        'model': newTask.model,
        'ratio': newTask.ratio,
        'quality': newTask.quality,
      });
    }
  }

  void _deleteTask(String taskId) {
    if (mounted) {
      setState(() => _tasks.removeWhere((t) => t.id == taskId));
      _saveTasks();
      _logger.info('删除绘图任务', module: '绘图空间');
    }
  }

  void _updateTask(DrawingTask task) {
    if (mounted) {
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) _tasks[index] = task;
      });
      _saveTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, _, __) {
        return Container(
          color: AppTheme.scaffoldBackground,
          child: Column(
            children: [
              _buildToolbar(),
              Expanded(
                child: _tasks.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(24),
                        itemCount: _tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 20),
                        itemBuilder: (context, index) => TaskCard(
                          key: ValueKey(_tasks[index].id),
                          task: _tasks[index],
                          onUpdate: _updateTask,
                          onDelete: () => _deleteTask(_tasks[index].id),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Text('绘图空间', style: TextStyle(color: AppTheme.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          _toolButton(Icons.delete_sweep_rounded, '清空全部', () {
            if (_tasks.isEmpty) return;
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppTheme.surfaceBackground,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text('清空全部任务', style: TextStyle(color: AppTheme.textColor)),
                content: Text('确定要删除所有任务吗？此操作不可恢复。', style: TextStyle(color: AppTheme.subTextColor)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: TextStyle(color: AppTheme.subTextColor))),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      final count = _tasks.length;
                      setState(() => _tasks.clear());
                      _saveTasks();
                      _logger.warning('清空所有绘图任务', module: '绘图空间', extra: {'删除数量': count});
                    },
                    child: const Text('确定', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(width: 12),
          _newTaskButton(),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: AppTheme.textColor.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Icon(icon, color: color ?? AppTheme.subTextColor, size: 16),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color ?? AppTheme.subTextColor, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _newTaskButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _addNewTask,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: const Color(0xFF2AF598).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: const [
              Icon(Icons.add, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('新建任务', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.art_track, size: 100, color: AppTheme.subTextColor.withOpacity(0.2)),
          const SizedBox(height: 24),
          Text('开始你的创作之旅', style: TextStyle(color: AppTheme.textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('创建一个新任务，开始AI绘图', style: TextStyle(color: AppTheme.subTextColor, fontSize: 14)),
          const SizedBox(height: 32),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _addNewTask,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: const Color(0xFF2AF598).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('创建任务', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TaskCard extends StatefulWidget {
  final DrawingTask task;
  final Function(DrawingTask) onUpdate;
  final VoidCallback onDelete;

  const TaskCard({super.key, required this.task, required this.onUpdate, required this.onDelete});

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  late final TextEditingController _controller;
  List<String> _models = ['DALL-E 3', 'Midjourney', 'Stable Diffusion', 'Flux'];
  final List<String> _ratios = ['1:1', '9:16', '16:9', '4:3', '3:4'];
  final List<String> _qualities = ['1K', '2K', '4K'];
  final LogManager _logger = LogManager();
  final SecureStorageManager _storage = SecureStorageManager();
  String _imageProvider = 'openai';  // 当前图片服务商

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.prompt);
    _loadImageProvider();  // 加载服务商和模型列表
  }

  /// 从设置加载图片服务商，并更新可用模型列表
  Future<void> _loadImageProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('image_provider') ?? 'openai';
      
      if (mounted) {
        setState(() {
          _imageProvider = provider;
          _models = _getModelsForProvider(provider);
          
          // 如果当前任务的模型不在新列表中，设置为列表第一个
          if (!_models.contains(widget.task.model)) {
            widget.task.model = _models.first;
          }
        });
      }
    } catch (e) {
      _logger.error('加载图片服务商失败: $e', module: '绘图空间');
    }
  }

  /// 根据服务商获取可用模型列表
  List<String> _getModelsForProvider(String provider) {
    switch (provider.toLowerCase()) {
      case 'geeknow':
        return GeekNowImageModels.models;
      case 'openai':
        return ['gpt-4o', 'gpt-4-turbo', 'dall-e-3', 'dall-e-2'];
      case 'gemini':
        return ['gemini-3-pro-image-preview', 'gemini-2.5-flash-image', 'gemini-pro-vision'];
      case 'midjourney':
        return ['midjourney-v6', 'midjourney-v5.2', 'midjourney-niji'];
      default:
        return ['DALL-E 3', 'Midjourney', 'Stable Diffusion', 'Flux'];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update(DrawingTask task) => widget.onUpdate(task);

  /// 显示任务菜单
  void _showTaskMenu(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 20, 0),  // 右上角位置
      color: AppTheme.surfaceBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        widget.onDelete();
      }
    });
  }

  /// 下载并保存图片到本地
  Future<List<String>> _downloadAndSaveImages(List<String> imageUrls) async {
    final savedPaths = <String>[];
    
    try {
      // 从设置中读取保存路径
      final prefs = await SharedPreferences.getInstance();
      final savePath = imageSavePathNotifier.value;
      
      _logger.info('图片保存路径', module: '绘图空间', extra: {
        'path': savePath,
        'imageCount': imageUrls.length,
      });
      
      if (savePath == '未设置' || savePath.isEmpty) {
        _logger.warning('未设置图片保存路径，图片仅在线显示', module: '绘图空间');
        return imageUrls;  // 返回原 URL
      }
      
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      
      // 下载并保存每张图片（带重试）
      for (var i = 0; i < imageUrls.length; i++) {
        try {
          final url = imageUrls[i];
          String? savedPath;
          
          // 重试最多3次
          for (var retry = 0; retry < 3; retry++) {
            try {
              final response = await http.get(
                Uri.parse(url),
                headers: {'Connection': 'keep-alive'},
              ).timeout(const Duration(seconds: 30));
              
              if (response.statusCode == 200) {
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final fileName = 'image_${timestamp}_$i.png';
                final filePath = path.join(savePath, fileName);
                
                final file = File(filePath);
                await file.writeAsBytes(response.bodyBytes);
                
                savedPath = filePath;
                _logger.success('图片已保存', module: '绘图空间', extra: {
                  'path': filePath,
                  'retry': retry,
                });
                break;  // 成功，跳出重试
              } else {
                _logger.warning('下载失败 (重试 $retry/3): HTTP ${response.statusCode}', module: '绘图空间');
              }
            } catch (e) {
              _logger.warning('下载异常 (重试 $retry/3): $e', module: '绘图空间');
              if (retry < 2) {
                await Future.delayed(Duration(seconds: retry + 1));  // 等待1/2/3秒后重试
              }
            }
          }
          
          savedPaths.add(savedPath ?? url);  // 使用本地路径或在线 URL
          
        } catch (e) {
          _logger.error('保存图片失败: $e', module: '绘图空间');
          savedPaths.add(imageUrls[i]);  // 保存失败，使用在线 URL
        }
      }
    } catch (e) {
      _logger.error('保存图片失败: $e', module: '绘图空间');
      return imageUrls;  // 出错，返回原 URL
    }
    
    return savedPaths;
  }

  /// 真实的图片生成（调用 GeekNow API）
  Future<void> _generateImages() async {
    if (widget.task.prompt.trim().isEmpty) {
      _logger.warning('提示词为空', module: '绘图空间');
      return;
    }

    final batchCount = widget.task.batchCount;

    _logger.info('开始生成图片', module: '绘图空间', extra: {
      'model': widget.task.model,
      'count': batchCount,
      'ratio': widget.task.ratio,
      'quality': widget.task.quality,
      'references': widget.task.referenceImages.length,
    });

    // 立即添加占位符（显示"生成中"）
    final placeholders = List.generate(batchCount, (i) => 'loading_${DateTime.now().millisecondsSinceEpoch}_$i');
    _update(widget.task.copyWith(
      generatedImages: [...widget.task.generatedImages, ...placeholders],
    ));

    try {
      // 从设置中读取图片 API 配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('image_provider') ?? 'geeknow';
      final baseUrl = await _storage.getBaseUrl(provider: provider);
      final apiKey = await _storage.getApiKey(provider: provider);

      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置图片 API，请先在设置中配置');
      }

      // 创建 API 配置
      final config = ApiConfig(
        provider: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );

      // 创建服务
      final service = OpenAIService(config);

      // 📤 详细记录发送给 API 的所有参数
      _logger.info('📤 发送给 API 的完整参数', module: '绘图空间', extra: {
        '🌐 API Provider': provider,
        '🔗 API BaseUrl': baseUrl,
        '📝 提示词': widget.task.prompt,
        '🤖 模型': widget.task.model,
        '📐 比例 (ratio/size)': widget.task.ratio,
        '🎨 质量 (quality)': widget.task.quality,
        '🔢 批量数量': batchCount,
        '🖼️ 参考图片数量': widget.task.referenceImages.length,
        '📁 参考图片路径': widget.task.referenceImages.isEmpty 
            ? '无参考图片（文生图）' 
            : widget.task.referenceImages.join(' | '),
      });

      // 批量生成：多次调用 API
      final allImageUrls = <String>[];
      
      for (int i = 0; i < batchCount; i++) {
        _logger.info('🎯 生成第 ${i + 1}/$batchCount 张', module: '绘图空间');
        
        _logger.info('📦 单次 API 请求 parameters', module: '绘图空间', extra: {
          'n': 1,
          'size': widget.task.ratio,
          'quality': widget.task.quality,
        });
        
        // 调用图片生成 API（每次生成1张）
        final result = await service.generateImagesByChat(
          prompt: widget.task.prompt,
          model: widget.task.model,
          referenceImagePaths: widget.task.referenceImages.isNotEmpty ? widget.task.referenceImages : null,
          parameters: {
            'n': 1,  // 每次生成1张
            'size': widget.task.ratio,  // 传递比例参数
            'quality': widget.task.quality,  // 传递质量参数
          },
        );

        if (result.isSuccess && result.data != null && result.data!.imageUrls.isNotEmpty) {
          allImageUrls.addAll(result.data!.imageUrls);
          _logger.success('第 ${i + 1} 张生成成功', module: '绘图空间', extra: {
            'urls': result.data!.imageUrls.join(', '),
          });
        } else {
          // 📝 详细记录失败原因
          _logger.error('第 ${i + 1} 张生成失败', module: '绘图空间', extra: {
            'isSuccess': result.isSuccess,
            'hasData': result.data != null,
            'imageUrlsCount': result.data?.imageUrls.length ?? 0,
            'errorMessage': result.errorMessage ?? '无错误信息',
            'statusCode': result.statusCode,
          });
        }
        
        // 避免请求过快
        if (i < batchCount - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (allImageUrls.isNotEmpty) {
        _logger.success('批量生成完成，共 ${allImageUrls.length} 张图片', module: '绘图空间', extra: {
          'requested': batchCount,
          'received': allImageUrls.length,
          'urls': allImageUrls.join(', '),
        });
        
        final imageUrls = allImageUrls;
        
        // 下载并保存图片到本地
        final savedPaths = await _downloadAndSaveImages(imageUrls);
        
        // 替换占位符为本地路径
        final currentImages = List<String>.from(widget.task.generatedImages);
        // 移除刚添加的占位符
        for (var placeholder in placeholders) {
          final index = currentImages.indexOf(placeholder);
          if (index != -1) {
            currentImages.removeAt(index);
          }
        }
        // 添加保存的本地路径
        currentImages.addAll(savedPaths);
        
        // 确保状态更新为 completed
        _update(widget.task.copyWith(
          generatedImages: currentImages,
          status: TaskStatus.completed,
        ));
      } else {
        throw Exception('批量生成失败：没有生成任何图片');
      }

    } catch (e, stackTrace) {
      _logger.error('图片生成失败: $e', module: '绘图空间');
      debugPrint('Stack Trace: $stackTrace');
      
      // 移除占位符或标记为失败
      final currentImages = List<String>.from(widget.task.generatedImages);
      for (var placeholder in placeholders) {
        final index = currentImages.indexOf(placeholder);
        if (index != -1) {
          currentImages[index] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
        }
      }
      
      // 检查是否还有"生成中"的占位符
      final hasLoadingPlaceholder = currentImages.any((img) => img.startsWith('loading_'));
      
      _update(widget.task.copyWith(
        generatedImages: currentImages,
        status: hasLoadingPlaceholder ? TaskStatus.generating : TaskStatus.completed,
      ));
    }
  }

  // 构建单个图片项（处理占位符、真实图片、失败状态）
  Widget _buildImageItem(String imageUrl) {
    return Stack(
      children: [
        // 图片内容
        _buildImageContent(imageUrl),
        
        // 删除按钮（右上角）
        Positioned(
          top: 4,
          right: 4,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _deleteImage(imageUrl),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageContent(String imageUrl) {
    // 占位符：生成中
    if (imageUrl.startsWith('loading_')) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 12),
            Text('生成中...', style: TextStyle(color: AppTheme.accentColor, fontSize: 11)),
          ],
        ),
      );
    }
    
    // 失败状态
    if (imageUrl.startsWith('failed_')) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text('生成失败', style: TextStyle(color: Colors.red, fontSize: 11)),
          ],
        ),
      );
    }
    
    // 真实图片（支持点击放大和右键）
    final imageFile = File(imageUrl);
    final isLocalFile = imageFile.existsSync();
    final isOnlineUrl = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // 左键点击：放大查看
        onTap: () => _showImagePreviewNew(imageUrl, isLocalFile),
        // 右键：显示菜单（本地文件和在线图片都支持）
        onSecondaryTapDown: (isLocalFile || isOnlineUrl)
            ? (details) => _showContextMenu(context, details.globalPosition, imageUrl, isLocalFile)
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isLocalFile
              ? Image.file(imageFile, fit: BoxFit.cover)
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(Icons.broken_image, color: AppTheme.subTextColor, size: 40),
                    );
                  },
                ),
        ),
      ),
    );
  }

  // 删除图片
  void _deleteImage(String imageUrl) {
    final currentImages = List<String>.from(widget.task.generatedImages);
    currentImages.remove(imageUrl);
    
    // 检查是否还有"生成中"的占位符
    final hasLoadingPlaceholder = currentImages.any((img) => img.startsWith('loading_'));
    final newStatus = hasLoadingPlaceholder ? TaskStatus.generating : TaskStatus.completed;
    
    _update(widget.task.copyWith(
      generatedImages: currentImages,
      status: newStatus,
    ));
    
    _logger.info('删除图片', module: '绘图空间', extra: {
      'remainingImages': currentImages.length,
      'hasLoading': hasLoadingPlaceholder,
      'newStatus': newStatus.toString(),
    });
  }

  // 显示图片预览（放大）- 新版本支持本地文件
  void _showImagePreviewNew(String imageUrl, bool isLocalFile) {
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
                child: isLocalFile
                    ? Image.file(File(imageUrl))
                    : Image.network(imageUrl),
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

  // 显示右键菜单
  void _showContextMenu(BuildContext context, Offset position, String imageUrl, bool isLocalFile) {
    final menuItems = <PopupMenuEntry<String>>[];
    
    if (isLocalFile) {
      // 本地文件：显示"查看文件夹"
      menuItems.add(
        PopupMenuItem<String>(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: AppTheme.textColor),
              const SizedBox(width: 12),
              Text('查看文件夹', style: TextStyle(color: AppTheme.textColor)),
            ],
          ),
        ),
      );
    } else {
      // 在线图片：显示"复制链接"
      menuItems.add(
        PopupMenuItem<String>(
          value: 'copy_url',
          child: Row(
            children: [
              Icon(Icons.link, size: 18, color: AppTheme.textColor),
              const SizedBox(width: 12),
              Text('复制图片链接', style: TextStyle(color: AppTheme.textColor)),
            ],
          ),
        ),
      );
    }
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: menuItems,
    ).then((value) {
      if (value == 'open_folder') {
        _openFileLocation(imageUrl);
      } else if (value == 'copy_url') {
        Clipboard.setData(ClipboardData(text: imageUrl));
        _logger.success('图片链接已复制', module: '绘图空间');
      }
    });
  }

  // 打开文件所在文件夹
  Future<void> _openFileLocation(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final directory = file.parent.path;
        await Process.run('explorer', ['/select,', filePath], runInShell: true);
        _logger.success('已打开文件夹', module: '绘图空间', extra: {'path': directory});
      }
    } catch (e) {
      _logger.error('打开文件夹失败: $e', module: '绘图空间');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(flex: 55, child: _buildLeft()),
          Container(width: 1, color: AppTheme.dividerColor),
          Expanded(flex: 45, child: _buildRight()),
        ],
      ),
    );
  }

  Widget _buildLeft() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                // 消费滚轮事件，阻止向外传播
              },
              child: Container(
                decoration: BoxDecoration(color: AppTheme.inputBackground, borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.all(14),
                child: SingleChildScrollView(
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    style: TextStyle(color: AppTheme.textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '输入画面描述...',
                      hintStyle: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onChanged: (v) => _update(widget.task.copyWith(prompt: v)),
                  ),
                ),
              ),
            ),
          ),
          if (widget.task.referenceImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildReferenceImages(),
          ],
          const SizedBox(height: 16),
          _bottomControls(),
        ],
      ),
    );
  }

  Widget _buildReferenceImages() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.task.referenceImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final imagePath = widget.task.referenceImages[index];
          return Stack(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showImagePreview(context, imagePath),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.inputBackground,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.dividerColor),
                      image: DecorationImage(
                        image: FileImage(File(imagePath)),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 1,
                right: 1,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      final newImages = List<String>.from(widget.task.referenceImages);
                      newImages.removeAt(index);
                      _update(widget.task.copyWith(referenceImages: newImages));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 10),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showImagePreview(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
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

  Widget _bottomControls() {
    return Row(
      children: [
        _addImageButton(),
        const SizedBox(width: 12),
        Expanded(child: _params()),
        const SizedBox(width: 12),
        _genButton(),
      ],
    );
  }

  Widget _params() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _compactModelSelector(),  // 紧凑型模型选择器
        _dropdown(null, widget.task.ratio, _ratios, (v) => _update(widget.task.copyWith(ratio: v))),
        _dropdown(null, widget.task.quality, _qualities, (v) => _update(widget.task.copyWith(quality: v))),
        _batch(),
      ],
    );
  }

  /// 紧凑型模型选择器（只显示"模型"文字，不显示当前选中值）
  Widget _compactModelSelector() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.inputBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('模型', style: TextStyle(color: AppTheme.subTextColor, fontSize: 11)),
          PopupMenuButton<String>(
            icon: Icon(Icons.arrow_drop_down, color: AppTheme.subTextColor, size: 16),
            offset: const Offset(0, 40),
            color: AppTheme.surfaceBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            itemBuilder: (context) {
              return _models.map((model) {
                final isSelected = model == widget.task.model;
                return PopupMenuItem<String>(
                  value: model,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check : Icons.check_box_outline_blank,
                        size: 16,
                        color: isSelected ? AppTheme.accentColor : Colors.transparent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          model,
                          style: TextStyle(
                            color: isSelected ? AppTheme.accentColor : AppTheme.textColor,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            onSelected: (v) => _update(widget.task.copyWith(model: v)),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String? label, String value, List<String> items, Function(String) onChanged) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.inputBackground, 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: AppTheme.dividerColor)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(label, style: TextStyle(color: AppTheme.subTextColor, fontSize: 11)),
            const SizedBox(width: 6),
          ],
          DropdownButton<String>(
            value: value,
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: TextStyle(color: AppTheme.textColor, fontSize: 12)))).toList(),
            onChanged: (v) => onChanged(v!),
            underline: const SizedBox(),
            dropdownColor: AppTheme.surfaceBackground,
            icon: Icon(Icons.arrow_drop_down, color: AppTheme.subTextColor, size: 16),
            isDense: true,
          ),
        ],
      ),
    );
  }

  Widget _batch() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.inputBackground, 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: AppTheme.dividerColor)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('批量', style: TextStyle(color: AppTheme.subTextColor, fontSize: 11)),
          const SizedBox(width: 6),
          _batchBtn(Icons.remove, widget.task.batchCount > 1, () => _update(widget.task.copyWith(batchCount: widget.task.batchCount - 1))),
          SizedBox(width: 28, child: Center(child: Text('${widget.task.batchCount}', style: TextStyle(color: AppTheme.textColor, fontSize: 12, fontWeight: FontWeight.bold)))),
          _batchBtn(Icons.add, widget.task.batchCount < 20, () => _update(widget.task.copyWith(batchCount: widget.task.batchCount + 1))),
        ],
      ),
    );
  }

  Widget _batchBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Icon(icon, color: enabled ? AppTheme.textColor : AppTheme.subTextColor.withOpacity(0.3), size: 16),
      ),
    );
  }

  Widget _addImageButton() {
    final canAddMore = widget.task.referenceImages.length < 9;
    return MouseRegion(
      cursor: canAddMore ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: canAddMore ? () async {
          try {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.image,
              allowMultiple: true,
            );
            if (result != null && result.files.isNotEmpty) {
              final currentCount = widget.task.referenceImages.length;
              final availableSlots = 9 - currentCount;
              final newImages = result.files
                  .take(availableSlots)
                  .map((file) => file.path!)
                  .toList();
              _update(widget.task.copyWith(
                referenceImages: [...widget.task.referenceImages, ...newImages],
              ));
              _logger.success('添加 ${newImages.length} 张参考图片', module: '绘图空间');
            }
          } catch (e) {
            _logger.error('添加图片失败: $e', module: '绘图空间');
          }
        } : null,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: canAddMore ? AppTheme.inputBackground : AppTheme.inputBackground.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Icon(
            Icons.add_photo_alternate_outlined, 
            color: canAddMore ? AppTheme.subTextColor : AppTheme.subTextColor.withOpacity(0.3), 
            size: 22
          ),
        ),
      ),
    );
  }

  Widget _genButton() {
    final isGen = widget.task.status == TaskStatus.generating;
    return MouseRegion(
      cursor: isGen ? SystemMouseCursors.wait : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isGen ? null : _generateImages,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: const Color(0xFF2AF598).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Center(
            child: isGen
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildRight() {
    final isGenerating = widget.task.status == TaskStatus.generating;
    
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: isGenerating && widget.task.generatedImages.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text('生成中...', style: TextStyle(color: AppTheme.accentColor, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('请稍候', style: TextStyle(color: AppTheme.subTextColor, fontSize: 12)),
                ]))
              : widget.task.generatedImages.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.image_outlined, size: 64, color: AppTheme.subTextColor.withOpacity(0.2)),
                      const SizedBox(height: 12),
                      Text('等待生成', style: TextStyle(color: AppTheme.subTextColor, fontSize: 14)),
                    ]))
                  : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, 
                    crossAxisSpacing: 12, 
                    mainAxisSpacing: 12, 
                    childAspectRatio: 1.0,
                  ),
                  itemCount: widget.task.generatedImages.length,  // 显示所有图片
                  itemBuilder: (context, index) {
                    final imageUrl = widget.task.generatedImages[index];
                    return _buildImageItem(imageUrl);
                  },
                ),
        ),
        Positioned(
          top: -2,  // 上移到卡片边缘外
          right: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showTaskMenu(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBackground.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.more_horiz, color: AppTheme.textColor, size: 16),  // ⋯ 横向三个点
              ),
            ),
          ),
        ),
      ],
    );
  }
}
