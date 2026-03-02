import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/auth/data/avatar_upload_service.dart';
import '../auth_provider.dart';
import 'login_register_dialog.dart';

class UserHeaderWidget extends StatelessWidget {
  final AuthProvider authProvider;
  final AvatarUploadService _avatarUploadService = AvatarUploadService();

  UserHeaderWidget({
    super.key,
    required this.authProvider,
  });

  Future<void> _handleAvatarTap(BuildContext context) async {
    if (!authProvider.isAuthenticated) {
      _showLoginDialog(context);
      return;
    }

    // 已登录：显示用户菜单
    _showUserMenu(context);
  }

  // 显示专业的用户菜单
  void _showUserMenu(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: AppTheme.surfaceBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.dividerColor,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 用户信息头部
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accentColor.withValues(alpha: 0.1),
                      AppTheme.surfaceBackground,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    // 头像
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.accentColor,
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: authProvider.currentUser?.avatar != null
                            ? Image.network(
                                authProvider.currentUser!.avatar!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildDefaultAvatar();
                                },
                              )
                            : _buildDefaultAvatar(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 用户信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authProvider.currentUser!.username,
                            style: TextStyle(
                              color: AppTheme.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            authProvider.currentUser!.email,
                            style: TextStyle(
                              color: AppTheme.subTextColor,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: authProvider.currentUser!.isExpired
                                  ? Colors.red.withValues(alpha: 0.2)
                                  : AppTheme.accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatExpireDate(authProvider.currentUser!.expireDate),
                              style: TextStyle(
                                color: authProvider.currentUser!.isExpired
                                    ? Colors.red
                                    : AppTheme.accentColor,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // 菜单项
              _buildMenuItem(
                context,
                icon: Icons.person_outline,
                iconColor: Colors.blue,
                title: '编辑个人资料',
                subtitle: '修改用户名、头像',
                onTap: () {
                  Navigator.pop(context);
                  _showEditProfileDialog(context);
                },
              ),
              
              Divider(color: AppTheme.dividerColor, height: 1),
              
              _buildMenuItem(
                context,
                icon: Icons.settings_outlined,
                iconColor: Colors.purple,
                title: '账号设置',
                subtitle: '修改密码、安全设置',
                onTap: () {
                  Navigator.pop(context);
                  _showAccountSettingsDialog(context);
                },
              ),
              
              Divider(color: AppTheme.dividerColor, height: 1),
              
              _buildMenuItem(
                context,
                icon: Icons.logout,
                iconColor: Colors.orange,
                title: '退出登录',
                subtitle: '安全退出当前账号',
                onTap: () {
                  Navigator.pop(context);
                  _handleLogout(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建菜单项
  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.subTextColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppTheme.subTextColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 编辑个人资料对话框
  void _showEditProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _EditProfileDialog(
        authProvider: authProvider,
        avatarUploadService: _avatarUploadService,
      ),
    );
  }

  // 账号设置对话框
  void _showAccountSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AccountSettingsDialog(authProvider: authProvider),
    );
  }

  // 退出登录
  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBackground,
        title: Text('确认退出', style: TextStyle(color: AppTheme.textColor)),
        content: Text('确定要退出登录吗？', style: TextStyle(color: AppTheme.subTextColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
          ),
          TextButton(
            onPressed: () async {
              await authProvider.logout();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已退出登录'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text('确定', style: TextStyle(color: AppTheme.accentColor)),
          ),
        ],
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return LoginRegisterDialog(authProvider: authProvider);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  String _formatExpireDate(DateTime expireDate) {
    final now = DateTime.now();
    final difference = expireDate.difference(now);
    
    if (difference.isNegative) {
      return '已过期';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} 天后过期';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} 小时后过期';
    } else {
      return '即将过期';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: authProvider,
      builder: (context, _) {
        final user = authProvider.currentUser;
        final isAuthenticated = authProvider.isAuthenticated;

        // 调试输出
        debugPrint('=== UserHeaderWidget ===');
        debugPrint('isAuthenticated: $isAuthenticated');
        debugPrint('user: $user');
        debugPrint('username: ${user?.username}');
        debugPrint('=======================');

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => isAuthenticated ? null : _showLoginDialog(context),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              color: Colors.transparent,
              child: Row(
                children: [
                  // 头像
                  GestureDetector(
                    onTap: () => _handleAvatarTap(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2C2C2C),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentColor.withValues(alpha: 0.2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: user?.avatar != null
                            ? Image.network(
                                user!.avatar!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildDefaultAvatar();
                                },
                              )
                            : _buildDefaultAvatar(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  
                  // 用户信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAuthenticated ? user!.username : '点击登录',
                          style: TextStyle(
                            color: AppTheme.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isAuthenticated
                              ? _formatExpireDate(user!.expireDate)
                              : '同步创意',
                          style: TextStyle(
                            color: isAuthenticated && user!.isExpired
                                ? Colors.red
                                : AppTheme.subTextColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 箭头图标
                  if (!isAuthenticated)
                    Icon(
                      Icons.chevron_right,
                      color: AppTheme.subTextColor,
                      size: 14,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDefaultAvatar() {
    return Image.asset(
      'assets/logo.png',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.stars, color: AppTheme.accentColor, size: 22);
      },
    );
  }
}


// 编辑个人资料对话框
class _EditProfileDialog extends StatefulWidget {
  final AuthProvider authProvider;
  final AvatarUploadService avatarUploadService;

  const _EditProfileDialog({
    required this.authProvider,
    required this.avatarUploadService,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late TextEditingController _usernameController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.authProvider.currentUser?.username ?? '',
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _uploadAvatar() async {
    // 暂时禁用头像上传功能（OSS 权限问题）
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('头像上传功能开发中，敬请期待'),
        backgroundColor: Colors.orange,
      ),
    );
    return;

    /* 原头像上传代码（待 OSS 权限配置后启用）
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image != null && mounted) {
      setState(() => _isLoading = true);

      try {
        final avatarUrl = await widget.avatarUploadService.uploadAvatar(
          userId: widget.authProvider.currentUser!.id,
          localPath: image.path,
        );
        
        await widget.authProvider.updateAvatar(avatarUrl);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('头像更新成功'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('头像更新失败: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
    */
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authProvider.currentUser;
    if (user == null) {
      return const SizedBox();
    }

    return Dialog(
      backgroundColor: AppTheme.surfaceBackground,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '编辑个人资料',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            // 头像编辑
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.accentColor, width: 2),
                    ),
                    child: ClipOval(
                      child: user.avatar != null && user.avatar!.isNotEmpty
                          ? Image.network(
                              user.avatar!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/logo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Icon(Icons.person, color: AppTheme.accentColor, size: 50);
                                  },
                                );
                              },
                            )
                          : Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Icon(Icons.person, color: AppTheme.accentColor, size: 50);
                              },
                            ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _isLoading ? null : _uploadAvatar,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // 用户名编辑
            Text(
              '用户名',
              style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              style: TextStyle(color: AppTheme.textColor),
              decoration: InputDecoration(
                hintText: '输入用户名',
                hintStyle: TextStyle(color: AppTheme.subTextColor),
                filled: true,
                fillColor: AppTheme.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // 按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    // TODO: 实现用户名更新
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('用户名更新功能开发中')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 账号设置对话框
class _AccountSettingsDialog extends StatefulWidget {
  final AuthProvider authProvider;

  const _AccountSettingsDialog({required this.authProvider});

  @override
  State<_AccountSettingsDialog> createState() => _AccountSettingsDialogState();
}

class _AccountSettingsDialogState extends State<_AccountSettingsDialog> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceBackground,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '账号设置',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            Text(
              '修改密码',
              style: TextStyle(color: AppTheme.textColor, fontSize: 16),
            ),
            const SizedBox(height: 16),
            
            _buildPasswordField('当前密码', _oldPasswordController),
            const SizedBox(height: 12),
            _buildPasswordField('新密码', _newPasswordController),
            const SizedBox(height: 12),
            _buildPasswordField('确认新密码', _confirmPasswordController),
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    // TODO: 实现密码修改
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('密码修改功能开发中')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('确认修改'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: true,
          style: TextStyle(color: AppTheme.textColor),
          decoration: InputDecoration(
            hintText: '请输入$label',
            hintStyle: TextStyle(color: AppTheme.subTextColor),
            filled: true,
            fillColor: AppTheme.inputBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
