import 'package:flutter/material.dart';
import 'package:xinghe_new/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:xinghe_new/services/watermark_remover_service.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

class WatermarkRemoverPage extends StatefulWidget {
  const WatermarkRemoverPage({super.key});

  @override
  State<WatermarkRemoverPage> createState() => _WatermarkRemoverPageState();
}

class _WatermarkRemoverPageState extends State<WatermarkRemoverPage> {
  // 图片列表（支持批量）
  List<File> _imageFiles = [];
  int _currentImageIndex = 0;
  
  // 处理状态
  bool _isProcessing = false;
  Map<int, Uint8List?> _processedImages = {}; // 存储处理后的图片
  bool _showComparison = false; // 是否显示对比模式
  String _processingStatus = ''; // 处理状态文本
  double _processingProgress = 0.0; // 处理进度 0-1
  
  // 工具状态
  String _currentTool = 'detect'; // detect, brush, rect
  double _brushSize = 20.0;
  double _detectSensitivity = 0.7;
  
  // 绘制数据
  List<Offset> _brushPoints = [];
  List<Rect> _selectedRects = [];
  Offset? _rectStart;
  Offset? _currentRectEnd; // 当前正在绘制的矩形的结束点
  
  // 保存路径
  String _savePath = '';
  
  @override
  void initState() {
    super.initState();
    _loadSavePath();
  }
  
  /// 加载保存路径
  Future<void> _loadSavePath() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savePath = prefs.getString('canvas_save_path') ?? '';
    });
  }
  
  /// 当前显示的图片
  File? get _currentImage {
    if (_imageFiles.isEmpty) return null;
    return _imageFiles[_currentImageIndex];
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Column(
        children: [
          // 顶部标题栏
          _buildHeader(),
          // 主内容区
          Expanded(
            child: Row(
              children: [
                // 左侧：图片预览区
                Expanded(
                  flex: 3,
                  child: _buildImagePreviewArea(),
                ),
                // 右侧：工具栏
                Container(
                  width: 300,
                  decoration: BoxDecoration(
                    color: AppTheme.scaffoldBackground,
                    border: Border(
                      left: BorderSide(
                        color: AppTheme.dividerColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                  child: _buildToolbar(),
                ),
              ],
            ),
          ),
          // 底部操作栏
          _buildBottomBar(),
        ],
      ),
    );
  }

  /// 构建顶部标题栏
  Widget _buildHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 返回按钮
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: AppTheme.textColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 标题
          Text(
            '图片去水印',
            style: TextStyle(
              color: AppTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
        ],
      ),
    );
  }

  /// 构建图片预览区
  Widget _buildImagePreviewArea() {
    if (_imageFiles.isEmpty) {
      return _buildEmptyState();
    }
    
    final currentImage = _currentImage!;
    final processedImage = _processedImages[_currentImageIndex];
    
    return Container(
      color: AppTheme.scaffoldBackground,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          // 图片导航（如果有多张图片）
          if (_imageFiles.length > 1) ...[
            _buildImageNavigation(),
            const SizedBox(height: 16),
          ],
          // 图片显示（带绘制功能）
          Expanded(
            child: Center(
              child: _buildInteractiveImage(currentImage, processedImage),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建可交互的图片（支持绘制）
  Widget _buildInteractiveImage(File imageFile, Uint8List? processedImage) {
    // 如果是对比模式且有处理结果
    if (_showComparison && processedImage != null) {
      return _buildComparisonView(imageFile, processedImage);
    }
    
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 900,
        maxHeight: 700,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.dividerColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onPanStart: _currentTool != 'detect' && processedImage == null ? _onPanStart : null,
          onPanUpdate: _currentTool != 'detect' && processedImage == null ? _onPanUpdate : null,
          onPanEnd: _currentTool != 'detect' && processedImage == null ? _onPanEnd : null,
          child: Stack(
            children: [
              // 显示图片
              if (processedImage != null)
                Image.memory(
                  processedImage,
                  fit: BoxFit.contain,
                )
              else
                Image.file(
                  imageFile,
                  fit: BoxFit.contain,
                ),
              // 绘制涂抹痕迹和矩形框（覆盖整个容器）
              if (processedImage == null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DrawingPainter(
                      brushPoints: _brushPoints,
                      rects: _selectedRects,
                      currentRect: _rectStart != null && _currentTool == 'rect'
                          ? Rect.fromPoints(_rectStart!, _currentRectEnd ?? _rectStart!)
                          : null,
                      brushSize: _brushSize,
                      showBrush: true, // 始终显示
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 构建对比视图（左右对比）
  Widget _buildComparisonView(File originalFile, Uint8List processedImage) {
    return Row(
      children: [
        // 左侧：原图
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '原图',
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Image.file(
                  originalFile,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
        // 分隔线
        Container(
          width: 2,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: AppTheme.dividerColor.withValues(alpha: 0.5),
        ),
        // 右侧：处理后
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '处理后',
                style: TextStyle(
                  color: const Color(0xFF4FFFB0),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Image.memory(
                  processedImage,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  /// 开始绘制
  void _onPanStart(DragStartDetails details) {
    debugPrint('开始绘制: ${details.localPosition}, 工具: $_currentTool');
    setState(() {
      if (_currentTool == 'brush') {
        _brushPoints.add(details.localPosition);
        debugPrint('添加涂抹点: ${details.localPosition}');
      } else if (_currentTool == 'rect') {
        _rectStart = details.localPosition;
        _currentRectEnd = details.localPosition;
        debugPrint('开始矩形: $_rectStart');
      }
    });
  }
  
  /// 更新绘制
  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      if (_currentTool == 'brush') {
        _brushPoints.add(details.localPosition);
      } else if (_currentTool == 'rect') {
        _currentRectEnd = details.localPosition;
      }
    });
  }
  
  /// 结束绘制
  void _onPanEnd(DragEndDetails details) {
    if (_currentTool == 'rect' && _rectStart != null && _currentRectEnd != null) {
      debugPrint('完成矩形: $_rectStart -> $_currentRectEnd');
      setState(() {
        _selectedRects.add(Rect.fromPoints(_rectStart!, _currentRectEnd!));
        debugPrint('矩形列表: ${_selectedRects.length} 个');
        _rectStart = null;
        _currentRectEnd = null;
      });
    } else if (_currentTool == 'brush') {
      debugPrint('完成涂抹，共 ${_brushPoints.length} 个点');
    }
  }
  
  /// 构建图片导航
  Widget _buildImageNavigation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 上一张
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            onPressed: _currentImageIndex > 0
                ? () => setState(() => _currentImageIndex--)
                : null,
            color: AppTheme.textColor,
          ),
          const SizedBox(width: 16),
          // 当前位置
          Text(
            '${_currentImageIndex + 1} / ${_imageFiles.length}',
            style: TextStyle(
              color: AppTheme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          const SizedBox(width: 16),
          // 下一张
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            onPressed: _currentImageIndex < _imageFiles.length - 1
                ? () => setState(() => _currentImageIndex++)
                : null,
            color: AppTheme.textColor,
          ),
        ],
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 图标 - 极简设计
          Icon(
            Icons.image_outlined,
            size: 80,
            color: AppTheme.accentColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 32),
          Text(
            '选择图片开始去水印',
            style: TextStyle(
              color: AppTheme.textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFamily: 'Microsoft YaHei',
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '支持 JPG、PNG 格式',
            style: TextStyle(
              color: AppTheme.subTextColor.withValues(alpha: 0.7),
              fontSize: 13,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          const SizedBox(height: 40),
          _buildPrimaryButton(
            label: '选择图片',
            icon: Icons.folder_open,
            onTap: _pickImage,
          ),
        ],
      ),
    );
  }

  /// 构建工具栏
  Widget _buildToolbar() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 工具选择
          _buildSectionTitle('检测工具'),
          const SizedBox(height: 12),
          _buildToolButton(
            icon: Icons.auto_fix_high,
            label: '智能检测',
            isSelected: _currentTool == 'detect',
            onTap: () => setState(() => _currentTool = 'detect'),
          ),
          const SizedBox(height: 4),
          _buildToolButton(
            icon: Icons.brush_outlined,
            label: '手动涂抹',
            isSelected: _currentTool == 'brush',
            onTap: () => setState(() => _currentTool = 'brush'),
          ),
          const SizedBox(height: 4),
          _buildToolButton(
            icon: Icons.crop_square,
            label: '矩形框选',
            isSelected: _currentTool == 'rect',
            onTap: () => setState(() => _currentTool = 'rect'),
          ),
          
          const SizedBox(height: 32),
          Divider(color: AppTheme.dividerColor.withValues(alpha: 0.3), height: 1),
          const SizedBox(height: 32),
          
          // 画笔设置（仅在手动涂抹时显示）
          if (_currentTool == 'brush') ...[
            _buildSectionTitle('画笔大小'),
            const SizedBox(height: 20),
            _buildSlider(
              value: _brushSize / 50.0, // 归一化到 0-1
              onChanged: (value) {
                setState(() {
                  _brushSize = value * 50.0; // 范围 0-50
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              '${_brushSize.toInt()} px',
              style: TextStyle(
                color: AppTheme.subTextColor.withValues(alpha: 0.7),
                fontSize: 11,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
            const SizedBox(height: 32),
          ],
          
          // 检测灵敏度（仅在智能检测时显示）
          if (_currentTool == 'detect') ...[
            _buildSectionTitle('检测灵敏度'),
            const SizedBox(height: 20),
            _buildSlider(
              value: _detectSensitivity,
              onChanged: (value) {
                setState(() {
                  _detectSensitivity = value;
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              '${(_detectSensitivity * 100).toInt()}%',
              style: TextStyle(
                color: AppTheme.subTextColor.withValues(alpha: 0.7),
                fontSize: 11,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
            const SizedBox(height: 32),
          ],
          
          // 操作按钮
          if (_imageFiles.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: _buildSecondaryButton(
                label: '清除标记',
                icon: Icons.clear,
                onTap: () {
                  setState(() {
                    _clearDrawing();
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _buildSecondaryButton(
                label: '对比原图',
                icon: Icons.compare,
                onTap: _toggleComparison,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建底部操作栏
  Widget _buildBottomBar() {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        border: Border(
          top: BorderSide(
            color: AppTheme.dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 状态信息
          if (_imageFiles.isNotEmpty)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _imageFiles.length == 1 
                      ? '已选择 1 张图片' 
                      : '已选择 ${_imageFiles.length} 张图片',
                  style: TextStyle(
                    color: AppTheme.subTextColor.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                // 显示处理进度
                if (_isProcessing && _processingStatus.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _processingStatus,
                    style: TextStyle(
                      color: const Color(0xFF4FFFB0),
                      fontSize: 11,
                      fontFamily: 'Microsoft YaHei',
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: _processingProgress,
                      backgroundColor: AppTheme.dividerColor.withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4FFFB0)),
                    ),
                  ),
                ],
              ],
            ),
          const Spacer(),
          // 操作按钮
          if (_imageFiles.isEmpty)
            _buildPrimaryButton(
              label: '选择图片',
              icon: Icons.folder_open,
              onTap: _pickImage,
            )
          else ...[
            _buildSecondaryButton(
              label: '重新选择',
              icon: Icons.refresh,
              onTap: _pickImage,
            ),
            const SizedBox(width: 14),
            // 批量处理按钮（如果有多张图片）
            if (_imageFiles.length > 1)
              _buildSecondaryButton(
                label: '批量处理',
                icon: Icons.auto_awesome,
                onTap: _isProcessing ? () {} : () => _batchProcess(),
              ),
            if (_imageFiles.length > 1) const SizedBox(width: 14),
            // 单张处理按钮
            _buildPrimaryButton(
              label: _isProcessing ? '处理中...' : '处理当前',
              icon: Icons.play_arrow,
              onTap: _isProcessing ? null : _processImage,
            ),
            const SizedBox(width: 14),
            // 保存按钮（如果有处理结果）
            if (_processedImages.isNotEmpty)
              _buildPrimaryButton(
                label: '保存结果',
                icon: Icons.save,
                onTap: _saveResults,
              ),
          ],
        ],
      ),
    );
  }

  /// 构建章节标题
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: AppTheme.textColor.withValues(alpha: 0.9),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        fontFamily: 'Microsoft YaHei',
        letterSpacing: 0.5,
      ),
    );
  }

  /// 构建工具按钮 - 简洁风格（类似主页选择）
  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.surfaceBackground.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected 
                    ? AppTheme.textColor
                    : AppTheme.subTextColor.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isSelected 
                      ? AppTheme.textColor
                      : AppTheme.subTextColor.withValues(alpha: 0.7),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建滑块 - 渐变风格
  Widget _buildSlider({
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: const Color(0xFF4FFFB0),
        inactiveTrackColor: AppTheme.dividerColor.withValues(alpha: 0.3),
        thumbColor: const Color(0xFF3B9EFF),
        overlayColor: const Color(0xFF4FFFB0).withValues(alpha: 0.1),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      child: Slider(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  /// 构建主要按钮 - 渐变风格
  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    
    return MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          decoration: BoxDecoration(
            gradient: isDisabled
                ? LinearGradient(
                    colors: [
                      const Color(0xFF4FFFB0).withValues(alpha: 0.3),
                      const Color(0xFF3B9EFF).withValues(alpha: 0.3),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : const LinearGradient(
                    colors: [
                      Color(0xFF4FFFB0), // 青绿色
                      Color(0xFF3B9EFF), // 蓝色
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: isDisabled ? null : [
              BoxShadow(
                color: const Color(0xFF4FFFB0).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: Colors.white.withValues(alpha: isDisabled ? 0.6 : 1.0),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: isDisabled ? 0.6 : 1.0),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Microsoft YaHei',
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建次要按钮 - 简洁风格
  Widget _buildSecondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBackground.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: AppTheme.textColor.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textColor.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选择图片（支持批量）
  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true, // 支持批量选择
      );
      
      if (result != null && result.files.isNotEmpty) {
        final files = result.files
            .where((file) => file.path != null)
            .map((file) => File(file.path!))
            .toList();
        
        if (files.isNotEmpty) {
          setState(() {
            _imageFiles = files;
            _currentImageIndex = 0;
            _processedImages.clear();
            _clearDrawing();
          });
        }
      }
    } catch (e) {
      debugPrint('选择图片失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('选择图片失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// 清除绘制数据
  void _clearDrawing() {
    _brushPoints.clear();
    _selectedRects.clear();
    _rectStart = null;
  }

  /// 处理图片
  Future<void> _processImage() async {
    if (_currentImage == null) return;
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      // 根据当前工具选择处理方式
      if (_currentTool == 'detect') {
        // 智能检测模式
        await _processWithDetection();
      } else if (_currentTool == 'brush' && _brushPoints.isNotEmpty) {
        // 手动涂抹模式
        await _processWithBrush();
      } else if (_currentTool == 'rect' && _selectedRects.isNotEmpty) {
        // 矩形框选模式
        await _processWithRects();
      } else {
        throw Exception('请先标记水印区域');
      }
      
      // 不显示提示框，静默完成
    } catch (e) {
      debugPrint('处理图片失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('处理失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  /// 使用智能检测处理
  Future<void> _processWithDetection() async {
    final imagePath = _currentImage!.path;
    
    // 先检测水印区域
    final detectedRects = await WatermarkRemoverService.detectWatermark(imagePath);
    
    if (detectedRects.isEmpty) {
      throw Exception('未检测到水印区域，请尝试手动标记');
    }
    
    // 使用检测到的区域去除水印
    final result = await WatermarkRemoverService.removeWatermark(
      imagePath: imagePath,
      maskRects: detectedRects,
    );
    
    if (result != null) {
      setState(() {
        _processedImages[_currentImageIndex] = result;
      });
    } else {
      throw Exception('处理失败');
    }
  }
  
  /// 使用手动涂抹处理
  Future<void> _processWithBrush() async {
    // 获取图片实际尺寸
    final imageBytes = await _currentImage!.readAsBytes();
    final decodedImage = await decodeImageFromList(imageBytes);
    
    // 计算缩放比例
    final displayWidth = 900.0;
    final displayHeight = 700.0;
    
    final imageWidth = decodedImage.width.toDouble();
    final imageHeight = decodedImage.height.toDouble();
    
    final scaleX = imageWidth / displayWidth;
    final scaleY = imageHeight / displayHeight;
    final scale = scaleX > scaleY ? scaleX : scaleY;
    
    debugPrint('涂抹坐标转换 - 缩放比例: $scale');
    
    // 转换涂抹点坐标到实际图片坐标
    final scaledPoints = _brushPoints.map((point) {
      return Offset(point.dx * scale, point.dy * scale);
    }).toList();
    
    debugPrint('原始点数: ${_brushPoints.length}, 缩放后点数: ${scaledPoints.length}');
    
    final result = await WatermarkRemoverService.removeWatermark(
      imagePath: _currentImage!.path,
      maskPoints: scaledPoints,
      brushSize: _brushSize * scale, // 画笔大小也要缩放
    );
    
    if (result != null) {
      setState(() {
        _processedImages[_currentImageIndex] = result;
      });
    } else {
      throw Exception('处理失败');
    }
  }
  
  /// 使用矩形框选处理
  Future<void> _processWithRects() async {
    // 获取图片实际尺寸
    final imageBytes = await _currentImage!.readAsBytes();
    final decodedImage = await decodeImageFromList(imageBytes);
    
    // 计算缩放比例（显示尺寸 vs 实际尺寸）
    // 注意：这里需要根据实际显示的容器大小来计算
    // 假设最大显示尺寸是 900x700
    final displayWidth = 900.0;
    final displayHeight = 700.0;
    
    final imageWidth = decodedImage.width.toDouble();
    final imageHeight = decodedImage.height.toDouble();
    
    // 计算实际的缩放比例（保持宽高比）
    final scaleX = imageWidth / displayWidth;
    final scaleY = imageHeight / displayHeight;
    final scale = scaleX > scaleY ? scaleX : scaleY;
    
    debugPrint('图片实际尺寸: ${imageWidth}x$imageHeight');
    debugPrint('显示尺寸: ${displayWidth}x$displayHeight');
    debugPrint('缩放比例: $scale');
    
    // 转换矩形坐标到实际图片坐标
    final scaledRects = _selectedRects.map((rect) {
      final scaledRect = Rect.fromLTRB(
        rect.left * scale,
        rect.top * scale,
        rect.right * scale,
        rect.bottom * scale,
      );
      debugPrint('原始矩形: $rect -> 缩放后: $scaledRect');
      return scaledRect;
    }).toList();
    
    final result = await WatermarkRemoverService.removeWatermark(
      imagePath: _currentImage!.path,
      maskRects: scaledRects,
    );
    
    if (result != null) {
      setState(() {
        _processedImages[_currentImageIndex] = result;
      });
    } else {
      throw Exception('处理失败');
    }
  }
  
  /// 从字节数据解码图片
  Future<ui.Image> decodeImageFromList(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
  
  /// 对比原图
  void _toggleComparison() {
    final processedImage = _processedImages[_currentImageIndex];
    if (processedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先处理图片'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      _showComparison = !_showComparison;
    });
  }
  
  /// 批量处理所有图片
  Future<void> _batchProcess() async {
    if (_imageFiles.isEmpty) return;
    
    setState(() {
      _isProcessing = true;
      _processingProgress = 0.0;
    });
    
    int successCount = 0;
    int failCount = 0;
    
    for (int i = 0; i < _imageFiles.length; i++) {
      try {
        setState(() {
          _currentImageIndex = i;
          _processingStatus = '正在处理第 ${i + 1}/${_imageFiles.length} 张图片...';
          _processingProgress = (i + 1) / _imageFiles.length;
        });
        
        // 根据当前工具处理
        if (_currentTool == 'detect') {
          await _processWithDetection();
        } else if (_currentTool == 'brush' && _brushPoints.isNotEmpty) {
          await _processWithBrush();
        } else if (_currentTool == 'rect' && _selectedRects.isNotEmpty) {
          await _processWithRects();
        } else {
          // 如果没有标记，使用智能检测
          await _processWithDetection();
        }
        
        successCount++;
      } catch (e) {
        debugPrint('处理第 ${i + 1} 张图片失败: $e');
        failCount++;
      }
    }
    
    setState(() {
      _isProcessing = false;
      _processingStatus = '';
      _processingProgress = 0.0;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('批量处理完成！成功: $successCount, 失败: $failCount'),
          backgroundColor: const Color(0xFF4FFFB0),
        ),
      );
    }
  }
  
  /// 保存处理结果
  Future<void> _saveResults() async {
    if (_processedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有可保存的结果'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      // 确定保存路径
      String savePath = _savePath;
      if (savePath.isEmpty) {
        // 如果没有设置保存路径，使用原图所在目录
        savePath = path.dirname(_imageFiles.first.path);
      }
      
      // 创建保存目录
      final saveDir = Directory(path.join(savePath, 'watermark_removed'));
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      
      int savedCount = 0;
      
      // 保存所有处理过的图片
      for (final entry in _processedImages.entries) {
        final index = entry.key;
        final imageData = entry.value;
        
        if (imageData != null) {
          final originalFile = _imageFiles[index];
          final fileName = path.basenameWithoutExtension(originalFile.path);
          final ext = path.extension(originalFile.path);
          final saveName = '${fileName}_removed$ext';
          final saveFile = File(path.join(saveDir.path, saveName));
          
          await saveFile.writeAsBytes(imageData);
          savedCount++;
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功保存 $savedCount 张图片到:\n${saveDir.path}'),
            backgroundColor: const Color(0xFF4FFFB0),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('保存失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// 绘制画笔和矩形的 Painter
class _DrawingPainter extends CustomPainter {
  final List<Offset> brushPoints;
  final List<Rect> rects;
  final Rect? currentRect;
  final double brushSize;
  final bool showBrush;

  _DrawingPainter({
    required this.brushPoints,
    required this.rects,
    this.currentRect,
    required this.brushSize,
    required this.showBrush,
  });

  @override
  void paint(Canvas canvas, Size size) {
    debugPrint('绘制 Painter: size=$size, 涂抹点=${brushPoints.length}, 矩形=${rects.length}, showBrush=$showBrush');
    
    // 绘制画笔痕迹（无论 showBrush 是什么，只要有点就显示）
    if (brushPoints.isNotEmpty) {
      final paint = Paint()
        ..color = const Color(0xFF4FFFB0).withValues(alpha: 0.5)
        ..strokeWidth = brushSize
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < brushPoints.length - 1; i++) {
        canvas.drawLine(brushPoints[i], brushPoints[i + 1], paint);
      }
      
      // 绘制圆点表示画笔点
      final pointPaint = Paint()
        ..color = const Color(0xFF4FFFB0).withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      
      for (final point in brushPoints) {
        canvas.drawCircle(point, brushSize / 2, pointPaint);
      }
      
      debugPrint('已绘制 ${brushPoints.length} 个涂抹点');
    }

    // 绘制已完成的矩形
    final rectPaint = Paint()
      ..color = const Color(0xFF4FFFB0).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    
    final rectBorderPaint = Paint()
      ..color = const Color(0xFF4FFFB0)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final rect in rects) {
      canvas.drawRect(rect, rectPaint);
      canvas.drawRect(rect, rectBorderPaint);
      debugPrint('绘制矩形: $rect');
    }

    // 绘制正在绘制的矩形
    if (currentRect != null) {
      canvas.drawRect(currentRect!, rectPaint);
      canvas.drawRect(currentRect!, rectBorderPaint);
      debugPrint('绘制当前矩形: $currentRect');
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter oldDelegate) {
    // 只要有任何变化就重绘
    return true;
  }
}
