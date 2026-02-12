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

    // 选择头像
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image != null && context.mounted) {
      // 显示上传进度
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // 上传到 OSS
        final avatarUrl = await _avatarUploadService.uploadAvatar(
          userId: authProvider.currentUser!.id,
          localPath: image.path,
        );
        
        // 更新用户头像
        await authProvider.updateAvatar(avatarUrl);
        
        if (context.mounted) {
          Navigator.of(context).pop(); // 关闭进度对话框
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('头像更新成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop(); // 关闭进度对话框
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('头像更新失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
