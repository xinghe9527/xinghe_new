/// 错误信息翻译器
/// 将技术性的英文错误信息转换为用户友好的中文描述
class ErrorTranslator {
  /// 将错误信息翻译为通俗易懂的中文
  static String translate(String error) {
    // 先检查是否是"中文描述: 英文错误"的混合格式
    // 例如："加载视频配置失败: Error 0x00000000: Failure on CryptUnprotectData()"
    final mixedPrefixMatch = RegExp(r'^([\u4e00-\u9fff]+[^a-zA-Z]*?)[：:]\s*(.+)$').firstMatch(error);
    if (mixedPrefixMatch != null) {
      final chinesePrefix = mixedPrefixMatch.group(1)!;
      final englishSuffix = mixedPrefixMatch.group(2)!;
      if (!_isMostlyChinese(englishSuffix)) {
        final translatedSuffix = translate(englishSuffix);
        return '$chinesePrefix：$translatedSuffix';
      }
    }

    final lower = error.toLowerCase();

    // ── 网络相关 ──
    if (lower.contains('socketexception') || lower.contains('connection refused')) {
      return '无法连接到服务器，请检查服务是否已启动';
    }
    if (lower.contains('timeoutexception') || lower.contains('timed out') || lower.contains('timeout')) {
      return '连接超时，服务器可能无响应，请稍后重试';
    }
    if (lower.contains('failed host lookup') || lower.contains('no address associated')) {
      return '无法解析服务器地址，请检查网络连接';
    }
    if (lower.contains('connection reset') || lower.contains('connection closed')) {
      return '连接被中断，请检查网络稳定性';
    }
    if (lower.contains('handshakeexception') || lower.contains('certificate')) {
      return '安全连接失败，可能是证书问题';
    }
    if (lower.contains('no internet') || lower.contains('network is unreachable')) {
      return '没有网络连接，请检查网络设置';
    }

    // ── HTTP 状态码 ──
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return '认证失败，请检查 API 密钥是否正确';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return '权限不足，当前密钥无权访问此功能';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      if (lower.contains('api') || lower.contains('endpoint') || lower.contains('url')) {
        return '接口地址不存在，请检查服务商配置和基础地址';
      }
    }
    if (lower.contains('429') || lower.contains('too many requests') || lower.contains('rate limit')) {
      return '请求太频繁，请稍后再试';
    }
    if (lower.contains('500') && lower.contains('internal server error')) {
      return '服务器内部出错，请稍后重试';
    }
    if (lower.contains('502') || lower.contains('bad gateway')) {
      return '服务器网关错误，服务可能正在重启';
    }
    if (lower.contains('503') || lower.contains('service unavailable')) {
      return '服务暂时不可用，请稍后重试';
    }

    // ── 数据格式 ──
    if (lower.contains('formatexception') || lower.contains('unexpected character')) {
      return '服务器返回了无法识别的数据格式';
    }
    if (lower.contains('type \'null\' is not a subtype') || lower.contains('null check operator')) {
      return '数据缺失，服务器返回的数据不完整';
    }
    if (lower.contains('type \'') && lower.contains('is not a subtype of type')) {
      return '数据类型不匹配，服务器返回了意料之外的数据结构';
    }
    if (lower.contains('rangeerror') || lower.contains('invalid value: valid value range is empty')) {
      return '数据为空，服务器没有返回有效结果';
    }

    // ── 文件操作 ──
    if (lower.contains('filesystemexception') || lower.contains('cannot open file')) {
      return '文件操作失败，请检查文件路径和权限';
    }
    if (lower.contains('no such file or directory') || lower.contains('pathnotfoundexception')) {
      return '找不到文件或文件夹，路径可能不存在';
    }
    if (lower.contains('permission denied') || lower.contains('access is denied')) {
      return '没有权限访问该文件，请检查文件夹权限';
    }
    if (lower.contains('no space left') || lower.contains('disk full')) {
      return '磁盘空间不足，请清理一些文件';
    }

    // ── API 服务 ──
    if (lower.contains('invalid api key') || lower.contains('incorrect api key')) {
      return 'API 密钥无效，请在设置中重新填写';
    }
    if (lower.contains('model not found') || lower.contains('model_not_found')) {
      return '模型不存在，请检查模型名称是否正确';
    }
    if (lower.contains('insufficient_quota') || lower.contains('billing')) {
      return 'API 额度不足，请检查账户余额';
    }
    if (lower.contains('content_policy') || lower.contains('content policy')) {
      return '内容被安全策略拦截，请修改提示词后重试';
    }

    // ── Windows 系统错误 ──
    if (lower.contains('cryptunprotectdata') || lower.contains('crypt')) {
      return '系统加密存储读取失败，可能需要重新配置相关设置';
    }
    if (RegExp(r'error 0x[0-9a-f]+').hasMatch(lower)) {
      return '系统操作出错，请重试或检查系统设置';
    }

    // ── 生成相关 ──
    if (lower.contains('生成超时')) {
      return error; // 已经是中文
    }

    // ── 已经是中文的消息，直接返回 ──
    if (_isMostlyChinese(error)) {
      return error;
    }

    // ── 默认：提取关键信息 ──
    return _simplifyError(error);
  }

  /// 判断字符串是否主要由中文组成
  static bool _isMostlyChinese(String text) {
    if (text.isEmpty) return false;
    final chineseChars = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
    final totalChars = text.replaceAll(RegExp(r'\s'), '').length;
    if (totalChars == 0) return false;
    return chineseChars / totalChars > 0.3;
  }

  /// 简化英文/混合错误信息
  static String _simplifyError(String error) {
    // 从 "Exception: xxx" 或 "Error: xxx" 中提取 xxx
    final match = RegExp(r'(?:Exception|Error|Failed):\s*(.+)', caseSensitive: false).firstMatch(error);
    if (match != null) {
      final msg = match.group(1)!.trim();
      if (_isMostlyChinese(msg)) return msg;
      return '操作失败：$msg';
    }

    // 太长的技术信息截断
    if (error.length > 100) {
      return '操作失败，请查看系统日志了解详情';
    }

    return '操作失败：$error';
  }
}
