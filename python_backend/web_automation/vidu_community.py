"""深入分析：
1. 社区feed中视频的实际URL格式
2. craftify路径下的文件名模式
3. feed-detail页面为何报错
"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]
        cdp = await ctx.new_cdp_session(page)
        await cdp.send("Network.enable")
        
        captured_urls = []
        
        def on_request(params):
            url = params.get('request', {}).get('url', '')
            if 'files.vidu' in url and '.mp4' in url:
                captured_urls.append(url)
        
        cdp.on("Network.requestWillBeSent", on_request)

        # 1. 访问社区/探索页面
        print("=" * 60)
        print("[1] 访问社区/探索页面，看别人的视频URL...")
        
        await page.goto("https://www.vidu.cn/explore", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(5)
        
        explore_videos = await page.evaluate("""() => {
            const videos = document.querySelectorAll('video');
            return Array.from(videos).map(v => ({
                src: v.src || '',
                width: v.videoWidth,
                height: v.videoHeight,
            })).slice(0, 5);
        }""")
        
        print(f"  探索页视频数: {len(explore_videos)}")
        for i, v in enumerate(explore_videos[:5]):
            src = v['src']
            has_wm = '-wm' in src or 'watermark' in src.lower()
            print(f"  视频{i+1}: {'[WM]' if has_wm else '[NO-WM]'} {src[:150]}")

        # 2. 在探索页面点击一个视频看详情
        print("\n" + "=" * 60)
        print("[2] 点击探索页面的视频进入详情...")
        
        # 找到链接
        feed_links = await page.evaluate("""() => {
            return Array.from(document.querySelectorAll('a[href*="feed-detail"]'))
                .map(a => a.href)
                .slice(0, 5);
        }""")
        print(f"  feed-detail链接: {feed_links[:3]}")
        
        if feed_links:
            captured_urls.clear()
            await page.goto(feed_links[0], wait_until="domcontentloaded", timeout=20000)
            await asyncio.sleep(5)
            
            print(f"  新URL: {page.url}")
            print(f"  页面标题: {await page.title()}")
            
            detail_videos = await page.evaluate("""() => {
                const videos = document.querySelectorAll('video');
                return Array.from(videos).map(v => ({
                    src: v.src || '',
                    currentSrc: v.currentSrc || '',
                }));
            }""")
            
            print(f"  详情页视频:")
            for v in detail_videos:
                has_wm = '-wm' in v['src'] or 'watermark' in v['src'].lower()
                print(f"    {'[WM]' if has_wm else '[NO-WM]'} {v['src'][:150]}")
            
            print(f"\n  网络捕获的MP4:")
            for url in captured_urls:
                has_wm = '-wm' in url or 'watermark' in url.lower()
                print(f"    {'[WM]' if has_wm else '[NO-WM]'} {url[:200]}")

        # 3. 测试craftify路径下的多种文件名
        print("\n" + "=" * 60)
        print("[3] 测试craftify路径下的文件名模式...")
        
        # 用户的发布视频路径
        base_path = "https://files.vidu.cn/craftify/media_asset/26/0317/19/3210244702221402/"
        
        # 获取原始URL的签名参数
        original_url = None
        for url in captured_urls:
            if '3210244702221402' in url:
                original_url = url
                break
        
        if not original_url:
            # 从profile获取
            await page.goto("https://www.vidu.cn/profile", wait_until="domcontentloaded", timeout=20000)
            await asyncio.sleep(3)
            
            tabs = await page.query_selector_all("text=已发布")
            for tab in tabs:
                if await tab.is_visible():
                    await tab.click()
                    await asyncio.sleep(2)
                    break
            
            video_srcs = await page.evaluate("""() => {
                return Array.from(document.querySelectorAll('video')).map(v => v.src);
            }""")
            if video_srcs:
                for src in video_srcs:
                    if '3210244702221402' in src:
                        original_url = src
                        break
                if not original_url:
                    original_url = video_srcs[0]
        
        if original_url:
            # 提取签名参数
            sign_params = original_url.split('?')[1] if '?' in original_url else ''
            base = original_url.split('?')[0].rsplit('/', 1)[0] + '/'
            
            print(f"  基础路径: {base}")
            print(f"  签名参数: {sign_params[:100]}...")
            
            # 测试多种文件名
            filenames = [
                'video-propogated-wm.mp4',    # 原始（已知200）
                'video-propogated.mp4',        # 去掉-wm（预期403）
                'video.mp4',
                'original.mp4',
                'output.mp4',
                'export.mp4',
                'result.mp4',
                'final.mp4',
                'nomark.mp4',
                'nowatermark.mp4',
                'clean.mp4',
                'video-propogated-nomark.mp4',
                'creation.mp4',
                'media.mp4',
            ]
            
            test_results = await page.evaluate("""async (params) => {
                const {base, sign, filenames} = params;
                const results = {};
                for (const fn of filenames) {
                    try {
                        const url = base + fn + '?' + sign;
                        const r = await fetch(url, {method: 'HEAD'});
                        results[fn] = {status: r.status, contentLength: r.headers.get('content-length'), contentType: r.headers.get('content-type')};
                    } catch(e) {
                        results[fn] = {error: e.message};
                    }
                }
                return results;
            }""", {"base": base, "sign": sign_params, "filenames": filenames})
            
            for fn, res in test_results.items():
                status = res.get('status', 'err')
                marker = "✅" if status == 200 else ("⚠️" if status != 403 else "❌")
                print(f"  {marker} {fn}: {res}")

        # 4. 也测试infer/tasks路径下的文件名
        print("\n" + "=" * 60)
        print("[4] 测试infer/tasks路径下的文件名模式...")
        
        task_base = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.page_sz=1', {credentials: 'include'});
            const d = await r.json();
            if (d.tasks && d.tasks[0] && d.tasks[0].creations && d.tasks[0].creations[0]) {
                const uri = d.tasks[0].creations[0].uri;
                // 提取base路径
                return uri.split('?')[0].rsplit ? uri : uri;
            }
            return null;
        }""")
        
        if task_base:
            # 解析task URL
            task_url_clean = task_base.split('?')[0]
            task_dir = task_url_clean.rsplit('/', 1)[0] + '/'
            task_sign = task_base.split('?')[1] if '?' in task_base else ''
            
            print(f"  Task路径: {task_dir}")
            
            task_filenames = [
                'watermarked.mp4',
                'video.mp4',
                'video-propogated.mp4',
                'video-propogated-wm.mp4',
                'output.mp4',
                'result.mp4',
                'nomark.mp4',
                'original.mp4',
                'creation.mp4',
            ]
            
            task_results = await page.evaluate("""async (params) => {
                const {dir, sign, filenames} = params;
                const results = {};
                for (const fn of filenames) {
                    try {
                        const url = dir + fn + '?' + sign;
                        const r = await fetch(url, {method: 'HEAD'});
                        results[fn] = {status: r.status, contentLength: r.headers.get('content-length'), contentType: r.headers.get('content-type')};
                    } catch(e) {
                        results[fn] = {error: e.message};
                    }
                }
                return results;
            }""", {"dir": task_dir, "sign": task_sign, "filenames": task_filenames})
            
            for fn, res in task_results.items():
                status = res.get('status', 'err')
                marker = "✅" if status == 200 else ("⚠️" if status != 403 else "❌")
                print(f"  {marker} {fn}: {res}")

        # 5. 检查社区页面上用户自己的投稿 - 点击发布tab
        print("\n" + "=" * 60)
        print("[5] 重新检查profile - 切换到'已发布' tab...")
        
        await page.goto("https://www.vidu.cn/profile", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        # 获取所有tab
        all_tabs = await page.evaluate("""() => {
            return Array.from(document.querySelectorAll('[role="tab"], [class*="tab"]'))
                .filter(t => t.offsetParent !== null)
                .map(t => ({
                    text: t.textContent?.trim()?.substring(0, 20),
                    class: (t.className||'').toString().substring(0, 50),
                    ariaSelected: t.getAttribute('aria-selected'),
                }));
        }""")
        print(f"  Tabs: {[t['text'] for t in all_tabs]}")
        
        # 查看"已推荐"的推荐属性
        recommended = await page.evaluate("""() => {
            const text = document.body?.innerText || '';
            const parts = [];
            if (text.includes('已推荐')) parts.push('已推荐');
            if (text.includes('奖励')) parts.push(text.match(/奖励.{0,20}/)?.[0] || '');
            if (text.includes('已发布')) parts.push('已发布');
            if (text.includes('赞过')) parts.push('赞过');
            if (text.includes('收藏')) parts.push('收藏');
            if (text.includes('灵感')) parts.push('灵感');
            return parts;
        }""")
        print(f"  页面标记: {recommended}")

        # 6. 获取"推荐"的feed api
        print("\n" + "=" * 60)
        print("[6] 查询推荐/投稿API...")
        
        recommend_apis = await page.evaluate("""async () => {
            const apis = [
                '/vidu/v1/feed/recommended?limit=3',
                '/vidu/v1/feed/my_recommended?limit=3',
                '/vidu/v1/recommendations/me?limit=3',
                '/vidu/v1/share_elements/recommended/me?limit=3',
                '/vidu/v1/user/recommended?limit=3',
                '/vidu/v1/craftify/submissions/me?limit=3',
                '/vidu/v1/craftify/works/me?limit=3',
                '/craftify/v1/submissions/me?limit=3',
                '/craftify/v1/works/me?limit=3',
                '/craftify/v1/media/me?limit=3',
            ];
            const results = {};
            for (const path of apis) {
                try {
                    const r = await fetch('https://service.vidu.cn' + path, {credentials: 'include'});
                    const text = await r.text();
                    results[path] = {status: r.status, body: text.substring(0, 200)};
                } catch(e) {
                    results[path] = {error: e.message};
                }
            }
            return results;
        }""")
        
        for path, data in recommend_apis.items():
            status = data.get('status', 'err')
            if status != 404:
                print(f"  ⭐ {path}: [{status}] {data.get('body', '')[:150]}")

        print("\n[完成]")

asyncio.run(main())
