import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xinghe_new/core/logger/log_manager.dart';

/// IndexTTS 语音合成服务
/// 支持情感控制、声音克隆、时间偏移等功能
///
/// 调用方式：优先通过本地 WebUI（Gradio）http://127.0.0.1:7860 的 /call/gen_single 接口，
/// 在已启动的 WebUI 进程内合成（模型只加载一次、速度快、界面有记录）；失败则回退到 Python 子进程。
class IndexTTSService {
  /// Gradio WebUI 根地址，如 http://127.0.0.1:7860
  final String baseUrl;
  final String? pythonPath;
  final String? indexttsPath;
  final LogManager _logger = LogManager();

  static const String _gradioApiGenSingle = 'gen_single';

  IndexTTSService({
    required this.baseUrl,
    this.pythonPath,
    this.indexttsPath,
  });

  /// 测试服务连接（GET 根路径，Gradio 会返回 200）
  Future<bool> testConnection() async {
    try {
      _logger.info('测试 IndexTTS 连接', module: 'IndexTTS', extra: {
        'baseUrl': baseUrl,
      });

      final url = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      _logger.info('IndexTTS 响应', module: 'IndexTTS', extra: {
        'statusCode': response.statusCode,
        'body': response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body,
      });

      return response.statusCode == 200;
    } catch (e) {
      _logger.error('IndexTTS连接测试失败: $e', module: 'IndexTTS');
      return false;
    }
  }

  /// Gradio 5 的 API 统一前缀（upload、call 等都在此前缀下）
  static const String _gradioApiPrefix = '/gradio_api';

  /// IndexTTS WebUI 情感控制方式选项文案（与 webui.py EMO_CHOICES 一致），Radio 需传文案而非索引
  static const List<String> _emoChoiceLabels = [
    '与音色参考音频相同',
    '使用情感参考音频',
    '使用情感向量控制',
    '使用情感描述文本控制',
  ];

  /// 将上传后的服务端路径封装为 Gradio 5 /call API 期望的 FileData 格式，避免 event:error
  static Map<String, dynamic> _gradioFileData(String serverPath, String localPath) {
    final origName = localPath.split(RegExp(r'[/\\]')).last;
    return {
      'path': serverPath,
      'orig_name': origName,
      'meta': {'_type': 'gradio.FileData'},
    };
  }

  /// 上传文件到 Gradio 服务（用于 /call 接口的文件入参）
  /// 返回服务端文件路径，供 data 数组使用；失败返回 null。
  Future<String?> _uploadFileToGradio(String localPath) async {
    final root = baseUrl.replaceAll(RegExp(r'/$'), '');
    for (final path in ['$_gradioApiPrefix/upload', '/upload', '/api/upload']) {
      try {
        final file = File(localPath);
        if (!file.existsSync()) return null;
        final uri = Uri.parse('$root$path');
        var request = http.MultipartRequest('POST', uri);
        request.files.add(await http.MultipartFile.fromPath('files', localPath));
        final streamed = await request.send().timeout(const Duration(seconds: 30));
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode != 200) {
          print('[IndexTTS] 上传失败 $path: status=${streamed.statusCode} body=${body.length > 200 ? "${body.substring(0, 200)}..." : body}');
          continue;
        }
        final decoded = jsonDecode(body);
        String? serverPath;
        if (decoded is List && decoded.isNotEmpty) {
          final first = decoded[0];
          if (first is String) serverPath = first;
          if (first is Map && first['path'] != null) serverPath = first['path'] as String;
        } else if (decoded is String) {
          serverPath = decoded;
        }
        if (serverPath != null) {
          print('[IndexTTS] 上传成功 $path -> $serverPath');
          return serverPath;
        }
      } catch (e) {
        print('[IndexTTS] 上传异常 $path: $e');
      }
    }
    return null;
  }

  /// 调用 Gradio /call/gen_single：提交 data，轮询结果，返回输出列表（如 [output_audio]）
  Future<List<dynamic>?> _callGradioGenSingle(List<dynamic> data) async {
    final root = baseUrl.replaceAll(RegExp(r'/$'), '');
    for (final prefix in [_gradioApiPrefix, '', '/api']) {
      try {
        final postUri = Uri.parse('$root$prefix/call/$_gradioApiGenSingle');
        final postResponse = await http
            .post(
              postUri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'data': data}),
            )
            .timeout(const Duration(seconds: 15));
        final postBodyStr = postResponse.body;
        if (postResponse.statusCode != 200) {
          print('[IndexTTS] /call/gen_single 提交失败 $prefix: status=${postResponse.statusCode} body=${postBodyStr.length > 300 ? "${postBodyStr.substring(0, 300)}..." : postBodyStr}');
          continue;
        }
        final postBody = jsonDecode(postBodyStr) as Map<String, dynamic>?;
        final eventId = postBody?['event_id'] as String?;
        if (eventId == null || eventId.isEmpty) {
          print('[IndexTTS] /call/gen_single 未返回 event_id $prefix, body=$postBodyStr');
          continue;
        }
        print('[IndexTTS] /call/gen_single 已提交 event_id=$eventId，轮询结果...');

        final getUri = Uri.parse('$root$prefix/call/$_gradioApiGenSingle/$eventId');
        const maxWait = Duration(seconds: 120);
        const pollInterval = Duration(milliseconds: 800);
        final deadline = DateTime.now().add(maxWait);
        while (DateTime.now().isBefore(deadline)) {
          final getResponse = await http.get(getUri).timeout(const Duration(seconds: 15));
          if (getResponse.statusCode != 200) {
            await Future.delayed(pollInterval);
            continue;
          }
          final text = getResponse.body;
          String? currentEvent;
          String? currentData;
          for (final line in text.split('\n')) {
            final t = line.trim();
            if (t.startsWith('event:')) currentEvent = t.substring(6).trim();
            if (t.startsWith('data:')) currentData = t.substring(5).trim();
          }
          if (currentEvent == 'complete' && currentData != null && currentData.isNotEmpty && currentData != 'null') {
            try {
              final decoded = jsonDecode(currentData);
              print('[IndexTTS] WebUI complete 原始 data: $currentData');
              print('[IndexTTS] WebUI complete 解码类型: ${decoded.runtimeType}');
              if (decoded is List && decoded.isNotEmpty) {
                print('[IndexTTS] WebUI 合成完成（在后台可见）, output[0]=${decoded[0].runtimeType} ${decoded[0]}');
                return decoded;
              }
            } catch (e) {
              print('[IndexTTS] WebUI complete JSON 解析异常: $e data=$currentData');
            }
            break;
          }
          if (currentEvent == 'error') {
            print('[IndexTTS] WebUI 返回 event:error data=$currentData');
            break;
          }
          await Future.delayed(pollInterval);
        }
      } catch (e) {
        print('[IndexTTS] /call 异常 $prefix: $e');
      }
    }
    return null;
  }

  /// 从 Gradio 返回的 output_audio（FileData 或 path 字符串）下载到本地并返回本地路径
  Future<String?> _downloadGradioOutputToLocal(dynamic outputAudio, String? savePath) async {
    String? url;
    String? serverPath;
    if (outputAudio is Map) {
      // Gradio 5 对 Audio 输出的 complete data 结构为
      // [{"visible": true, "value": {path: ..., url: ... , ...}, "__type__": "update"}]
      // 这里需要优先从 value 里取 FileData，再回退到顶层字段
      final dynamic value = outputAudio['value'];
      if (value is Map) {
        url = value['url'] as String?;
        serverPath = value['path'] as String?;
      }
      url ??= outputAudio['url'] as String?;
      serverPath ??= outputAudio['path'] as String?;
    } else if (outputAudio is String && outputAudio.isNotEmpty) {
      serverPath = outputAudio;
    }
    if (url == null && serverPath == null) {
      print('[IndexTTS] 下载失败: WebUI 返回的 output 既没有 url 也没有 path, output=$outputAudio');
      return null;
    }
    final root = baseUrl.replaceAll(RegExp(r'/$'), '');
    final String downloadUrl;
    if (url != null && url.isNotEmpty) {
      downloadUrl = url.startsWith('http') ? url : '$root$url';
    } else {
      final pathForUrl = serverPath!.replaceAll('\\', '/');
      // Gradio 5 的文件路由在 API 前缀下：/gradio_api/file=...
      downloadUrl = '$root$_gradioApiPrefix/file=${Uri.encodeComponent(pathForUrl)}';
    }
    print('[IndexTTS] 尝试下载 WebUI 输出: $downloadUrl (url=$url, serverPath=$serverPath)');
    try {
      final response = await http.get(Uri.parse(downloadUrl)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        if (response.statusCode == 403) {
          print('[IndexTTS] 下载 403: 请确保 WebUI 已设置 allowed_paths 包含输出目录（如 outputs）');
        } else {
          print('[IndexTTS] 下载失败: status=${response.statusCode} url=$downloadUrl');
        }
        return null;
      }
      final path = savePath ?? '${Directory.systemTemp.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(response.bodyBytes);
      return path;
    } catch (e) {
      _logger.warning('下载 Gradio 输出失败: $e', module: 'IndexTTS');
      return null;
    }
  }

  /// 使用 Python 脚本生成语音（WebUI 不可用时的回退方式）
  Future<String?> _synthesizeWithPython({
    required String text,
    required String voicePromptPath,
    String? outputPath,
    String? emotionPromptPath,
    double emotionAlpha = 1.0,
    bool useRandom = false,
    List<double>? emotionVector,
    String? emotionText,
    bool useEmotionText = false,
  }) async {
    try {
      // 生成输出路径
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalOutputPath = outputPath ?? '${Directory.systemTemp.path}/tts_$timestamp.wav';
      
      // 构建 Python 代码
      final pythonCode = StringBuffer();
      pythonCode.writeln('from indextts.infer_v2 import IndexTTS2');
      pythonCode.writeln('import sys');
      pythonCode.writeln('');
      pythonCode.writeln('try:');
      pythonCode.writeln('    tts = IndexTTS2(');
      pythonCode.writeln('        cfg_path="checkpoints/config.yaml",');
      pythonCode.writeln('        model_dir="checkpoints",');
      pythonCode.writeln('        use_fp16=False,');
      pythonCode.writeln('        use_cuda_kernel=False,');
      pythonCode.writeln('        use_deepspeed=False');
      pythonCode.writeln('    )');
      pythonCode.writeln('    ');
      pythonCode.writeln('    result = tts.infer(');
      pythonCode.writeln('        spk_audio_prompt=r"${voicePromptPath.replaceAll('\\', '\\\\')}",');
      pythonCode.writeln('        text="""$text""",');
      pythonCode.writeln('        output_path=r"${finalOutputPath.replaceAll('\\', '\\\\')}",');
      
      // 添加情感控制参数
      if (emotionPromptPath != null) {
        pythonCode.writeln('        emo_audio_prompt=r"${emotionPromptPath.replaceAll('\\', '\\\\')}",');
        pythonCode.writeln('        emo_alpha=$emotionAlpha,');
      } else if (emotionVector != null) {
        pythonCode.writeln('        emo_vector=$emotionVector,');
      } else if (useEmotionText && emotionText != null) {
        pythonCode.writeln('        emo_text="""$emotionText""",');
        pythonCode.writeln('        emo_alpha=$emotionAlpha,');
        pythonCode.writeln('        use_emo_text=True,');
      }
      
      pythonCode.writeln('        use_random=${useRandom ? "True" : "False"},');
      pythonCode.writeln('        verbose=True');
      pythonCode.writeln('    )');
      pythonCode.writeln('    print("SUCCESS")');
      pythonCode.writeln('except Exception as e:');
      pythonCode.writeln('    print(f"ERROR: {e}")');
      pythonCode.writeln('    sys.exit(1)');
      
      // 保存临时 Python 脚本
      final scriptPath = '${Directory.systemTemp.path}/tts_script_$timestamp.py';
      await File(scriptPath).writeAsString(pythonCode.toString());
      
      final workDir = (indexttsPath ?? 'D:\\Index-TTS2_XH').replaceAll(RegExp(r'[/\\]+$'), '');
      
      _logger.info('执行 IndexTTS Python 脚本', module: 'IndexTTS', extra: {
        'scriptPath': scriptPath,
        'outputPath': finalOutputPath,
        'workDir': workDir,
      });
      
      // 先保存脚本内容到日志，方便调试
      _logger.info('生成的 Python 脚本内容:', module: 'IndexTTS', extra: {
        'script': pythonCode.toString().substring(0, pythonCode.length > 500 ? 500 : pythonCode.length),
      });
      
      // 优先使用 IndexTTS 目录下的虚拟环境 Python（支持 .venv/venv，且支持 python 在 Scripts 或 venv 根目录）
      final venvCandidates = Platform.isWindows
          ? [
              '$workDir\\.venv\\Scripts\\python.exe',
              '$workDir\\venv\\Scripts\\python.exe',
              '$workDir\\.venv\\python.exe',
              '$workDir\\venv\\python.exe',  // 部分 venv 的 python.exe 在根目录
            ]
          : [
              '$workDir/.venv/bin/python',
              '$workDir/venv/bin/python',
              '$workDir/.venv/python',
              '$workDir/venv/python',
            ];
      String? venvPython;
      for (final candidate in venvCandidates) {
        if (await File(candidate).exists()) {
          venvPython = candidate;
          break;
        }
      }
      late ProcessResult result;
      if (venvPython != null) {
        _logger.info('使用 IndexTTS 虚拟环境 Python', module: 'IndexTTS', extra: {'venvPython': venvPython});
        print('[IndexTTS] 使用 venv: $venvPython');
        result = await Process.run(
          venvPython,
          [scriptPath],
          workingDirectory: workDir,
          runInShell: false,
        );
      } else {
        // 回退：先尝试 uv，若找不到则用 python -m uv
        result = await Process.run(
          'uv',
          ['run', 'python', scriptPath],
          workingDirectory: workDir,
          runInShell: true,
        );
        final stderrFirst = result.stderr.toString();
        final isUvNotFound = result.exitCode != 0 &&
            (stderrFirst.contains("'uv'") && stderrFirst.contains('不是内部或外部命令') ||
             stderrFirst.toLowerCase().contains('uv') && stderrFirst.toLowerCase().contains('not recognized'));
        final bool noModuleUv = result.exitCode != 0 && stderrFirst.contains('No module named uv');
        if (isUvNotFound || noModuleUv) {
          _logger.info('未找到/未安装 uv，尝试使用 python -m uv', module: 'IndexTTS');
          print('[IndexTTS] uv 不可用，改用 python -m uv');
          result = await Process.run(
            'python',
            ['-m', 'uv', 'run', 'python', scriptPath],
            workingDirectory: workDir,
            runInShell: true,
          );
          final stderrPy = result.stderr.toString();
          final isPyNotFound = result.exitCode != 0 &&
              (stderrPy.contains("'python'") && stderrPy.contains('不是内部或外部命令') ||
               stderrPy.toLowerCase().contains('not recognized'));
          if (isPyNotFound && Platform.isWindows) {
            print('[IndexTTS] python 未找到，尝试 py -m uv');
            result = await Process.run(
              'py',
              ['-m', 'uv', 'run', 'python', scriptPath],
              workingDirectory: workDir,
              runInShell: true,
            );
          }
        }
      }
      
      // 详细日志输出（同时 print 方便控制台查看）
      final stdoutStr = result.stdout.toString();
      final stderrStr = result.stderr.toString();
      _logger.info('Python 脚本执行完成', module: 'IndexTTS', extra: {
        'exitCode': result.exitCode,
        'stdoutLength': stdoutStr.length,
        'stderrLength': stderrStr.length,
      });
      print('[IndexTTS] exitCode=${result.exitCode} workDir=$workDir');
      print('[IndexTTS] stdout: $stdoutStr');
      print('[IndexTTS] stderr: $stderrStr');
      
      _logger.info('Stdout: $stdoutStr', module: 'IndexTTS');
      _logger.info('Stderr: $stderrStr', module: 'IndexTTS');
      
      // 清理临时脚本
      try {
        await File(scriptPath).delete();
      } catch (e) {
        _logger.warning('清理临时脚本失败: $e', module: 'IndexTTS');
      }
      
      // 检查结果
      if (result.exitCode == 0 && result.stdout.toString().contains('SUCCESS')) {
        if (await File(finalOutputPath).exists()) {
          final fileSize = await File(finalOutputPath).length();
          _logger.success('Python脚本生成成功', module: 'IndexTTS', extra: {
            'path': finalOutputPath,
            'size': '${(fileSize / 1024).toStringAsFixed(2)} KB',
          });
          return finalOutputPath;
        } else {
          throw Exception('脚本执行成功但输出文件不存在');
        }
      }
      
      // 构建详细错误信息
      final errorMsg = StringBuffer();
      errorMsg.writeln('Python 脚本执行失败');
      errorMsg.writeln('Exit code: ${result.exitCode}');
      errorMsg.writeln('工作目录: $workDir');
      errorMsg.writeln('\nStdout:');
      errorMsg.writeln(result.stdout.toString().substring(0, result.stdout.toString().length > 1000 ? 1000 : result.stdout.toString().length));
      errorMsg.writeln('\nStderr:');
      errorMsg.writeln(result.stderr.toString().substring(0, result.stderr.toString().length > 1000 ? 1000 : result.stderr.toString().length));
      
      throw Exception(errorMsg.toString());
    } on ProcessException catch (e) {
      _logger.error('IndexTTS 进程执行失败: $e', module: 'IndexTTS');
      print('[IndexTTS] ProcessException: $e');
      throw Exception(
        '无法执行 uv 命令。请确保：\n'
        '1. 已安装 uv（pip install uv 或从 https://github.com/astral-sh/uv 安装）\n'
        '2. uv 已加入系统 PATH（重启本应用后再试）\n\n'
        '原始错误: $e',
      );
    } catch (e, st) {
      _logger.error('Python脚本生成失败: $e', module: 'IndexTTS');
      print('[IndexTTS] 合成异常: $e');
      print('[IndexTTS] 堆栈: $st');
      rethrow;
    }
  }

  /// 基础语音合成
  /// 
  /// [text] 要合成的文本
  /// [voicePromptPath] 声音参考文件路径（本地路径）
  /// [outputPath] 输出文件路径（可选，不提供则返回临时文件）
  /// [emotionPromptPath] 情感参考音频路径（可选）
  /// [emotionAlpha] 情感强度 0.0-1.0（默认1.0）
  /// [useRandom] 是否使用随机采样（默认false）
  /// 
  /// 返回生成的音频文件路径
  /// 优先尝试 WebUI HTTP API（需先启动 webui.bat），模型常驻内存，后续请求快且会在 webui 界面有记录；失败则回退到 Python 子进程。
  Future<String?> synthesize({
    required String text,
    required String voicePromptPath,
    String? outputPath,
    String? emotionPromptPath,
    double emotionAlpha = 1.0,
    bool useRandom = false,
  }) async {
    // 1. 若配置了 baseUrl，先尝试 Gradio WebUI（在已启动的 webui 进程内合成，后台可见）
    if (baseUrl.isNotEmpty && (baseUrl.startsWith('http://') || baseUrl.startsWith('https://'))) {
      try {
        final result = await _synthesizeViaGradio(
          text: text,
          voicePromptPath: voicePromptPath,
          outputPath: outputPath,
          emotionPromptPath: emotionPromptPath,
          emotionAlpha: emotionAlpha,
          useRandom: useRandom,
        );
        if (result != null) {
          _logger.info('本次合成通过 WebUI 完成', module: 'IndexTTS');
          return result;
        }
      } catch (e) {
        _logger.info('WebUI 不可用，改用 Python 子进程: $e', module: 'IndexTTS');
      }
    }
    // 2. 回退到 Python 脚本调用（每次新进程会重新加载模型，较慢）
    if (indexttsPath != null || await Directory('D:\\Index-TTS2_XH').exists()) {
      return await _synthesizeWithPython(
        text: text,
        voicePromptPath: voicePromptPath,
        outputPath: outputPath,
        emotionPromptPath: emotionPromptPath,
        emotionAlpha: emotionAlpha,
        useRandom: useRandom,
      );
    }
    return null;
  }

  /// 通过 Gradio WebUI /call/gen_single 合成（需先启动 webui，模型常驻、界面有记录）
  Future<String?> _synthesizeViaGradio({
    required String text,
    required String voicePromptPath,
    String? outputPath,
    String? emotionPromptPath,
    double emotionAlpha = 1.0,
    bool useRandom = false,
    List<double>? emotionVector,
    String? emotionText,
    bool useEmotionText = false,
  }) async {
    print('[IndexTTS] 尝试 WebUI 合成: baseUrl=$baseUrl');
    if (!File(voicePromptPath).existsSync()) {
      throw Exception('声音参考文件不存在: $voicePromptPath');
    }
    final promptFile = await _uploadFileToGradio(voicePromptPath);
    if (promptFile == null) {
      print('[IndexTTS] WebUI 失败: 音色参考上传失败，回退 Python');
      throw Exception('音色参考上传失败，请确认 WebUI 已启动且可访问 $baseUrl');
    }
    String? emoFile;
    if (emotionPromptPath != null && File(emotionPromptPath).existsSync()) {
      emoFile = await _uploadFileToGradio(emotionPromptPath);
    }
    int emoMode = 0;
    if (emotionVector != null && emotionVector.length == 8) {
      emoMode = 2;
    } else if (useEmotionText && emotionText != null && emotionText.isNotEmpty) {
      emoMode = 3;
    } else if (emoFile != null) {
      emoMode = 1;
    }
    // Gradio 5 /call API 对文件类入参期望 FileData 格式，否则服务端可能报 event:error
    final promptPayload = _gradioFileData(promptFile, voicePromptPath);
    final emoPayload = emoFile != null && emotionPromptPath != null
        ? _gradioFileData(emoFile, emotionPromptPath)
        : null;
    final vec = emotionVector ?? [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    final emoLabel = _emoChoiceLabels[emoMode.clamp(0, _emoChoiceLabels.length - 1)];
    final data = <dynamic>[
      emoLabel,
      promptPayload,
      text,
      emoPayload,
      emotionAlpha,
      vec[0], vec[1], vec[2], vec[3], vec[4], vec[5], vec[6], vec[7],
      emotionText ?? '',
      useRandom,
      120,
      true,
      0.8,
      30,
      0.8,
      0.0,
      3,
      10.0,
      1500,
    ];
    final result = await _callGradioGenSingle(data);
    if (result == null || result.isEmpty) {
      print('[IndexTTS] WebUI 失败: 合成未返回结果，回退 Python');
      throw Exception('WebUI 合成未返回结果');
    }
    final outPath = await _downloadGradioOutputToLocal(result[0], outputPath);
    if (outPath == null) {
      print('[IndexTTS] WebUI 失败: 下载输出文件失败，回退 Python');
      throw Exception('下载 WebUI 输出失败');
    }
    _logger.success('语音合成完成(WebUI)', module: 'IndexTTS', extra: {'outputPath': outPath});
    return outPath;
  }

  /// 使用情感向量合成语音
  /// 
  /// [text] 要合成的文本
  /// [voicePromptPath] 声音参考文件路径
  /// [emotionVector] 8维情感向量 [happy, angry, sad, afraid, disgusted, melancholic, surprised, calm]
  /// [outputPath] 输出文件路径（可选）
  /// [useRandom] 是否使用随机采样（默认false）
  /// 
  /// 返回生成的音频文件路径
  Future<String?> synthesizeWithEmotionVector({
    required String text,
    required String voicePromptPath,
    required List<double> emotionVector,
    String? outputPath,
    bool useRandom = false,
  }) async {
    if (emotionVector.length != 8) {
      throw Exception('情感向量必须是8维: [happy, angry, sad, afraid, disgusted, melancholic, surprised, calm]');
    }
    
    // 1. 先尝试 WebUI（Gradio /call/gen_single）
    if (baseUrl.isNotEmpty && (baseUrl.startsWith('http://') || baseUrl.startsWith('https://'))) {
      try {
        final result = await _synthesizeViaGradio(
          text: text,
          voicePromptPath: voicePromptPath,
          outputPath: outputPath,
          emotionVector: emotionVector,
          useRandom: useRandom,
        );
        if (result != null) return result;
      } catch (_) {}
    }
    // 2. 回退到 Python
    if (indexttsPath != null || await Directory('D:\\Index-TTS2_XH').exists()) {
      return await _synthesizeWithPython(
        text: text,
        voicePromptPath: voicePromptPath,
        outputPath: outputPath,
        emotionVector: emotionVector,
        useRandom: useRandom,
      );
    }
    return null;
  }


  /// 使用文本描述情感合成语音
  /// 
  /// [text] 要合成的文本
  /// [voicePromptPath] 声音参考文件路径
  /// [emotionText] 情感描述文本（可选，如"他很生气地说"）
  /// [useEmotionText] 是否启用文本情感分析
  /// [emotionAlpha] 情感强度 0.0-1.0
  /// [outputPath] 输出文件路径（可选）
  /// [useRandom] 是否使用随机采样（默认false）
  /// 
  /// 返回生成的音频文件路径
  Future<String?> synthesizeWithEmotionText({
    required String text,
    required String voicePromptPath,
    String? emotionText,
    bool useEmotionText = true,
    double emotionAlpha = 0.6,
    String? outputPath,
    bool useRandom = false,
  }) async {
    // 1. 先尝试 WebUI（Gradio /call/gen_single）
    if (baseUrl.isNotEmpty && (baseUrl.startsWith('http://') || baseUrl.startsWith('https://'))) {
      try {
        final result = await _synthesizeViaGradio(
          text: text,
          voicePromptPath: voicePromptPath,
          outputPath: outputPath,
          emotionAlpha: emotionAlpha,
          useRandom: useRandom,
          emotionText: useEmotionText ? (emotionText ?? text) : null,
          useEmotionText: useEmotionText,
        );
        if (result != null) return result;
      } catch (_) {}
    }
    // 2. 回退到 Python
    if (indexttsPath != null || await Directory('D:\\Index-TTS2_XH').exists()) {
      return await _synthesizeWithPython(
        text: text,
        voicePromptPath: voicePromptPath,
        outputPath: outputPath,
        emotionText: emotionText,
        emotionAlpha: emotionAlpha,
        useRandom: useRandom,
        useEmotionText: useEmotionText,
      );
    }
    return null;
  }


  /// 获取音频时长（秒）
  /// 
  /// 注意：这是一个简化实现，实际应该用专门的音频库
  Future<double> getAudioDuration(String audioPath) async {
    try {
      // TODO: 实现真实的音频时长获取
      // 可以使用 ffmpeg 或其他音频库
      // 这里返回一个估算值
      final file = File(audioPath);
      if (!file.existsSync()) {
        return 0.0;
      }
      
      final bytes = await file.length();
      // 简单估算：假设是 16kHz, 16bit, mono 的 WAV 文件
      // WAV 文件头大约 44 字节
      final audioBytes = bytes - 44;
      final bytesPerSecond = 16000 * 2; // 16kHz * 2 bytes
      final duration = audioBytes / bytesPerSecond;
      
      return duration;
    } catch (e) {
      _logger.error('获取音频时长失败: $e', module: 'IndexTTS');
      return 0.0;
    }
  }
}
