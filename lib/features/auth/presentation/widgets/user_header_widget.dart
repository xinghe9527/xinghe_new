import 'package:flutter/material.dart';
import 'package:xinghe_new/main.dart';
import '../auth_provider.dart';
import 'login_register_dialog.dart';

class UserHeaderWidget extends StatelessWidget {
  final AuthProvider authProvider;

  const UserHeaderWidget({
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
                icon: Icons.settings_outlined,
                iconColor: Colors.purple,
                title: '账号设置',
                subtitle: '修改密码',
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
  String? _errorMessage; // 错误消息（在表单内显示）

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdatePassword() async {
    // 验证输入
    if (_oldPasswordController.text.isEmpty) {
      setState(() => _errorMessage = '请输入当前密码');
      return;
    }
    if (_newPasswordController.text.isEmpty) {
      setState(() => _errorMessage = '请输入新密码');
      return;
    }
    if (_newPasswordController.text.length < 8) {
      setState(() => _errorMessage = '新密码至少需要8个字符');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = '两次输入的新密码不一致');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null; // 清除之前的错误
    });

    try {
      await widget.authProvider.updatePassword(
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        Navigator.pop(context);
        _showSuccessSnackBar('密码修改成功，请重新登录');
        
        // 延迟退出登录，让用户看到成功提示
        Future.delayed(const Duration(seconds: 1), () async {
          await widget.authProvider.logout();
        });
      }
    } catch (e) {
      if (mounted) {
        // 提取纯净的错误信息
        String errorMsg = e.toString().replaceAll('Exception: ', '');
        if (errorMsg.contains('Exception: ')) {
          errorMsg = errorMsg.split('Exception: ').last;
        }
        if (errorMsg.contains('旧密码') || errorMsg.contains('old password')) {
          errorMsg = '当前密码错误';
        }
        setState(() {
          _isLoading = false;
          _errorMessage = errorMsg;
        });
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
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
            
            // 错误提示（在表单内显示）
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleUpdatePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('确认修改'),
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
