#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""测试即梦登录检查 - 找出正确的请求方式"""
import sys, os, io, json, time

if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    except: pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from auto_jimeng import JimengBrowserAPI, build_api_url, JIMENG_BASE_URL

profile = sys.argv[1] if len(sys.argv) > 1 else 'jimeng_web_video_plugin_seedance_2_0/.jimeng_cdp_profile'
print(f"Profile: {profile}")

api = JimengBrowserAPI(profile_dir=profile)
if not api.start():
    print("启动失败")
    sys.exit(1)

try:
    # 测试不同的请求方式
    tests = [
        ("GET /commerce/v1/benefits/user_credit (无参数)", 
         f'{JIMENG_BASE_URL}/commerce/v1/benefits/user_credit', 'GET', None),
        ("POST /commerce/v1/benefits/user_credit (空body)", 
         f'{JIMENG_BASE_URL}/commerce/v1/benefits/user_credit', 'POST', {}),
        ("POST /commerce/v1/benefits/user_credit (带aid参数)", 
         f'{JIMENG_BASE_URL}/commerce/v1/benefits/user_credit?aid=513695', 'POST', {}),
        ("POST /mweb/v1/get_user_info (带查询参数)", 
         build_api_url('/mweb/v1/get_user_info'), 'POST', {}),
        ("POST /mweb/v1/get_user_info (无查询参数)", 
         f'{JIMENG_BASE_URL}/mweb/v1/get_user_info', 'POST', {}),
        ("POST /mweb/v1/get_ug_info (带查询参数)", 
         build_api_url('/mweb/v1/get_ug_info'), 'POST', {}),
    ]
    
    for desc, url, method, body in tests:
        print(f"\n{'='*50}")
        print(f"  {desc}")
        print(f"  URL: {url[:120]}")
        print(f"{'='*50}")
        
        try:
            # 直接用 page.evaluate 发请求
            fetch_opts = {
                'method': method,
                'headers': {'Content-Type': 'application/json', 'Accept': 'application/json'},
                'credentials': 'include',
            }
            if body is not None and method == 'POST':
                fetch_opts['body'] = json.dumps(body)
            
            js = f"""
            async () => {{
                try {{
                    const resp = await fetch({json.dumps(url)}, {json.dumps(fetch_opts)});
                    const text = await resp.text();
                    return {{ ok: resp.ok, status: resp.status, body: text.substring(0, 500) }};
                }} catch(e) {{
                    return {{ ok: false, status: 0, body: e.message }};
                }}
            }}
            """
            result = api.page.evaluate(js)
            print(f"  HTTP {result['status']} ok={result['ok']}")
            print(f"  Body: {result['body'][:300]}")
        except Exception as e:
            print(f"  错误: {e}")

finally:
    api.stop()
