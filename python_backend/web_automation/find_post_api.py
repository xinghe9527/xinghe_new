"""查找 VIDU 投稿/发布相关的 API 接口"""
import json
from playwright.sync_api import sync_playwright

with sync_playwright() as pw:
    browser = pw.chromium.connect_over_cdp('http://127.0.0.1:9223')
    ctx = browser.contexts[0]
    page = [p for p in ctx.pages if 'vidu' in p.url][0]
    
    # 搜索页面上的投稿/发布按钮
    result = page.evaluate("""
        () => {
            const patterns = [];
            const buttons = document.querySelectorAll('button, a, [role="button"]');
            for (const btn of buttons) {
                const text = btn.textContent?.trim() || '';
                if (text.includes('投稿') || text.includes('发布') || text.includes('Post') || 
                    text.includes('Publish') || text.includes('分享') || text.includes('下载')) {
                    patterns.push({
                        text: text.slice(0, 50),
                        tag: btn.tagName,
                        classes: (btn.className || '').slice(0, 80),
                    });
                }
            }
            
            // 搜索 __NEXT_DATA__
            const nextData = document.getElementById('__NEXT_DATA__');
            let apiHints = [];
            if (nextData) {
                const text = nextData.textContent || '';
                const apiMatches = text.match(/\\/vidu\\/v1\\/[a-zA-Z_\\/]+/g);
                if (apiMatches) {
                    apiHints = [...new Set(apiMatches)];
                }
            }
            
            return { buttons: patterns, apiHints: apiHints };
        }
    """)
    
    print('=== 投稿/发布/下载 按钮 ===')
    for btn in result.get('buttons', []):
        print(f"  [{btn['tag']}] \"{btn['text']}\" class={btn['classes'][:60]}")
    
    print()
    print('=== NEXT_DATA API 路径 ===')
    for api in result.get('apiHints', []):
        print(f'  {api}')
    
    # 尝试拦截投稿 API：搜索 JS bundle
    print()
    print('=== 搜索 JS 中的 post/publish API ===')
    
    # 通过 performance API 看已经请求过的 API
    perf_apis = page.evaluate("""
        () => {
            const entries = performance.getEntriesByType('resource');
            const apis = [];
            for (const e of entries) {
                if (e.name.includes('service.vidu') || e.name.includes('/vidu/v1/')) {
                    apis.push(e.name);
                }
            }
            return [...new Set(apis)];
        }
    """)
    
    print('=== 已请求的 VIDU API ===')
    for api in perf_apis:
        print(f'  {api[:150]}')
    
    # 尝试常见的投稿 API 路径
    print()
    print('=== 探测投稿相关 API ===')
    
    # 获取一个 creation_id 来测试
    d = json.load(open('vidu_api_response.json', 'r', encoding='utf-8'))
    tasks = d.get('tasks', [])
    creation = tasks[0].get('creations', [{}])[0] if tasks else {}
    creation_id = creation.get('id', '')
    task_id = creation.get('task_id', '')
    
    print(f'  测试用 creation_id: {creation_id}')
    print(f'  测试用 task_id: {task_id}')
    
    # 试探可能的 API
    test_apis = [
        ('GET', f'https://service.vidu.cn/vidu/v1/creations/{creation_id}'),
        ('GET', f'https://service.vidu.cn/vidu/v1/creations/{creation_id}/nomark'),
        ('GET', f'https://service.vidu.cn/vidu/v1/works'),
        ('GET', f'https://service.vidu.cn/vidu/v1/posts'),
        ('GET', f'https://service.vidu.cn/vidu/v1/user/info'),
        ('GET', f'https://service.vidu.cn/vidu/v1/user/membership'),
        ('GET', f'https://service.vidu.cn/vidu/v1/user/vip'),
    ]
    
    for method, url in test_apis:
        resp = page.evaluate(f"""
            async () => {{
                try {{
                    const resp = await fetch('{url}', {{ credentials: 'include' }});
                    let body = null;
                    try {{ body = await resp.json(); }} catch(e) {{}}
                    return {{ status: resp.status, url: '{url}', body: body }};
                }} catch(e) {{
                    return {{ error: e.message, url: '{url}' }};
                }}
            }}
        """)
        
        status = resp.get('status', '?')
        body = resp.get('body')
        print(f'  {method} {url.split("service.vidu.cn")[1] if "service.vidu.cn" in url else url}')
        print(f'    → {status}', end='')
        if body and isinstance(body, dict):
            # 简短显示
            body_str = json.dumps(body, ensure_ascii=False)
            if len(body_str) > 200:
                body_str = body_str[:200] + '...'
            print(f' | {body_str}')
        else:
            print(f' | {resp.get("error", "no body")}')
