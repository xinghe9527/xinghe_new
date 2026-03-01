#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""测试即梦内部 API 调用"""
import sys
import os
import io
import json
import time
import requests

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

JIMENG_BASE_URL = 'https://jimeng.jianying.com'

def get_session_id():
    """从插件 profile 获取 sessionid（测试用）"""
    from playwright.sync_api import sync_playwright
    
    profile = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                           'jimeng_web_video_plugin_seedance_2_0', '.jimeng_cdp_profile')
    
    pw = sync_playwright().start()
    ctx = pw.chromium.launch_persistent_context(
        user_data_dir=profile,
        headless=True,
        args=['--disable-gpu', '--no-sandbox'],
    )
    page = ctx.new_page()
    page.goto('https://jimeng.jianying.com', wait_until='domcontentloaded', timeout=20000)
    time.sleep(1)
    
    cookies = ctx.cookies(['https://jimeng.jianying.com'])
    session_id = None
    all_cookies = {}
    for c in cookies:
        all_cookies[c['name']] = c['value']
        if c['name'] == 'sessionid':
            session_id = c['value']
    
    ctx.close()
    pw.stop()
    return session_id, all_cookies


def test_api(session_id, all_cookies):
    """测试即梦 API"""
    session = requests.Session()
    
    # 设置请求头
    session.headers.update({
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36',
        'Origin': JIMENG_BASE_URL,
        'Referer': f'{JIMENG_BASE_URL}/ai-tool/home?type=video',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
    })
    
    # 设置所有 cookie（不只是 sessionid）
    for name, value in all_cookies.items():
        session.cookies.set(name, value, domain='.jianying.com')
    
    # 测试1：获取积分余额
    print("\n📊 测试1: 获取积分余额")
    try:
        resp = session.get(f'{JIMENG_BASE_URL}/mweb/v1/get_credit_balance', timeout=10)
        print(f"   HTTP {resp.status_code}")
        data = resp.json()
        print(f"   ret={data.get('ret')} msg={data.get('msg', '')}")
        if data.get('ret') == 0:
            print(f"   ✅ 积分: {json.dumps(data.get('data', {}), ensure_ascii=False)}")
        else:
            print(f"   ❌ 失败: {data}")
    except Exception as e:
        print(f"   ❌ 错误: {e}")
    
    # 测试2：获取用户信息
    print("\n👤 测试2: 获取用户信息")
    try:
        resp = session.get(f'{JIMENG_BASE_URL}/mweb/v1/get_user_info', timeout=10)
        print(f"   HTTP {resp.status_code}")
        data = resp.json()
        print(f"   ret={data.get('ret')} msg={data.get('msg', '')}")
        if data.get('ret') == 0:
            user = data.get('data', {})
            print(f"   ✅ 用户: {user.get('nickname', '未知')}")
        else:
            # 尝试其他接口路径
            resp2 = session.post(f'{JIMENG_BASE_URL}/mweb/v1/user/info', json={}, timeout=10)
            data2 = resp2.json()
            print(f"   备用接口 ret={data2.get('ret')}")
    except Exception as e:
        print(f"   ❌ 错误: {e}")
    
    # 测试3：获取历史记录（验证 API 可用性）
    print("\n📜 测试3: 获取历史记录")
    try:
        resp = session.post(
            f'{JIMENG_BASE_URL}/mweb/v1/get_history_list',
            json={
                'offset': 0,
                'limit': 3,
                'http_common': {'aid': 513695},
            },
            timeout=10,
        )
        print(f"   HTTP {resp.status_code}")
        data = resp.json()
        print(f"   ret={data.get('ret')} msg={data.get('msg', '')}")
        if data.get('ret') == 0:
            items = data.get('data', {}).get('history_list', [])
            print(f"   ✅ 历史记录数: {len(items)}")
            for item in items[:3]:
                print(f"      - {item.get('prompt', '无提示词')[:50]}")
    except Exception as e:
        print(f"   ❌ 错误: {e}")


# 主流程
print("🔑 获取 sessionid...")
sid, cookies = get_session_id()
if sid:
    print(f"✅ sessionid: {sid[:12]}...")
    test_api(sid, cookies)
else:
    print("❌ 获取 sessionid 失败")
