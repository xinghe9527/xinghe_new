"""尝试触发看广告去水印弹窗"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 先找到用户自己的创作
        print("=" * 60)
        print("[1] 寻找用户自己的创作页面...")
        
        # 尝试各种可能的路径
        paths = [
            "/my-creations",
            "/my-works", 
            "/history",
            "/create/history",
            "/tasks",
            "/my",
            "/profile",
            "/user/creations",
        ]
        
        for path in paths:
            url = f"https://www.vidu.cn{path}"
            try:
                resp = await page.goto(url, wait_until="domcontentloaded", timeout=10000)
                await asyncio.sleep(1)
                final_url = page.url
                title = await page.evaluate("() => document.title")
                has_404 = await page.evaluate("() => document.body?.innerText?.includes('404') || document.body?.innerText?.includes('找不到')")
                status = "✅" if not has_404 else "❌ 404"
                print(f"  {path} → {final_url[:60]} [{status}] title={title[:30]}")
            except:
                print(f"  {path} → 超时")

        # 2. 从JS中找用户创作历史的正确页面路径
        print("\n" + "=" * 60)
        print("[2] 从JS搜索创作历史路径...")
        
        await page.goto("https://www.vidu.cn/create", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        history_paths = await page.evaluate("""async () => {
            const results = [];
            const scripts = performance.getEntriesByType('resource').filter(r => r.name.includes('.js'));
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    
                    // 搜索 my-creation, history, task-history 等路径
                    for (const pat of ['my-creation', '/my/', 'history', 'task-list', 'task-history', 'my-works', 'profile', '/works', 'creation-list']) {
                        let idx = text.indexOf(pat);
                        if (idx > -1) {
                            const ctx = text.substring(Math.max(0, idx - 100), Math.min(text.length, idx + 200));
                            if (ctx.includes('href') || ctx.includes('push') || ctx.includes('route') || ctx.includes('navigate')) {
                                results.push({pattern: pat, code: ctx});
                            }
                        }
                    }
                    
                    // 搜索 remove_watermark 和 watch_ad_watermark
                    for (const pat of ['remove_watermark', 'watch_ad_watermark', 'watermark_ad', 'removeWatermark', 'adWatermark', 'watch_ad']) {
                        let idx = 0;
                        while ((idx = text.indexOf(pat, idx)) !== -1) {
                            const ctx = text.substring(Math.max(0, idx - 200), Math.min(text.length, idx + 400));
                            results.push({pattern: pat, code: ctx});
                            idx += pat.length;
                            if (results.length > 20) break;
                        }
                    }
                } catch(e) {}
            }
            return results.slice(0, 15);
        }""")
        
        for r in history_paths:
            print(f"\n  [{r['pattern']}]:")
            print(f"    {r['code'][:300]}")

        # 3. 找下载弹窗组件并尝试触发
        print("\n" + "=" * 60)
        print("[3] 查找下载组件和水印去除选项...")
        
        download_dialog = await page.evaluate("""async () => {
            const results = [];
            const scripts = performance.getEntriesByType('resource').filter(r => r.name.includes('.js'));
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    
                    // 找下载dialog中的广告/水印选项
                    const patterns = ['remove_watermark_ad', 'watermarkFree', 'removeWatermarkDialog', 'downloadNoWatermark', 'adDownload', 'rewardDownload'];
                    for (const pat of patterns) {
                        let idx = text.indexOf(pat);
                        if (idx > -1) {
                            const ctx = text.substring(Math.max(0, idx - 300), Math.min(text.length, idx + 500));
                            results.push({pattern: pat, file: s.name.split('/').pop(), code: ctx});
                        }
                    }
                    
                    // 找 DownloadButton 或 download button 组件
                    for (const pat of ['DownloadButton', 'downloadBtn', 'download-btn', 'DownloadCreation']) {
                        let idx = text.indexOf(pat);
                        if (idx > -1) {
                            const ctx = text.substring(Math.max(0, idx - 200), Math.min(text.length, idx + 500));
                            results.push({pattern: pat, file: s.name.split('/').pop(), code: ctx});
                        }
                    }
                } catch(e) {}
            }
            return results.slice(0, 10);
        }""")
        
        for r in download_dialog:
            print(f"\n  [{r['pattern']}] in {r.get('file', '?')}:")
            print(f"    {r['code'][:400]}")

        # 4. 在创建页面找到已有的视频结果
        print("\n" + "=" * 60)
        print("[4] 在create页查找用户自己的生成结果...")
        
        # 先检查页面左侧或底部是否有"我的任务"/"历史"列表
        task_section = await page.evaluate("""() => {
            const allText = document.body?.innerText || '';
            // 找包含"我的"/"历史"/"任务"的区域
            const sections = document.querySelectorAll('[class*="task"], [class*="history"], [class*="result"], [class*="creation"], [class*="gallery"]');
            return {
                sectionCount: sections.length,
                sectionClasses: Array.from(sections).map(s => ({
                    class: (s.className || '').toString().substring(0, 60),
                    text: (s.textContent || '').substring(0, 100)
                })).slice(0, 10),
                hasHistory: allText.includes('历史') || allText.includes('我的'),
                hasResult: allText.includes('结果') || allText.includes('生成'),
            };
        }""")
        print(f"  任务区域: {task_section.get('sectionCount', 0)}")
        print(f"  has历史: {task_section.get('hasHistory')}, has结果: {task_section.get('hasResult')}")
        for s in task_section.get('sectionClasses', []):
            print(f"    class='{s['class'][:50]}' text='{s['text'][:80]}'")

        # 5. 搜索tasks API路径（新的endpoint可能不叫tasks了）
        print("\n" + "=" * 60)
        print("[5] 搜索正确的tasks API路径...")
        
        # 通过CDP拦截所有API请求
        cdp = await ctx.new_cdp_session(page)
        await cdp.send("Network.enable")
        
        all_api = []
        def on_req(params):
            url = params.get('request', {}).get('url', '')
            if 'service.vidu.cn' in url and 'track' not in url:
                all_api.append(url[:150])
        
        cdp.on("Network.requestWillBeSent", on_req)
        
        # 刷新创建页
        await page.reload(wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(5)
        
        await cdp.send("Network.disable")
        
        print(f"  API请求 ({len(all_api)}):")
        for url in sorted(set(all_api)):
            print(f"    {url}")

        # 6. 尝试直接在页面上找下载图标并点击
        print("\n" + "=" * 60)
        print("[6] 搜索页面上的下载图标...")
        
        # 查找所有SVG图标（下载通常是箭头向下的图标）
        download_icons = await page.evaluate("""() => {
            const svgs = document.querySelectorAll('svg');
            const results = [];
            svgs.forEach(svg => {
                const paths = svg.querySelectorAll('path');
                const d = Array.from(paths).map(p => p.getAttribute('d')?.substring(0, 30)).join('|');
                const parent = svg.parentElement;
                const pText = parent?.textContent?.trim()?.substring(0, 30) || '';
                const pClass = (parent?.className || '').toString().substring(0, 50);
                const title = svg.getAttribute('title') || parent?.getAttribute('title') || parent?.getAttribute('aria-label') || '';
                // 下载图标通常位于视频附近
                const rect = svg.getBoundingClientRect();
                if (rect.width > 0 && rect.height > 0 && rect.top > 0 && rect.top < 2000) {
                    if (title.toLowerCase().includes('download') || title.includes('下载') || 
                        pClass.includes('download') || pText.includes('下载')) {
                        results.push({d: d, text: pText, class: pClass, title: title, x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.width), h: Math.round(rect.height)});
                    }
                }
            });
            return results;
        }""")
        
        if download_icons:
            print(f"  找到下载图标: {len(download_icons)}")
            for d in download_icons:
                print(f"    title='{d['title']}' text='{d['text']}' pos=({d['x']},{d['y']}) size={d['w']}x{d['h']}")
        else:
            print("  未找到下载图标，搜索所有含'下载'文字的元素...")
            dl_elements = await page.evaluate("""() => {
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                const results = [];
                while (walker.nextNode()) {
                    const text = walker.currentNode.textContent.trim();
                    if (text.includes('下载') && text.length < 20) {
                        const parent = walker.currentNode.parentElement;
                        const rect = parent?.getBoundingClientRect();
                        if (rect && rect.width > 0) {
                            results.push({
                                text: text,
                                tag: parent.tagName,
                                class: (parent.className || '').toString().substring(0, 50),
                                x: Math.round(rect.x),
                                y: Math.round(rect.y)
                            });
                        }
                    }
                }
                return results;
            }""")
            for e in dl_elements:
                print(f"    [{e['tag']}] '{e['text']}' class='{e['class']}' pos=({e['x']},{e['y']})")

        print("\n[完成]")

asyncio.run(main())
