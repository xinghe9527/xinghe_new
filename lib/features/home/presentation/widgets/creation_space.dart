import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class CreationSpace extends StatelessWidget {
  const CreationSpace({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '创作空间',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '释放你的创意，开启 AI 创作之旅',
            style: TextStyle(
              color: AppColors.text.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _buildCreationCard(
                  '文本创作',
                  'AI 辅助写作、翻译与润色',
                  Icons.edit_note,
                  AppColors.activeBlue,
                ),
                _buildCreationCard(
                  '图像生成',
                  '从文字描述生成精美图像',
                  Icons.image_search,
                  const Color(0xFFE91E63),
                ),
                _buildCreationCard(
                  '代码助手',
                  '快速生成与重构代码片段',
                  Icons.code,
                  const Color(0xFF4CAF50),
                ),
                _buildCreationCard(
                  '视频脚本',
                  '自动生成短视频创意脚本',
                  Icons.movie_filter,
                  const Color(0xFFFF9800),
                ),
                _buildCreationCard(
                  '语音合成',
                  '高保真 AI 语音克隆与转换',
                  Icons.record_voice_over,
                  const Color(0xFF9C27B0),
                ),
                _buildCreationCard(
                  '智能翻译',
                  '多语种即时上下文理解翻译',
                  Icons.translate,
                  const Color(0xFF00BCD4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreationCard(String title, String desc, IconData icon, Color color) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.secondary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
