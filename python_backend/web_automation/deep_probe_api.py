"""深入探测 VIDU API - 查看用户信息、订阅状态、投稿 API"""
import json
from playwright.sync_api import sync_playwright

with sync_playwright() as pw:
    browser = pw.chromium.connect_over_cdp('http://127.0.0.1:9223')
    ctx = browser.contexts[0]
    page = [p for p in ctx.pages if 'vidu' in p.url][0]
    
    # 获取 creation_id
    d = json.load(open('vidu_api_response.json', 'r', encoding='utf-8'))
    tasks = d.get('tasks', [])
    creation = tasks[0].get('creations', [{}])[0] if tasks else {}
    creation_id = creation.get('id', '')
    task_id = creation.get('task_id', '')
    
    # 探测已知存在的 API
    known_apis = [
        ('用户信息', 'GET', 'https://service.vidu.cn/iam/v1/users/me'),
        ('订阅状态', 'GET', 'https://service.vidu.cn/credit/v1/subscriptions/me'),
        ('积分信息', 'GET', 'https://service.vidu.cn/credit/v1/credits/me'),
        ('试用信息', 'GET', 'https://service.vidu.cn/credit/v1/trials/me/all'),
        ('任务详情', 'GET', f'https://service.vidu.cn/vidu/v1/tasks/{task_id}'),
        ('分享素材', 'GET', 'https://service.vidu.cn/vidu/v1/material/share_elements/last_reviewed'),
        ('灵感素材', 'GET', 'https://service.vidu.cn/vidu/v1/inspirations/media-assets'),
        ('推荐', 'GET', 'https://service.vidu.cn/vidu/vpp/v1/spotlights'),
    ]
    
    for label, method, url in known_apis:
        resp = page.evaluate(f"""
            async () => {{
                try {{
                    const resp = await fetch('{url}', {{ credentials: 'include' }});
                    let body = null;
                    try {{ body = await resp.json(); }} catch(e) {{}}
                    return {{ status: resp.status, body: body }};
                }} catch(e) {{
                    return {{ error: e.message }};
                }}
            }}
        """)
        
        status = resp.get('status', '?')
        body = resp.get('body')
        print(f'\n{"="*60}')
        print(f'📡 {label}: {method} ...{url.split("service.vidu.cn")[1]}')
        print(f'   状态: {status}')
        if body:
            body_str = json.dumps(body, ensure_ascii=False, indent=2)
            if len(body_str) > 1500:
                body_str = body_str[:1500] + '\n...(截断)'
            print(body_str)
    
    # 尝试找到投稿 API：搜索页面 JS 资源中的 API 路径
    print(f'\n{"="*60}')
    print('🔍 搜索 JS bundle 中的 work/post/share/submit API...')
    
    # 获取所有 JS 资源 URL
    js_urls = page.evaluate("""
        () => {
            const entries = performance.getEntriesByType('resource');
            return entries
                .filter(e => e.name.includes('.js') && e.name.includes('vidu'))
                .map(e => e.name)
                .slice(0, 5);
        }
    """)
    
    print(f'找到 {len(js_urls)} 个 VIDU JS 资源')
    
    # 尝试获取一个主要的 JS bundle 并搜索 API 路径
    if js_urls:
        for js_url in js_urls[:2]:
            print(f'\n检查: {js_url[-60:]}')
            # 在页面中 fetch JS 内容并搜索关键词
            api_paths = page.evaluate(f"""
                async () => {{
                    try {{
                        const resp = await fetch('{js_url}');
                        const text = await resp.text();
                        
                        // 搜索包含 post/work/share/publish/submit/material 的 API 路径
                        const patterns = [
                            /\\/vidu\\/v[0-9]+\\/[a-zA-Z_\\/]*(?:post|work|share|publish|submit|material|creation|nomark|download|watermark)[a-zA-Z_\\/]*/gi,
                            /\\/iam\\/v[0-9]+\\/[a-zA-Z_\\/]*(?:post|share|publish)[a-zA-Z_\\/]*/gi,
                        ];
                        
                        const found = [];
                        for (const p of patterns) {{
                            const matches = text.match(p);
                            if (matches) {{
                                found.push(...matches);
                            }}
                        }}
                        
                        // 搜索 nomark 关键词上下文
                        const nomarkIdx = text.indexOf('nomark');
                        let nomarkContext = '';
                        if (nomarkIdx >= 0) {{
                            nomarkContext = text.slice(Math.max(0, nomarkIdx - 100), nomarkIdx + 100);
                        }}
                        
                        // 搜索 watermark 关键词上下文
                        const wmIdx = text.indexOf('watermark');
                        let wmContext = '';
                        if (wmIdx >= 0) {{
                            wmContext = text.slice(Math.max(0, wmIdx - 100), wmIdx + 100);
                        }}
                        
                        return {{
                            apiPaths: [...new Set(found)],
                            nomarkContext: nomarkContext,
                            wmContext: wmContext,
                            hasPost: text.includes('/post'),
                            hasWork: text.includes('/work'),
                            hasShare: text.includes('share_element'),
                            hasNomark: text.includes('nomark'),
                        }};
                    }} catch(e) {{
                        return {{ error: e.message }};
                    }}
                }}
            """)
            
            if api_paths.get('error'):
                print(f'  ❌ {api_paths["error"]}')
                continue
            
            print(f'  hasPost={api_paths.get("hasPost")} hasWork={api_paths.get("hasWork")} hasShare={api_paths.get("hasShare")} hasNomark={api_paths.get("hasNomark")}')
            
            if api_paths.get('apiPaths'):
                print(f'  找到 API 路径:')
                for p in api_paths['apiPaths']:
                    print(f'    {p}')
            
            if api_paths.get('nomarkContext'):
                print(f'  nomark 上下文: {api_paths["nomarkContext"]}')
            
            if api_paths.get('wmContext'):
                print(f'  watermark 上下文: {api_paths["wmContext"]}')
