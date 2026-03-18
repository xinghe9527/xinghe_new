"""找到正确的API路径：/vidu/v1/material/share_elements/
调用 /my 获取用户的已发布作品，检查nomark_uri
"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        await page.goto("https://www.vidu.cn/create", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(2)

        # 1. 获取用户自己的share_elements
        print("=" * 60)
        print("[1] 调用 /material/share_elements/my ...")
        
        my_shares = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/material/share_elements/my', {credentials: 'include'});
            const text = await r.text();
            return {status: r.status, body: text};
        }""")
        print(f"  状态: {my_shares['status']}")
        body_text = my_shares['body']
        print(f"  响应: {body_text[:2000]}")
        
        # 解析JSON找视频URL
        try:
            data = json.loads(body_text)
            if isinstance(data, dict) and 'share_elements' in data:
                print(f"\n  找到 {len(data['share_elements'])} 个share_elements:")
                for se in data['share_elements']:
                    print(f"\n  --- share_element ---")
                    print(f"    id: {se.get('id')}")
                    print(f"    state: {se.get('state')}")
                    print(f"    type: {se.get('type')}")
                    # 深层遍历找所有uri
                    def find_uris(obj, prefix=""):
                        if isinstance(obj, dict):
                            for k, v in obj.items():
                                if isinstance(v, str) and ('uri' in k.lower() or 'url' in k.lower()):
                                    # 只打印视频相关的
                                    print(f"    {prefix}{k}: {v[:150]}")
                                elif isinstance(v, (dict, list)):
                                    find_uris(v, prefix + k + ".")
                        elif isinstance(obj, list):
                            for i, item in enumerate(obj):
                                find_uris(item, prefix + f"[{i}].")
                    find_uris(se)
        except json.JSONDecodeError:
            print("  (非JSON响应)")

        # 2. 获取share_elements的详细信息
        print("\n" + "=" * 60)
        print("[2] 获取share_element详情...")
        
        share_ids = []
        try:
            data = json.loads(body_text)
            if isinstance(data, dict) and 'share_elements' in data:
                share_ids = [se['id'] for se in data['share_elements'] if se.get('id')]
        except:
            pass
        
        if not share_ids:
            # 使用从profile页面获取的ID
            share_ids = ["3210244702221402", "3210273079224399"]
        
        for sid in share_ids[:2]:
            print(f"\n  --- share_element {sid} ---")
            detail = await page.evaluate("""async (shareId) => {
                // 尝试多种获取详情的方式
                const paths = [
                    `/vidu/v1/material/share_elements/${shareId}`,
                    `/vidu/v1/material/share_elements/detail/${shareId}`,
                ];
                const results = {};
                for (const path of paths) {
                    try {
                        const r = await fetch('https://service.vidu.cn' + path, {credentials: 'include'});
                        const text = await r.text();
                        results[path] = {status: r.status, body: text.substring(0, 1500)};
                    } catch(e) {
                        results[path] = {error: e.message};
                    }
                }
                return results;
            }""", sid)
            
            for path, d in detail.items():
                status = d.get('status', 'err')
                print(f"  {path}: [{status}]")
                if status == 200:
                    print(f"    {d['body'][:1500]}")

        # 3. 也看看feed接口
        print("\n" + "=" * 60)
        print("[3] feed接口...")
        
        feed_result = await page.evaluate("""async () => {
            const paths = [
                '/vidu/v1/material/share_elements/feed?pager.page_sz=2',
                '/vidu/v1/material/share_elements/feed?pager.page_sz=2&type=video',
            ];
            const results = {};
            for (const path of paths) {
                try {
                    const r = await fetch('https://service.vidu.cn' + path, {credentials: 'include'});
                    const text = await r.text();
                    results[path] = {status: r.status, body: text.substring(0, 300)};
                } catch(e) {
                    results[path] = {error: e.message};
                }
            }
            return results;
        }""")
        
        for path, d in feed_result.items():
            status = d.get('status', 'err')
            print(f"  {path}: [{status}] {d.get('body', '')[:200]}")

        # 4. 用persona接口获取用户的发布
        print("\n" + "=" * 60)
        print("[4] persona接口...")
        
        # 获取用户ID
        user_id = "3209556353473214"  # 从profile页面URL获取的
        
        persona_result = await page.evaluate("""async (userId) => {
            const r = await fetch(`https://service.vidu.cn/vidu/v1/material/share_elements/persona/${userId}`, {credentials: 'include'});
            const text = await r.text();
            return {status: r.status, body: text};
        }""", user_id)
        
        print(f"  状态: {persona_result['status']}")
        body = persona_result['body']
        print(f"  响应: {body[:3000]}")
        
        # 解析找video URL
        try:
            data = json.loads(body)
            if isinstance(data, dict) and 'share_elements' in data:
                for se in data['share_elements']:
                    print(f"\n  share_element {se.get('id')}:")
                    # 找所有包含uri的字段
                    def deep_find(obj, path=""):
                        if isinstance(obj, dict):
                            for k, v in obj.items():
                                full = f"{path}.{k}" if path else k
                                if isinstance(v, str) and ('uri' in k.lower() or 'url' in k.lower() or 'src' in k.lower()):
                                    has_wm = '-wm' in v or 'watermark' in v.lower()
                                    label = " [WM!]" if has_wm else " [NO-WM?]"
                                    if 'mp4' in v or 'video' in v or 'cover' in v:
                                        print(f"    {full}: {v[:150]}{label}")
                                elif isinstance(v, (dict, list)):
                                    deep_find(v, full)
                        elif isinstance(obj, list):
                            for i, item in enumerate(obj):
                                deep_find(item, f"{path}[{i}]")
                    deep_find(se)
        except:
            pass

        # 5. 导航到feed-detail页面并用CDP监控实际加载的API
        print("\n" + "=" * 60)
        print("[5] 重新访问feed-detail，详细监控...")
        
        cdp = await ctx.new_cdp_session(page)
        await cdp.send("Network.enable")
        
        api_responses = {}
        
        async def capture_response(params):
            url = params.get('response', {}).get('url', '')
            if 'service.vidu.cn' in url and 'material' in url:
                request_id = params.get('requestId', '')
                api_responses[url] = {'status': params.get('response', {}).get('status', 0), 'requestId': request_id}
        
        cdp.on("Network.responseReceived", lambda params: asyncio.ensure_future(capture_response(params)) if 'service.vidu.cn' in params.get('response', {}).get('url', '') else None)
        
        await page.goto(f"https://www.vidu.cn/feed-detail/{share_ids[0] if share_ids else '3210244702221402'}", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(5)
        
        print(f"  URL: {page.url}")
        print(f"  Title: {await page.title()}")
        
        # 检查页面内容
        content = await page.evaluate("""() => {
            return {
                videos: document.querySelectorAll('video').length,
                bodyTextLen: document.body?.innerText?.length || 0,
                bodyFirst500: document.body?.innerText?.substring(0, 500) || '',
                allVideoSrc: Array.from(document.querySelectorAll('video')).map(v => v.src?.substring(0, 150) || 'empty'),
            };
        }""")
        print(f"  视频数: {content['videos']}")
        print(f"  文本长度: {content['bodyTextLen']}")
        print(f"  视频URL: {content['allVideoSrc']}")
        print(f"  内容: {content['bodyFirst500'][:300]}")
        
        # 打印捕获的API
        print(f"\n  捕获的material API:")
        for url, info in api_responses.items():
            print(f"    [{info['status']}] {url[:200]}")

        print("\n[完成]")

asyncio.run(main())
