"""用CDP全面监控feed-detail页面的加载过程"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]
        cdp = await ctx.new_cdp_session(page)

        # 启用网络监控
        await cdp.send("Network.enable")
        
        all_requests = []
        all_responses = []
        
        def on_request(params):
            url = params.get('request', {}).get('url', '')
            if 'vidu' in url or 'files.vidu' in url:
                all_requests.append({
                    'url': url[:250],
                    'method': params.get('request', {}).get('method', ''),
                    'type': params.get('type', ''),
                })
        
        def on_response(params):
            url = params.get('response', {}).get('url', '')
            status = params.get('response', {}).get('status', 0)
            if 'service.vidu' in url or 'files.vidu' in url:
                all_responses.append({
                    'url': url[:250],
                    'status': status,
                })
        
        cdp.on("Network.requestWillBeSent", on_request)
        cdp.on("Network.responseReceived", on_response)

        feed_id = "3210244702221402"
        
        # 1. 先清空，然后导航
        print("=" * 60)
        print(f"[1] 导航到 feed-detail/{feed_id} 并监控网络...")
        
        await page.goto(f"https://www.vidu.cn/feed-detail/{feed_id}", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(5)
        
        print(f"  URL: {page.url}")
        print(f"  Title: {await page.title()}")
        
        # 检查页面内容
        page_html_len = await page.evaluate("document.documentElement.innerHTML.length")
        body_text = await page.evaluate("document.body?.innerText?.substring(0, 500) || ''")
        print(f"  HTML长度: {page_html_len}")
        print(f"  页面文字: {body_text[:300]}")
        
        # 打印所有API请求
        print(f"\n  API请求 ({len(all_requests)} 个):")
        for r in all_requests:
            if 'service.vidu.cn' in r['url']:
                print(f"    [{r['method']}] {r['url']}")
        
        print(f"\n  API响应 ({len(all_responses)} 个):")
        for r in all_responses:
            if 'service.vidu.cn' in r['url']:
                print(f"    [{r['status']}] {r['url']}")
        
        # 视频请求
        print(f"\n  视频/媒体请求:")
        for r in all_requests:
            if any(x in r['url'].lower() for x in ['.mp4', '.m3u8', 'video', 'media', 'files.vidu']):
                print(f"    [{r['method']}] {r['url']}")

        # 2. 检查页面是否有 iframe
        print("\n" + "=" * 60)
        print("[2] 检查iframe和视频容器...")
        
        iframe_info = await page.evaluate("""() => {
            const iframes = document.querySelectorAll('iframe');
            const videos = document.querySelectorAll('video');
            const canvases = document.querySelectorAll('canvas');
            return {
                iframes: Array.from(iframes).map(f => ({src: f.src?.substring(0, 100), w: f.clientWidth, h: f.clientHeight})),
                videos: videos.length,
                canvases: canvases.length,
                divCount: document.querySelectorAll('div').length,
                imgCount: document.querySelectorAll('img').length,
            };
        }""")
        print(f"  {json.dumps(iframe_info, indent=2, ensure_ascii=False)}")

        # 3. 也许feed-detail需要通过特定API获取数据
        print("\n" + "=" * 60)
        print("[3] 手动调用feed API...")
        
        # 从JS代码中找到的API模式
        apis_to_try = await page.evaluate("""async (feedId) => {
            const apis = [
                {url: `/vidu/v1/share_elements/${feedId}`, method: 'GET'},
                {url: `/vidu/v1/share_elements/detail?id=${feedId}`, method: 'GET'},
                {url: `/vidu/v1/feed/detail?id=${feedId}`, method: 'GET'},
                {url: `/vidu/v1/feed/elements/${feedId}`, method: 'GET'},
                {url: `/craftify/v1/media_asset/${feedId}`, method: 'GET'},
                {url: `/craftify/v1/media_asset/detail/${feedId}`, method: 'GET'},
                {url: `/craftify/v1/works/${feedId}`, method: 'GET'},
                {url: `/craftify/v1/works/detail/${feedId}`, method: 'GET'},
                {url: `/vidu/v1/share_elements?id=${feedId}`, method: 'GET'},
                // 社区feed API with type
                {url: `/vidu/v1/feed/list?type=video&limit=1&id=${feedId}`, method: 'GET'},
                {url: `/vidu/v1/feed/list?type=all&limit=1&element_id=${feedId}`, method: 'GET'},
            ];
            const results = {};
            for (const api of apis) {
                try {
                    const r = await fetch(`https://service.vidu.cn${api.url}`, {
                        method: api.method,
                        credentials: 'include'
                    });
                    const text = await r.text();
                    results[api.url] = {status: r.status, body: text.substring(0, 400)};
                } catch(e) {
                    results[api.url] = {error: e.message};
                }
            }
            return results;
        }""", feed_id)
        
        for path, data in apis_to_try.items():
            status = data.get('status', 'err')
            if status != 404:
                print(f"  ⭐ {path}: [{status}]")
                body = data.get('body', '')
                if body and status == 200:
                    print(f"    {body[:300]}")
            # 也打印404的
            else:
                print(f"  ❌ {path}: [404]")

        # 4. 看看JS代码中feed-detail页面用什么API
        print("\n" + "=" * 60)
        print("[4] 分析JS中的feed-detail API调用...")
        
        js_analysis = await page.evaluate("""async () => {
            // 获取所有JS文件
            const scripts = document.querySelectorAll('script[src]');
            const results = [];
            
            for (const s of scripts) {
                if (s.src.includes('_next/static')) {
                    try {
                        const r = await fetch(s.src);
                        const code = await r.text();
                        
                        // 搜索feed-detail或share_elements相关代码
                        if (code.includes('feed-detail') || code.includes('feed_detail') || 
                            code.includes('share_element') || code.includes('shareElement') ||
                            code.includes('craftify')) {
                            const filename = s.src.split('/').pop();
                            
                            // 提取相关代码片段
                            const patterns = ['feed-detail', 'feed_detail', 'share_element', 'shareElement', 'craftify', 'noWaterMark', 'waterMarkUri', 'nomark'];
                            const snippets = [];
                            
                            for (const pat of patterns) {
                                let idx = code.indexOf(pat);
                                while (idx !== -1 && snippets.length < 20) {
                                    const start = Math.max(0, idx - 50);
                                    const end = Math.min(code.length, idx + pat.length + 100);
                                    snippets.push({pattern: pat, context: code.substring(start, end)});
                                    idx = code.indexOf(pat, idx + 1);
                                }
                            }
                            
                            if (snippets.length > 0) {
                                results.push({file: filename, snippets: snippets});
                            }
                        }
                    } catch(e) {}
                }
            }
            return results;
        }""")
        
        for r in js_analysis:
            print(f"\n  文件: {r['file']}")
            for s in r['snippets'][:15]:
                print(f"    [{s['pattern']}] ...{s['context']}...")

        print("\n[完成]")

asyncio.run(main())
