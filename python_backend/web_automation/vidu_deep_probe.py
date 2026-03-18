#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""深入分析VIDU JS逻辑和投稿API参数格式"""

import sys
import json
sys.stdout.reconfigure(encoding='utf-8')

from playwright.sync_api import sync_playwright

def main():
    pw = sync_playwright().start()
    browser = pw.chromium.connect_over_cdp('http://127.0.0.1:9223')
    ctx = browser.contexts[0]
    vidu_page = [p for p in ctx.pages if 'vidu' in p.url][0]
    
    print(f'连接: {vidu_page.url[:60]}')
    
    # ============================================================
    # 第一步：深入分析包含 nomark/watermark 的 JS 逻辑
    # ============================================================
    print('\n' + '='*60)
    print('[1] 深入分析 JS 中的水印/下载逻辑...')
    
    js_deep = vidu_page.evaluate("""
        async () => {
            const results = [];
            const scripts = Array.from(document.querySelectorAll('script[src]'));
            const jsUrls = scripts.map(s => s.src).filter(u => u.includes('_next') || u.includes('chunk'));
            
            for (const url of jsUrls) {
                try {
                    const resp = await fetch(url);
                    const text = await resp.text();
                    
                    // 搜索 nomark 相关上下文（更大范围）
                    const keywords = ['nomark_uri', 'nomark', 'remove_watermark', 'watch_ad_watermark', 'share_elements', 'material/share', 'download_uri', 'watermarkOnly', 'noWatermarkOnly'];
                    for (const kw of keywords) {
                        let startIdx = 0;
                        while (true) {
                            const idx = text.indexOf(kw, startIdx);
                            if (idx < 0) break;
                            const context = text.substring(Math.max(0, idx - 200), Math.min(text.length, idx + kw.length + 200));
                            results.push({ 
                                file: url.split('/').pop().split('?')[0], 
                                keyword: kw, 
                                context: context,
                                position: idx
                            });
                            startIdx = idx + kw.length;
                            if (results.length > 40) break;
                        }
                    }
                } catch(e) {}
            }
            return results;
        }
    """)
    
    if js_deep:
        # 按文件分组
        by_file = {}
        for r in js_deep:
            f = r['file']
            if f not in by_file:
                by_file[f] = []
            by_file[f].append(r)
        
        for f, items in by_file.items():
            print(f'\n  === {f} ({len(items)} 匹配) ===')
            for item in items:
                print(f'    [{item["keyword"]}] @{item["position"]}:')
                # 清理上下文，缩短显示
                ctx = item['context'].replace('\n', ' ').replace('\r', '')
                print(f'      {ctx[:300]}')
                print()
    else:
        print('  未找到匹配')
    
    # ============================================================
    # 第二步：分析 share_elements/submit 需要什么参数
    # ============================================================
    print('\n' + '='*60)
    print('[2] 分析 share_elements API 需要的参数...')
    
    # 搜索 JS 中 share_elements 调用的上下文
    share_js = vidu_page.evaluate("""
        async () => {
            const results = [];
            const scripts = Array.from(document.querySelectorAll('script[src]'));
            const jsUrls = scripts.map(s => s.src).filter(u => u.includes('_next') || u.includes('chunk'));
            
            for (const url of jsUrls) {
                try {
                    const resp = await fetch(url);
                    const text = await resp.text();
                    
                    // 搜索 share_elements 更大上下文
                    const kw = 'share_elements';
                    let startIdx = 0;
                    while (true) {
                        const idx = text.indexOf(kw, startIdx);
                        if (idx < 0) break;
                        const context = text.substring(Math.max(0, idx - 500), Math.min(text.length, idx + kw.length + 500));
                        results.push({ 
                            file: url.split('/').pop().split('?')[0],
                            context: context,
                            pos: idx
                        });
                        startIdx = idx + kw.length;
                    }
                    
                    // 也搜索 is_posted 或 post 相关逻辑
                    const postKw = 'is_posted';
                    startIdx = 0;
                    while (true) {
                        const idx = text.indexOf(postKw, startIdx);
                        if (idx < 0) break;
                        const context = text.substring(Math.max(0, idx - 300), Math.min(text.length, idx + postKw.length + 300));
                        results.push({
                            file: url.split('/').pop().split('?')[0],
                            context: context,
                            pos: idx,
                            type: 'is_posted'
                        });
                        startIdx = idx + postKw.length;
                    }
                    
                } catch(e) {}
            }
            return results;
        }
    """)
    
    if share_js:
        print(f'  找到 {len(share_js)} 个匹配:')
        for r in share_js:
            tp = r.get('type', 'share')
            print(f'\n  [{tp}] in {r["file"]} @{r["pos"]}:')
            ctx = r['context'].replace('\n', ' ').replace('\r', '')
            print(f'    {ctx[:400]}')
    
    # ============================================================
    # 第三步：尝试不同的 share_elements/submit body 格式
    # ============================================================
    print('\n' + '='*60)
    print('[3] 尝试不同的 submit body 格式...')
    
    # 先获取一个 task 和 creation
    tasks_result = vidu_page.evaluate("""
        async () => {
            const resp = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.pagesz=3&scene_mode=none&types=text2video&types=character2video', { credentials: 'include' });
            return await resp.json();
        }
    """)
    tasks = tasks_result.get('tasks', [])
    if not tasks:
        print('  没有任务可测试')
        pw.stop()
        return
    
    task = tasks[0]
    creation = task['creations'][0]
    task_id = str(task['id'])
    creation_id = str(creation['id'])
    print(f'  测试: task_id={task_id}, creation_id={creation_id}')
    
    # 尝试各种 body 格式
    bodies = [
        # 格式1: element 包含 creation_id
        {"element": {"creation_id": creation_id, "task_id": task_id}},
        # 格式2: 直接字段
        {"creation_id": creation_id, "task_id": task_id, "title": "test", "description": "test"},
        # 格式3: share_info 风格
        {"share_info": {"title": "test"}, "element": {"creation_id": creation_id}},
        # 格式4: elements 数组
        {"elements": [{"creation_id": creation_id, "type": "video"}]},
        # 格式5: creation_ids 数组
        {"creation_ids": [creation_id]},
        # 格式6: proto3 风格（空对象时会报 nil）
        {"element": {"id": creation_id}, "share_info": {"title": "test", "desc": "test"}},
        # 格式7: 纯 creation
        {"creation": {"id": creation_id}},
    ]
    
    for i, body in enumerate(bodies):
        result = vidu_page.evaluate(f"""
            async () => {{
                try {{
                    const resp = await fetch('https://service.vidu.cn/vidu/v1/material/share_elements/submit', {{
                        credentials: 'include',
                        method: 'POST',
                        headers: {{ 'Content-Type': 'application/json' }},
                        body: JSON.stringify({json.dumps(body)})
                    }});
                    const text = await resp.text();
                    return {{ status: resp.status, body: text.slice(0, 500) }};
                }} catch(e) {{ return {{ error: e.message }}; }}
            }}
        """)
        status = result.get('status', 'err')
        resp_body = result.get('body', '')[:200]
        marker = '✅' if status in [200, 201] else '⚠️' if status == 400 else '❌'
        print(f'  {marker} [{status}] 格式{i+1}: {json.dumps(body, ensure_ascii=False)[:80]}')
        print(f'    响应: {resp_body}')
    
    # ============================================================
    # 第四步：探测看广告接口
    # ============================================================
    print('\n' + '='*60)
    print('[4] 探测看广告去水印流程...')
    
    # 从 JS 分析，watch_ad_watermark 是一个前端弹窗 key，不是 API
    # 真正的 API 可能是通过广告 SDK 回调触发的
    # 搜索 JS 中广告 SDK 和回调的上下文
    ad_js = vidu_page.evaluate("""
        async () => {
            const results = [];
            const scripts = Array.from(document.querySelectorAll('script[src]'));
            const jsUrls = scripts.map(s => s.src).filter(u => u.includes('_next') || u.includes('chunk'));
            
            for (const url of jsUrls) {
                try {
                    const resp = await fetch(url);
                    const text = await resp.text();
                    
                    // 搜索广告回调和积分相关
                    const keywords = ['ad_callback', 'reward_ad', 'rewardedAd', 'adReward', 'credit', 'insufficient', 'watch_ad', 'ad_popup', 'removeWatermark', 'free_download'];
                    for (const kw of keywords) {
                        const idx = text.indexOf(kw);
                        if (idx >= 0) {
                            const context = text.substring(Math.max(0, idx - 150), Math.min(text.length, idx + kw.length + 150));
                            results.push({ file: url.split('/').pop().split('?')[0], keyword: kw, context: context });
                        }
                    }
                } catch(e) {}
            }
            return results;
        }
    """)
    
    if ad_js:
        print(f'  找到 {len(ad_js)} 个广告相关匹配:')
        for r in ad_js:
            print(f'    [{r["keyword"]}] in {r["file"]}:')
            ctx = r['context'].replace('\n', ' ').replace('\r', '')
            print(f'      {ctx[:250]}')
            print()
    
    # ============================================================
    # 第五步：检查当前视频URL中是否有水印
    # ============================================================
    print('\n' + '='*60)
    print('[5] 检查当前视频的完整URI...')
    
    for i, t in enumerate(tasks[:2]):
        for c in t.get('creations', []):
            uri = c.get('uri', '')
            dl = c.get('download_uri', '')
            nomark = c.get('nomark_uri', '')
            print(f'  任务[{i}]:')
            print(f'    完整 uri: {uri}')
            print(f'    完整 download_uri: {dl}')
            print(f'    nomark_uri: "{nomark}"')
            # 分析 URI 路径部分
            if uri:
                from urllib.parse import urlparse
                parsed = urlparse(uri)
                print(f'    路径: {parsed.path}')
                # 检查文件名
                filename = parsed.path.split('/')[-1]
                print(f'    文件名: {filename}')
                has_wm = '-wm' in filename or 'watermark' in filename.lower()
                print(f'    文件名含水印标记: {has_wm}')
            print()
    
    pw.stop()
    print('[完成]')


if __name__ == '__main__':
    main()
