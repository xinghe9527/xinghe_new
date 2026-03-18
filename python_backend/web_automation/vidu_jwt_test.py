"""用JWT token测试API和URL替换"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 确保在vidu.cn
        if 'vidu.cn' not in page.url:
            await page.goto("https://www.vidu.cn/create", wait_until="networkidle", timeout=30000)
            await asyncio.sleep(2)

        # 1. 获取JWT token
        print("=" * 60)
        print("[1] 获取JWT token...")
        
        cdp = await ctx.new_cdp_session(page)
        cookies_data = await cdp.send("Network.getAllCookies")
        jwt_token = None
        for c in cookies_data.get('cookies', []):
            if c['name'] == 'JWT' and 'vidu' in c.get('domain', ''):
                jwt_token = c['value']
                print(f"  JWT token (domain={c['domain']}): {jwt_token[:60]}...")
                break
        
        if not jwt_token:
            # 在vidu.cn域名的cookies中找
            for c in cookies_data.get('cookies', []):
                if c['name'] == 'JWT':
                    jwt_token = c['value']
                    print(f"  JWT token (domain={c['domain']}): {jwt_token[:60]}...")
                    break
        
        if not jwt_token:
            # 尝试所有看起来像JWT的cookie
            for c in cookies_data.get('cookies', []):
                if c['value'].startswith('eyJ') and 'vidu' in c.get('domain', ''):
                    jwt_token = c['value']
                    print(f"  可能的JWT: {c['name']} (domain={c['domain']}): {jwt_token[:60]}...")
                    break

        if not jwt_token:
            print("  在CDP cookies中没找到VIDU JWT，尝试从页面JS获取...")
            # 尝试从页面的__NEXT_DATA__或window对象中获取
            token_from_page = await page.evaluate("""() => {
                // 尝试从__NEXT_DATA__
                const nd = window.__NEXT_DATA__;
                if (nd) {
                    const str = JSON.stringify(nd);
                    const match = str.match(/eyJ[A-Za-z0-9_-]+\\.eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+/);
                    if (match) return {source: '__NEXT_DATA__', token: match[0]};
                }
                
                // localStorage
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    const val = localStorage.getItem(key) || '';
                    if (val.startsWith('eyJ')) return {source: 'localStorage:' + key, token: val};
                    // 尝试JSON解析
                    try {
                        const obj = JSON.parse(val);
                        for (const [k, v] of Object.entries(obj)) {
                            if (typeof v === 'string' && v.startsWith('eyJ')) return {source: 'localStorage:' + key + '.' + k, token: v};
                        }
                    } catch(e) {}
                }
                
                return null;
            }""")
            if token_from_page:
                jwt_token = token_from_page['token']
                print(f"  从{token_from_page['source']}获取: {jwt_token[:60]}...")

        # 2. 用JWT调用VIDU API
        print("\n" + "=" * 60)
        print("[2] 用JWT调用tasks API...")
        
        if jwt_token:
            api_result = await page.evaluate("""async (token) => {
                try {
                    const r = await fetch('https://service.vidu.cn/vidu/v1/tasks?limit=1', {
                        headers: {
                            'Authorization': 'Bearer ' + token,
                            'Content-Type': 'application/json'
                        }
                    });
                    if (!r.ok) return {status: r.status, statusText: r.statusText};
                    const data = await r.json();
                    const task = data.tasks?.[0];
                    const creation = task?.creations?.[0];
                    return {
                        status: r.status,
                        task_id: task?.id,
                        creation_id: creation?.id,
                        uri: creation?.uri?.substring(0, 150),
                        nomark_uri: creation?.nomark_uri || '(empty)',
                        has_copyright: creation?.has_copyright,
                        type: task?.type,
                        state: task?.state,
                        subs_plan: data?.subs_plan
                    };
                } catch(e) {
                    return {error: e.message};
                }
            }""", jwt_token)
            print(f"  {json.dumps(api_result, indent=2, ensure_ascii=False)}")
            
            # 3. URL替换测试
            if api_result.get('uri') and 'watermarked' in str(api_result.get('uri', '')):
                print("\n" + "=" * 60)
                print("[3] 测试URL路径替换...")
                
                base_uri = api_result['uri']
                url_results = await page.evaluate("""async (uri) => {
                    const results = {};
                    const variants = {
                        'output.mp4': uri.replace('watermarked.mp4', 'output.mp4'),
                        'video.mp4': uri.replace('watermarked.mp4', 'video.mp4'),
                        'original.mp4': uri.replace('watermarked.mp4', 'original.mp4'),
                        'result.mp4': uri.replace('watermarked.mp4', 'result.mp4'),
                        'merged.mp4': uri.replace('watermarked.mp4', 'merged.mp4'),
                        'no_wm.mp4': uri.replace('watermarked.mp4', 'no_wm.mp4'),
                        'final.mp4': uri.replace('watermarked.mp4', 'final.mp4'),
                        'nomark.mp4': uri.replace('watermarked.mp4', 'nomark.mp4'),
                        'clean.mp4': uri.replace('watermarked.mp4', 'clean.mp4'),
                    };
                    
                    // 先检查原URL能否访问
                    try {
                        const full_uri = 'https://files.vidu.cn' + uri;
                        const r = await fetch(full_uri, {method: 'HEAD'});
                        results['original'] = {status: r.status, size: r.headers.get('content-length')};
                    } catch(e) {
                        results['original'] = {error: e.message};
                    }
                    
                    for (const [name, url] of Object.entries(variants)) {
                        try {
                            const full = 'https://files.vidu.cn' + url;
                            const r = await fetch(full, {method: 'HEAD'});
                            results[name] = {status: r.status, size: r.headers.get('content-length')};
                        } catch(e) {
                            results[name] = {error: e.message};
                        }
                    }
                    return results;
                }""", base_uri)
                print(f"  {json.dumps(url_results, indent=2, ensure_ascii=False)}")
        
        # 4. 检查eT变量（决定watermarkMode）
        print("\n" + "=" * 60)
        print("[4] 分析eT变量...")
        
        et_analysis = await page.evaluate("""async () => {
            const results = [];
            const scripts = performance.getEntriesByType('resource')
                .filter(r => r.name.includes('3204'));
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    
                    // 找eT的定义
                    // e5=e=>"china"===C.Ey&&("audio"===e||eT)?"watermarkOnly" 中的eT
                    const e5Idx = text.indexOf('e5=');
                    if (e5Idx > -1) {
                        // 往前搜索eT的赋值
                        let searchChunk = text.substring(Math.max(0, e5Idx - 3000), e5Idx);
                        
                        // 找 eT= 或 eT =
                        let defIdx = searchChunk.lastIndexOf('eT=');
                        if (defIdx === -1) defIdx = searchChunk.lastIndexOf('eT =');
                        
                        if (defIdx > -1) {
                            const ctx = searchChunk.substring(defIdx, Math.min(searchChunk.length, defIdx + 300));
                            results.push({type: 'eT_definition', code: ctx});
                        }
                        
                        // 也找 ,eT, 或 ;eT
                        let destructIdx = searchChunk.lastIndexOf(',eT');
                        if (destructIdx > -1) {
                            const ctx = searchChunk.substring(Math.max(0, destructIdx - 100), Math.min(searchChunk.length, destructIdx + 200));
                            results.push({type: 'eT_destructure', code: ctx});
                        }
                    }
                } catch(e) {}
            }
            return results;
        }""")
        for r in et_analysis:
            print(f"\n  [{r['type']}]:")
            print(f"    {r['code'][:400]}")

        # 5. 尝试直接导航到vidu.studio
        print("\n" + "=" * 60)
        print("[5] 尝试导航到 vidu.studio...")
        
        try:
            new_page = await ctx.new_page()
            await new_page.goto("https://www.vidu.studio/create", wait_until="networkidle", timeout=30000)
            print(f"  导航成功: {new_page.url}")
            
            # 检查是否登录
            studio_user = await new_page.evaluate("""async () => {
                try {
                    // 从cookie获取token
                    const cookies = document.cookie;
                    const jwtMatch = cookies.match(/JWT=([^;]+)/);
                    if (jwtMatch) {
                        const r = await fetch('https://service.vidu.studio/vidu/v1/user', {
                            headers: {'Authorization': 'Bearer ' + jwtMatch[1]}
                        });
                        if (r.ok) return await r.json();
                        return {status: r.status};
                    }
                    return {cookies: cookies.substring(0, 200)};
                } catch(e) {
                    return {error: e.message};
                }
            }""")
            print(f"  vidu.studio用户: {json.dumps(studio_user, indent=2, ensure_ascii=False)}")
            
            await new_page.close()
        except Exception as e:
            print(f"  导航失败: {e}")

        # 6. 发现：从浏览器请求中拦截到真正的API调用
        print("\n" + "=" * 60)
        print("[6] 刷新页面拦截所有API请求，找到token...")
        
        api_calls = []
        async def capture_all(request):
            url = request.url
            if 'service.vidu.cn' in url:
                auth = request.headers.get('authorization', '')
                api_calls.append({
                    'url': url[:120],
                    'method': request.method,
                    'auth': auth[:80] if auth else '(none)'
                })
        
        page.on("request", capture_all)
        await page.goto("https://www.vidu.cn/create", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(5)
        page.remove_listener("request", capture_all)
        
        print(f"  拦截到 {len(api_calls)} 个API请求:")
        for call in api_calls[:15]:
            print(f"    [{call['method']}] {call['url'][:100]}")
            if call['auth'] != '(none)':
                print(f"         Auth: {call['auth']}")

        print("\n[完成]")

asyncio.run(main())
