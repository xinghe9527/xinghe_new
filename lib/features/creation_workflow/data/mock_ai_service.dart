import 'dart:math';
import '../domain/models/script_line.dart';
import '../domain/models/entity.dart';

/// Mock AI 服务（用于测试UI流程）
class MockAIService {
  final Random _random = Random();

  /// 生成中文剧本
  Future<List<ScriptLine>> generateScript({required String theme}) async {
    // 模拟网络延迟
    await Future.delayed(const Duration(seconds: 2));

    return [
      ScriptLine(
        id: _generateId(),
        content: '黎明时分，紫色的天空下，一座未来都市的轮廓渐渐清晰。',
        type: ScriptLineType.action,
        aiPrompt: '紫色黎明，未来都市剪影，赛博朋克风格',
        contextTags: ['开场', '都市', '黎明'],
      ),
      ScriptLine(
        id: _generateId(),
        content: '主角：「又是新的一天，今天会发生什么呢？」',
        type: ScriptLineType.dialogue,
        aiPrompt: '年轻主角站在高楼阳台，眺望城市',
        contextTags: ['主角', '独白', '思考'],
      ),
      ScriptLine(
        id: _generateId(),
        content: '突然，天空中闪过一道刺眼的蓝光，整个城市的全息屏幕同时黑屏。',
        type: ScriptLineType.action,
        aiPrompt: '蓝色闪光穿过天空，城市全息屏幕黑屏，动态效果',
        contextTags: ['异常事件', '光效', '科技故障'],
      ),
      ScriptLine(
        id: _generateId(),
        content: '主角：「这是...系统崩溃？还是有人在搞破坏？」',
        type: ScriptLineType.dialogue,
        aiPrompt: '主角震惊表情，手持通讯设备',
        contextTags: ['主角', '疑惑', '紧张'],
      ),
      ScriptLine(
        id: _generateId(),
        content: '远处传来警报声，无数飞行器从城市中心升起。',
        type: ScriptLineType.action,
        aiPrompt: '未来警用飞行器群起飞，红色警报灯闪烁，广角镜头',
        contextTags: ['紧急响应', '飞行器', '混乱'],
      ),
    ];
  }

  /// 扩写剧本（在指定位置插入新内容）
  Future<ScriptLine> expandScript({
    required String previousContext,
    required String nextContext,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1500));

    return ScriptLine(
      id: _generateId(),
      content: '主角快速穿上外套，冲向门口，决定去一探究竟。',
      type: ScriptLineType.action,
      aiPrompt: '主角穿衣动作，快速移动，紧张氛围',
      contextTags: ['主角', '行动', '过渡'],
    );
  }

  /// 从剧本提取实体
  Future<List<Entity>> extractEntities({
    required List<ScriptLine> scriptLines,
  }) async {
    await Future.delayed(const Duration(milliseconds: 2000));

    return [
      Entity(
        id: _generateId(),
        type: EntityType.character,
        name: '主角',
        fixedPrompt: '20岁左右的年轻人，银白短发，蓝色眼睛，穿着黑色机能风外套，赛博朋克风格',
        isLocked: false,
      ),
      Entity(
        id: _generateId(),
        type: EntityType.scene,
        name: '未来都市',
        fixedPrompt: '赛博朋克风格的现代化大都市，高楼林立，全息广告牌，紫蓝色调',
        isLocked: false,
      ),
      Entity(
        id: _generateId(),
        type: EntityType.scene,
        name: '主角公寓',
        fixedPrompt: '高层公寓内部，简约科技风，大落地窗，俯瞰城市',
        isLocked: false,
      ),
    ];
  }

  /// 生成分镜图片（返回模拟的图片URL）
  Future<String> generateStoryboardImage({
    required String prompt,
  }) async {
    await Future.delayed(const Duration(seconds: 3));

    // 返回模拟的图片URL（实际使用时替换为真实API）
    final imageIndex = _random.nextInt(10) + 1;
    return 'https://picsum.photos/seed/$imageIndex/800/450';
  }

  /// 生成视频片段（返回模拟的视频URL）
  Future<String> generateVideoClip({
    required String prompt,
    String? imageUrl,
    String? startFrameUrl,
    String? endFrameUrl,
  }) async {
    await Future.delayed(const Duration(seconds: 5));

    // 返回模拟的视频URL
    return 'https://example.com/video_${_generateId()}.mp4';
  }

  /// 拼接最终提示词
  String buildFinalPrompt({
    required String sceneDescription,
    required List<Entity> involvedEntities,
    required String scriptContent,
  }) {
    final parts = <String>[];

    // 场景描述
    parts.add('场景：$sceneDescription');

    // 角色固定描述
    for (final entity in involvedEntities) {
      if (entity.type == EntityType.character && entity.isLocked) {
        parts.add('${entity.name}：${entity.fixedPrompt}');
      }
    }

    // 当前剧本意图
    parts.add('动作：$scriptContent');

    return parts.join('，');
  }

  /// 生成唯一ID
  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        _random.nextInt(1000).toString();
  }
}
