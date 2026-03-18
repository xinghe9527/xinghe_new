"""专注测试：URL替换+全球版+token获取"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 先回到我的创作页面
        await page.goto("https://www.vidu.cn/create", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(2)

        # 1. 找到token（可能在localStorage/sessionStorage而非cookie）
        print("=" * 60)
        print("[1] 寻找auth token...")
        
        token_info = await page.evaluate("""() => {
            const result = {};
            // 检查localStorage
            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                const val = localStorage.getItem(key);
                if (key.toLowerCase().includes('token') || key.toLowerCase().includes('auth') || key.toLowerCase().includes('session')) {
                    result['ls_' + key] = val?.substring(0, 100);
                }
            }
            // sessionStorage
            for (let i = 0; i < sessionStorage.length; i++) {
                const key = sessionStorage.key(i);
                const val = sessionStorage.getItem(key);
                if (key.toLowerCase().includes('token') || key.toLowerCase().includes('auth')) {
                    result['ss_' + key] = val?.substring(0, 100);
                }
            }
            // cookies
            result.cookies = document.cookie.substring(0, 200);
            return result;
        }""")
        print(f"  {json.dumps(token_info, indent=2, ensure_ascii=False)}")

        # 2. 通过拦截网络请求获取token
        print("\n" + "=" * 60)
        print("[2] 拦截API请求获取Authorization header...")
        
        auth_token = None
        async def capture_auth(route, request):
            nonlocal auth_token
            headers = request.headers
            if 'authorization' in headers:
                auth_token = headers['authorization']
            await route.continue_()
        
        await page.route("**/vidu/v1/**", capture_auth)
        
        # 触发一个API请求
        await page.evaluate("""() => {
            fetch('/api/vidu/v1/user').catch(() => {});
        }""")
        await asyncio.sleep(2)
        
        # 也可以直接从CDP获取cookies
        cdp_session = await ctx.new_cdp_session(page)
        cookies = await cdp_session.send("Network.getAllCookies")
        token_cookies = [c for c in cookies.get('cookies', []) if 'token' in c['name'].lower() or 'auth' in c['name'].lower()]
        print(f"  CDP cookies with token/auth:")
        for c in token_cookies:
            print(f"    {c['name']} = {c['value'][:80]}... (domain={c['domain']})")
        
        await page.unroute("**/vidu/v1/**")

        # 如果没找到token，从请求头中获取
        if not auth_token:
            print("  尝试从网络请求中获取...")
            request_data = []
            async def on_request(request):
                if 'vidu' in request.url and 'authorization' in {k.lower(): v for k, v in request.headers.items()}:
                    request_data.append({
                        'url': request.url[:100],
                        'auth': request.headers.get('authorization', '')[:80]
                    })
            
            page.on("request", on_request)
            await page.reload(wait_until="networkidle", timeout=30000)
            await asyncio.sleep(3)
            page.remove_listener("request", on_request)
            
            if request_data:
                auth_token = request_data[0]['auth']
                print(f"  从网络请求获取到token: {auth_token[:60]}...")
            else:
                print("  未找到token")

        if not auth_token:
            # 最后尝试：直接从所有cookie中找
            all_cookies = {c['name']: c['value'][:80] for c in cookies.get('cookies', [])}
            print(f"  所有cookies: {list(all_cookies.keys())}")
            # 也许token在httpOnly cookie中
            for c in cookies.get('cookies', []):
                if len(c['value']) > 100:  # 长值可能是JWT
                    print(f"  长cookie: {c['name']} = {c['value'][:60]}... (len={len(c['value'])})")
            
            # 直接用fetch看看能不能成功（浏览器会自动带cookie）
            print("  尝试浏览器内fetch...")
            api_test = await page.evaluate("""async () => {
                try {
                    const r = await fetch('https://service.vidu.cn/vidu/v1/tasks?limit=1');
                    return {status: r.status, ok: r.ok};
                } catch(e) {
                    return {error: e.message};
                }
            }""")
            print(f"  直接fetch结果: {api_test}")

        # 3. 用获取到的token或浏览器fetch测试URL替换
        print("\n" + "=" * 60)
        print("[3] 测试URL替换（去掉watermarked）...")
        
        url_test = await page.evaluate("""async () => {
            // 先获取一个creation的URL
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks?limit=1');
            if (!r.ok) return {error: 'tasks API failed: ' + r.status};
            const data = await r.json();
            const creation = data.tasks?.[0]?.creations?.[0];
            if (!creation) return {error: 'no creation'};
            
            const uri = creation.uri || '';
            const results = {
                original_uri: uri.substring(0, 120),
                nomark_uri: creation.nomark_uri || '(empty)'
            };
            
            // 尝试替换URL路径中的watermarked.mp4
            if (uri.includes('watermarked')) {
                const variants = {
                    'output.mp4': uri.replace('watermarked.mp4', 'output.mp4'),
                    'video.mp4': uri.replace('watermarked.mp4', 'video.mp4'),
                    'original.mp4': uri.replace('watermarked.mp4', 'original.mp4'),
                    'result.mp4': uri.replace('watermarked.mp4', 'result.mp4'),
                    'no_suffix': uri.replace('/watermarked.mp4', '.mp4'),
                    'merged.mp4': uri.replace('watermarked.mp4', 'merged.mp4'),
                };
                
                for (const [name, url] of Object.entries(variants)) {
                    try {
                        const resp = await fetch(url, {method: 'HEAD'});
                        results[name] = {status: resp.status, contentLength: resp.headers.get('content-length')};
                    } catch(e) {
                        results[name] = {error: e.message};
                    }
                }
            }
            
            return results;
        }""")
        print(f"  {json.dumps(url_test, indent=2, ensure_ascii=False)}")

        # 4. 试试访问vidu.studio
        print("\n" + "=" * 60)
        print("[4] 测试全球版 vidu.studio...")
        
        global_test = await page.evaluate("""async () => {
            const results = {};
            
            // 直接fetch全球版API（可能CORS挡住）
            try {
                const r = await fetch('https://service.vidu.studio/vidu/v1/tasks?limit=1');
                results.global_tasks = {status: r.status};
            } catch(e) {
                results.global_tasks_error = e.message;
            }
            
            return results;
        }""")
        print(f"  {json.dumps(global_test, indent=2, ensure_ascii=False)}")

        # 5. 分析 watermark mode function e5
        print("\n" + "=" * 60)
        print("[5] 解析watermarkMode函数 e5...")
        
        e5_code = await page.evaluate("""async () => {
            const scripts = performance.getEntriesByType('resource')
                .filter(r => r.name.includes('3204'));
            const results = [];
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    
                    // 找e5函数定义
                    const idx = text.indexOf('watermarkMode:e5');
                    if (idx > -1) {
                        // 往前搜索e5的定义
                        // e5 = ... 或 let e5 = 或 const e5 =
                        let searchStart = Math.max(0, idx - 5000);
                        let chunk = text.substring(searchStart, idx);
                        
                        // 从后往前找 e5= 或 e5 =
                        let defIdx = chunk.lastIndexOf('e5=');
                        if (defIdx === -1) defIdx = chunk.lastIndexOf('e5 =');
                        
                        if (defIdx > -1) {
                            results.push({
                                type: 'e5_definition',
                                code: chunk.substring(defIdx, Math.min(chunk.length, defIdx + 500))
                            });
                        }
                        
                        // 也展示使用上下文
                        results.push({
                            type: 'e5_usage',
                            code: text.substring(idx - 200, idx + 300)
                        });
                    }
                    
                    // 找download组件中的watermark mode判断逻辑
                    const wmIdx = text.indexOf('watermarkMode');
                    if (wmIdx > -1) {
                        let search = text.substring(wmIdx, Math.min(text.length, wmIdx + 2000));
                        // 找switch或if语句判断watermarkMode的值
                        let cases = [];
                        let pos = 0;
                        while ((pos = search.indexOf('watermarkMode', pos + 1)) !== -1) {
                            cases.push(search.substring(pos - 50, pos + 100));
                        }
                        if (cases.length > 0) {
                            results.push({type: 'watermarkMode_cases', cases: cases.slice(0, 5)});
                        }
                    }
                } catch(e) {}
            }
            return results;
        }""")
        
        for r in e5_code:
            print(f"\n  [{r.get('type')}]:")
            if 'code' in r:
                print(f"    {r['code'][:400]}")
            if 'cases' in r:
                for c in r['cases']:
                    print(f"    {c}")

        # 6. 搜索所有JS中的download dialog实现
        print("\n" + "=" * 60)
        print("[6] 找下载对话框的具体实现...")
        
        dl_impl = await page.evaluate("""async () => {
            const results = [];
            const scripts = performance.getEntriesByType('resource').filter(r => r.name.includes('.js'));
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    
                    // 找 watermarkOnly/both/none 这些mode的处理
                    for (const mode of ['watermarkOnly', '"single"', '"none"', '"both"']) {
                        let idx = text.indexOf(mode);
                        while (idx > -1) {
                            const ctx = text.substring(Math.max(0, idx - 150), Math.min(text.length, idx + 200));
                            if (ctx.includes('download') || ctx.includes('watermark') || ctx.includes('nomark') || ctx.includes('uri')) {
                                results.push({mode: mode, file: s.name.split('/').pop(), code: ctx});
                            }
                            idx = text.indexOf(mode, idx + 1);
                            if (results.length > 20) break;
                        }
                        if (results.length > 20) break;
                    }
                } catch(e) {}
                if (results.length > 20) break;
            }
            return results.slice(0, 10);
        }""")
        
        for r in dl_impl:
            print(f"\n  [{r['mode']}] in {r['file']}:")
            print(f"    {r['code'][:300]}")

        print("\n[完成]")

asyncio.run(main())
