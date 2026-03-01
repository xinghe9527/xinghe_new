#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
简化测试脚本 - 诊断 auto_vidu_complete.py 为什么没有输出
"""

import sys
import os

print("="*60)
print("  测试脚本启动")
print("="*60)

print(f"\nPython 版本: {sys.version}")
print(f"当前目录: {os.getcwd()}")
print(f"脚本目录: {os.path.dirname(os.path.abspath(__file__))}")

print("\n检查依赖...")

try:
    from playwright.sync_api import sync_playwright
    print("✅ playwright 已安装")
except ImportError as e:
    print(f"❌ playwright 未安装: {e}")
    sys.exit(1)

try:
    import requests
    print("✅ requests 已安装")
except ImportError as e:
    print(f"❌ requests 未安装: {e}")
    sys.exit(1)

print("\n尝试导入 auto_vidu_complete.py...")

try:
    # 添加当前目录到路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, script_dir)
    
    # 尝试读取文件
    auto_vidu_path = os.path.join(script_dir, 'auto_vidu_complete.py')
    print(f"文件路径: {auto_vidu_path}")
    print(f"文件存在: {os.path.exists(auto_vidu_path)}")
    
    if os.path.exists(auto_vidu_path):
        with open(auto_vidu_path, 'r', encoding='utf-8') as f:
            content = f.read()
            print(f"文件大小: {len(content)} 字节")
            print(f"文件行数: {len(content.splitlines())} 行")
    
    print("\n✅ 所有检查通过")
    print("\n现在尝试运行 auto_vidu_complete.py...")
    
except Exception as e:
    print(f"\n❌ 错误: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n" + "="*60)
print("  测试完成")
print("="*60)
