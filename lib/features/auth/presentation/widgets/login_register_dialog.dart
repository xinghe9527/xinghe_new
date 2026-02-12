import 'package:flutter/material.dart';
import '../auth_provider.dart';

class LoginRegisterDialog extends StatefulWidget {
  final AuthProvider authProvider;

  const LoginRegisterDialog({
    super.key,
    required this.authProvider,
  });

  @override
  State<LoginRegisterDialog> createState() => _LoginRegisterDialogState();
}

class _LoginRegisterDialogState extends State<LoginRegisterDialog> {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _rememberMe = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _invitationCodeController = TextEditingController();
  final _verificationCodeController = TextEditingController(); // 新增验证码控制器

  int _countdown = 0; // 倒计时秒数
  bool _isSendingCode = false; // 是否正在发送验证码

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final credentials = await widget.authProvider.storageService.loadCredentials();
    setState(() {
      _rememberMe = credentials['rememberMe'];
      _emailController.text = credentials['email'];
      _passwordController.text = credentials['password'];
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _invitationCodeController.dispose();
    _verificationCodeController.dispose(); // 释放验证码控制器
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('请填写完整信息');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.authProvider.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );
      
      if (mounted) {
        Navigator.of(context).pop();
        _showSuccess('登录成功');
      }
    } catch (e) {
      // 显示真实的底层错误信息，用于调试
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      _showError(errorMessage);
      
      // 同时打印到控制台，方便调试
      debugPrint('登录失败详情: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    if (_usernameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _invitationCodeController.text.isEmpty) {
      _showError('请填写完整信息');
      return;
    }

    // 暂时不强制验证码（后端未实现时）
    // if (_verificationCodeController.text.isEmpty) {
    //   _showError('请输入验证码');
    //   return;
    // }

    setState(() => _isLoading = true);

    try {
      await widget.authProvider.register(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        invitationCode: _invitationCodeController.text.trim(),
      );
      
      if (mounted) {
        Navigator.of(context).pop();
        _showSuccess('注册成功');
      }
    } catch (e) {
      // 显示真实的底层错误信息，用于调试
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      _showError(errorMessage);
      
      // 同时打印到控制台，方便调试
      debugPrint('注册失败详情: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 发送验证码
  Future<void> _sendVerificationCode() async {
    if (_emailController.text.trim().isEmpty) {
      _showError('请先输入邮箱');
      return;
    }

    // 邮箱格式验证
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(_emailController.text.trim())) {
      _showError('邮箱格式不正确');
      return;
    }

    setState(() => _isSendingCode = true);

    try {
      // TODO: 调用后端发送验证码接口
      // await widget.authProvider.apiService.sendVerificationCode(_emailController.text.trim());
      
      // 暂时模拟成功
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        _showSuccess('验证码功能需配置 SMTP，当前仅作演示');
        
        // 开始倒计时
        setState(() {
          _countdown = 60;
        });
        
        _startCountdown();
      }
    } catch (e) {
      _showError('发送验证码失败: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  // 倒计时
  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _countdown > 0) {
        setState(() => _countdown--);
        _startCountdown();
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 全屏背景：纯黑色半透明遮罩（不模糊，保证错误提示可见）
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),
          
          // 弹窗主体
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 420,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  // 渐变边框
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      const Color(0xFFAA00FF).withValues(alpha: 0.3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(1.5), // 边框宽度
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D), // 更深的黑色
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 标题和切换按钮
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _TabButton(
                              label: '登录',
                              isSelected: _isLogin,
                              onTap: () => setState(() => _isLogin = true),
                            ),
                            const SizedBox(width: 40),
                            _TabButton(
                              label: '注册',
                              isSelected: !_isLogin,
                              onTap: () => setState(() => _isLogin = false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),

                        // 表单
                        if (!_isLogin) ...[
                          _GlassInputField(
                            controller: _usernameController,
                            label: '用户名',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 20),
                        ],
                        _GlassInputField(
                          controller: _emailController,
                          label: '邮箱',
                          icon: Icons.email_outlined,
                        ),
                        if (!_isLogin) ...[
                          const SizedBox(height: 20),
                          // 验证码输入框 + 获取验证码按钮
                          Row(
                            children: [
                              Expanded(
                                child: _GlassInputField(
                                  controller: _verificationCodeController,
                                  label: '验证码',
                                  icon: Icons.verified_user_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 获取验证码按钮 - 渐变色
                              SizedBox(
                                height: 48,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: (_countdown > 0 || _isSendingCode)
                                        ? null
                                        : const LinearGradient(
                                            colors: [
                                              Color(0xFF00E5FF),
                                              Color(0xFFAA00FF),
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                    color: (_countdown > 0 || _isSendingCode)
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : null,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: (_countdown > 0 || _isSendingCode)
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: (_countdown > 0 || _isSendingCode)
                                          ? null
                                          : _sendVerificationCode,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        alignment: Alignment.center,
                                        child: _isSendingCode
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : Text(
                                                _countdown > 0 ? '${_countdown}s' : '获取验证码',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: (_countdown > 0 || _isSendingCode)
                                                      ? Colors.white30
                                                      : Colors.white,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                        _GlassInputField(
                          controller: _passwordController,
                          label: '密码',
                          icon: Icons.lock_outline,
                          isPassword: true,
                        ),
                        if (!_isLogin) ...[
                          const SizedBox(height: 20),
                          _GlassInputField(
                            controller: _invitationCodeController,
                            label: '邀请码',
                            icon: Icons.card_giftcard,
                          ),
                        ],

                        // 记住我
                        if (_isLogin) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _rememberMe,
                                  onChanged: (value) => setState(() => _rememberMe = value ?? false),
                                  fillColor: WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return const Color(0xFF00E5FF);
                                    }
                                    return Colors.transparent;
                                  }),
                                  side: const BorderSide(color: Colors.white30, width: 1.5),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                '记住我',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 32),

                        // 提交按钮 - 渐变色
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF00E5FF),
                                  Color(0xFFAA00FF),
                                ],
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
                                onTap: _isLoading
                                    ? null
                                    : (_isLogin ? _handleLogin : _handleRegister),
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
                                      : Text(
                                          _isLogin ? '登录' : '注册',
                                          style: const TextStyle(
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white38,
              fontSize: 20,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 3,
            width: 50,
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFFAA00FF)],
                    )
                  : null,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

// 磨砂玻璃输入框
class _GlassInputField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isPassword;

  const _GlassInputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.isPassword = false,
  });

  @override
  State<_GlassInputField> createState() => _GlassInputFieldState();
}

class _GlassInputFieldState extends State<_GlassInputField> {
  bool _obscureText = true;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, color: Colors.white38, size: 18),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: TextField(
            controller: widget.controller,
            obscureText: widget.isPassword && _obscureText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              letterSpacing: 0.5,
            ),
            decoration: InputDecoration(
              hintText: '请输入${widget.label}',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 15,
              ),
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.white30,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscureText = !_obscureText),
                    )
                  : null,
              border: InputBorder.none,
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: _isFocused ? const Color(0xFF00E5FF) : Colors.white30,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
