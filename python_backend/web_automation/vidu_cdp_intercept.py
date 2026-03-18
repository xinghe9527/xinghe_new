"""CDP低层拦截+直接URL替换测试"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]
        
        # 确保在vidu页面
        if 'vidu' not in page.url:
            await page.goto("https://www.vidu.cn/create", wait_until="networkidle", timeout=30000)
            await asyncio.sleep(2)

        cdp = await ctx.new_cdp_session(page)

        # 1. 使用CDP Network拦截获取真实请求头
        print("=" * 60)
        print("[1] CDP Network拦截...")
        
        captured = []
        
        def on_request(params):
            url = params.get('request', {}).get('url', '')
            if 'service.vidu.cn' in url:
                headers = params.get('request', {}).get('headers', {})
                auth = headers.get('Authorization', headers.get('authorization', ''))
                cookie = headers.get('Cookie', headers.get('cookie', ''))
                captured.append({
                    'url': url[:120],
                    'method': params.get('request', {}).get('method', ''),
                    'auth': auth[:100] if auth else '(none)',
                    'cookie_keys': [c.split('=')[0].strip() for c in cookie.split(';')[:10]] if cookie else []
                })
        
        cdp.on("Network.requestWillBeSent", on_request)
        await cdp.send("Network.enable")
        
        # 触发页面刷新
        await page.goto("https://www.vidu.cn/create", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(5)
        
        await cdp.send("Network.disable")
        
        print(f"  拦截到 {len(captured)} 个请求")
        auth_token = None
        for c in captured[:20]:
            print(f"  [{c['method']}] {c['url'][:100]}")
            if c['auth'] != '(none)':
                print(f"    Auth: {c['auth']}")
                if not auth_token:
                    auth_token = c['auth'].replace('Bearer ', '')
            if c['cookie_keys']:
                print(f"    Cookies: {c['cookie_keys']}")

        # 2. 用获取到的token调用关键API
        print("\n" + "=" * 60)
        
        if auth_token:
            print(f"[2] 用token调用API: {auth_token[:50]}...")
            
            # 试不同的API路径
            endpoints = [
                '/vidu/v1/tasks?limit=1',
                '/vidu/v1/tasks?pager.page_sz=1',
                '/iam/v1/users/me',
                '/vidu/v1/region',
            ]
            
            for ep in endpoints:
                result = await page.evaluate("""async (args) => {
                    const [token, endpoint] = args;
                    try {
                        const r = await fetch('https://service.vidu.cn' + endpoint, {
                            headers: {'Authorization': 'Bearer ' + token}
                        });
                        const text = await r.text();
                        return {endpoint: endpoint, status: r.status, body: text.substring(0, 300)};
                    } catch(e) {
                        return {endpoint: endpoint, error: e.message};
                    }
                }""", [auth_token, ep])
                print(f"  {result.get('endpoint')}: [{result.get('status', 'err')}] {result.get('body', result.get('error', ''))[:200]}")

        # 3. 尝试找到creation的视频URL并测试路径替换
        print("\n" + "=" * 60)
        print("[3] 通过页面内JS获取视频URL并替换测试...")
        
        # 从页面上的视频元素获取URL
        video_urls = await page.evaluate("""() => {
            const videos = document.querySelectorAll('video');
            const srcs = [];
            videos.forEach(v => {
                if (v.src) srcs.push(v.src);
                v.querySelectorAll('source').forEach(s => {
                    if (s.src) srcs.push(s.src);
                });
            });
            // 也从网络请求缓存中获取
            const entries = performance.getEntriesByType('resource')
                .filter(r => r.name.includes('.mp4') || r.name.includes('infer'));
            entries.forEach(e => srcs.push(e.name));
            return [...new Set(srcs)];
        }""")
        
        print(f"  找到 {len(video_urls)} 个视频URL:")
        for url in video_urls[:5]:
            print(f"    {url[:150]}")
        
        # 对每个URL尝试替换
        if video_urls:
            test_url = video_urls[0]
            print(f"\n  测试URL替换 (基于第一个URL):")
            
            replacements = {}
            if 'watermarked.mp4' in test_url:
                base = test_url.replace('watermarked.mp4', '')
                replacements = {
                    'watermarked.mp4': test_url,
                    'output.mp4': base + 'output.mp4',
                    'video.mp4': base + 'video.mp4',
                    'original.mp4': base + 'original.mp4',
                    'result.mp4': base + 'result.mp4',
                    'merged.mp4': base + 'merged.mp4',
                    'nomark.mp4': base + 'nomark.mp4',
                }
            elif '-wm.mp4' in test_url:
                base = test_url.replace('-wm.mp4', '')
                replacements = {
                    '-wm.mp4': test_url,
                    '.mp4': base + '.mp4',
                    '-nomark.mp4': base + '-nomark.mp4',
                    '-clean.mp4': base + '-clean.mp4',
                }
            elif 'wm.mp4' in test_url or 'propogated-wm' in test_url:
                base = test_url.split('?')[0]
                query = '?' + test_url.split('?')[1] if '?' in test_url else ''
                variants_base = base.rsplit('/', 1)[0] + '/'
                fname = base.rsplit('/', 1)[1]
                replacements = {
                    'original': test_url,
                    'video.mp4': variants_base + 'video.mp4' + query,
                    'output.mp4': variants_base + 'output.mp4' + query,
                    'result.mp4': variants_base + 'result.mp4' + query,
                    'nomark.mp4': variants_base + 'nomark.mp4' + query,
                    fname.replace('-wm', ''): variants_base + fname.replace('-wm', '') + query,
                    fname.replace('propogated-wm', 'propogated'): variants_base + fname.replace('propogated-wm', 'propogated') + query,
                }
            else:
                print(f"  URL格式不包含已知水印标识: {test_url[:100]}")
            
            for name, url in replacements.items():
                try:
                    result = await page.evaluate("""async (url) => {
                        try {
                            const r = await fetch(url, {method: 'HEAD'});
                            return {status: r.status, size: r.headers.get('content-length'), type: r.headers.get('content-type')};
                        } catch(e) {
                            return {error: e.message};
                        }
                    }""", url)
                    status = result.get('status', 'err')
                    size = result.get('size', '?')
                    marker = " ✅ 可访问!" if status == 200 else ""
                    print(f"    {name}: [{status}] size={size}{marker}")
                except Exception as e:
                    print(f"    {name}: 错误 {e}")

        # 4. 导航到my-creations，看看能不能看到自己的创作
        print("\n" + "=" * 60)
        print("[4] 检查 my-creations 页面...")
        
        await page.goto("https://www.vidu.cn/my-creations", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(3)
        print(f"  当前URL: {page.url}")
        
        # 查看页面内容
        page_info = await page.evaluate("""() => {
            const h1s = document.querySelectorAll('h1, h2, h3');
            const texts = Array.from(h1s).map(h => h.textContent?.trim());
            const videos = document.querySelectorAll('video');
            const imgs = document.querySelectorAll('img');
            const buttons = document.querySelectorAll('button');
            const allText = document.body?.innerText?.substring(0, 500) || '';
            return {
                headings: texts,
                videoCount: videos.length,
                imgCount: imgs.length,
                buttonCount: buttons.length,
                bodyText: allText
            };
        }""")
        print(f"  标题: {page_info.get('headings')}")
        print(f"  视频: {page_info.get('videoCount')}, 图片: {page_info.get('imgCount')}")
        print(f"  页面文本: {page_info.get('bodyText', '')[:300]}")

        # 5. 从create页面找到自己生成的任务
        print("\n" + "=" * 60)
        print("[5] 回到create页面找自己的任务...")
        
        await page.goto("https://www.vidu.cn/create", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(3)
        
        # 拦截tasks API响应
        cdp2 = await ctx.new_cdp_session(page)
        await cdp2.send("Network.enable")
        
        task_data = []
        def on_response(params):
            url = params.get('response', {}).get('url', '')
            if 'tasks' in url and 'service.vidu.cn' in url:
                task_data.append({
                    'url': url[:120],
                    'status': params.get('response', {}).get('status', 0),
                    'requestId': params.get('requestId', '')
                })
        
        cdp2.on("Network.responseReceived", on_response)
        
        # 触发任务列表加载
        await page.reload(wait_until="networkidle", timeout=30000)
        await asyncio.sleep(5)
        
        print(f"  tasks相关响应: {len(task_data)}")
        for td in task_data:
            print(f"    {td['url']} [{td['status']}]")
            # 尝试获取响应体
            try:
                body = await cdp2.send("Network.getResponseBody", {"requestId": td['requestId']})
                body_text = body.get('body', '')[:500]
                data = json.loads(body_text) if body_text else {}
                if 'tasks' in data:
                    for task in data['tasks'][:2]:
                        print(f"      task: {task.get('id')} type={task.get('type')} state={task.get('state')}")
                        for cr in task.get('creations', [])[:1]:
                            print(f"        creation: {cr.get('id')}")
                            print(f"        uri: {cr.get('uri', '')[:100]}")
                            print(f"        nomark_uri: {cr.get('nomark_uri') or '(empty)'}")
                else:
                    print(f"      body: {body_text[:200]}")
            except Exception as e:
                print(f"      获取body失败: {e}")
        
        await cdp2.send("Network.disable")

        print("\n[完成]")

asyncio.run(main())
