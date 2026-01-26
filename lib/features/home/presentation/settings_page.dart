import 'package:flutter/material.dart';
import 'package:xinghe_new/main.dart'; // 引入全局 themeNotifier 和 pathNotifiers
import 'package:file_picker/file_picker.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onBack;

  const SettingsPage({super.key, required this.onBack});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _mainTabIndex = 0; // 0: API设置, 1: 风格设置, 2: 保存设置
  int _apiSubTabIndex = 0; // 0: LLM模型, 1: 图片模型, 2: 视频模型, 3: 上传设置
  bool _isPickingImagePath = false; // 图片路径选择状态
  bool _isPickingVideoPath = false; // 视频路径选择状态

  final List<String> _mainTabs = ['API设置', '风格设置', '保存设置'];
  final List<String> _apiSubTabs = ['LLM模型', '图片模型', '视频模型', '上传设置'];

  final List<Map<String, dynamic>> _styleOptions = [
    {
      'name': '深邃黑',
      'desc': '极客 OLED 风格，沉浸式创作体验',
      'colors': [const Color(0xFF161618), const Color(0xFF252629)],
      'accent': const Color(0xFF00E5FF),
    },
    {
      'name': '纯净白',
      'desc': '简约高雅，如同白纸般的纯净视野',
      'colors': [const Color(0xFFF5F5F7), const Color(0xFFFFFFFF)],
      'accent': const Color(0xFF009EFD),
    },
    {
      'name': '梦幻粉',
      'desc': '柔和浪漫，赋予灵感更多温润色彩',
      'colors': [const Color(0xFFFFF0F5), const Color(0xFFFFD1DC)],
      'accent': const Color(0xFFFF69B4),
    },
  ];

  // 选择图片保存路径
  Future<void> _pickImageDirectory() async {
    if (_isPickingImagePath) return;
    
    setState(() => _isPickingImagePath = true);
    
    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择图片保存文件夹',
        lockParentWindow: true,
      );
      
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        imageSavePathNotifier.value = selectedDirectory;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('图片保存路径已更新: $selectedDirectory'),
              backgroundColor: const Color(0xFF2AF598),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('选择文件夹时出错: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImagePath = false);
      }
    }
  }

  // 选择视频保存路径
  Future<void> _pickVideoDirectory() async {
    if (_isPickingVideoPath) return;
    
    setState(() => _isPickingVideoPath = true);
    
    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择视频保存文件夹',
        lockParentWindow: true,
      );
      
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        videoSavePathNotifier.value = selectedDirectory;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('视频保存路径已更新: $selectedDirectory'),
              backgroundColor: const Color(0xFF2AF598),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('选择文件夹时出错: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingVideoPath = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, currentThemeIndex, _) {
        return Container(
          color: AppTheme.scaffoldBackground,
          child: Column(
            children: [
              // 1. 顶部导航与主标签
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    _buildIconButton(Icons.arrow_back_ios_new_rounded, '返回工作台', widget.onBack),
                    const SizedBox(width: 40),
                    // 主标签切换
                    ...List.generate(_mainTabs.length, (index) {
                      final isSelected = _mainTabIndex == index;
                      return _buildMainTab(index, isSelected);
                    }),
                    const Spacer(),
                  ],
                ),
              ),
              Divider(height: 1, color: AppTheme.dividerColor),
              
              // 2. 内容区
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧子导航 (仅 API 设置显示)
                    if (_mainTabIndex == 0)
                      Container(
                        width: 180,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          border: Border(right: BorderSide(color: AppTheme.dividerColor)),
                        ),
                        child: Column(
                          children: List.generate(_apiSubTabs.length, (index) {
                            return _buildSubTab(index, _apiSubTabIndex == index);
                          }),
                        ),
                      ),
                    
                    // 右侧详情配置区
                    Expanded(
                      child: _buildContentArea(currentThemeIndex),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContentArea(int themeIndex) {
    switch (_mainTabIndex) {
      case 0:
        return _buildApiConfigurationForm();
      case 1:
        return _buildStyleSettings(themeIndex);
      case 2:
        return _buildSaveSettings();
      default:
        return _buildPlaceholderView();
    }
  }

  // --- 组件构建方法 ---

  Widget _buildMainTab(int index, bool isSelected) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _mainTabIndex = index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? AppTheme.accentColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            _mainTabs[index],
            style: TextStyle(
              color: isSelected ? AppTheme.textColor : AppTheme.subTextColor,
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubTab(int index, bool isSelected) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _apiSubTabIndex = index),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.sideBarItemHover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _apiSubTabs[index],
            style: TextStyle(
              color: AppTheme.textColor,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // 保存设置界面
  Widget _buildSaveSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormHeader('本地保存路径设置', icon: Icons.save_rounded),
          const SizedBox(height: 12),
          Text('配置生成后的图片与视频存放路径，系统将自动进行分类保存', style: TextStyle(color: AppTheme.subTextColor, fontSize: 13)),
          const SizedBox(height: 40),

          _buildPathSelector(
            title: '图片保存路径',
            notifier: imageSavePathNotifier,
            onPick: _pickImageDirectory,
            isLoading: _isPickingImagePath,
          ),

          const SizedBox(height: 32),

          _buildPathSelector(
            title: '视频保存路径',
            notifier: videoSavePathNotifier,
            onPick: _pickVideoDirectory,
            isLoading: _isPickingVideoPath,
          ),

          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.textColor.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: const Color(0xFF2AF598).withOpacity(0.7), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '设置已实时自动保存。生成内容时，系统将直接导出至上述文件夹。',
                    style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathSelector({
    required String title,
    required ValueNotifier<String> notifier,
    required VoidCallback onPick,
    bool isLoading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(title),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: notifier,
                builder: (context, path, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.textColor.withOpacity(0.05)),
                    ),
                    child: Text(
                      path,
                      style: TextStyle(
                        color: path == '未设置' ? AppTheme.subTextColor : AppTheme.textColor,
                        fontSize: 14,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            MouseRegion(
              cursor: isLoading ? SystemMouseCursors.wait : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: isLoading ? null : onPick,
                child: Opacity(
                  opacity: isLoading ? 0.6 : 1.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                      ),
                    ),
                    child: Row(
                      children: [
                        if (isLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          const Icon(Icons.folder_open_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isLoading ? '选择中...' : '更改目录',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 风格设置界面
  Widget _buildStyleSettings(int currentThemeIndex) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormHeader('视觉风格设置', icon: Icons.palette_rounded),
          const SizedBox(height: 12),
          Text('选择后立即自动应用全局风格。系统将自动调整全局色彩规则', style: TextStyle(color: AppTheme.subTextColor, fontSize: 13)),
          const SizedBox(height: 40),
          
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: List.generate(_styleOptions.length, (index) {
              final style = _styleOptions[index];
              final isSelected = currentThemeIndex == index;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    // 立即更新全局主题
                    themeNotifier.value = index;
                  },
                  child: Container(
                    width: 260,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.accentColor : AppTheme.textColor.withOpacity(0.05),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(color: AppTheme.accentColor.withOpacity(0.1), blurRadius: 15, spreadRadius: 2)
                      ] : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 预览色块
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                            gradient: LinearGradient(
                              colors: style['colors'],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: style['accent'],
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Center(
                                  child: Icon(Icons.check_circle, color: Colors.white, size: 40),
                                ),
                            ],
                          ),
                        ),
                        // 文字描述
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(style['name'], style: TextStyle(color: AppTheme.textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(style['desc'], style: TextStyle(color: AppTheme.subTextColor, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          
          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.textColor.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.accentColor.withOpacity(0.5), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '配置已实时自动保存。自定义皮肤功能正在内测中，敬请期待。',
                    style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiConfigurationForm() {
    String currentTitle = _apiSubTabs[_apiSubTabIndex];
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormHeader(currentTitle),
          const SizedBox(height: 40),
          
          _buildFieldLabel('API 服务商'),
          const SizedBox(height: 10),
          _buildDropdown(['OpenAI', 'GeekNow', 'Azure', 'Anthropic']),
          
          const SizedBox(height: 30),
          _buildFieldLabel('API Key'),
          const SizedBox(height: 10),
          _buildTextField('请输入您的 API 密钥...', isPassword: true),
          
          const SizedBox(height: 30),
          _buildFieldLabel('Base URL (API 地址)'),
          const SizedBox(height: 10),
          _buildTextField('https://api.openai.com/v1'),
          
          const SizedBox(height: 30),
          _buildFieldLabel('选择推理模型'),
          const SizedBox(height: 10),
          _buildModelPicker(),
          
          const SizedBox(height: 40),
          Text(
            '* 提示：填写的 API 信息将加密自动保存在本地，仅用于模型推理。',
            style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFormHeader(String title, {IconData icon = Icons.settings_input_component_rounded}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.accentColor, size: 20),
        ),
        const SizedBox(width: 16),
        Text(
          title.contains('设置') ? title : '$title配置中心',
          style: TextStyle(color: AppTheme.textColor, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(label, style: TextStyle(color: AppTheme.textColor.withOpacity(0.7), fontSize: 14, fontWeight: FontWeight.w500));
  }

  Widget _buildTextField(String hint, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textColor.withOpacity(0.05)),
      ),
      child: TextField(
        obscureText: isPassword,
        style: TextStyle(color: AppTheme.textColor, fontSize: 14),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.subTextColor),
          suffixIcon: isPassword ? Icon(Icons.visibility_off_rounded, color: AppTheme.subTextColor, size: 18) : null,
        ),
      ),
    );
  }

  Widget _buildDropdown(List<String> options) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textColor.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options[0],
          isExpanded: true,
          dropdownColor: AppTheme.surfaceBackground,
          icon: Icon(Icons.unfold_more_rounded, color: AppTheme.subTextColor, size: 20),
          items: options.map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(color: AppTheme.textColor, fontSize: 14)))).toList(),
          onChanged: (v) {},
        ),
      ),
    );
  }

  Widget _buildModelPicker() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textColor.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.search_rounded, color: AppTheme.subTextColor, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text('搜索并选择模型...', style: TextStyle(color: AppTheme.subTextColor, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.textColor.withOpacity(0.05), borderRadius: BorderRadius.circular(4)),
                child: Text('API 未连接', style: TextStyle(color: AppTheme.subTextColor, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Opacity(
            opacity: 0.5,
            child: Text(
              '请先完成上方配置，系统将根据您的 API 文档自动获取可用模型列表',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String label, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.subTextColor, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: AppTheme.subTextColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction_rounded, color: AppTheme.subTextColor, size: 64),
          const SizedBox(height: 16),
          Text(
            '${_mainTabs[_mainTabIndex]} 正在深度构建中...',
            style: TextStyle(color: AppTheme.subTextColor, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
