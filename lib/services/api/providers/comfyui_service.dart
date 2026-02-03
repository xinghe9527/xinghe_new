import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// ComfyUI API 服务
/// 
/// ComfyUI 是一个强大的本地 Stable Diffusion 工作流系统
/// 支持图片生成、视频生成等功能
class ComfyUIService extends ApiServiceBase {
  ComfyUIService(super.config);

  @override
  String get providerName => 'ComfyUI';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      debugPrint('🔍 测试 ComfyUI 连接: ${config.baseUrl}');
      
      // 测试 /system_stats 端点（获取系统信息）
      final response = await http.get(
        Uri.parse('${config.baseUrl}system_stats'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // 显示系统信息
        final deviceName = data['system']?['os'] ?? 'Unknown';
        debugPrint('✅ ComfyUI 连接成功');
        debugPrint('   系统: $deviceName');
        
        return ApiResponse.success(true, statusCode: response.statusCode);
      } else {
        return ApiResponse.failure(
          'ComfyUI 响应异常: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } on TimeoutException {
      return ApiResponse.failure(
        'ComfyUI 连接超时\n\n请检查：\n1. ComfyUI 是否运行\n2. 端口是否正确 (8188)\n3. 防火墙设置'
      );
    } on SocketException {
      return ApiResponse.failure(
        'ComfyUI 未运行\n\n💡 请先启动 ComfyUI：\npython main.py --listen 0.0.0.0 --port 8188'
      );
    } catch (e) {
      return ApiResponse.failure('连接失败: $e');
    }
  }

  @override
  Future<ApiResponse<List<ImageResponse>>> generateImages({
    required String prompt,
    String? model,
    int count = 1,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      debugPrint('\n🎨 ComfyUI 生成图片');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('   Prompt: ${prompt.substring(0, prompt.length > 100 ? 100 : prompt.length)}...');
      debugPrint('   参考图片: ${referenceImages?.length ?? 0} 张');
      debugPrint('   比例参数: ratio=$ratio, quality=$quality');
      debugPrint('   额外参数: $parameters');
      
      // 1. 加载选中的工作流
      final prefs = await SharedPreferences.getInstance();
      final selectedWorkflowId = prefs.getString('comfyui_selected_image_workflow');
      
      if (selectedWorkflowId == null) {
        throw Exception('未选择 ComfyUI 工作流\n请在设置中选择一个工作流');
      }
      
      final workflowsJson = prefs.getString('comfyui_workflows');
      if (workflowsJson == null) {
        throw Exception('未找到工作流数据\n请在设置中重新读取工作流');
      }
      
      final workflows = List<Map<String, dynamic>>.from(
        (jsonDecode(workflowsJson) as List).map((w) => Map<String, dynamic>.from(w as Map))
      );
      
      final workflow = workflows.firstWhere(
        (w) => w['id'] == selectedWorkflowId,
        orElse: () => throw Exception('工作流未找到: $selectedWorkflowId'),
      );
      
      debugPrint('   使用工作流: ${workflow['name'] ?? selectedWorkflowId}');
      
      // 2. 深度克隆工作流（避免修改原始数据，保留所有连接）
      final workflowData = jsonDecode(jsonEncode(workflow['workflow'])) as Map<String, dynamic>;
      
      debugPrint('\n📊 工作流分析');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('   总节点数: ${workflowData.length}');
      
      // 打印所有节点类型和连接
      final nodeTypes = <String, int>{};
      for (final entry in workflowData.entries) {
        final node = entry.value as Map<String, dynamic>;
        final classType = node['class_type'] as String;
        nodeTypes[classType] = (nodeTypes[classType] ?? 0) + 1;
        
        // 检查节点输入连接
        final inputs = node['inputs'] as Map<String, dynamic>?;
        if (inputs != null) {
          for (final inputEntry in inputs.entries) {
            if (inputEntry.value is List) {
              debugPrint('   节点 ${entry.key} ($classType):');
              debugPrint('      ${inputEntry.key} → 连接到节点 ${inputEntry.value}');
            }
          }
        }
      }
      
      debugPrint('\n   节点类型统计:');
      nodeTypes.forEach((type, count) {
        debugPrint('      - $type: $count 个');
      });
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // 3. 设置图片比例和尺寸
      // ✅ 优先从直接参数读取，如果没有则从 parameters 中读取
      final finalRatio = ratio ?? parameters?['size'];
      final finalQuality = quality ?? parameters?['quality'];
      
      if (finalRatio != null || finalQuality != null) {
        _setImageSizeInWorkflow(workflowData, finalRatio, finalQuality);
      } else {
        debugPrint('⚠️ 未提供比例参数，使用工作流默认尺寸\n');
      }
      
      // 4. 替换提示词（查找 CLIPTextEncode 节点）
      // 添加参数控制是否替换（调试用）
      final replacePrompt = parameters?['replace_prompt'] ?? true;
      if (replacePrompt) {
        _replacePromptInWorkflow(workflowData, prompt);
      } else {
        debugPrint('⚠️ 跳过提示词替换（使用工作流原始提示词）\n');
      }
      
      // 5. 随机 seed（增加多样性）
      final randomizeSeed = parameters?['randomize_seed'] ?? true;
      if (randomizeSeed) {
        _randomizeSeedInWorkflow(workflowData);
      } else {
        debugPrint('⚠️ 跳过 seed 随机化（使用工作流原始 seed）\n');
      }
      
      // 6. 处理参考图片
      if (referenceImages != null && referenceImages.isNotEmpty) {
        // 有参考图片：上传并设置
        await _uploadAndSetReferenceImages(workflowData, referenceImages);
      } else {
        // ✅ 没有参考图片：清空所有 LoadImage 节点（避免使用工作流原始图片）
        _clearAllLoadImageNodes(workflowData);
      }
      
      // 7. 提交工作流到 ComfyUI
      final promptId = await _submitWorkflow(workflowData);
      debugPrint('   任务ID: $promptId');
      
      // 7. 轮询等待完成
      final outputImages = await _waitForCompletion(promptId);
      
      debugPrint('\n📸 输出图片信息');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('   获取到 ${outputImages.length} 张图片');
      
      // 8. 构建图片 URL
      final imageUrls = <String>[];
      for (var i = 0; i < outputImages.length; i++) {
        final img = outputImages[i];
        final filename = img['filename'];
        final subfolder = img['subfolder'] ?? '';
        final type = img['type'] ?? 'output';
        
        // 构建完整的图片 URL
        var imageUrl = '${config.baseUrl}view?filename=$filename&type=$type';
        if (subfolder.isNotEmpty) {
          imageUrl += '&subfolder=$subfolder';
        }
        
        imageUrls.add(imageUrl);
        
        debugPrint('   图片${i + 1}:');
        debugPrint('      filename: $filename');
        debugPrint('      subfolder: ${subfolder.isEmpty ? "(无)" : subfolder}');
        debugPrint('      type: $type');
        debugPrint('      URL: $imageUrl');
      }
      
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      final images = imageUrls.map((url) => ImageResponse(
        imageUrl: url,
        imageId: null,
        metadata: {},
      )).toList();
      
      return ApiResponse.success(images, statusCode: 200);
    } catch (e) {
      debugPrint('❌ ComfyUI 生成失败: $e');
      return ApiResponse.failure('生成失败: $e');
    }
  }
  
  /// 在工作流中替换提示词
  void _replacePromptInWorkflow(Map<String, dynamic> workflow, String prompt) {
    debugPrint('\n🔍 提示词替换分析');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('   目标提示词: ${prompt.substring(0, prompt.length > 100 ? 100 : prompt.length)}...');
    debugPrint('   查找提示词编码节点...\n');
    
    var replacedCount = 0;
    var foundCount = 0;
    
    // ✅ 支持多种提示词编码节点类型
    final supportedNodeTypes = [
      'CLIPTextEncode',                    // 标准 CLIP 节点
      'TextEncodeQwenImageEditPlus',       // Qwen 图生图节点
      'CLIPTextEncodeSDXL',                // SDXL CLIP 节点
      'CLIPTextEncodeFlux',                // Flux CLIP 节点
      'BNK_CLIPTextEncodeAdvanced',        // 高级 CLIP 节点
    ];
    
    // 查找所有提示词编码节点
    for (final entry in workflow.entries) {
      final nodeId = entry.key;
      final node = entry.value as Map<String, dynamic>;
      final classType = node['class_type'] as String;
      
      if (supportedNodeTypes.contains(classType)) {
        foundCount++;
        final inputs = node['inputs'] as Map<String, dynamic>;
        
        // 不同节点类型的文本字段名称可能不同
        String? textFieldName;
        String? currentText;
        
        if (inputs.containsKey('text')) {
          textFieldName = 'text';
          currentText = inputs['text']?.toString() ?? '';
        } else if (inputs.containsKey('prompt')) {
          textFieldName = 'prompt';
          currentText = inputs['prompt']?.toString() ?? '';
        } else if (inputs.containsKey('positive')) {
          textFieldName = 'positive';
          currentText = inputs['positive']?.toString() ?? '';
        }
        
        if (textFieldName == null) {
          debugPrint('   节点 $nodeId ($classType):');
          debugPrint('      ⚠️ 未找到文本字段（跳过）');
          debugPrint('');
          continue;
        }
        
        debugPrint('   节点 $nodeId ($classType):');
        debugPrint('      字段: $textFieldName');
        debugPrint('      当前: ${currentText!.substring(0, currentText.length > 80 ? 80 : currentText.length)}${currentText.length > 80 ? "..." : ""}');
        
        // 判断是否为正向提示词节点（排除负面提示词）
        final isNegative = currentText.toLowerCase().contains('nsfw') ||
                          currentText.toLowerCase().contains('bad quality') ||
                          currentText.toLowerCase().contains('worst quality') ||
                          currentText.toLowerCase().contains('low quality') ||
                          currentText.toLowerCase().contains('blurry') ||
                          currentText.toLowerCase().contains('ugly') ||
                          currentText.toLowerCase().contains('deformed') ||
                          currentText.toLowerCase().contains('disfigured');
        
        if (!isNegative || currentText.isEmpty) {
          // 这是正向提示词节点，替换它
          inputs[textFieldName] = prompt;
          debugPrint('      类型: 正向提示词');
          debugPrint('      操作: ✅ 已替换');
          debugPrint('      新值: ${prompt.substring(0, prompt.length > 80 ? 80 : prompt.length)}${prompt.length > 80 ? "..." : ""}');
          replacedCount++;
          // ✅ 继续替换所有正向提示词节点，不要 break
        } else {
          debugPrint('      类型: 负面提示词');
          debugPrint('      操作: ⏭️ 跳过');
        }
        
        debugPrint('');
      }
    }
    
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('   找到提示词节点: $foundCount 个');
    debugPrint('   成功替换: $replacedCount 个');
    
    if (replacedCount > 1) {
      debugPrint('   💡 替换了多个提示词节点，确保所有人物描述一致');
    }
    
    if (foundCount == 0) {
      debugPrint('   ⚠️ 警告：工作流中没有识别的提示词编码节点！');
      debugPrint('   💡 当前支持的节点类型:');
      for (final type in supportedNodeTypes) {
        debugPrint('      - $type');
      }
    } else if (replacedCount == 0) {
      debugPrint('   ⚠️ 警告：所有提示词节点都被判断为负面提示词！');
    }
    
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }
  
  /// 设置图片尺寸和比例
  void _setImageSizeInWorkflow(Map<String, dynamic> workflow, String? ratio, String? quality) {
    debugPrint('\n📐 设置图片尺寸');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('   比例: ${ratio ?? "未指定"}');
    debugPrint('   质量: ${quality ?? "未指定"}');
    
    // 根据比例和质量计算宽高
    int width = 1024;
    int height = 1024;
    
    if (ratio != null) {
      switch (ratio) {
        case '1:1':
          width = 1024;
          height = 1024;
          break;
        case '16:9':
          width = 1920;
          height = 1080;
          break;
        case '9:16':
          width = 1080;
          height = 1920;
          break;
        case '4:3':
          width = 1536;
          height = 1152;
          break;
        case '3:4':
          width = 1152;
          height = 1536;
          break;
      }
      
      // 根据质量调整尺寸
      if (quality == '2K' || quality == 'hd') {
        width = (width * 1.5).toInt();
        height = (height * 1.5).toInt();
      } else if (quality == '4K') {
        width = width * 2;
        height = height * 2;
      }
    }
    
    debugPrint('   计算尺寸: ${width}x$height');
    
    // 查找并设置各种尺寸控制节点
    var foundCount = 0;
    
    // ✅ 支持的节点类型（按优先级）
    final sizeNodeTypes = [
      'EmptyLatentImage',
      'EmptySD3LatentImage',
      'EmptyFluxLatentImage',
      'ImageScale',
      'ImageScaleBy',
      'ImageScaleToTotalPixels',  // 你的工作流有这个！
      'LatentUpscale',
    ];
    
    for (final entry in workflow.entries) {
      final nodeId = entry.key;
      final node = entry.value as Map<String, dynamic>;
      final classType = node['class_type'] as String;
      
      if (sizeNodeTypes.contains(classType)) {
        final inputs = node['inputs'] as Map<String, dynamic>;
        
        // 不同节点类型有不同的参数
        if (classType == 'ImageScaleToTotalPixels') {
          // ✅ ImageScaleToTotalPixels 同时设置 megapixels、width 和 height
          final totalPixels = width * height;
          final megapixels = (totalPixels / 1000000).toStringAsFixed(1);
          
          final oldMegapixels = inputs['megapixels'] ?? '未设置';
          final oldWidth = inputs['width'];
          final oldHeight = inputs['height'];
          
          // 设置所有参数（强制宽高比）
          inputs['megapixels'] = megapixels;
          inputs['width'] = width;
          inputs['height'] = height;
          
          debugPrint('   ✅ 节点 $nodeId ($classType):');
          debugPrint('      原始: $oldMegapixels MP, ${oldWidth ?? "auto"}x${oldHeight ?? "auto"}');
          debugPrint('      新值: $megapixels MP, ${width}x$height (强制比例)');
          
          foundCount++;
        } else if (inputs.containsKey('width') && inputs.containsKey('height')) {
          // 标准 width/height 参数
          final oldWidth = inputs['width'];
          final oldHeight = inputs['height'];
          
          inputs['width'] = width;
          inputs['height'] = height;
          
          debugPrint('   ✅ 节点 $nodeId ($classType):');
          debugPrint('      原始: ${oldWidth}x$oldHeight');
          debugPrint('      新值: ${width}x$height');
          
          foundCount++;
        }
      }
    }
    
    if (foundCount == 0) {
      debugPrint('   ⚠️ 未找到 Latent 尺寸节点');
      debugPrint('   💡 工作流可能使用固定尺寸或其他方式控制');
    } else {
      debugPrint('   ✅ 成功设置 $foundCount 个节点的尺寸');
    }
    
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  /// 随机化 seed
  void _randomizeSeedInWorkflow(Map<String, dynamic> workflow) {
    final random = Random();
    for (final entry in workflow.entries) {
      final node = entry.value as Map<String, dynamic>;
      if (node['class_type'] == 'KSampler' || 
          node['class_type'] == 'KSamplerAdvanced') {
        final inputs = node['inputs'] as Map<String, dynamic>;
        inputs['seed'] = random.nextInt(4294967295);
        debugPrint('   ✅ 随机 seed: ${inputs['seed']}');
        break;
      }
    }
  }
  
  /// 警告：工作流需要参考图片
  void _clearAllLoadImageNodes(Map<String, dynamic> workflow) {
    debugPrint('\n⚠️ 参考图片缺失警告');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    // 检查工作流中的 LoadImage 节点数量
    var loadImageCount = 0;
    final loadImageNodes = <String>[];
    
    for (final entry in workflow.entries) {
      final node = entry.value as Map<String, dynamic>;
      if (node['class_type'] == 'LoadImage') {
        loadImageCount++;
        loadImageNodes.add(entry.key);
      }
    }
    
    if (loadImageCount > 0) {
      debugPrint('   ⚠️ 当前工作流包含 $loadImageCount 个 LoadImage 节点');
      debugPrint('   ⚠️ 但未提供参考图片');
      debugPrint('   ⚠️ 工作流将使用原始图片生成');
      debugPrint('   💡 建议：');
      debugPrint('      1. 添加风格参考图片');
      debugPrint('      2. 或使用纯文生图工作流（不包含 LoadImage 节点）');
    }
    
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  /// 上传并设置参考图片
  Future<void> _uploadAndSetReferenceImages(
    Map<String, dynamic> workflow,
    List<String> referenceImages,
  ) async {
    if (referenceImages.isEmpty) return;
    
    debugPrint('   📤 上传参考图片...');
    
    // ✅ 先查找所有 LoadImage 节点
    final loadImageNodes = <String>[];
    for (final entry in workflow.entries) {
      final node = entry.value as Map<String, dynamic>;
      if (node['class_type'] == 'LoadImage') {
        loadImageNodes.add(entry.key);
      }
    }
    
    debugPrint('      找到 ${loadImageNodes.length} 个 LoadImage 节点: ${loadImageNodes.join(", ")}');
    debugPrint('      提供 ${referenceImages.length} 张参考图片\n');
    
    // 上传并设置参考图片
    for (var i = 0; i < referenceImages.length; i++) {
      final imagePath = referenceImages[i];
      
      try {
        // 检查是URL还是本地文件
        File? imageFile;
        if (imagePath.startsWith('http')) {
          // 下载在线图片到临时文件
          final response = await http.get(Uri.parse(imagePath));
          if (response.statusCode == 200) {
            final tempDir = Directory.systemTemp;
            final tempFile = File('${tempDir.path}/comfyui_ref_$i.png');
            await tempFile.writeAsBytes(response.bodyBytes);
            imageFile = tempFile;
          }
        } else {
          // 直接使用本地文件
          imageFile = File(imagePath);
        }
        
        if (imageFile == null || !await imageFile.exists()) {
          debugPrint('      ⚠️ 图片${i + 1}不存在: $imagePath');
          continue;
        }
        
        // 上传到 ComfyUI
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${config.baseUrl}upload/image'),
        );
        
        request.files.add(await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
        ));
        
        request.fields['overwrite'] = 'true';
        
        final response = await request.send();
        final responseData = await response.stream.bytesToString();
        
        if (response.statusCode == 200) {
          final data = jsonDecode(responseData);
          final uploadedName = data['name'] as String;
          
          debugPrint('      ✅ 图片${i + 1}上传成功: $uploadedName');
          
          // ✅ 设置到对应的 LoadImage 节点
          if (i < loadImageNodes.length) {
            final targetNodeId = loadImageNodes[i];
            final node = workflow[targetNodeId] as Map<String, dynamic>;
            final inputs = node['inputs'] as Map<String, dynamic>;
            inputs['image'] = uploadedName;
            debugPrint('         → 设置到节点 $targetNodeId');
          } else {
            debugPrint('         ⚠️ LoadImage 节点不足，跳过设置');
          }
        } else {
          debugPrint('      ❌ 图片${i + 1}上传失败: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('      ❌ 图片${i + 1}上传异常: $e');
      }
    }
    
    // ✅ 处理未使用的 LoadImage 节点
    for (var i = referenceImages.length; i < loadImageNodes.length; i++) {
      final nodeId = loadImageNodes[i];
      final node = workflow[nodeId] as Map<String, dynamic>;
      final inputs = node['inputs'] as Map<String, dynamic>;
      
      if (inputs.containsKey('image')) {
        final originalImage = inputs['image'];
        
        // ✅ 选项1：使用第一张参考图片填充（避免使用工作流原始图片）
        if (referenceImages.isNotEmpty && i > 0) {
          // 重复使用已上传的第一张图片
          final firstNodeId = loadImageNodes[0];
          final firstNode = workflow[firstNodeId] as Map<String, dynamic>;
          final firstInputs = firstNode['inputs'] as Map<String, dynamic>;
          final firstImage = firstInputs['image'];
          
          inputs['image'] = firstImage;
          debugPrint('      ⚠️ LoadImage 节点 $nodeId: 参考图片不足');
          debugPrint('         原始图片: $originalImage');
          debugPrint('         → 已替换为第1张参考图片: $firstImage');
        } else {
          debugPrint('      ⚠️ LoadImage 节点 $nodeId 未被覆盖');
          debugPrint('         保留原始图片: $originalImage');
          debugPrint('         💡 这可能导致生成意外的内容');
        }
      }
    }
    
    debugPrint('');
  }
  
  /// 提交工作流到 ComfyUI
  Future<String> _submitWorkflow(Map<String, dynamic> workflow) async {
    final clientId = 'xinghe_${DateTime.now().millisecondsSinceEpoch}';
    
    final response = await http.post(
      Uri.parse('${config.baseUrl}prompt'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'prompt': workflow,
        'client_id': clientId,
      }),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['prompt_id'] as String;
    } else {
      throw Exception('提交失败: ${response.statusCode} - ${response.body}');
    }
  }
  
  /// 等待任务完成
  Future<List<Map<String, dynamic>>> _waitForCompletion(String promptId) async {
    debugPrint('   ⏳ 等待生成完成（包括排队时间）...');
    
    // ✅ 增加到30分钟，支持大批量图片生成
    for (var i = 0; i < 1800; i++) {  // 30分钟 = 1800秒
      await Future.delayed(const Duration(seconds: 1));
      
      try {
        final response = await http.get(
          Uri.parse('${config.baseUrl}history/$promptId'),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data[promptId] != null) {
            final history = data[promptId] as Map<String, dynamic>;
            final outputs = history['outputs'] as Map<String, dynamic>?;
            
            if (outputs != null) {
              // 查找 SaveImage 节点的输出
              for (final output in outputs.values) {
                if (output is Map && output['images'] != null) {
                  debugPrint('   ✅ 生成完成！');
                  return List<Map<String, dynamic>>.from(
                    (output['images'] as List).map((img) => Map<String, dynamic>.from(img as Map))
                  );
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('   ⚠️ 查询状态失败: $e');
      }
      
      // ✅ 改进日志输出（减少刷屏）
      if (i == 0 || i == 30 || i == 60 || (i > 60 && i % 60 == 0)) {
        final minutes = (i / 60).floor();
        final seconds = i % 60;
        if (minutes > 0) {
          debugPrint('   ⏳ 已等待 $minutes 分 $seconds 秒...');
        } else {
          debugPrint('   ⏳ 已等待 $seconds 秒...');
        }
      }
    }
    
    throw Exception('生成超时（30分钟）\n\n可能原因：\n1. ComfyUI 队列繁忙\n2. 模型加载缓慢\n3. 生成失败但未报错\n\n💡 建议：\n1. 检查 ComfyUI 控制台日志\n2. 减少批量生成的数量（建议单次不超过20个）');
  }

  @override
  Future<ApiResponse<List<VideoResponse>>> generateVideos({
    required String prompt,
    String? model,
    int count = 1,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      debugPrint('\n🎬 ComfyUI 生成视频');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('   Prompt: ${prompt.substring(0, prompt.length > 100 ? 100 : prompt.length)}...');
      debugPrint('   参考图片: ${referenceImages?.length ?? 0} 张');
      
      // 1. 加载选中的工作流
      final prefs = await SharedPreferences.getInstance();
      final selectedWorkflowId = prefs.getString('comfyui_selected_video_workflow');
      
      if (selectedWorkflowId == null) {
        throw Exception('未选择 ComfyUI 视频工作流\n请在设置中选择一个工作流');
      }
      
      final workflowsJson = prefs.getString('comfyui_workflows');
      if (workflowsJson == null) {
        throw Exception('未找到工作流数据\n请在设置中重新读取工作流');
      }
      
      final workflows = List<Map<String, dynamic>>.from(
        (jsonDecode(workflowsJson) as List).map((w) => Map<String, dynamic>.from(w as Map))
      );
      
      final workflow = workflows.firstWhere(
        (w) => w['id'] == selectedWorkflowId,
        orElse: () => throw Exception('工作流未找到: $selectedWorkflowId'),
      );
      
      debugPrint('   使用工作流: ${workflow['name'] ?? selectedWorkflowId}');
      
      // 2. 克隆工作流
      final workflowData = Map<String, dynamic>.from(workflow['workflow'] as Map);
      
      // 3. 设置图片比例和尺寸
      // ✅ 优先从直接参数读取，如果没有则从 parameters 中读取
      final finalRatio = ratio ?? parameters?['size'];
      final finalQuality = quality ?? parameters?['quality'];
      
      if (finalRatio != null || finalQuality != null) {
        _setImageSizeInWorkflow(workflowData, finalRatio, finalQuality);
      } else {
        debugPrint('⚠️ 未提供比例参数，使用工作流默认尺寸\n');
      }
      
      // 4. 替换提示词
      _replacePromptInWorkflow(workflowData, prompt);
      
      // 5. 随机 seed
      _randomizeSeedInWorkflow(workflowData);
      
      // 6. 处理参考图片
      if (referenceImages != null && referenceImages.isNotEmpty) {
        // 有参考图片：上传并设置
        await _uploadAndSetReferenceImages(workflowData, referenceImages);
      } else {
        // ✅ 没有参考图片：清空所有 LoadImage 节点（避免使用工作流原始图片）
        _clearAllLoadImageNodes(workflowData);
      }
      
      debugPrint('   工作流节点数: ${workflowData.length}');
      
      // 6. 提交工作流
      final promptId = await _submitWorkflow(workflowData);
      debugPrint('   任务ID: $promptId');
      
      // 7. 轮询等待完成（视频生成较慢，最多等待 5 分钟）
      final outputVideos = await _waitForVideoCompletion(promptId);
      
      // 8. 构建视频 URL
      final videoUrls = outputVideos.map((vid) {
        final filename = vid['filename'];
        return '${config.baseUrl}view?filename=$filename&type=output';
      }).toList();
      
      debugPrint('   生成视频: ${videoUrls.length} 个');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      final videos = videoUrls.map((url) => VideoResponse(
        videoUrl: url,
        videoId: null,
        duration: null,
        metadata: {},
      )).toList();
      
      return ApiResponse.success(videos, statusCode: 200);
    } catch (e) {
      debugPrint('❌ ComfyUI 视频生成失败: $e');
      return ApiResponse.failure('生成失败: $e');
    }
  }
  
  /// 等待视频任务完成（更长超时时间）
  Future<List<Map<String, dynamic>>> _waitForVideoCompletion(String promptId) async {
    debugPrint('   ⏳ 等待视频生成完成（包括排队时间）...');
    
    // ✅ 增加到120分钟，支持超大批量生成（最多40-50个视频）
    for (var i = 0; i < 7200; i++) {  // 120分钟 = 7200秒
      await Future.delayed(const Duration(seconds: 1));
      
      try {
        final response = await http.get(
          Uri.parse('${config.baseUrl}history/$promptId'),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data[promptId] != null) {
            final history = data[promptId] as Map<String, dynamic>;
            
            // ✅ 检查任务状态（是否失败）
            final status = history['status'] as Map<String, dynamic>?;
            if (status != null) {
              final completed = status['completed'] as bool? ?? false;
              final statusMessages = status['messages'] as List?;
              
              // 检查是否有错误消息
              if (statusMessages != null && statusMessages.isNotEmpty) {
                final errorMessages = statusMessages
                    .where((msg) => msg is List && msg.length >= 2 && msg[0] == 'error')
                    .map((msg) => msg[1].toString())
                    .toList();
                
                if (errorMessages.isNotEmpty) {
                  final errorDetail = errorMessages.join('\n');
                  debugPrint('   ❌ ComfyUI 任务失败: $errorDetail');
                  throw Exception('ComfyUI 工作流执行失败\n\n错误详情:\n$errorDetail\n\n💡 建议：\n1. 检查工作流是否包含视频生成节点（如 VHS_VideoCombine）\n2. 检查ComfyUI控制台是否有详细错误日志\n3. 确认所有必需的自定义节点已安装');
                }
              }
              
              if (completed) {
                debugPrint('   ℹ️ 任务已完成，但未找到视频输出');
              }
            }
            
            final outputs = history['outputs'] as Map<String, dynamic>?;
            
            if (outputs != null) {
              // 查找视频输出节点（VHS_VideoCombine 或其他）
              for (final entry in outputs.entries) {
                final output = entry.value;
                if (output is Map && output['gifs'] != null) {
                  debugPrint('   ✅ 视频生成完成！（节点: ${entry.key}）');
                  return List<Map<String, dynamic>>.from(
                    (output['gifs'] as List).map((vid) => Map<String, dynamic>.from(vid as Map))
                  );
                }
              }
              
              // ✅ 如果有outputs但没有gifs，打印详细信息
              if (outputs.isNotEmpty) {
                debugPrint('   ⚠️ 找到outputs但没有视频数据');
                debugPrint('   📋 输出节点类型: ${outputs.keys.join(", ")}');
                for (final entry in outputs.entries) {
                  if (entry.value is Map) {
                    final keys = (entry.value as Map).keys.join(", ");
                    debugPrint('   📋 节点 ${entry.key} 的输出字段: $keys');
                  }
                }
              }
            }
          }
        } else {
          debugPrint('   ⚠️ HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('ComfyUI 工作流执行失败')) {
          rethrow;  // 重新抛出工作流错误
        }
        debugPrint('   ⚠️ 查询状态失败: $e');
      }
      
      // ✅ 改进日志输出频率（减少刷屏）
      if (i == 0 || i == 30 || i == 60 || (i > 60 && i % 60 == 0)) {
        final minutes = (i / 60).floor();
        final seconds = i % 60;
        if (minutes > 0) {
          debugPrint('   ⏳ 已等待 $minutes 分 $seconds 秒...');
        } else {
          debugPrint('   ⏳ 已等待 $seconds 秒...');
        }
      }
    }
    
    throw Exception('视频生成超时（120分钟）\n\n可能原因：\n1. ComfyUI 队列中有大量任务\n2. 视频生成非常缓慢\n3. 工作流执行失败但未报错\n\n💡 建议：\n1. 检查 ComfyUI 控制台日志\n2. 查看 ComfyUI 队列中的任务数量\n3. 如果超过120分钟，建议分批生成\n4. 确认工作流包含 VHS_VideoCombine 等视频生成节点');
  }

  @override
  Future<ApiResponse<LlmResponse>> generateText({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    return ApiResponse.failure('ComfyUI 不支持文本生成');
  }

  @override
  Future<ApiResponse<LlmResponse>> generateTextWithMessages({
    required List<Map<String, String>> messages,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    return ApiResponse.failure('ComfyUI 不支持文本生成');
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    return ApiResponse.failure('ComfyUI 不支持文件上传（使用工作流内置上传）');
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    try {
      // ComfyUI 没有模型列表 API，返回固定列表
      return ApiResponse.success(['comfyui_workflow'], statusCode: 200);
    } catch (e) {
      return ApiResponse.failure('获取模型列表失败: $e');
    }
  }
}
