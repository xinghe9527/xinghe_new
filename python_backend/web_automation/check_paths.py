#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
路径诊断脚本 - 检查所有路径是否正确
"""

import sys
import json
import io
import os

# 确保标准输出使用 UTF-8 编码
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 获取路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
USER_DATA_ROOT = os.path.join(PROJECT_ROOT, 'python_backend', 'user_data')
VIDU_PROFILE = os.path.join(USER_DATA_ROOT, 'vidu_profile')

print("="*60)
print("  路径诊断报告")
print("="*60)
print()

print("📂 脚本目录:")
print(f"   {SCRIPT_DIR}")
print(f"   存在: {os.path.exists(SCRIPT_DIR)}")
print()

print("📂 项目根目录:")
print(f"   {PROJECT_ROOT}")
print(f"   存在: {os.path.exists(PROJECT_ROOT)}")
print()

print("📂 用户数据根目录:")
print(f"   {USER_DATA_ROOT}")
print(f"   存在: {os.path.exists(USER_DATA_ROOT)}")
print()

print("📂 Vidu Profile 目录:")
print(f"   {VIDU_PROFILE}")
print(f"   存在: {os.path.exists(VIDU_PROFILE)}")

if os.path.exists(VIDU_PROFILE):
    files = os.listdir(VIDU_PROFILE)
    print(f"   文件数量: {len(files)}")
    if len(files) > 0:
        print(f"   示例文件: {files[:5]}")
else:
    print("   ⚠️  目录不存在！请先运行 init_login.py vidu")

print()
print("="*60)

# 输出 JSON
result = {
    "script_dir": SCRIPT_DIR,
    "project_root": PROJECT_ROOT,
    "user_data_root": USER_DATA_ROOT,
    "vidu_profile": VIDU_PROFILE,
    "vidu_profile_exists": os.path.exists(VIDU_PROFILE),
    "vidu_profile_file_count": len(os.listdir(VIDU_PROFILE)) if os.path.exists(VIDU_PROFILE) else 0
}

print("\nJSON 输出:")
print(json.dumps(result, ensure_ascii=False, indent=2))
