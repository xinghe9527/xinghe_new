# -*- coding: utf-8 -*-
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 删除第一行的 dart:io 导入
if "import 'dart:io';" in lines[0]:
    lines.pop(0)
    print('✅ 已删除 dart:io 导入')
else:
    print('⚠️ 未找到 dart:io 导入')

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f'当前总行数: {len(lines)}')
