import 'package:flutter/material.dart';
import 'package:xinghe_new/services/web_automation_service.dart';
import 'package:xinghe_new/main.dart';

/// 网页自动化测试页面
/// 
/// 这是一个临时测试页面，用于验证 Flutter 与 Python 的通信
/// 测试通过后可以删除或隐藏
class WebAutomationTestPage extends StatefulWidget {
  const WebAutomationTestPage({super.key});

  @override
  State<WebAutomationTestPage> createState() => _WebAutomationTestPageState();
}

class _WebAutomationTestPageState extends State<WebAutomationTestPage> {
  final WebAutomationService _service = WebAutomationService();
  final TextEditingController _messageController = TextEditingController(
    text: '星河前端发来的测试指令',
  );
  
  bool _isLoading = false;
  String? _lastResult;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  /// 测试 Python 通信
  Future<void> _testPythonCommunication() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _lastResult = null;
    });
    
    try {
      // 调用 Python 脚本
      final result = await _service.testHelloFlutter(_messageController.text);
      
      // 检查返回结果
      if (result['success'] == true) {
        final message = result['message'] ?? '无消息';
        final receivedParam = result['received_param'] ?? '';
        final testChinese = result['test_chinese'] ?? '';
        final emojiTest = result['emoji_test'] ?? '';
        
        setState(() {
          _lastResult = '✅ 通信成功！\n\n'
              '📩 Python 返回消息：\n$message\n\n'
              '📥 接收到的参数：\n$receivedParam\n\n'
              '🇨🇳 中文测试：\n$testChinese\n\n'
              '😀 Emoji 测试：\n$emojiTest';
        });
        
        // 显示成功提示
        if (mounted) {
          _showSuccessDialog(message, testChinese);
        }
      } else {
        final error = result['error'] ?? '未知错误';
        setState(() {
          _lastResult = '❌ 通信失败：\n$error';
        });
        
        if (mounted) {
          _showErrorSnackBar('Python 返回错误: $error');
        }
      }
      
    } catch (e) {
      setState(() {
        _lastResult = '❌ 调用失败：\n$e';
      });
      
      if (mounted) {
        _showErrorSnackBar('调用 Python 失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 显示成功对话框
  void _showSuccessDialog(String message, String chineseTest) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.accentColor, size: 28),
            const SizedBox(width: 12),
            Text(
              'Python 通信成功！',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📩 Python 返回消息：',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '🇨🇳 中文测试：',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                chineseTest,
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '确定',
              style: TextStyle(color: AppTheme.accentColor),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示错误提示
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Python 通信测试',
          style: TextStyle(
            color: AppTheme.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 说明卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.accentColor.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.accentColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '测试说明',
                        style: TextStyle(
                          color: AppTheme.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '这个页面用于测试 Flutter 与 Python 脚本的通信。\n'
                    '点击下方按钮将调用 hello_flutter.py 并传递参数。',
                    style: TextStyle(
                      color: AppTheme.subTextColor,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 输入框
            Text(
              '输入测试消息',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              style: TextStyle(color: AppTheme.textColor),
              decoration: InputDecoration(
                hintText: '输入要传递给 Python 的消息',
                hintStyle: TextStyle(color: AppTheme.subTextColor),
                filled: true,
                fillColor: AppTheme.surfaceBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 测试按钮
            ElevatedButton(
              onPressed: _isLoading ? null : _testPythonCommunication,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text('正在调用 Python...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.play_arrow, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '测试 Python 通信',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
            
            // 结果显示
            if (_lastResult != null) ...[
              const SizedBox(height: 24),
              Text(
                '执行结果',
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: SelectableText(
                  _lastResult!,
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 13,
                    height: 1.6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
