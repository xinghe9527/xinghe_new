import 'package:flutter/material.dart';
import 'canvas_agent_service.dart';

/// Agent 聊天面板 — 嵌入画布右侧的设计助手对话界面
class AgentChatPanel extends StatefulWidget {
  final Function(DesignPlan plan) onPlanReady;
  final Future<String> Function(AgentActionBundle bundle) onActionBundleReady;
  final void Function(AgentActionBundle bundle)? onActionBundlePreview;
  final String? currentImageProvider;
  final String? currentImageModel;
  final String? currentVideoProvider;
  final String? currentVideoModel;
  final String? canvasContextSummary;
  final VoidCallback onClose;

  const AgentChatPanel({
    super.key,
    required this.onPlanReady,
    required this.onActionBundleReady,
    this.onActionBundlePreview,
    required this.onClose,
    this.currentImageProvider,
    this.currentImageModel,
    this.currentVideoProvider,
    this.currentVideoModel,
    this.canvasContextSummary,
  });

  @override
  State<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends State<AgentChatPanel> {
  final CanvasAgentService _agentService = CanvasAgentService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AgentMessage> _messages = [];
  bool _isLoading = false;

  // 配色
  static const Color _panelBg = Color(0xFFF8FBFF);
  static const Color _panelSurface = Color(0xFFEEF4FF);
  static const Color _panelSurfaceSoft = Color(0xFFFFFFFF);
  static const Color _userBubble = Color(0xFF2563EB);
  static const Color _assistantBubble = Color(0xFFFFFFFF);
  static const Color _borderColor = Color(0xFFD9E5F5);
  static const Color _accentBlue = Color(0xFF3B82F6);
  static const Color _accentCyan = Color(0xFF2AFADF);

  // Skills 模板
  static const List<_SkillTemplate> _skills = [
    _SkillTemplate(
      '社媒轮播图',
      Icons.view_carousel_outlined,
      '帮我设计一组社交媒体轮播图，主题自由发挥，包含封面和3-4页内容',
    ),
    _SkillTemplate(
      '社交媒体',
      Icons.phone_android_outlined,
      '帮我设计一张社交媒体宣传图，适合 Instagram/小红书 的竖版比例',
    ),
    _SkillTemplate(
      'Logo与品牌',
      Icons.palette_outlined,
      '帮我设计一套品牌视觉素材，包含 Logo 文字和品牌配色展示',
    ),
    _SkillTemplate(
      '分镜故事板',
      Icons.movie_creation_outlined,
      '帮我设计一组分镜故事板，4-6 个画面，用于短视频脚本可视化',
    ),
    _SkillTemplate(
      '营销宣传册',
      Icons.menu_book_outlined,
      '帮我设计一份产品营销宣传册，包含封面、卖点展示和产品细节',
    ),
    _SkillTemplate(
      '产品套图',
      Icons.inventory_2_outlined,
      '帮我设计一组电商产品展示套图，包含主图、细节图和场景图',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 添加欢迎消息
    _messages.add(
      AgentMessage(
        role: 'assistant',
        content:
            '你好！我是 AI 设计助手。\n\n你可以和我聊天讨论设计想法，也可以直接让我在画布里生成图片、视频和文本。\n\n试试：\n• "帮我在右侧补一张室内氛围图"\n• "把这个画面的标题改得更高级一点"\n• "你觉得科技产品海报用什么配色好"',
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _inputController.clear();

    setState(() {
      _messages.add(AgentMessage(role: 'user', content: text));
      _isLoading = true;
    });

    _scrollToBottom();

    // 调用 Agent 服务
    final response = await _agentService.chat(
      _messages,
      text,
      imageProvider: widget.currentImageProvider,
      imageModel: widget.currentImageModel,
      videoProvider: widget.currentVideoProvider,
      videoModel: widget.currentVideoModel,
      canvasContext: widget.canvasContextSummary,
    );

    setState(() {
      _messages.add(response);
      _isLoading = false;
    });

    if (response.actionBundle != null) {
      widget.onActionBundlePreview?.call(response.actionBundle!);
    }

    _scrollToBottom();

    if (response.actionBundle != null &&
        response.actionBundle!.hasExecutableActions &&
        !response.actionBundle!.requiresConfirmation) {
      await _applyActionsForMessage(response);
    }
  }

  Future<void> _applyActionsForMessage(AgentMessage message) async {
    final bundle = message.actionBundle;
    if (bundle == null || !bundle.hasExecutableActions) return;

    final index = _messages.indexOf(message);
    if (index == -1) return;

    setState(() {
      _messages[index] = _messages[index].copyWith(actionStatus: '正在应用到画布...');
    });

    try {
      final summary = await widget.onActionBundleReady(bundle);
      if (!mounted) return;
      setState(() {
        _messages[index] = _messages[index].copyWith(
          actionApplied: true,
          actionStatus: summary,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages[index] = _messages[index].copyWith(
          actionApplied: false,
          actionStatus: '执行失败：$e',
        );
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_panelBg, _panelSurface],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(left: BorderSide(color: _borderColor, width: 1)),
        boxShadow: [
          BoxShadow(
            color: _accentBlue.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(-8, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 顶栏
          _buildHeader(),
          // 消息列表
          Expanded(child: _buildMessageList()),
          // 输入区域
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: _borderColor, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_accentCyan, _accentBlue],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _accentBlue.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 设计助手',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '帮你排版、拆解画面、讨论创意',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const Spacer(),
          // 清空对话按钮
          _HeaderButton(
            icon: Icons.delete_outline,
            tooltip: '清空对话',
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add(
                  AgentMessage(role: 'assistant', content: '对话已清空。告诉我你想设计什么吧！'),
                );
              });
            },
          ),
          const SizedBox(width: 4),
          // 关闭按钮
          _HeaderButton(
            icon: Icons.close,
            tooltip: '关闭',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final showSkills =
        _messages.length == 1 &&
        _messages.first.role == 'assistant' &&
        !_isLoading;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (showSkills ? 1 : 0) + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _messages.length) {
          return _buildMessageBubble(_messages[index]);
        }
        if (showSkills && index == _messages.length) {
          return _buildSkillsSection();
        }
        return _buildLoadingBubble();
      },
    );
  }

  void _onSkillTap(_SkillTemplate skill) {
    _inputController.text = skill.prompt;
    _sendMessage();
  }

  Widget _buildSkillsSection() {
    return Padding(
      padding: const EdgeInsets.only(left: 36, top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              '试试这些 Skills',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _skills.map((s) => _buildSkillChip(s)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillChip(_SkillTemplate skill) {
    return GestureDetector(
      onTap: () => _onSkillTap(skill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _borderColor),
          boxShadow: [
            BoxShadow(
              color: _accentBlue.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(skill.icon, size: 16, color: _accentBlue),
            const SizedBox(width: 6),
            Text(
              skill.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(AgentMessage message) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // 助手头像
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accentCyan, _accentBlue],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? _userBubble : _assistantBubble,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    boxShadow: isUser
                        ? [
                            BoxShadow(
                              color: _accentBlue.withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 13,
                      color: isUser ? Colors.white : const Color(0xFF334155),
                      height: 1.5,
                    ),
                  ),
                ),
                if (message.actionBundle != null &&
                    message.actionBundle!.actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildActionBundleCard(message),
                ] else if (message.plan != null) ...[
                  const SizedBox(height: 8),
                  _buildPlanActions(message.plan!),
                ],
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildPlanActions(DesignPlan plan) {
    final imageCount = plan.elements.where((e) => e.type == 'image').length;
    final videoCount = plan.elements.where((e) => e.type == 'video').length;
    final textCount = plan.elements.where((e) => e.type == 'text').length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentBlue.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: _accentBlue.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 方案统计
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (imageCount > 0)
                _buildTag(Icons.image_outlined, '$imageCount 张图片'),
              if (videoCount > 0)
                _buildTag(Icons.videocam_outlined, '$videoCount 个视频'),
              if (textCount > 0) _buildTag(Icons.text_fields, '$textCount 段文字'),
            ],
          ),
          if (plan.style.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '风格：${plan.style}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
          const SizedBox(height: 10),
          // 应用方案按钮
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accentCyan, _accentBlue],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _accentBlue.withValues(alpha: 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => widget.onPlanReady(plan),
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text(
                  '应用到画布',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBundleCard(AgentMessage message) {
    final bundle = message.actionBundle!;
    final generateImageCount = bundle.actions
        .where((a) => a.type == 'generate_image')
        .length;
    final generateVideoCount = bundle.actions
        .where((a) => a.type == 'generate_video')
        .length;
    final textCount = bundle.actions
        .where(
          (a) => a.type == 'create_text_node' || a.type == 'create_note_node',
        )
        .length;
    final editCount = bundle.actions
        .where((a) => a.type == 'update_node' || a.type == 'move_node')
        .length;
    final deleteCount = bundle.actions
        .where((a) => a.type == 'delete_node')
        .length;
    final suggestionCount = bundle.actions
        .where((a) => a.type == 'layout_suggestion' || a.type == 'suggestion')
        .length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentBlue.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: _accentBlue.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (generateImageCount > 0)
                _buildTag(Icons.image_outlined, '$generateImageCount 张图片'),
              if (generateVideoCount > 0)
                _buildTag(Icons.videocam_outlined, '$generateVideoCount 个视频'),
              if (textCount > 0) _buildTag(Icons.text_fields, '$textCount 个文本'),
              if (editCount > 0)
                _buildTag(Icons.open_with_rounded, '$editCount 个调整'),
              if (deleteCount > 0)
                _buildTag(Icons.delete_outline, '$deleteCount 个删除'),
              if (suggestionCount > 0)
                _buildTag(
                  Icons.tips_and_updates_outlined,
                  '$suggestionCount 条建议',
                ),
            ],
          ),
          if (message.actionStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              message.actionStatus!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
          if (bundle.meta.reason?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              '说明：${bundle.meta.reason}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
          if (bundle.hasExecutableActions) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: bundle.requiresConfirmation
                      ? null
                      : const LinearGradient(
                          colors: [_accentCyan, _accentBlue],
                        ),
                  color: bundle.requiresConfirmation
                      ? const Color(0xFF334155)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _accentBlue.withValues(alpha: 0.24),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _applyActionsForMessage(message),
                  icon: Icon(
                    message.actionApplied
                        ? Icons.refresh_rounded
                        : Icons.auto_fix_high,
                    size: 16,
                  ),
                  label: Text(
                    message.actionApplied
                        ? '再次执行'
                        : bundle.requiresConfirmation
                        ? '确认并应用'
                        : '应用到画布',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _accentBlue),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_accentCyan, _accentBlue],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _assistantBubble,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accentBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '思考中...',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        border: Border(top: BorderSide(color: _borderColor, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 100),
              decoration: BoxDecoration(
                color: _panelSurfaceSoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor),
                boxShadow: [
                  BoxShadow(
                    color: _accentBlue.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _inputController,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: '聊聊设计想法，或让我直接生成...',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 发送按钮
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: _isLoading
                  ? null
                  : const LinearGradient(colors: [_accentCyan, _accentBlue]),
              color: _isLoading ? const Color(0xFF475569) : null,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: (_isLoading ? Colors.black : _accentBlue).withValues(
                    alpha: _isLoading ? 0.12 : 0.28,
                  ),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: GestureDetector(
              onTap: _isLoading ? null : _sendMessage,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.arrow_upward, size: 20, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skills 模板数据
class _SkillTemplate {
  final String name;
  final IconData icon;
  final String prompt;
  const _SkillTemplate(this.name, this.icon, this.prompt);
}

/// 顶栏小按钮
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        ),
      ),
    );
  }
}
