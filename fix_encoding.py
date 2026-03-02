# -*- coding: utf-8 -*-
import sys

# 读取文件
with open('lib/pages/ai_canvas/ai_canvas_page.dart', 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# 检查问题行
lines = content.split('\n')
print(f"总行数: {len(lines)}")
print("\n检查问题行:")
problem_lines = [291, 516, 554, 729, 739, 771, 797]
for line_num in problem_lines:
    if line_num < len(lines):
        line = lines[line_num]
        print(f"\n第 {line_num + 1} 行:")
        print(repr(line))
        # 检查是否有替换字符
        if '�' in line or '\ufffd' in line:
            print("  ⚠️ 发现乱码字符")
