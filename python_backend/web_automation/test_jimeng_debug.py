#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""调试即梦 API 返回的数据结构"""
import sys, os, io, json, time

if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    except: pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from auto_jimeng import JimengBrowserAPI, build_api_url, JIMENG_BASE_URL

profile = sys.argv[1] if len(sys.argv) > 1 else 'jimeng_web_video_plugin_seedance_2_0/.jimeng_cdp_profile'

api = JimengBrowserAPI(profile_dir=profile)
if not api.start():
    sys.exit(1)

try:
    # 1. 打印完整的模型配置
    print("=" * 60)
    print("  模型配置完整数据")
    print("=" * 60)
    url = build_api_url('/mweb/v1/video_generate/get_common_config')
    data = api._fetch_api(url, 'POST', {})
    # 打印完整 JSON（格式化）
    print(json.dumps(data, ensure_ascii=False, indent=2)[:3000])
    
    # 2. 抓取一次真实的生成请求
    # 通过监听网络请求，在页面上触发一次生成
    print("\n" + "=" * 60)
    print("  抓取页面上的生成请求格式")
    print("=" * 60)
    
    captured_requests = []
    
    def on_request(request):
        url = request.url
        if 'generate' in url or 'aigc_draft' in url:
            try:
                post_data = request.post_data
            except:
                post_data = None
            captured_requests.append({
                'method': request.method,
                'url': url,
                'post_data': post_data[:1000] if post_data else None,
            })
    
    api.page.on('request', on_request)
    
    # 等一会看看有没有自动的请求
    time.sleep(3)
    
    if captured_requests:
        print(f"   捕获到 {len(captured_requests)} 个生成相关请求:")
        for req in captured_requests:
            print(f"   [{req['method']}] {req['url'][:150]}")
            if req['post_data']:
                print(f"   Body: {req['post_data']}")
    else:
        print("   没有捕获到生成请求（需要在页面上手动触发）")
    
    # 3. 看看 creation_agent 配置（可能包含生成接口的信息）
    print("\n" + "=" * 60)
    print("  creation_agent 配置")
    print("=" * 60)
    url2 = build_api_url('/mweb/v1/creation_agent/v2/get_agent_config')
    data2 = api._fetch_api(url2, 'POST', {})
    # 只打印视频相关的部分
    video_data = data2.get('data', {}).get('video_data', data2.get('data', {}))
    print(json.dumps(video_data, ensure_ascii=False, indent=2)[:3000])

finally:
    api.stop()
