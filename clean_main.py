# -*- coding: utf-8 -*-
# 清理 main.dart 中的 SSL 覆盖代码

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 找到需要删除的行
new_lines = []
skip_until_line = -1
in_override_class = False

for i, line in enumerate(lines):
    line_num = i + 1
    
    # 跳过 HttpOverrides.global 挂载及其注释
    if '核心修复：全局忽略 SSL 证书错误' in line:
        skip_until_line = i + 2  # 跳过注释和下一行
        continue
    
    if i < skip_until_line:
        continue
    
    # 检测 MyHttpOverrides 类的开始
    if 'class MyHttpOverrides extends HttpOverrides' in line:
        in_override_class = True
        # 也跳过前面的注释行
        if new_lines and '全局 HTTP 覆盖类' in new_lines[-1]:
            new_lines.pop()
        if new_lines and new_lines[-1].strip() == '':
            new_lines.pop()
        continue
    
    # 在类内部，跳过所有内容直到类结束
    if in_override_class:
        if line.strip() == '}' and not line.strip().startswith('..'):
            in_override_class = False
        continue
    
    new_lines.append(line)

# 写回文件
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(f'✅ 清理完成！')
print(f'原始行数: {len(lines)}')
print(f'清理后行数: {len(new_lines)}')
print(f'删除了 {len(lines) - len(new_lines)} 行')
