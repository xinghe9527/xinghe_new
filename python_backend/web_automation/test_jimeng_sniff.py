#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""用 Playwright 抓取即梦网页发出的 API 请求，找到正确的接口路径"""
import sys
import os
import io
import json
import time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

from playwright.sync_api import sync_playwright

profile = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                       'jimeng_web_video_plugin_seedance_2_0', '.jimeng_cdp_profile')

print(f"Profile: {profile}\n")

pw = sync_playwright().start()

# 用有头模式打开，方便观察
ctx = pw.chromium.launch_persistent_context(
    user_data_dir=profile,
    headless=True,
    args=['--disable-gpu', '--no-sandbox'],
)

page = ctx.new_page()

# 收集所有 API 请求
api_requests = []

def on_request(request):
    url = request.url
    # 只记录即梦相关的 API 请求
    if 'jianying.com' in url and '/api/' in url.lower():
        api_requests.append({
            'method': request.method,
            'url': url,
        })
    elif 'jianying.com' in url and '/mweb/' in url.lower():
        api_requests.append({
            'method': request.method,
            'url': url,
        })
    elif 'jianying.com' in url and ('/v1/' in url or '/v2/' in url):
        api_requests.append({
            'method': request.method,
            'url': url,
        })

def on_response(response):
    url = response.url
    if 'jianying.com' in url and any(p in url for p in ['/api/', '/mweb/', '/v1/', '/v2/', 'credit', 'user', 'history', 'aigc']):
        status = response.status
        try:
            # 尝试获取响应体
            body = response.text()
            body_preview = body[:200] if body else ''
        except:
            body_preview = '[无法读取]'
        
        api_requests.append({
            'method': 'RESPONSE',
            'url': url,
            'status': status,
            'body': body_preview,
        })

page.on('request', on_request)
page.on('response', on_response)

print("正在访问即梦首页...")
page.goto('https://jimeng.jianying.com/ai-tool/home?type=video', wait_until='networkidle', timeout=30000)
time.sleep(5)

print(f"\n捕获到 {len(api_requests)} 个 API 请求:\n")
for req in api_requests:
    if req.get('method') == 'RESPONSE':
        print(f"  ← [{req.get('status')}] {req['url'][:120]}")
        if req.get('body'):
            print(f"     {req['body'][:150]}")
    else:
        print(f"  → [{req['method']}] {req['url'][:120]}")

ctx.close()
pw.stop()
