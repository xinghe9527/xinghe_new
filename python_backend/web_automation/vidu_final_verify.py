#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
VIDU 最终验证脚本：
1. 获取 categories 并正确调用 share_elements/submit
2. 检验国际版域名
3. 验证下载组件的 watermarkMode 实际行为
"""

import sys
import json
import time
sys.stdout.reconfigure(encoding='utf-8')

from playwright.sync_api import sync_playwright

def main():
    pw = sync_playwright().start()
    browser = pw.chromium.connect_over_cdp('http://127.0.0.1:9223')
    ctx = browser.contexts[0]
    vidu_page = [p for p in ctx.pages if 'vidu' in p.url][0]
    
    print(f'连接: {vidu_page.url[:60]}')
    
    # ============================================================
    # 第一步：获取 categories
    # ============================================================
    print('\n' + '='*60)
    print('[1] 获取 share_elements categories...')
    
    categories = vidu_page.evaluate("""
        async () => {
            try {
                const resp = await fetch('https://service.vidu.cn/vidu/v1/material/share_elements/categories', { credentials: 'include' });
                return await resp.json();
            } catch(e) { return { error: e.message }; }
        }
    """)
    print(json.dumps(categories, ensure_ascii=False, indent=2, default=str)[:1500])
    
    # ============================================================
    # 第二步：获取最新任务信息
    # ============================================================
    print('\n' + '='*60)
    print('[2] 获取最新任务...')
    
    tasks_data = vidu_page.evaluate("""
        async () => {
            const resp = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.pagesz=2&scene_mode=none&types=text2video&types=character2video', { credentials: 'include' });
            return await resp.json();
        }
    """)
    
    tasks = tasks_data.get('tasks', [])
    if not tasks:
        print('  没有任务！')
        pw.stop()
        return
    
    task = tasks[0]
    creation = task['creations'][0]
    task_id = str(task['id'])
    creation_id = str(creation['id'])
    task_type = task.get('type', '')
    creation_type = creation.get('type', '')
    uri = creation.get('uri', '')
    cover_uri = creation.get('cover_uri', '')
    
    print(f'  task_id={task_id}, creation_id={creation_id}')
    print(f'  type={task_type}/{creation_type}')
    print(f'  uri: ...{uri[-60:]}')
    
    # ============================================================
    # 第三步：用正确格式调用 share_elements/submit
    # ============================================================
    print('\n' + '='*60)
    print('[3] 尝试正确的 share_elements/submit 格式...')
    
    # 从 JS 分析，"element" 和 "share_info" 两个字段都需要
    # element 应该包含 creation 的信息
    # share_info 应该包含投稿的标题、分类等
    
    # 先拿一个 category_id（如果有的话）
    category_id = ''
    if isinstance(categories, dict):
        cats = categories.get('categories', categories.get('data', []))
        if isinstance(cats, list) and cats:
            category_id = str(cats[0].get('id', ''))
            print(f'  第一个分类: id={category_id}, name={cats[0].get("name", "")}')
    
    # 更多格式尝试（基于 proto3/gRPC 和错误信息 "element or share info nil"）
    bodies = [
        # 格式A: 双层结构，element含creation引用，share_info含投稿信息
        {
            "element": {
                "creation_id": int(creation_id),
                "type": creation_type,
            },
            "share_info": {
                "title": "test_auto",
                "description": "test",
                "category_id": int(category_id) if category_id else 0,
            }
        },
        # 格式B: element 包含 uri
        {
            "element": {
                "creation_id": int(creation_id),
                "task_id": int(task_id),
                "type": creation_type,
                "uri": uri,
                "cover_uri": cover_uri,
            },
            "share_info": {
                "title": "test_auto",
            }
        },
        # 格式C: 字符串ID
        {
            "element": {
                "creation_id": creation_id,
                "type": creation_type,
            },
            "share_info": {
                "title": "test_auto",
                "desc": "test",
            }
        },
        # 格式D: 模仿 proto3 风格 (snake_case)
        {
            "element": {
                "creation_id": creation_id,
                "task_id": task_id,
            },
            "share_info": {
                "title": "test",
                "description": "test auto submission",
                "category_ids": [category_id] if category_id else [],
            }
        },
        # 格式E: 最简化（也许 element 只要 id）
        {
            "element": {
                "id": creation_id,
            },
            "share_info": {
                "title": "test",
            }
        },
        # 格式F: creation + share (不叫 element)
        {
            "creation_id": creation_id,
            "share_info": {
                "title": "test",
            }
        },
    ]
    
    for i, body in enumerate(bodies):
        label = chr(65 + i)  # A, B, C, ...
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
        resp_body = result.get('body', '')[:250]
        marker = '✅' if status in [200, 201] else '⚠️' if status == 400 else '❌'
        body_short = json.dumps(body, ensure_ascii=False)[:100]
        print(f'  {marker} [{status}] 格式{label}: {body_short}')
        
        # 如果不是 "element or share info nil" 错误，说明进了一步
        if 'element or share info nil' not in resp_body:
            print(f'    >>> 新响应: {resp_body}')
        else:
            print(f'    仍然 nil')
        
        # 如果成功了，记录 share_id 并立即取消
        if status in [200, 201]:
            try:
                resp_json = json.loads(result['body'])
                share_id = resp_json.get('id', resp_json.get('share_id', resp_json.get('data', {}).get('id', '')))
                print(f'    🎉 成功！share_id={share_id}')
                
                # 立即取消投稿
                if share_id:
                    cancel_result = vidu_page.evaluate(f"""
                        async () => {{
                            try {{
                                const resp = await fetch('https://service.vidu.cn/vidu/v1/material/share_elements/{share_id}/cancel', {{
                                    credentials: 'include',
                                    method: 'POST',
                                    headers: {{ 'Content-Type': 'application/json' }},
                                    body: '{{}}'
                                }});
                                return {{ status: resp.status, body: await resp.text() }};
                            }} catch(e) {{ return {{ error: e.message }}; }}
                        }}
                    """)
                    print(f'    取消结果: [{cancel_result.get("status")}] {cancel_result.get("body", "")[:100]}')
            except:
                pass
            break  # 成功就不继续了
    
    # ============================================================
    # 第四步：JS 中搜索 submit 的调用代码
    # ============================================================
    print('\n' + '='*60)
    print('[4] 搜索 JS 中 submit 的实际调用代码...')
    
    # 搜索包含 share_elements 并且有 body 的代码段
    submit_calls = vidu_page.evaluate("""
        async () => {
            const results = [];
            const scripts = Array.from(document.querySelectorAll('script[src]'));
            const jsUrls = scripts.map(s => s.src).filter(u => u.includes('_next') || u.includes('chunk'));
            
            for (const url of jsUrls) {
                try {
                    const resp = await fetch(url);
                    const text = await resp.text();
                    
                    // 搜索包含 submit 调用的模式
                    // 投稿的调用可能类似: ep({body: {...}}) 或 submitShareElement({body: ...})
                    const patterns = [
                        'share_elements/submit',
                        'submitShareElement',
                        'handleSubmit',
                        'onSubmit',
                        'postCreation',
                        'shareCreation',
                    ];
                    
                    for (const pat of patterns) {
                        let startIdx = 0;
                        while (true) {
                            const idx = text.indexOf(pat, startIdx);
                            if (idx < 0) break;
                            
                            // 向前找到函数调用的开始
                            let funcStart = idx;
                            let braceCount = 0;
                            let inFunc = false;
                            
                            // 向后找完整的函数调用体（到下一个分号或匹配的大括号）
                            const ctx = text.substring(Math.max(0, idx - 400), Math.min(text.length, idx + 800));
                            
                            results.push({
                                file: url.split('/').pop().split('?')[0],
                                pattern: pat,
                                context: ctx
                            });
                            
                            startIdx = idx + pat.length;
                            if (results.length > 15) break;
                        }
                    }
                } catch(e) {}
            }
            return results;
        }
    """)
    
    if submit_calls:
        seen = set()
        for r in submit_calls:
            ctx = r['context'].replace('\n', ' ').replace('\r', '')
            key = ctx[:100]
            if key in seen:
                continue
            seen.add(key)
            print(f'\n  [{r["pattern"]}] in {r["file"]}:')
            print(f'    {ctx[:500]}')
    
    # ============================================================
    # 第五步：导航到创建页面，查看下载按钮的实际选项
    # ============================================================
    print('\n' + '='*60)
    print('[5] 导航到创建页面查看视频和下载选项...')
    
    # 导航到 text2video 页面
    vidu_page.goto('https://www.vidu.cn/create/text2video', wait_until='networkidle', timeout=30000)
    time.sleep(3)
    
    # 查找已完成的视频缩略图（通常在右侧历史面板）
    history_info = vidu_page.evaluate("""
        () => {
            const result = { videos: [], downloadBtns: [] };
            
            // 查找视频缩略图
            const videos = document.querySelectorAll('video');
            for (const v of videos) {
                const rect = v.getBoundingClientRect();
                if (rect.width > 30 && rect.height > 30) {
                    result.videos.push({
                        src: (v.src || v.currentSrc || '').slice(0, 100),
                        poster: (v.poster || '').slice(0, 100),
                        x: Math.round(rect.left + rect.width / 2),
                        y: Math.round(rect.top + rect.height / 2),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height)
                    });
                }
            }
            
            // 查找所有 SVG 图标按钮（可能是下载图标）
            const svgs = document.querySelectorAll('svg');
            for (const svg of svgs) {
                const btn = svg.closest('button, [role="button"], a');
                if (!btn) continue;
                const rect = btn.getBoundingClientRect();
                if (rect.width === 0) continue;
                
                const ariaLabel = btn.getAttribute('aria-label') || '';
                const title = btn.getAttribute('title') || '';
                const text = btn.textContent?.trim() || '';
                const pathD = svg.querySelector('path')?.getAttribute('d') || '';
                
                // 匹配可能的下载图标
                if (ariaLabel.includes('download') || title.includes('download') || 
                    ariaLabel.includes('下载') || title.includes('下载') ||
                    text.includes('下载') || text.includes('download') ||
                    pathD.includes('M12 16') || pathD.includes('M19 9h-4V3H9v6H5')) {
                    result.downloadBtns.push({
                        text: text.slice(0, 30),
                        ariaLabel: ariaLabel,
                        title: title,
                        x: Math.round(rect.left + rect.width / 2),
                        y: Math.round(rect.top + rect.height / 2),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height)
                    });
                }
            }
            
            return result;
        }
    """)
    
    print(f'  视频元素: {len(history_info.get("videos", []))}')
    for v in history_info.get('videos', []):
        print(f'    {v["w"]}x{v["h"]} at ({v["x"]}, {v["y"]}) src={v["src"][:60]}')
    
    print(f'  下载按钮: {len(history_info.get("downloadBtns", []))}')
    for b in history_info.get('downloadBtns', []):
        print(f'    "{b["text"]}" aria="{b["ariaLabel"]}" at ({b["x"]}, {b["y"]})')
    
    # 如果有视频，尝试悬停触发下载按钮
    videos = history_info.get('videos', [])
    if videos:
        target_vid = videos[0]
        print(f'\n  悬停视频: ({target_vid["x"]}, {target_vid["y"]})')
        vidu_page.mouse.move(target_vid['x'], target_vid['y'])
        time.sleep(2)
        
        # 再查找一次下载按钮（悬停后可能出现）
        hover_btns = vidu_page.evaluate("""
            () => {
                const btns = [];
                const allBtns = document.querySelectorAll('button, [role="button"]');
                for (const btn of allBtns) {
                    const rect = btn.getBoundingClientRect();
                    if (rect.width === 0) continue;
                    const text = btn.textContent?.trim() || '';
                    const ariaLabel = btn.getAttribute('aria-label') || '';
                    const title = btn.getAttribute('title') || '';
                    btns.push({
                        text: text.slice(0, 30),
                        ariaLabel: ariaLabel,
                        title: title,
                        x: Math.round(rect.left + rect.width / 2),
                        y: Math.round(rect.top + rect.height / 2),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height),
                        visible: rect.width > 0 && rect.height > 0
                    });
                }
                return btns.filter(b => b.visible);
            }
        """)
        
        print(f'  悬停后按钮: {len(hover_btns)}')
        # 显示附近的按钮（靠近视频位置的）
        nearby = [b for b in hover_btns if abs(b['x'] - target_vid['x']) < 200 and abs(b['y'] - target_vid['y']) < 200]
        for b in nearby:
            print(f'    "{b["text"]}" at ({b["x"]}, {b["y"]})')
    
    vidu_page.screenshot(path='debug_create_page.png')
    print('  已截图 debug_create_page.png')
    
    pw.stop()
    print('\n[完成]')


if __name__ == '__main__':
    main()
