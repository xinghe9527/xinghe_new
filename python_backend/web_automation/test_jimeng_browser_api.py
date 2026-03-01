#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
测试即梦浏览器代理 API 方案

验证：
1. 能否通过 Playwright 启动浏览器并加载即梦页面
2. 能否通过 page.evaluate(fetch) 调用即梦内部 API
3. 能否正确获取用户信息和积分
4. 能否正确提交视频生成任务

用法：
    python test_jimeng_browser_api.py
    python test_jimeng_browser_api.py --profile <profile_dir>
"""

import sys
import os
import io
import json
import time
import argparse

if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')
    except:
        pass

# 添加脚本目录到 path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from auto_jimeng import JimengBrowserAPI, build_api_url, JIMENG_PROFILE_DIR


def main():
    parser = argparse.ArgumentParser(description='测试即梦浏览器代理 API')
    parser.add_argument('--profile', default=None, help='浏览器 profile 目录')
    args = parser.parse_args()
    
    profile = args.profile or JIMENG_PROFILE_DIR
    
    print("\n" + "=" * 60)
    print("  🧪 即梦浏览器代理 API 测试")
    print("=" * 60)
    print(f"\n📁 Profile: {profile}")
    print(f"   存在: {os.path.exists(profile)}")
    
    if not os.path.exists(profile):
        print(f"\n❌ Profile 目录不存在！")
        print(f"   请先运行: python open_browser_for_login.py jimeng")
        return 1
    
    # 启动浏览器代理
    print(f"\n{'='*40}")
    print(f"  测试1: 启动浏览器代理")
    print(f"{'='*40}")
    
    api = JimengBrowserAPI(profile_dir=profile)
    if not api.start():
        print("❌ 启动失败")
        return 1
    
    try:
        # 测试2: 检查登录
        print(f"\n{'='*40}")
        print(f"  测试2: 检查登录状态")
        print(f"{'='*40}")
        
        login_ok = api.check_login()
        print(f"   结果: {'✅ 已登录' if login_ok else '❌ 未登录'}")
        
        # 测试3: 获取用户信息
        print(f"\n{'='*40}")
        print(f"  测试3: 获取用户信息")
        print(f"{'='*40}")
        
        user_info = api.get_user_info()
        if user_info:
            print(f"   ✅ 用户信息: {json.dumps(user_info, ensure_ascii=False)[:300]}")
        else:
            print(f"   ⚠️  未获取到用户信息")
        
        # 测试4: 获取历史记录（验证 API 可用性）
        print(f"\n{'='*40}")
        print(f"  测试4: 获取历史记录")
        print(f"{'='*40}")
        
        try:
            url = build_api_url('/mweb/v1/get_user_local_item_list')
            data = api._fetch_api(url, 'POST', {
                'offset': 0,
                'limit': 3,
                'http_common': {'aid': 513695},
            })
            print(f"   ret={data.get('ret')}")
            if data.get('ret') == 0:
                items = data.get('data', {})
                print(f"   ✅ 返回数据: {json.dumps(items, ensure_ascii=False)[:300]}")
            else:
                print(f"   ⚠️  返回: {json.dumps(data, ensure_ascii=False)[:300]}")
        except Exception as e:
            print(f"   ❌ 错误: {e}")
        
        # 测试5: 获取模型配置
        print(f"\n{'='*40}")
        print(f"  测试5: 获取模型配置")
        print(f"{'='*40}")
        
        try:
            url = build_api_url('/mweb/v1/video_generate/get_common_config')
            data = api._fetch_api(url, 'POST', {})
            print(f"   ret={data.get('ret')}")
            if data.get('ret') == 0:
                config = data.get('data', {})
                print(f"   ✅ 配置: {json.dumps(config, ensure_ascii=False)[:500]}")
            else:
                print(f"   ⚠️  返回: {json.dumps(data, ensure_ascii=False)[:300]}")
        except Exception as e:
            print(f"   ❌ 错误: {e}")
        
        # 测试6: 尝试抓取页面上的 API 请求（观察实际请求格式）
        print(f"\n{'='*40}")
        print(f"  测试6: 抓取页面 API 请求")
        print(f"{'='*40}")
        
        try:
            # 注册请求监听
            captured = []
            
            def on_response(response):
                url = response.url
                if 'jianying.com' in url and any(p in url for p in ['/mweb/', '/commerce/', '/aigc']):
                    try:
                        body = response.text()
                        body_preview = body[:200] if body else ''
                    except:
                        body_preview = '[无法读取]'
                    captured.append({
                        'url': url[:150],
                        'status': response.status,
                        'body': body_preview,
                    })
            
            api.page.on('response', on_response)
            
            # 刷新页面触发 API 请求
            api.page.reload(wait_until='networkidle', timeout=20000)
            time.sleep(3)
            
            print(f"   捕获到 {len(captured)} 个 API 响应:")
            for req in captured[:10]:
                print(f"   [{req['status']}] {req['url']}")
                if req['body']:
                    print(f"         {req['body'][:150]}")
        except Exception as e:
            print(f"   ❌ 错误: {e}")
        
        print(f"\n{'='*60}")
        print(f"  ✅ 测试完成")
        print(f"{'='*60}\n")
        
    finally:
        api.stop()
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
