"""验证水印是否为CSS覆盖层（canvas/div overlay）
如果水印只是网页叠加的，猫抓下载的原始mp4文件就是无水印的！
"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 访问一个有效的feed-detail页面
        print("=" * 60)
        print("[1] 访问feed-detail页面...")
        
        # 先去explore找一个有效的链接
        await page.goto("https://www.vidu.cn/explore", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        feed_link = await page.evaluate("""() => {
            const links = document.querySelectorAll('a[href*="feed-detail"]');
            return links[0]?.href || '';
        }""")
        
        if not feed_link:
            print("  找不到feed-detail链接")
            return
        
        print(f"  链接: {feed_link}")
        await page.goto(feed_link, wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(5)

        # 2. 深度检查video元素周围的所有覆盖层
        print("\n" + "=" * 60)
        print("[2] 深度检查video元素周围的覆盖层...")
        
        overlay_analysis = await page.evaluate("""() => {
            const video = document.querySelector('video');
            if (!video) return {error: 'no video found'};
            
            const videoRect = video.getBoundingClientRect();
            const results = {
                videoRect: {x: videoRect.x, y: videoRect.y, w: videoRect.width, h: videoRect.height},
                videoSrc: video.src?.substring(0, 100),
                overlays: [],
                watermarkImages: [],
                canvases: [],
            };
            
            // 检查所有在视频区域上方的绝对定位元素
            document.querySelectorAll('*').forEach(el => {
                if (el === video || el.tagName === 'SCRIPT' || el.tagName === 'STYLE') return;
                
                const style = window.getComputedStyle(el);
                const rect = el.getBoundingClientRect();
                
                // 检查是否在视频区域上方且绝对/固定定位
                if (style.position === 'absolute' || style.position === 'fixed') {
                    // 检查是否与视频区域重叠
                    if (rect.right > videoRect.left && rect.left < videoRect.right &&
                        rect.bottom > videoRect.top && rect.top < videoRect.bottom &&
                        el.offsetParent !== null) {
                        
                        results.overlays.push({
                            tag: el.tagName,
                            class: (el.className || '').toString().substring(0, 100),
                            text: (el.textContent || '').trim().substring(0, 50),
                            rect: {x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.width), h: Math.round(rect.height)},
                            zIndex: style.zIndex,
                            opacity: style.opacity,
                            pointerEvents: style.pointerEvents,
                            display: style.display,
                            visibility: style.visibility,
                            bgImage: style.backgroundImage !== 'none' ? style.backgroundImage.substring(0, 200) : '',
                            bgColor: style.backgroundColor,
                            innerHTML: el.innerHTML?.substring(0, 200) || '',
                        });
                    }
                }
                
                // 检查img元素是否在视频上方
                if (el.tagName === 'IMG') {
                    if (rect.right > videoRect.left && rect.left < videoRect.right &&
                        rect.bottom > videoRect.top && rect.top < videoRect.bottom &&
                        el.offsetParent !== null) {
                        results.watermarkImages.push({
                            src: el.src?.substring(0, 200) || '',
                            alt: el.alt,
                            rect: {x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.width), h: Math.round(rect.height)},
                            opacity: style.opacity,
                        });
                    }
                }
                
                // 检查canvas
                if (el.tagName === 'CANVAS') {
                    results.canvases.push({
                        rect: {x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.width), h: Math.round(rect.height)},
                    });
                }
            });
            
            // 检查video的祖先元素链
            let ancestor = video.parentElement;
            const parentChain = [];
            while (ancestor && ancestor !== document.body) {
                const astyle = window.getComputedStyle(ancestor);
                parentChain.push({
                    tag: ancestor.tagName,
                    class: (ancestor.className || '').toString().substring(0, 80),
                    position: astyle.position,
                    overflow: astyle.overflow,
                    childCount: ancestor.children.length,
                });
                ancestor = ancestor.parentElement;
            }
            results.parentChain = parentChain.slice(0, 10);
            
            return results;
        }""")
        
        print(f"  视频位置: {overlay_analysis.get('videoRect')}")
        print(f"  视频src: {overlay_analysis.get('videoSrc')}")
        
        print(f"\n  覆盖层 ({len(overlay_analysis.get('overlays', []))} 个):")
        for ov in overlay_analysis.get('overlays', []):
            print(f"    {ov['tag']} class='{ov['class'][:50]}' rect={ov['rect']} z={ov['zIndex']} opacity={ov['opacity']}")
            if ov['text']:
                print(f"      text: '{ov['text']}'")
            if ov['bgImage']:
                print(f"      bgImage: {ov['bgImage'][:100]}")
            if 'vidu' in ov['innerHTML'].lower() or 'logo' in ov['innerHTML'].lower() or 'svg' in ov['innerHTML'].lower():
                print(f"      innerHTML: {ov['innerHTML'][:200]}")
        
        print(f"\n  视频区域的图片 ({len(overlay_analysis.get('watermarkImages', []))} 个):")
        for img in overlay_analysis.get('watermarkImages', []):
            print(f"    src={img['src'][:100]} rect={img['rect']} opacity={img['opacity']}")
        
        print(f"\n  Canvas: {overlay_analysis.get('canvases', [])}")
        
        print(f"\n  祖先元素链:")
        for p in overlay_analysis.get('parentChain', []):
            print(f"    {p['tag']} class='{p['class'][:50]}' pos={p['position']} overflow={p['overflow']} children={p['childCount']}")

        # 3. 特别检查：SVG水印
        print("\n" + "=" * 60)
        print("[3] 检查SVG水印...")
        
        svg_check = await page.evaluate("""() => {
            const svgs = document.querySelectorAll('svg');
            const video = document.querySelector('video');
            if (!video) return [];
            const videoRect = video.getBoundingClientRect();
            
            return Array.from(svgs)
                .filter(svg => {
                    const rect = svg.getBoundingClientRect();
                    return rect.right > videoRect.left && rect.left < videoRect.right &&
                           rect.bottom > videoRect.top && rect.top < videoRect.bottom;
                })
                .map(svg => ({
                    class: (svg.className?.baseVal || '').substring(0, 50),
                    rect: {
                        x: Math.round(svg.getBoundingClientRect().x),
                        y: Math.round(svg.getBoundingClientRect().y),
                        w: Math.round(svg.getBoundingClientRect().width),
                        h: Math.round(svg.getBoundingClientRect().height),
                    },
                    innerHTML: svg.innerHTML?.substring(0, 200) || '',
                }));
        }""")
        
        print(f"  视频区域的SVG ({len(svg_check)} 个):")
        for svg in svg_check:
            print(f"    rect={svg['rect']} class='{svg['class']}'")
            if svg['innerHTML']:
                print(f"    html: {svg['innerHTML'][:100]}")

        # 4. 关键测试：截图对比 - 隐藏所有覆盖层后截图
        print("\n" + "=" * 60)
        print("[4] 截图对比：原始 vs 隐藏覆盖层...")
        
        import os
        screenshots_dir = os.path.join(os.path.dirname(__file__), 'screenshots')
        os.makedirs(screenshots_dir, exist_ok=True)
        
        # 原始截图
        await page.screenshot(path=os.path.join(screenshots_dir, 'feed_original.png'))
        print(f"  原始截图已保存")
        
        # 隐藏所有覆盖层
        await page.evaluate("""() => {
            const video = document.querySelector('video');
            if (!video) return;
            const videoRect = video.getBoundingClientRect();
            
            document.querySelectorAll('*').forEach(el => {
                if (el === video || el.contains(video)) return;
                const style = window.getComputedStyle(el);
                const rect = el.getBoundingClientRect();
                
                if ((style.position === 'absolute' || style.position === 'fixed') &&
                    rect.right > videoRect.left && rect.left < videoRect.right &&
                    rect.bottom > videoRect.top && rect.top < videoRect.bottom) {
                    el.style.display = 'none';
                }
            });
        }""")
        
        await page.screenshot(path=os.path.join(screenshots_dir, 'feed_no_overlay.png'))
        print(f"  隐藏覆盖层后截图已保存")

        # 5. 下载视频文件的前几字节检查
        print("\n" + "=" * 60)
        print("[5] 下载视频文件分析...")
        
        video_src = await page.evaluate("document.querySelector('video')?.src || ''")
        if video_src:
            print(f"  视频URL: {video_src[:150]}")
            
            # 检查文件大小
            head_info = await page.evaluate("""async (url) => {
                const r = await fetch(url, {method: 'HEAD'});
                return {
                    status: r.status,
                    contentLength: r.headers.get('content-length'),
                    contentType: r.headers.get('content-type'),
                };
            }""", video_src)
            print(f"  HEAD: {head_info}")
            
            # 文件名分析
            filename = video_src.split('?')[0].split('/')[-1]
            print(f"  文件名: {filename}")
            print(f"  含-wm: {'-wm' in filename}")

        # 6. 检查JS中的propogated-wm含义
        print("\n" + "=" * 60)
        print("[6] 搜索JS中'propogated'的含义...")
        
        propogated_search = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            const results = [];
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    if (code.includes('propogated') || code.includes('propagated')) {
                        const filename = s.src.split('/').pop();
                        // 找到相关代码片段
                        const indices = [];
                        let idx = 0;
                        while ((idx = code.indexOf('propogated', idx)) !== -1) {
                            indices.push(idx);
                            idx++;
                        }
                        idx = 0;
                        while ((idx = code.indexOf('propagated', idx)) !== -1) {
                            indices.push(idx);
                            idx++;
                        }
                        const snippets = indices.map(i => code.substring(Math.max(0, i - 60), Math.min(code.length, i + 80)));
                        results.push({file: filename, count: indices.length, snippets: snippets.slice(0, 5)});
                    }
                } catch(e) {}
            }
            return results;
        }""")
        
        for r in propogated_search:
            print(f"\n  文件: {r['file']} ({r['count']}处)")
            for s in r['snippets']:
                print(f"    ...{s}...")

        print("\n[完成]")

asyncio.run(main())
