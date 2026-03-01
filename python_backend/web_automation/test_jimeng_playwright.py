#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""测试通过 Playwright 从即梦 profile 获取 sessionid"""
import sys
import os
import io
import time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 我们自己的 profile 目录
OUR_PROFILE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                           'python_backend', 'user_data', 'jimeng_profile')

# 插件的 profile 目录（临时测试用）
PLUGIN_PROFILE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                              'jimeng_web_video_plugin_seedance_2_0', '.jimeng_cdp_profile')

def test_get_session(profile_dir, label):
    """用 Playwright headless 模式打开 profile，获取 cookie"""
    print(f"\n{'='*50}")
    print(f"测试: {label}")
    print(f"Profile: {profile_dir}")
    print(f"存在: {os.path.exists(profile_dir)}")
    
    if not os.path.exists(profile_dir):
        print("❌ Profile 目录不存在")
        return
    
    from playwright.sync_api import sync_playwright
    
    pw = sync_playwright().start()
    
    try:
        # 用 headless 模式打开 persistent context
        ctx = pw.chromium.launch_persistent_context(
            user_data_dir=profile_dir,
            headless=True,
            args=['--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage'],
        )
        
        page = ctx.new_page()
        
        # 访问即梦首页（触发 cookie 加载）
        print("正在访问即梦首页...")
        page.goto('https://jimeng.jianying.com', wait_until='domcontentloaded', timeout=20000)
        time.sleep(2)
        
        # 获取所有 cookie
        cookies = ctx.cookies(['https://jimeng.jianying.com'])
        print(f"获取到 {len(cookies)} 个 cookie")
        
        session_id = None
        for c in cookies:
            if c['name'] == 'sessionid':
                session_id = c['value']
                print(f"\n✅ sessionid: {session_id[:20]}...{session_id[-8:]}")
                print(f"   长度: {len(session_id)}")
                print(f"   domain: {c.get('domain', '')}")
                break
        
        if not session_id:
            print("\n❌ 未找到 sessionid")
            print("所有 cookie 名称:")
            for c in cookies:
                print(f"  {c['name']} (domain: {c.get('domain', '')})")
        
        # 检查页面是否已登录
        title = page.title()
        print(f"\n页面标题: {title}")
        
        ctx.close()
        
    except Exception as e:
        print(f"❌ 错误: {e}")
    finally:
        pw.stop()

# 先测试插件的 profile（已登录）
test_get_session(PLUGIN_PROFILE, "即梦插件 Profile")

# 再测试我们自己的 profile（可能未登录）
if os.path.exists(OUR_PROFILE):
    test_get_session(OUR_PROFILE, "我们的 Profile")
else:
    print(f"\n我们的 profile 不存在: {OUR_PROFILE}")
    print("需要先运行: python open_browser_for_login.py jimeng")
