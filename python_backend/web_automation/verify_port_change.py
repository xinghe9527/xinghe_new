#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
端口修改验证脚本
检查所有文件中的端口配置是否已正确更新为 8123

用法：
    python python_backend/web_automation/verify_port_change.py
"""

import os
import re

# 需要检查的文件
FILES_TO_CHECK = [
    'api_server.py',
    'test_api.py',
]

# 当前脚本所在目录
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def check_file(filename):
    """检查文件中的端口配置"""
    filepath = os.path.join(SCRIPT_DIR, filename)
    
    if not os.path.exists(filepath):
        print(f"❌ 文件不存在: {filename}")
        return False
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 查找所有端口引用
    port_8000_matches = re.findall(r'(?:port[=\s]+|:)8000\b', content)
    port_8123_matches = re.findall(r'(?:port[=\s]+|:)8123\b', content)
    
    print(f"\n📄 检查文件: {filename}")
    print(f"   8000 端口引用: {len(port_8000_matches)} 处")
    print(f"   8123 端口引用: {len(port_8123_matches)} 处")
    
    if port_8000_matches:
        print(f"   ⚠️  发现旧端口 8000 的引用:")
        # 显示上下文
        lines = content.split('\n')
        for i, line in enumerate(lines, 1):
            if re.search(r'(?:port[=\s]+|:)8000\b', line):
                print(f"      第 {i} 行: {line.strip()}")
        return False
    
    if port_8123_matches:
        print(f"   ✅ 端口已正确更新为 8123")
        return True
    else:
        print(f"   ⚠️  未找到端口配置")
        return False

def main():
    """主函数"""
    print("="*60)
    print("  🔍 端口修改验证")
    print("="*60)
    
    all_ok = True
    
    for filename in FILES_TO_CHECK:
        if not check_file(filename):
            all_ok = False
    
    print("\n" + "="*60)
    if all_ok:
        print("  ✅ 所有文件的端口配置已正确更新为 8123")
        print("  🚀 可以启动服务器了！")
    else:
        print("  ❌ 发现问题，请检查上述文件")
    print("="*60 + "\n")
    
    return 0 if all_ok else 1

if __name__ == "__main__":
    exit(main())
