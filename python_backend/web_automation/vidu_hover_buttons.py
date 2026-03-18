"""探索悬停视频后出现的按钮，找下载入口"""
import asyncio
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 找到JS中ep(share submit)的实际调用位置
        print("=" * 60)
        print("[1] 搜索 ep() share submit 实际调用代码...")
        js_chunks = await page.evaluate("""() => {
            const scripts = performance.getEntriesByType('resource')
                .filter(r => r.name.includes('.js') && r.name.includes('8603'));
            return scripts.map(s => s.name);
        }""")
        print(f"  目标JS: {js_chunks}")

        # 从页面获取JS源码中ep调用的上下文
        ep_calls = await page.evaluate("""async () => {
            const results = [];
            const scripts = performance.getEntriesByType('resource')
                .filter(r => r.name.includes('.js'));
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    // 找 ep( 调用（但ep是share submit函数）
                    // 实际上我们要找 share_elements/submit 附近的body构造
                    const idx = text.indexOf('share_elements/submit');
                    if (idx > -1) {
                        // 找这个函数定义附近的代码
                        const start = Math.max(0, idx - 500);
                        const end = Math.min(text.length, idx + 1000);
                        const context = text.substring(start, end);
                        results.push({file: s.name.split('/').pop(), context: context});
                        
                        // 找所有可能调用这个submit的地方
                        // 搜索 body: 或 data: 关键词在附近
                        const bodyIdx = text.indexOf('body:', idx);
                        if (bodyIdx > -1 && bodyIdx - idx < 500) {
                            const bodyCtx = text.substring(bodyIdx - 100, bodyIdx + 300);
                            results.push({file: 'body_context', context: bodyCtx});
                        }
                    }
                    
                    // 搜索 shareSubmit / handleShare / onShare 等函数
                    const sharePatterns = ['shareSubmit', 'handleShare', 'onShare', 'submitShare', 'shareElement'];
                    for (const pat of sharePatterns) {
                        const pi = text.indexOf(pat);
                        if (pi > -1) {
                            const ctx = text.substring(Math.max(0, pi - 200), Math.min(text.length, pi + 500));
                            results.push({file: s.name.split('/').pop(), pattern: pat, context: ctx});
                        }
                    }
                } catch(e) {}
            }
            return results;
        }""")
        for r in ep_calls:
            print(f"\n  [{r.get('pattern', 'submit')}] in {r.get('file', '?')}:")
            ctx_text = r.get('context', '')
            # 打印关键部分
            for line in ctx_text.split('\n')[:10]:
                print(f"    {line[:200]}")

        # 2. 导航到创建页面并悬停视频
        print("\n" + "=" * 60)
        print("[2] 悬停视频，分析出现的按钮...")
        
        await page.goto("https://www.vidu.cn/create", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(3)
        
        # 找到视频元素
        videos = await page.query_selector_all("video")
        print(f"  视频数量: {len(videos)}")
        
        if videos:
            # 悬停第一个视频
            box = await videos[0].bounding_box()
            if box:
                await page.mouse.move(box['x'] + box['width']/2, box['y'] + box['height']/2)
                await asyncio.sleep(2)
                
                # 收集所有按钮信息
                buttons_info = await page.evaluate("""() => {
                    const btns = document.querySelectorAll('button, [role="button"], a[href], [onclick], svg[class*="icon"], [class*="download"], [class*="share"], [class*="action"]');
                    return Array.from(btns).map(b => {
                        const rect = b.getBoundingClientRect();
                        if (rect.width === 0 || rect.height === 0) return null;
                        return {
                            tag: b.tagName,
                            text: (b.textContent || '').trim().substring(0, 50),
                            className: (b.className || '').toString().substring(0, 100),
                            title: b.title || '',
                            ariaLabel: b.getAttribute('aria-label') || '',
                            href: b.href || '',
                            x: Math.round(rect.x),
                            y: Math.round(rect.y),
                            w: Math.round(rect.width),
                            h: Math.round(rect.height),
                            visible: rect.top >= 0 && rect.top < window.innerHeight
                        };
                    }).filter(b => b && b.visible);
                }""")
                
                # 过滤视频附近的按钮
                video_y = box['y']
                nearby = [b for b in buttons_info if abs(b['y'] - video_y) < 200]
                print(f"  视频附近按钮 ({len(nearby)}):")
                for b in nearby:
                    print(f"    [{b['tag']}] text='{b['text'][:30]}' class='{b['className'][:60]}' title='{b['title']}' pos=({b['x']},{b['y']}) size={b['w']}x{b['h']}")
                
                # 找所有带download/share/投稿相关的元素
                all_relevant = [b for b in buttons_info if any(k in (b['text'] + b['className'] + b['title'] + b['ariaLabel']).lower() for k in ['download', '下载', 'share', '分享', '投稿', 'post', 'watermark', '水印'])]
                print(f"\n  下载/分享相关元素 ({len(all_relevant)}):")
                for b in all_relevant:
                    print(f"    [{b['tag']}] text='{b['text'][:40]}' class='{b['className'][:60]}' title='{b['title']}' aria='{b['ariaLabel']}'")

        # 3. 搜索右键菜单或更多操作
        print("\n" + "=" * 60)
        print("[3] 搜索视频卡片中的操作菜单...")
        
        card_actions = await page.evaluate("""() => {
            // 找视频容器的父元素中的按钮
            const videos = document.querySelectorAll('video');
            const results = [];
            videos.forEach((v, i) => {
                let parent = v.parentElement;
                for (let j = 0; j < 8; j++) {
                    if (!parent) break;
                    const btns = parent.querySelectorAll('button, [role="button"], svg');
                    if (btns.length > 0) {
                        const info = Array.from(btns).map(b => ({
                            tag: b.tagName,
                            text: (b.textContent || '').trim().substring(0, 30),
                            className: (b.className || '').toString().substring(0, 80),
                            title: b.title || '',
                            ariaLabel: b.getAttribute('aria-label') || '',
                            svgPath: b.tagName === 'svg' ? (b.querySelector('path')?.getAttribute('d') || '').substring(0, 50) : ''
                        }));
                        results.push({video: i, level: j, parentClass: (parent.className || '').toString().substring(0, 60), buttons: info});
                    }
                    parent = parent.parentElement;
                }
            });
            return results;
        }""")
        
        for item in card_actions[:10]:
            print(f"\n  视频{item['video']} 层级{item['level']} parent='{item['parentClass'][:50]}'")
            for b in item['buttons'][:8]:
                extra = f" svg={b['svgPath'][:30]}" if b['svgPath'] else ""
                print(f"    [{b['tag']}] '{b['text'][:25]}' class='{b['className'][:50]}'{extra}")

        # 4. 尝试通过网络拦截方式找下载URL
        print("\n" + "=" * 60)
        print("[4] 设置网络拦截，尝试触发下载...")
        
        download_urls = []
        async def on_response(response):
            url = response.url
            if any(k in url for k in ['download', 'nomark', '.mp4', 'watermark']):
                download_urls.append(url)
                print(f"  [拦截] {url[:120]}")
        
        page.on("response", on_response)
        
        # 点击视频附近的每个小按钮看看
        if videos:
            box = await videos[0].bounding_box()
            if box:
                # 找视频右下角的图标按钮
                icons = await page.evaluate("""(videoRect) => {
                    const els = document.elementsFromPoint(videoRect.x + videoRect.width - 30, videoRect.y + videoRect.height - 30);
                    return els.map(e => ({
                        tag: e.tagName,
                        text: (e.textContent || '').trim().substring(0, 30),
                        className: (e.className || '').toString().substring(0, 80)
                    }));
                }""", box)
                print(f"\n  视频右下角元素: {icons[:5]}")

        # 5. 搜索JS中的download相关代码
        print("\n" + "=" * 60)
        print("[5] 搜索JS中download函数的实现...")
        
        download_code = await page.evaluate("""async () => {
            const results = [];
            const scripts = performance.getEntriesByType('resource')
                .filter(r => r.name.includes('.js'));
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    
                    // 搜索 download 函数
                    const patterns = ['handleDownload', 'onDownload', 'downloadVideo', 'startDownload', 'download_video', 'nomark'];
                    for (const pat of patterns) {
                        let idx = 0;
                        while ((idx = text.indexOf(pat, idx)) !== -1) {
                            const ctx = text.substring(Math.max(0, idx - 200), Math.min(text.length, idx + 400));
                            results.push({file: s.name.split('/').pop(), pattern: pat, context: ctx});
                            idx += pat.length;
                            if (results.length > 15) break;
                        }
                        if (results.length > 15) break;
                    }
                } catch(e) {}
                if (results.length > 15) break;
            }
            return results;
        }""")
        
        for r in download_code[:10]:
            print(f"\n  [{r['pattern']}] in {r['file']}:")
            ctx = r['context']
            print(f"    {ctx[:300]}")

        page.remove_listener("response", on_response)
        print(f"\n  拦截到的下载URL: {download_urls}")
        print("\n[完成]")

asyncio.run(main())
