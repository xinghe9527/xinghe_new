# -*- coding: utf-8 -*-
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()
    lines = content.split('\n')

print('✅ 生产环境清理验证:')
print(f'包含 dart:io: {"dart:io" in content}')
print(f'包含 HttpOverrides: {"HttpOverrides" in content}')
print(f'包含 MyHttpOverrides: {"MyHttpOverrides" in content}')
print(f'包含 badCertificateCallback: {"badCertificateCallback" in content}')
print(f'\n总行数: {len(lines)}')
print(f'\n前8行:')
for i in range(min(8, len(lines))):
    print(f'{i+1}: {lines[i]}')
