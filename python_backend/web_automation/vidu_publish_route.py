"""研究投稿后视频的无水印机制
用户方案：生成视频 → 投稿 → 猫抓下载 = 无水印
需要验证：
1. 投稿后的视频URL是否与创建时不同
2. feed/社区页面的视频是否包含水印
3. 投稿流程的API
"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 查看用户的已发布作品
        print("=" * 60)
        print("[1] 查看用户已发布作品的feed详情...")
        
        await page.goto("https://www.vidu.cn/profile", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        # 点击"已发布"tab
        tabs = await page.query_selector_all("text=已发布")
        for tab in tabs:
            if await tab.is_visible():
                await tab.click()
                await asyncio.sleep(2)
                break
        
        # 获取所有视频的src和相关数据
        video_data = await page.evaluate("""() => {
            const videos = document.querySelectorAll('video');
            const results = [];
            for (const v of videos) {
                const parent = v.closest('a') || v.closest('[href]');
                const sources = v.querySelectorAll('source');
                results.push({
                    src: v.src || '',
                    poster: v.poster || '',
                    parentHref: parent?.getAttribute('href') || '',
                    parentTag: parent?.tagName || '',
                    sources: Array.from(sources).map(s => s.src).join(', '),
                    width: v.videoWidth,
                    height: v.videoHeight,
                });
            }
            return results;
        }""")
        
        for i, v in enumerate(video_data):
            print(f"\n  视频{i+1}:")
            print(f"    src: {v['src'][:120]}...")
            print(f"    href: {v['parentHref']}")
            print(f"    poster: {v['poster'][:80] if v['poster'] else 'none'}")

        # 2. 尝试进入第一个发布作品的详情页
        print("\n" + "=" * 60)
        print("[2] 通过链接进入作品详情页...")
        
        # 获取所有链接
        links = await page.evaluate("""() => {
            const links = document.querySelectorAll('a[href*="feed-detail"], a[href*="creation"], a[href*="video"]');
            return Array.from(links).map(l => ({href: l.href, text: l.textContent?.trim()?.substring(0, 30)})).slice(0, 10);
        }""")
        print(f"  找到的详情链接: {links}")
        
        # 如果没有明确链接，直接点击视频区域
        if not links or len(links) == 0:
            # 尝试点击第一个视频
            print("  没找到直接链接，尝试点击视频...")
            
            first_video = await page.query_selector('video')
            if first_video:
                box = await first_video.bounding_box()
                if box:
                    print(f"  视频位置: ({box['x']:.0f}, {box['y']:.0f}) {box['width']:.0f}x{box['height']:.0f}")
                    await page.mouse.click(box['x'] + box['width']/2, box['y'] + box['height']/2)
                    await asyncio.sleep(3)
                    print(f"  点击后URL: {page.url}")

        # 3. 查看feed列表中的视频格式
        print("\n" + "=" * 60)
        print("[3] 查看社区feed中视频的URL格式...")
        
        # 获取用户发布的作品在社区feed中的表现
        feed_data = await page.evaluate("""async () => {
            // 获取发布的作品列表
            const r = await fetch('https://service.vidu.cn/vidu/v1/feed/list?limit=5&sort=latest', {credentials: 'include'});
            const d = await r.json().catch(() => null);
            if (!d || !d.data) return {error: 'no data', raw: JSON.stringify(d).substring(0, 300)};
            
            return d.data.slice(0, 3).map(item => ({
                id: item.id,
                title: (item.title || item.description || '').substring(0, 50),
                uri: item.uri || item.video_url || '',
                media_url: item.media_url || '',
                watermark_uri: item.watermark_uri || item.waterMarkUri || '',
                nomark_uri: item.nomark_uri || item.noWaterMarkUri || '',
                type: item.type,
                keys: Object.keys(item).join(', ')
            }));
        }""")
        print(f"  feed数据: {json.dumps(feed_data, indent=2, ensure_ascii=False)[:1500]}")

        # 4. 获取用户自己发布的作品
        print("\n" + "=" * 60)
        print("[4] 获取用户自己的 published 作品...")
        
        my_published = await page.evaluate("""async () => {
            // 多种可能的API路径
            const paths = [
                '/vidu/v1/share_elements/me?pager.page_sz=3',
                '/vidu/v1/share_elements/mine?pager.page_sz=3',
                '/vidu/v1/share_elements/my?pager.page_sz=3',
                '/vidu/v1/feed/me?pager.page_sz=3',
                '/vidu/v1/feed/list/me?pager.page_sz=3',
                '/vidu/v1/user/creations?pager.page_sz=3',
                '/vidu/v1/user/published?pager.page_sz=3',
                '/vidu/v1/published/me?pager.page_sz=3',
                '/vidu/v1/craftify/me?pager.page_sz=3',
                '/vidu/v1/craftify/list?pager.page_sz=3',
                '/craftify/v1/media_asset/me?pager.page_sz=3',
                '/craftify/v1/works/me?pager.page_sz=3',
            ];
            const results = {};
            for (const path of paths) {
                try {
                    const r = await fetch('https://service.vidu.cn' + path, {credentials: 'include'});
                    const body = await r.text();
                    results[path] = {status: r.status, body: body.substring(0, 200)};
                } catch(e) {
                    results[path] = {error: e.message};
                }
            }
            return results;
        }""")
        
        for path, data in my_published.items():
            status = data.get('status', 'err')
            if status == 200:
                print(f"  ✅ {path}: [{status}] {data.get('body', '')[:150]}")
            elif status != 404:
                print(f"  ⚠️ {path}: [{status}] {data.get('body', '')[:100]}")

        # 5. 投稿API探索 - share_elements相关
        print("\n" + "=" * 60)
        print("[5] share_elements API详细探索...")
        
        share_explore = await page.evaluate("""async () => {
            const paths = [
                '/vidu/v1/share_elements?pager.page_sz=3',
                '/vidu/v1/share_elements?pager.page_sz=3&creator=me',
                '/vidu/v1/share_elements?pager.page_sz=3&filter=mine',
                '/vidu/v1/share_elements/list?pager.page_sz=3',
                '/vidu/v1/share_elements/published?pager.page_sz=3',
            ];
            const results = {};
            for (const path of paths) {
                try {
                    const r = await fetch('https://service.vidu.cn' + path, {credentials: 'include'});
                    const body = await r.text();
                    results[path] = {status: r.status, body: body.substring(0, 300)};
                } catch(e) {
                    results[path] = {error: e.message};
                }
            }
            return results;
        }""")
        
        for path, data in share_explore.items():
            status = data.get('status', 'err')
            if status != 404:
                print(f"  {path}: [{status}] {data.get('body', '')[:200]}")

        # 6. 从profile页面抓取发布作品的实际URL路径
        print("\n" + "=" * 60)
        print("[6] 从profile页面分析发布作品URL模式...")
        
        await page.goto("https://www.vidu.cn/profile", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        # 点击"已发布"
        tabs = await page.query_selector_all("text=已发布")
        for tab in tabs:
            if await tab.is_visible():
                await tab.click()
                await asyncio.sleep(2)
                break
        
        # 获取完整视频URL
        full_urls = await page.evaluate("""() => {
            const videos = document.querySelectorAll('video');
            return Array.from(videos).map(v => v.src);
        }""")
        
        for i, url in enumerate(full_urls):
            print(f"\n  视频{i+1} 完整URL:")
            print(f"    {url}")
            # 分析URL结构
            parts = url.split('?')[0].split('/')
            filename = parts[-1] if parts else ''
            print(f"    文件名: {filename}")
            # 提取路径中的关键部分
            path_key = '/'.join(parts[-4:]) if len(parts) >= 4 else url.split('?')[0]
            print(f"    路径: {path_key}")

        # 7. 对比：任务创建的视频URL vs 发布后的视频URL
        print("\n" + "=" * 60)
        print("[7] 对比任务URL vs 发布URL...")
        
        task_url = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.page_sz=3', {credentials: 'include'});
            const d = await r.json();
            if (d.tasks && d.tasks.length > 0) {
                const creations = d.tasks[0].creations || [];
                return creations.map(c => ({
                    id: c.id,
                    uri: c.uri || '',
                    nomark_uri: c.nomark_uri || '(empty)',
                    type: c.type
                }));
            }
            return [];
        }""")
        
        print(f"  任务创建的视频:")
        for c in task_url:
            print(f"    id={c['id']} uri={c['uri'][:100]}...")
            print(f"    nomark_uri={c['nomark_uri']}")
        
        print(f"\n  发布后的视频:")
        for i, url in enumerate(full_urls):
            print(f"    视频{i+1}: {url.split('?')[0].split('/')[-4:]}")

        # 8. 尝试将发布视频URL中的wm去掉
        print("\n" + "=" * 60)
        print("[8] 尝试发布视频URL的wm替换...")
        
        for i, url in enumerate(full_urls[:1]):
            # 原始URL（带wm）
            no_wm_url = url.replace('video-propogated-wm.mp4', 'video-propogated.mp4')
            
            test_result = await page.evaluate("""async (urls) => {
                const results = {};
                for (const [label, url] of Object.entries(urls)) {
                    try {
                        const r = await fetch(url, {method: 'HEAD'});
                        results[label] = {status: r.status, contentType: r.headers.get('content-type'), contentLength: r.headers.get('content-length')};
                    } catch(e) {
                        results[label] = {error: e.message};
                    }
                }
                return results;
            }""", {"wm_original": url, "no_wm": no_wm_url})
            
            for label, res in test_result.items():
                print(f"  {label}: {res}")

        print("\n[完成]")

asyncio.run(main())
