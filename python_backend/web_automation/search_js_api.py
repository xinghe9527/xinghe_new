"""搜索所有VIDU JS chunk中的水印/投稿相关API路径"""
import json
from playwright.sync_api import sync_playwright

with sync_playwright() as pw:
    browser = pw.chromium.connect_over_cdp('http://127.0.0.1:9223')
    ctx = browser.contexts[0]
    page = [p for p in ctx.pages if 'vidu' in p.url][0]
    
    # 获取所有 JS chunk URLs
    all_js = page.evaluate("""
        () => {
            const entries = performance.getEntriesByType('resource');
            return entries
                .filter(e => e.name.endsWith('.js'))
                .map(e => e.name);
        }
    """)
    
    print(f'找到 {len(all_js)} 个 JS 文件')
    
    # 搜索每个 JS 文件中的关键词
    keywords_found = {}
    
    for i, js_url in enumerate(all_js):
        result = page.evaluate(f"""
            async () => {{
                try {{
                    const resp = await fetch('{js_url}');
                    const text = await resp.text();
                    
                    const findings = {{}};
                    
                    // 搜索关键词及其上下文
                    const searchTerms = ['nomark', 'watermark', 'share_element', 'is_work', 'is_posted', 'post_creation', 'submit_work'];
                    
                    for (const term of searchTerms) {{
                        const idx = text.indexOf(term);
                        if (idx >= 0) {{
                            findings[term] = text.slice(Math.max(0, idx - 80), idx + 80);
                        }}
                    }}
                    
                    // 特别搜索 API 路径
                    const apiMatches = text.match(/\\/vidu\\/v[0-9]+\\/[a-zA-Z\\/_-]+/g);
                    const uniqueApis = apiMatches ? [...new Set(apiMatches)] : [];
                    
                    // 搜索包含 work/post/share 的 API
                    const relevantApis = uniqueApis.filter(a => 
                        a.includes('work') || a.includes('post') || a.includes('share') || 
                        a.includes('creation') || a.includes('nomark') || a.includes('material') ||
                        a.includes('download')
                    );
                    
                    if (Object.keys(findings).length > 0 || relevantApis.length > 0) {{
                        return {{
                            url: '{js_url}'.slice(-60),
                            findings: findings,
                            relevantApis: relevantApis,
                            allApis: uniqueApis,
                        }};
                    }}
                    return null;
                }} catch(e) {{
                    return null;
                }}
            }}
        """)
        
        if result:
            print(f'\n{"="*60}')
            print(f'📦 JS: ...{result["url"]}')
            
            if result.get('findings'):
                print(f'  🔍 关键词匹配:')
                for term, ctx in result['findings'].items():
                    # 清理上下文中的不可见字符
                    ctx_clean = ctx.replace('\n', ' ').replace('\r', '')
                    print(f'    [{term}]: ...{ctx_clean}...')
            
            if result.get('relevantApis'):
                print(f'  📡 相关 API:')
                for api in result['relevantApis']:
                    print(f'    {api}')
            
            if result.get('allApis'):
                print(f'  📋 所有 API ({len(result["allApis"])} 个):')
                for api in result['allApis']:
                    print(f'    {api}')
