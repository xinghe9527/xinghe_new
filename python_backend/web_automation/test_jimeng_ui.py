#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
测试即梦 UI 自动化基本流程

验证：
1. 浏览器启动
2. 页面导航
3. 登录检查
4. 模型选择
5. 提示词输入
6. 生成按钮点击
"""
import sys, os, io, json, time

if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    except: pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from auto_jimeng import JimengAutomation

profile = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.dirname(SCRIPT_DIR)), 'python_backend', 'user_data', 'jimeng_profile'
)

print(f"\n{'='*60}")
print(f"  🧪 即梦 UI 自动化测试")
print(f"{'='*60}")
print(f"Profile: {profile}")

auto = JimengAutomation(profile_dir=profile)

print(f"\n--- 测试1: 启动浏览器 ---")
if not auto.start():
    print("❌ 启动失败")
    sys.exit(1)
print("✅ 启动成功")

try:
    print(f"\n--- 测试2: 检查登录 ---")
    logged_in = auto.check_login()
    print(f"结果: {'✅ 已登录' if logged_in else '❌ 未登录'}")
    
    if not logged_in:
        print("请先登录即梦")
        print("浏览器保持打开，按 Ctrl+C 退出...")
        try:
            while True:
                auto.page.wait_for_timeout(1000)
        except KeyboardInterrupt:
            pass
        sys.exit(0)
    
    print(f"\n--- 测试3: 选择模型 ---")
    auto.select_model('seedance-2.0-fast')
    
    print(f"\n--- 测试4: 设置宽高比 ---")
    auto.set_aspect_ratio('16:9')
    
    print(f"\n--- 测试5: 设置时长 ---")
    auto.set_duration(5)
    
    print(f"\n--- 测试6: 输入提示词 ---")
    auto.input_prompt('测试提示词：一只可爱的小猫在草地上奔跑')
    
    print(f"\n--- 测试7: 截图确认 ---")
    screenshot_path = os.path.join(SCRIPT_DIR, 'jimeng_test_screenshot.png')
    auto.page.screenshot(path=screenshot_path)
    print(f"截图已保存: {screenshot_path}")
    
    print(f"\n{'='*60}")
    print(f"  ✅ 基本流程测试完成（未点击生成）")
    print(f"{'='*60}")
    
    # 不点击生成，只验证 UI 操作
    print("\n按 Ctrl+C 退出...")
    try:
        while True:
            auto.page.wait_for_timeout(1000)
    except KeyboardInterrupt:
        pass

finally:
    auto.stop()
