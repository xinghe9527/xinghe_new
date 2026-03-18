"""获取完整的task详情 + 尝试profile页面下载"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 获取完整task详情
        print("=" * 60)
        print("[1] 获取完整task详情...")
        
        task_detail = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.page_sz=3', {
                credentials: 'include'
            });
            const d = await r.json();
            return d;
        }""")
        print(json.dumps(task_detail, indent=2, ensure_ascii=False)[:3000])

        # 2. 看看有没有专门的creation下载API
        print("\n" + "=" * 60)
        print("[2] 尝试creation下载API...")
        
        # 获取creation_id
        creation_id = None
        if task_detail.get('tasks'):
            for t in task_detail['tasks']:
                if t.get('creations'):
                    for c in t['creations']:
                        if c.get('id'):
                            creation_id = c['id']
                            break
                if creation_id:
                    break
        
        if creation_id:
            print(f"  creation_id: {creation_id}")
            
            download_apis = await page.evaluate("""async (cid) => {
                const apis = [
                    `/vidu/v1/creations/${cid}/download`,
                    `/vidu/v1/creations/${cid}/download?type=nomark`,
                    `/vidu/v1/creations/${cid}/nomark`,
                    `/vidu/v1/creations/${cid}`,
                    `/vidu/v1/creations/${cid}/watermark-free`,
                    `/vidu/v1/download/${cid}`,
                    `/vidu/v1/download/${cid}?watermark=false`,
                ];
                const results = {};
                for (const api of apis) {
                    try {
                        const r = await fetch('https://service.vidu.cn' + api, {credentials: 'include'});
                        const text = await r.text();
                        results[api] = {status: r.status, body: text.substring(0, 300)};
                    } catch(e) {
                        results[api] = {error: e.message};
                    }
                }
                return results;
            }""", creation_id)
            
            for api, data in download_apis.items():
                print(f"  {api}: [{data.get('status', 'err')}] {data.get('body', data.get('error', ''))[:100]}")

        # 3. 看profile页面是否有下载按钮
        print("\n" + "=" * 60)
        print("[3] 访问profile查看作品...")
        
        await page.goto("https://www.vidu.cn/profile", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        # 点击"已发布"tab看看
        published = await page.query_selector_all("text=已发布")
        for p_el in published:
            visible = await p_el.is_visible()
            if visible:
                print(f"  找到'已发布'按钮，点击...")
                await p_el.click()
                await asyncio.sleep(2)
                break
        
        # 查看发布的视频
        videos = await page.query_selector_all("video")
        print(f"  视频数: {len(videos)}")
        
        # 获取视频src
        for i, v in enumerate(videos[:3]):
            src = await v.get_attribute("src")
            print(f"  视频{i+1} src: {src[:100] if src else 'None'}...")

        # 4. 点击视频看看弹出什么
        print("\n" + "=" * 60)
        print("[4] 尝试点击视频/卡片...")
        
        # 找到视频卡片
        cards = await page.evaluate("""() => {
            // 找所有可能是视频卡片的元素
            const elements = document.querySelectorAll('[class*="card"], [class*="video"], [class*="item"], [class*="creation"]');
            return Array.from(elements)
                .filter(e => {
                    const rect = e.getBoundingClientRect();
                    return rect.width > 100 && rect.width < 500 && rect.height > 100 && rect.height < 500 && rect.top > 100;
                })
                .map(e => ({
                    tag: e.tagName,
                    class: (e.className || '').toString().substring(0, 80),
                    x: Math.round(e.getBoundingClientRect().x + e.getBoundingClientRect().width/2),
                    y: Math.round(e.getBoundingClientRect().y + e.getBoundingClientRect().height/2),
                    w: Math.round(e.getBoundingClientRect().width),
                    h: Math.round(e.getBoundingClientRect().height),
                    hasVideo: e.querySelector('video') !== null
                }))
                .slice(0, 10);
        }""")
        print(f"  找到 {len(cards)} 个卡片元素:")
        for c in cards[:5]:
            print(f"    {c['tag']} class={c['class'][:50]} at ({c['x']},{c['y']}) {c['w']}x{c['h']} video={c['hasVideo']}")

        # 试试点击视频/卡片进入详情
        if cards:
            # 找有video的卡片
            target = None
            for c in cards:
                if c['hasVideo']:
                    target = c
                    break
            if not target:
                target = cards[0]
            
            print(f"\n  点击视频卡片 at ({target['x']}, {target['y']})...")
            await page.mouse.click(target['x'], target['y'])
            await asyncio.sleep(3)
            
            new_url = page.url
            print(f"  点击后URL: {new_url}")
            
            # 检查页面上的按钮
            buttons_after = await page.evaluate("""() => {
                return Array.from(document.querySelectorAll('button, [role="button"], a'))
                    .filter(b => b.offsetParent !== null)
                    .map(b => ({
                        text: b.textContent?.trim()?.substring(0, 30) || '',
                        tag: b.tagName,
                        class: (b.className || '').toString().substring(0, 50),
                        href: b.href || ''
                    }))
                    .filter(b => {
                        const t = b.text.toLowerCase();
                        return t.includes('下载') || t.includes('download') || 
                               t.includes('水印') || t.includes('watermark') ||
                               t.includes('去水印') || t.includes('去除') ||
                               t.includes('高清') || t.includes('hd');
                    })
                    .slice(0, 10);
            }""")
            
            if buttons_after:
                print(f"  找到下载/水印相关按钮:")
                for b in buttons_after:
                    print(f"    '{b['text']}' {b['tag']} class={b['class'][:40]} href={b['href'][:60]}")
            else:
                print(f"  未找到下载/水印相关按钮")
                
                # 列出所有可见按钮
                all_btns = await page.evaluate("""() => {
                    return Array.from(document.querySelectorAll('button, [role="button"]'))
                        .filter(b => b.offsetParent !== null && b.textContent?.trim())
                        .map(b => b.textContent.trim().substring(0, 30))
                        .filter(t => t.length > 0)
                        .slice(0, 30);
                }""")
                print(f"  所有可见按钮: {all_btns}")
                
                # 查找svg图标按钮（下载图标可能没有文字）
                icon_btns = await page.evaluate("""() => {
                    return Array.from(document.querySelectorAll('button, [role="button"]'))
                        .filter(b => {
                            const svg = b.querySelector('svg');
                            return svg && b.offsetParent !== null && b.textContent?.trim().length < 5;
                        })
                        .map(b => ({
                            class: (b.className || '').toString().substring(0, 60),
                            ariaLabel: b.getAttribute('aria-label') || '',
                            title: b.getAttribute('title') || '',
                            x: Math.round(b.getBoundingClientRect().x),
                            y: Math.round(b.getBoundingClientRect().y),
                            w: Math.round(b.getBoundingClientRect().width),
                            h: Math.round(b.getBoundingClientRect().height),
                            svgPath: b.querySelector('path')?.getAttribute('d')?.substring(0, 50) || ''
                        }))
                        .slice(0, 15);
                }""")
                if icon_btns:
                    print(f"\n  SVG图标按钮 ({len(icon_btns)} 个):")
                    for ib in icon_btns:
                        print(f"    at ({ib['x']},{ib['y']}) {ib['w']}x{ib['h']} aria={ib['ariaLabel']} title={ib['title']} class={ib['class'][:40]}")

        # 5. 尝试feed-detail页面
        print("\n" + "=" * 60)
        print("[5] 尝试feed-detail页面...")
        
        if creation_id:
            await page.goto(f"https://www.vidu.cn/feed-detail/{creation_id}", wait_until="domcontentloaded", timeout=20000)
            await asyncio.sleep(3)
            print(f"  URL: {page.url}")
            print(f"  Title: {await page.title()}")
            
            # 查找所有按钮
            feed_btns = await page.evaluate("""() => {
                return Array.from(document.querySelectorAll('button, [role="button"]'))
                    .filter(b => b.offsetParent !== null && b.textContent?.trim())
                    .map(b => b.textContent.trim().substring(0, 40))
                    .filter(t => t.length > 0)
                    .slice(0, 30);
            }""")
            print(f"  按钮: {feed_btns}")
            
            # 查看页面是否有下载入口
            download_elements = await page.evaluate("""() => {
                const texts = [];
                document.querySelectorAll('*').forEach(el => {
                    if (el.children.length === 0 && el.offsetParent !== null) {
                        const t = el.textContent?.trim();
                        if (t && (t.includes('下载') || t.includes('download') || t.includes('去水印') || t.includes('水印'))) {
                            texts.push({tag: el.tagName, text: t.substring(0, 50), class: (el.className||'').toString().substring(0,40)});
                        }
                    }
                });
                return texts;
            }""")
            print(f"  下载/水印相关文本: {download_elements}")

        print("\n[完成]")

asyncio.run(main())
