import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:xinghe_new/features/auth/presentation/auth_provider.dart';
import 'package:xinghe_new/features/auth/presentation/widgets/login_register_dialog.dart';

/// 全局认证守卫包装器
/// 
/// 三道防线：
/// - 防线 A：是否登录（isAuthenticated）
/// - 防线 B：是否激活邮箱（verified）
/// - 防线 C：是否过期（expire_date）
class AuthGuardWrapper extends StatefulWidget {
  final Widget child;
  final AuthProvider authProvider;

  const AuthGuardWrapper({
    super.key,
    required this.child,
    required this.authProvider,
  });

  @override
  State<AuthGuardWrapper> createState() => _AuthGuardWrapperState();
}

class _AuthGuardWrapperState extends State<AuthGuardWrapper> {
  @override
  void initState() {
    super.initState();
    widget.authProvider.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    widget.authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      setState(() {});
      // 🚨 检查是否被踢下线，弹出醒目提示
      _checkKicked();
    }
  }

  void _checkKicked() {
    final message = widget.authProvider.kickedMessage;
    if (message != null && mounted) {
      // 清除标志，防止重复弹窗
      widget.authProvider.clearKickedMessage();
      // 延迟弹窗，确保 build 完成
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.redAccent, width: 2),
            ),
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 56),
            title: const Text(
              '强制下线通知',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            content: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('我知道了', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      });
    }
  }

  /// 判断当前应该显示哪个拦截层
  _AuthGuardState _getGuardState() {
    final auth = widget.authProvider;

    // 防线 A：未登录
    if (!auth.isAuthenticated || auth.currentUser == null) {
      return _AuthGuardState.notAuthenticated;
    }

    // 防线 B：未激活邮箱
    if (!auth.currentUser!.verified) {
      return _AuthGuardState.notVerified;
    }

    // 防线 C：已过期
    if (auth.currentUser!.isExpired) {
      return _AuthGuardState.expired;
    }

    // 全部通过
    return _AuthGuardState.passed;
  }

  @override
  Widget build(BuildContext context) {
    final guardState = _getGuardState();

    return Stack(
      children: [
        // 底层：始终渲染主内容（但被遮罩覆盖时不可交互）
        widget.child,

        // 拦截层
        if (guardState != _AuthGuardState.passed) ...[
          // 全局遮罩 + 模糊
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),

          // 对应的拦截 UI
          Positioned.fill(
            child: _buildGuardOverlay(guardState),
          ),
        ],
      ],
    );
  }

  Widget _buildGuardOverlay(_AuthGuardState state) {
    switch (state) {
      case _AuthGuardState.notAuthenticated:
        return _LoginRequiredOverlay(authProvider: widget.authProvider);
      case _AuthGuardState.notVerified:
        return _VerificationRequiredOverlay(authProvider: widget.authProvider);
      case _AuthGuardState.expired:
        return _ExpiredOverlay(authProvider: widget.authProvider);
      case _AuthGuardState.passed:
        return const SizedBox.shrink();
    }
  }
}

enum _AuthGuardState {
  notAuthenticated,
  notVerified,
  expired,
  passed,
}

// ============================================================
// 防线 A：未登录拦截页
// ============================================================
class _LoginRequiredOverlay extends StatelessWidget {
  final AuthProvider authProvider;
  const _LoginRequiredOverlay({required this.authProvider});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 锁图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF00E5FF).withValues(alpha: 0.2),
                    const Color(0xFFAA00FF).withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFF00E5FF),
                size: 40,
              ),
            ),
            const SizedBox(height: 24),

            // 标题
            const Text(
              '需要登录',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),

            // 描述
            Text(
              '请先登录您的账号才能使用创作工具',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // 登录按钮
            SizedBox(
              width: double.infinity,
              height: 50,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFFAA00FF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showLoginDialog(context),
                    borderRadius: BorderRadius.circular(12),
                    child: const Center(
                      child: Text(
                        '立即登录 / 注册',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return LoginRegisterDialog(authProvider: authProvider);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }
}

// ============================================================
// 防线 B：未激活邮箱拦截页
// ============================================================
class _VerificationRequiredOverlay extends StatefulWidget {
  final AuthProvider authProvider;
  const _VerificationRequiredOverlay({required this.authProvider});

  @override
  State<_VerificationRequiredOverlay> createState() => _VerificationRequiredOverlayState();
}

class _VerificationRequiredOverlayState extends State<_VerificationRequiredOverlay> {
  bool _isSending = false;
  bool _sent = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  
  // 基于全局时间戳的倒计时
  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // 组件初始化时，根据全局时间戳计算剩余倒计时
    _syncCountdownFromTimestamp();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// 从 AuthProvider 的全局时间戳同步剩余倒计时秒数
  void _syncCountdownFromTimestamp() {
    final lastSent = widget.authProvider.lastVerificationEmailSentTime;
    if (lastSent != null) {
      final elapsed = DateTime.now().difference(lastSent).inSeconds;
      final remaining = 60 - elapsed;
      if (remaining > 0) {
        _countdown = remaining;
        _startCountdownTimer();
      }
    }
  }

  /// 启动每秒递减的 Timer
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _countdown--;
          if (_countdown <= 0) {
            _countdown = 0;
            timer.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _resendEmail() async {
    if (_countdown > 0) return; // 倒计时中，拒绝操作

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await widget.authProvider.resendVerificationEmail();
      setState(() {
        _sent = true;
        _isSending = false;
        _countdown = 60;
      });
      // 发送成功后启动倒计时
      _startCountdownTimer();
    } catch (e) {
      String msg = e.toString().replaceAll('Exception: ', '');
      setState(() {
        _errorMessage = msg;
        _isSending = false;
      });
    }
  }

  /// 刷新用户信息以检查是否已激活（使用 PocketBase auth-refresh）
  Future<void> _refreshUserInfo() async {
    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });

    try {
      await widget.authProvider.refreshUserInfo();
      // refreshUserInfo 可能会触发 logout（token 失效时）
      // 如果用户已被登出，AuthGuardWrapper 会自动切到防线 A
      if (mounted && widget.authProvider.currentUser != null && !widget.authProvider.currentUser!.verified) {
        setState(() {
          _errorMessage = '邮箱尚未激活，请检查邮箱（包括垃圾邮件文件夹）';
          _isRefreshing = false;
        });
      } else if (mounted) {
        setState(() => _isRefreshing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '刷新失败，请稍后重试';
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.authProvider.currentUser?.email ?? '';

    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.orange.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.1),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 邮箱图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.mark_email_unread_outlined,
                color: Colors.orange,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),

            // 标题
            const Text(
              '邮箱未激活',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),

            // 描述
            Text(
              '请先前往邮箱点击激活链接以完成账号验证',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // 邮箱信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mail_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      email,
                      style: const TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            // 成功提示
            if (_sent) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '验证邮件已重新发送，请检查您的邮箱（包括垃圾邮件文件夹）',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 错误提示
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
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 重新发送按钮（带60秒倒计时防刷）
            SizedBox(
              width: double.infinity,
              height: 50,
              child: Container(
                decoration: BoxDecoration(
                  gradient: _countdown > 0
                      ? null  // 倒计时中不使用渐变
                      : const LinearGradient(
                          colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  color: _countdown > 0 ? Colors.grey.shade800 : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _countdown > 0
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.3),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: (_isSending || _countdown > 0) ? null : _resendEmail,
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: _isSending
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _countdown > 0
                                  ? '重新发送 (${_countdown}s)'
                                  : '重新发送激活邮件',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _countdown > 0 ? Colors.white38 : Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 已激活？刷新状态按钮
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: _isRefreshing ? null : _refreshUserInfo,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isRefreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                        ),
                      )
                    : Text(
                        '已完成激活？点击刷新',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 12),

            // 退出登录链接
            TextButton(
              onPressed: () => widget.authProvider.logout(),
              child: Text(
                '切换账号',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 防线 C：已过期拦截页
// ============================================================
class _ExpiredOverlay extends StatefulWidget {
  final AuthProvider authProvider;
  const _ExpiredOverlay({required this.authProvider});

  @override
  State<_ExpiredOverlay> createState() => _ExpiredOverlayState();
}

class _ExpiredOverlayState extends State<_ExpiredOverlay> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _success = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleRenew() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = '请输入邀请码');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authProvider.renewWithInvitationCode(code);
      setState(() {
        _success = true;
        _isLoading = false;
      });
    } catch (e) {
      String msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('Exception: ')) {
        msg = msg.split('Exception: ').last;
      }
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authProvider.currentUser;
    final expiredDays = user != null
        ? DateTime.now().difference(user.expireDate).inDays
        : 0;

    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.1),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 过期图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.timer_off_outlined,
                color: Colors.red,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),

            // 标题
            const Text(
              '使用授权已过期',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),

            // 描述
            Text(
              '您的账号已过期 $expiredDays 天，请输入新的邀请码来续期',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 邀请码输入
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.card_giftcard, color: Colors.white.withValues(alpha: 0.4), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '邀请码',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    hintText: '请输入邀请码',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xFF00E5FF),
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _handleRenew(),
                ),
              ],
            ),

            // 错误提示
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
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 成功提示
            if (_success) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '续期成功！正在刷新...',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 续期按钮
            SizedBox(
              width: double.infinity,
              height: 50,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5252), Color(0xFFFF1744)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.3),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isLoading ? null : _handleRenew,
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              '使用邀请码续期',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 退出登录链接
            TextButton(
              onPressed: () => widget.authProvider.logout(),
              child: Text(
                '切换账号',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
