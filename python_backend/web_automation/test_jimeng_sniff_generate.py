#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
抓取即梦页面上真实的视频生成请求格式

方法：在页面上输入提示词并点击生成按钮，抓取发出的 API 请求
"""
import sys, os, io, json, time

if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    except: pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from playwright.sync_api import sync_playwright

profile = sys.argv[1] if len(sys.argv) > 1 else 'jimeng_web_video_plugin_seedance_2_0/.jimeng_cdp_profile'

print(f"Profile: {profile}")

pw = sync_playwright().start()

# 用有头模式，方便观察
ctx = pw.chromium.launch_persistent_context(
    user_data_dir=profile,
    headless=False,
    args=['--disable-gpu', '--no-sandbox', '--disable-blink-features=AutomationControlled'],
    viewport={'width': 1920, 'height': 1080},
)

page = ctx.new_page()

# 收集所有生成相关的请求
generate_requests = []

def on_request(request):
    url = request.url
    if any(kw in url for kw in ['generate', 'aigc_draft', 'aigc/draft', 'submit_task']):
        try:
            post_data = request.post_data
        except:
            post_data = None
        generate_requests.append({
            'type': 'REQUEST',
            'method': request.method,
            'url': url,
            'headers': dict(request.headers),
            'post_data': post_data,
        })
        print(f"\n🔴 捕获生成请求:")
        print(f"   [{request.method}] {url}")
        if post_data:
            print(f"   Body: {post_data[:2000]}")

def on_response(response):
    url = response.url
    if any(kw in url for kw in ['generate', 'aigc_draft', 'aigc/draft', 'submit_task']):
        try:
            body = response.text()
        except:
            body = '[无法读取]'
        generate_requests.append({
            'type': 'RESPONSE',
            'url': url,
            'status': response.status,
            'body': body[:2000],
        })
        print(f"\n🟢 捕获生成响应:")
        print(f"   [{response.status}] {url}")
        print(f"   Body: {body[:500]}")

page.on('request', on_request)
page.on('response', on_response)

print("\n正在访问即梦视频生成页面...")
page.goto('https://jimeng.jianying.com/ai-tool/home?type=video', wait_until='networkidle', timeout=30000)
time.sleep(3)

print("\n" + "=" * 60)
print("  浏览器已打开，请手动操作：")
print("  1. 在页面上输入提示词")
print("  2. 点击生成按钮")
print("  3. 脚本会自动抓取请求格式")
print("  4. 按 Ctrl+C 退出")
print("=" * 60)

try:
    while True:
        page.wait_for_timeout(1000)
except KeyboardInterrupt:
    pass

print(f"\n\n{'='*60}")
print(f"  共捕获 {len(generate_requests)} 个生成相关请求/响应")
print(f"{'='*60}")

for i, req in enumerate(generate_requests):
    print(f"\n--- #{i+1} ({req['type']}) ---")
    if req['type'] == 'REQUEST':
        print(f"[{req['method']}] {req['url']}")
        if req.get('post_data'):
            # 尝试格式化 JSON
            try:
                parsed = json.loads(req['post_data'])
                print(f"Body:\n{json.dumps(parsed, ensure_ascii=False, indent=2)}")
            except:
                print(f"Body: {req['post_data']}")
        # 打印关键 headers
        headers = req.get('headers', {})
        for h in ['content-type', 'cookie', 'x-sign', 'a-bogus']:
            if h in headers:
                val = headers[h]
                if h == 'cookie':
                    val = val[:100] + '...'
                print(f"Header {h}: {val}")
    else:
        print(f"[{req['status']}] {req['url']}")
        print(f"Body: {req['body']}")

# 保存到文件
with open(os.path.join(SCRIPT_DIR, 'jimeng_generate_capture.json'), 'w', encoding='utf-8') as f:
    json.dump(generate_requests, f, ensure_ascii=False, indent=2)
    print(f"\n💾 已保存到 jimeng_generate_capture.json")

ctx.close()
pw.stop()
