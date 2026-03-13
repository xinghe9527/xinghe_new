import 'package:flutter/material.dart';
import 'canvas_agent_service.dart';

/// Agent 聊天面板 — 嵌入画布右侧的设计助手对话界面
class AgentChatPanel extends StatefulWidget {
  final Function(DesignPlan plan) onPlanReady;
  final String? currentImageModel;
  final String? currentVideoModel;
  final VoidCallback onClose;

  const AgentChatPanel({
    super.key,
    required this.onPlanReady,
    required this.onClose,
    this.currentImageModel,
    this.currentVideoModel,
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
  static const Color _panelBg = Color(0xFFF8F9FA);
  static const Color _userBubble = Color(0xFF3B82F6);
  static const Color _assistantBubble = Color(0xFFFFFFFF);
  static const Color _borderColor = Color(0xFFE5E7EB);
  static const Color _accentBlue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    // 添加欢迎消息
    _messages.add(
      AgentMessage(
        role: 'assistant',
        content:
            '你好！我是 AI 设计助手。\n\n告诉我你想设计什么，我会自动规划布局并生成设计方案。\n\n例如：\n• "设计一个运动鞋品牌的产品展示页"\n• "做一组咖啡店的宣传素材"\n• "制作一个科技产品发布海报"',
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
      imageModel: widget.currentImageModel,
      videoModel: widget.currentVideoModel,
    );

    setState(() {
      _messages.add(response);
      _isLoading = false;
    });

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
        color: _panelBg,
        border: Border(left: BorderSide(color: _borderColor, width: 1)),
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 20, color: _accentBlue),
          const SizedBox(width: 8),
          const Text(
            'AI 设计助手',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
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
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildLoadingBubble();
        }
        return _buildMessageBubble(_messages[index]);
      },
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
                color: _accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.auto_awesome, size: 16, color: _accentBlue),
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
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 13,
                      color: isUser ? Colors.white : const Color(0xFF374151),
                      height: 1.5,
                    ),
                  ),
                ),
                // 如果有设计方案，显示"应用方案"按钮
                if (message.plan != null) ...[
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
        color: _accentBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentBlue.withValues(alpha: 0.2)),
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
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 10),
          // 应用方案按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => widget.onPlanReady(plan),
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text(
                '应用到画布',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
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
            style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
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
              color: _accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.auto_awesome, size: 16, color: _accentBlue),
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
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
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
                  '正在分析设计需求...',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
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
        color: Colors.white,
        border: Border(top: BorderSide(color: _borderColor, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 100),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _inputController,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: '描述你想设计的内容...',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 发送按钮
          GestureDetector(
            onTap: _isLoading ? null : _sendMessage,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _isLoading ? Colors.grey[300] : _accentBlue,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.arrow_upward, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
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
          child: Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        ),
      ),
    );
  }
}
