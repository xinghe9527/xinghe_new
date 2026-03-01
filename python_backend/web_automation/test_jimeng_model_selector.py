#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""测试即梦模型选择器 - 使用 auto_jimeng 的实际方法"""
import sys, os, io, time

if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    except: pass

# 添加脚本目录到 path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from auto_jimeng import JimengAutomation

print("=" * 60)
print("  即梦模型选择器测试")
print("=" * 60)

auto = JimengAutomation()

print("\n--- 启动浏览器 ---")
if not auto.start():
    print("❌ 启动失败")
    sys.exit(1)
print("✅ 启动成功")

print("\n--- 检查登录 ---")
logged_in = auto.check_login()
print(f"结果: {'✅ 已登录' if logged_in else '❌ 未登录'}")

# 测试选择不同模型
test_models = [
    'seedance-2.0-fast',
    'seedance-2.0',
    'jimeng-video-3.0-fast',
]

for model in test_models:
    print(f"\n--- 测试选择模型: {model} ---")
    result = auto.select_model(model)
    print(f"结果: {'✅' if result else '❌'}")
    time.sleep(2)

# 测试设置参数
print(f"\n--- 测试设置宽高比: 16:9 ---")
auto.set_aspect_ratio('16:9')

print(f"\n--- 测试设置时长: 5s ---")
auto.set_duration(5)

# 截图
screenshot_path = os.path.join(SCRIPT_DIR, 'jimeng_model_test.png')
auto.page.screenshot(path=screenshot_path)
print(f"\n📸 截图: {screenshot_path}")

print("\n" + "=" * 60)
print("  测试完成，按 Ctrl+C 退出")
print("=" * 60)

try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    pass

auto.stop()
