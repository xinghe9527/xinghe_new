#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""分析即梦视频生成页面的 UI 结构"""
import sys, os, io, json, time

if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    except: pass

from playwright.sync_api import sync_playwright

profile = sys.argv[1] if len(sys.argv) > 1 else 'jimeng_web_video_plugin_seedance_2_0/.jimeng_cdp_profile'

pw = sync_playwright().start()

# 先尝试用 headless 模式，避免 profile 锁冲突
try:
    ctx = pw.chromium.launch_persistent_context(
        user_data_dir=profile,
        headless=True,
        args=['--disable-gpu', '--no-sandbox', '--disable-blink-features=AutomationControlled'],
    )
except Exception as e:
    print(f"persistent context 失败: {e}")
    print("使用临时 context...")
    browser = pw.chromium.launch(headless=False, args=['--disable-gpu', '--no-sandbox'])
    ctx = browser.new_context(viewport={'width': 1920, 'height': 1080})

page = ctx.new_page()
print("正在访问即梦视频生成页面...")
page.goto('https://jimeng.jianying.com/ai-tool/home?type=video', wait_until='networkidle', timeout=30000)
time.sleep(3)

# 1. 查找底部模式切换栏
print("\n" + "=" * 60)
print("  1. 底部模式切换栏")
print("=" * 60)
# 查找包含"视频生成"文字的元素
video_btns = page.query_selector_all('text=视频生成')
print(f"   '视频生成' 文字元素: {len(video_btns)} 个")
for i, btn in enumerate(video_btns):
    tag = btn.evaluate('el => el.tagName')
    cls = btn.evaluate('el => el.className')
    parent_tag = btn.evaluate('el => el.parentElement?.tagName')
    parent_cls = btn.evaluate('el => el.parentElement?.className')
    print(f"   [{i}] <{tag} class='{cls[:80]}'> parent=<{parent_tag} class='{parent_cls[:80]}'>")

# 2. 查找提示词输入框
print("\n" + "=" * 60)
print("  2. 提示词输入框")
print("=" * 60)
textareas = page.query_selector_all('textarea')
print(f"   textarea 元素: {len(textareas)} 个")
for i, ta in enumerate(textareas):
    placeholder = ta.get_attribute('placeholder') or ''
    cls = ta.evaluate('el => el.className')
    print(f"   [{i}] placeholder='{placeholder[:60]}' class='{cls[:80]}'")

# contenteditable
editables = page.query_selector_all('[contenteditable="true"]')
print(f"   contenteditable 元素: {len(editables)} 个")
for i, ed in enumerate(editables):
    tag = ed.evaluate('el => el.tagName')
    cls = ed.evaluate('el => el.className')
    text = ed.inner_text()[:50]
    print(f"   [{i}] <{tag} class='{cls[:80]}'> text='{text}'")

# 3. 查找生成按钮
print("\n" + "=" * 60)
print("  3. 生成按钮")
print("=" * 60)
gen_btns = page.query_selector_all('button')
print(f"   button 元素: {len(gen_btns)} 个")
for i, btn in enumerate(gen_btns):
    text = btn.inner_text().strip()[:40]
    cls = btn.evaluate('el => el.className')[:60]
    disabled = btn.get_attribute('disabled')
    if text:
        print(f"   [{i}] text='{text}' disabled={disabled} class='{cls}'")

# 也找包含"生成"文字的元素
gen_texts = page.query_selector_all('text=生成')
print(f"\n   包含'生成'文字的元素: {len(gen_texts)} 个")
for i, el in enumerate(gen_texts):
    tag = el.evaluate('el => el.tagName')
    text = el.inner_text().strip()[:40]
    cls = el.evaluate('el => el.className')[:60]
    print(f"   [{i}] <{tag}> text='{text}' class='{cls}'")

# 4. 查找文件上传 input
print("\n" + "=" * 60)
print("  4. 文件上传 input")
print("=" * 60)
file_inputs = page.query_selector_all('input[type="file"]')
print(f"   input[type=file] 元素: {len(file_inputs)} 个")
for i, fi in enumerate(file_inputs):
    accept = fi.get_attribute('accept') or ''
    multiple = fi.get_attribute('multiple')
    cls = fi.evaluate('el => el.className')
    parent_cls = fi.evaluate('el => el.parentElement?.className || ""')[:60]
    print(f"   [{i}] accept='{accept}' multiple={multiple} parent_class='{parent_cls}'")

# 5. 查找模型选择器
print("\n" + "=" * 60)
print("  5. 模型选择相关")
print("=" * 60)
seedance = page.query_selector_all('text=Seedance')
print(f"   'Seedance' 文字元素: {len(seedance)} 个")
for i, el in enumerate(seedance):
    text = el.inner_text().strip()[:60]
    tag = el.evaluate('el => el.tagName')
    print(f"   [{i}] <{tag}> '{text}'")

# 6. 查找宽高比/时长选择器
print("\n" + "=" * 60)
print("  6. 宽高比/时长选择")
print("=" * 60)
for keyword in ['16:9', '9:16', '1:1', '5s', '10s', '720p', '1080p']:
    els = page.query_selector_all(f'text="{keyword}"')
    if els:
        print(f"   '{keyword}': {len(els)} 个元素")

# 7. 查找角色/主体库相关
print("\n" + "=" * 60)
print("  7. 角色/主体库")
print("=" * 60)
for keyword in ['角色', '主体', '资产', 'character']:
    els = page.query_selector_all(f'text={keyword}')
    if els:
        print(f"   '{keyword}': {len(els)} 个元素")
        for i, el in enumerate(els[:3]):
            text = el.inner_text().strip()[:60]
            print(f"      [{i}] '{text}'")

# 8. 页面 URL
print(f"\n当前 URL: {page.url}")

print("\n分析完成")

ctx.close()
pw.stop()
