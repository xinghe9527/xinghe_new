#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""VIDU 综合探测脚本 - 无水印下载方案探索"""

import sys
import json
sys.stdout.reconfigure(encoding='utf-8')

from playwright.sync_api import sync_playwright

def main():
    pw = sync_playwright().start()
    try:
        browser = pw.chromium.connect_over_cdp('http://127.0.0.1:9223')
    except Exception as e:
        print(f'CDP连接失败: {e}')
        return
    
    ctx = browser.contexts[0]
    vidu_page = None
    for p in ctx.pages:
        if 'vidu' in p.url:
            vidu_page = p
            break
    
    if not vidu_page:
        print('ERROR: 没找到VIDU页面')
        pw.stop()
        return
    
    print(f'[1] 连接成功: {vidu_page.url[:80]}')
    
    # ============================================================
    # 第一步：获取任务历史，查看 nomark_uri 状态
    # ============================================================
    print('\n' + '='*60)
    print('[2] 调用任务历史API...')
    
    api_result = vidu_page.evaluate("""
        async () => {
            try {
                const url = 'https://service.vidu.cn/vidu/v1/tasks/history/me?pager.pagesz=5&scene_mode=none&types=img2video&types=character2video&types=text2video&types=reference2image&types=text2image';
                const resp = await fetch(url, { credentials: 'include' });
                return { status: resp.status, data: await resp.json() };
            } catch(e) { return { error: e.message }; }
        }
    """)
    
    test_creation_id = ''
    test_task_id = ''
    tasks = []
    
    if api_result.get('error'):
        print(f'API调用失败: {api_result["error"]}')
    else:
        print(f'API状态: {api_result["status"]}')
        data = api_result.get('data', {})
        tasks = data.get('tasks', [])
        print(f'任务数量: {len(tasks)}')
        
        for i, task in enumerate(tasks[:3]):
            creations = task.get('creations', [])
            print(f'\n  任务[{i}]: type={task.get("type")}, state={task.get("state")}')
            for j, c in enumerate(creations[:2]):
                uri = c.get('uri', '')
                nomark = c.get('nomark_uri', '')
                download = c.get('download_uri', '')
                grade = c.get('grade', '')
                is_posted = c.get('is_posted', '')
                cid = str(c.get('id', ''))
                tid = str(task.get('id', ''))
                
                if not test_creation_id and uri:
                    test_creation_id = cid
                    test_task_id = tid
                
                print(f'    creation[{j}]: id={cid}')
                print(f'      uri: ...{uri[-80:]}' if len(uri) > 80 else f'      uri: {uri}')
                print(f'      nomark_uri: "{nomark}"')
                print(f'      download_uri: ...{download[-80:]}' if len(download) > 80 else f'      download_uri: {download}')
                print(f'      grade={grade}, is_posted={is_posted}')
                
                # 检查 uri 和 download_uri 中是否有 -wm 标记
                wm_in_uri = '-wm' in uri
                wm_in_dl = '-wm' in download
                print(f'      水印标记: uri含-wm={wm_in_uri}, download含-wm={wm_in_dl}')
                
                # 打印完整的 creation 字段（找其他可能有用的）
                other_keys = [k for k in c.keys() if k not in ('uri', 'nomark_uri', 'download_uri', 'grade', 'is_posted', 'id')]
                useful_keys = {}
                for k in other_keys:
                    v = c[k]
                    if v and v != '' and v != 0 and v != False:
                        if isinstance(v, str) and len(v) > 150:
                            useful_keys[k] = v[:100] + '...'
                        else:
                            useful_keys[k] = v
                if useful_keys:
                    print(f'      其他字段: {json.dumps(useful_keys, ensure_ascii=False, default=str)[:300]}')
    
    # ============================================================
    # 第二步：查看用户信息
    # ============================================================
    print('\n' + '='*60)
    print('[3] 查询用户信息...')
    user_result = vidu_page.evaluate("""
        async () => {
            try {
                const resp = await fetch('https://service.vidu.cn/vidu/v1/user/me', { credentials: 'include' });
                return await resp.json();
            } catch(e) { return { error: e.message }; }
        }
    """)
    if not user_result.get('error'):
        user = user_result.get('data', user_result)
        if isinstance(user, dict):
            for k in ['subs_plan', 'vip_level', 'nickname', 'points', 'credits', 'coins', 'balance', 'email', 'phone']:
                if k in user:
                    print(f'  {k}: {user[k]}')
    
    # ============================================================
    # 第三步：探测看广告去水印 + 下载相关 API
    # ============================================================
    print('\n' + '='*60)
    print(f'[4] 探测去水印/下载API (task_id={test_task_id}, creation_id={test_creation_id})...')
    
    # GET 探测
    get_endpoints = [
        f'creations/{test_creation_id}/remove_watermark',
        f'creations/{test_creation_id}/nomark',
        f'creations/{test_creation_id}/download',
        f'tasks/{test_task_id}/remove_watermark',
        f'tasks/{test_task_id}/download',
        'watch_ad/watermark',
        'ad/remove_watermark',
        'user/credits/ad',
        'user/watch_ad',
        'activities/ad_watermark',
        f'creations/{test_creation_id}/unwatermark',
        f'tasks/{test_task_id}/creations/{test_creation_id}',
    ]
    
    for endpoint in get_endpoints:
        url = f'https://service.vidu.cn/vidu/v1/{endpoint}'
        result = vidu_page.evaluate(f"""
            async () => {{
                try {{
                    const resp = await fetch('{url}', {{ credentials: 'include' }});
                    const text = await resp.text();
                    return {{ status: resp.status, body: text.slice(0, 300) }};
                }} catch(e) {{ return {{ error: e.message }}; }}
            }}
        """)
        status = result.get('status', 'err')
        body = result.get('body', result.get('error', ''))[:120]
        marker = '✅' if status == 200 else '❌' if status in [404, 405] else '⚠️'
        print(f'  {marker} GET [{status}] {endpoint}')
        if status == 200:
            print(f'      {body}')
    
    # POST 探测
    print('\n  --- POST 方式 ---')
    post_endpoints = [
        f'creations/{test_creation_id}/remove_watermark',
        f'creations/{test_creation_id}/nomark',
        'watch_ad/watermark',
        'ad/remove_watermark',
        f'material/share_elements/submit',
        f'creations/{test_creation_id}/post',
        f'creations/{test_creation_id}/publish',
    ]
    
    for endpoint in post_endpoints:
        url = f'https://service.vidu.cn/vidu/v1/{endpoint}'
        result = vidu_page.evaluate(f"""
            async () => {{
                try {{
                    const resp = await fetch('{url}', {{
                        credentials: 'include',
                        method: 'POST',
                        headers: {{ 'Content-Type': 'application/json' }},
                        body: JSON.stringify({{ creation_id: '{test_creation_id}', task_id: '{test_task_id}' }})
                    }});
                    const text = await resp.text();
                    return {{ status: resp.status, body: text.slice(0, 500) }};
                }} catch(e) {{ return {{ error: e.message }}; }}
            }}
        """)
        status = result.get('status', 'err')
        body = result.get('body', result.get('error', ''))[:200]
        marker = '✅' if status == 200 else '❌' if status in [404, 405] else '⚠️'
        print(f'  {marker} POST [{status}] {endpoint}')
        if status in [200, 201, 400, 422]:
            print(f'      {body}')
    
    # ============================================================
    # 第四步：搜索 JS 中的去水印逻辑
    # ============================================================
    print('\n' + '='*60)
    print('[5] 搜索JS中的去水印/广告相关逻辑...')
    
    js_search = vidu_page.evaluate("""
        async () => {
            const results = [];
            const scripts = Array.from(document.querySelectorAll('script[src]'));
            const jsUrls = scripts.map(s => s.src).filter(u => u.includes('_next') || u.includes('chunk'));
            
            for (const url of jsUrls.slice(0, 15)) {
                try {
                    const resp = await fetch(url);
                    const text = await resp.text();
                    
                    // 搜索关键词
                    const keywords = ['nomark', 'watermark', 'remove_watermark', 'watch_ad', 'ad_popup', 'unwatermark', 'no_watermark'];
                    for (const kw of keywords) {
                        const idx = text.indexOf(kw);
                        if (idx >= 0) {
                            const context = text.substring(Math.max(0, idx - 80), idx + kw.length + 80);
                            results.push({ url: url.split('/').pop(), keyword: kw, context: context });
                        }
                    }
                } catch(e) {}
            }
            return results;
        }
    """)
    
    if js_search:
        print(f'  找到 {len(js_search)} 个匹配:')
        for r in js_search:
            print(f'    [{r["keyword"]}] in {r["url"]}:')
            print(f'      ...{r["context"][:150]}...')
    else:
        print('  未在前15个JS文件中找到关键词')
    
    # ============================================================
    # 第五步：尝试直接获取无水印URL的已知方法
    # ============================================================
    print('\n' + '='*60)
    print('[6] 分析URI结构，尝试构造无水印URL...')
    
    if tasks:
        for t in tasks[:1]:
            for c in t.get('creations', []):
                uri = c.get('uri', '')
                if '-wm' in uri:
                    # 尝试去掉 -wm
                    nomark_url = uri.replace('-wm.mp4', '.mp4').replace('-wm.webm', '.webm')
                    print(f'  原始URL: ...{uri[-80:]}')
                    print(f'  去wm URL: ...{nomark_url[-80:]}')
                    
                    # 测试去wm的URL是否可访问（通过浏览器fetch带cookie）
                    test_result = vidu_page.evaluate(f"""
                        async () => {{
                            try {{
                                const resp = await fetch('{nomark_url}', {{ method: 'HEAD', credentials: 'include' }});
                                return {{ status: resp.status, headers: Object.fromEntries(resp.headers.entries()) }};
                            }} catch(e) {{ return {{ error: e.message }}; }}
                        }}
                    """)
                    status = test_result.get('status', 'err')
                    print(f'  去wm URL 可访问: {status == 200} (status={status})')
                    if status == 200:
                        headers = test_result.get('headers', {})
                        print(f'    content-type: {headers.get("content-type", "?")}')
                        print(f'    content-length: {headers.get("content-length", "?")}')
                    break
    
    pw.stop()
    print('\n[完成] 全部探测结束')


if __name__ == '__main__':
    main()
