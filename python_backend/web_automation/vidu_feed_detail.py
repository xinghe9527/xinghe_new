"""深入分析feed-detail页面的视频播放机制
用户说投稿后用猫抓下载无水印 - 需要找出机制
"""
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
        
        video_requests = []
        
        def on_request(params):
            url = params.get('request', {}).get('url', '')
            if any(ext in url.lower() for ext in ['.mp4', '.m3u8', '.ts', '.webm', 'video', 'media']):
                video_requests.append({
                    'url': url[:200],
                    'type': params.get('type', ''),
                    'method': params.get('request', {}).get('method', ''),
                    'requestId': params.get('requestId', ''),
                })
        
        cdp.on("Network.requestWillBeSent", on_request)

        # 1. 访问第一个发布作品的feed-detail页面
        feed_id = "3210244702221402"
        print("=" * 60)
        print(f"[1] 访问 feed-detail/{feed_id}...")
        
        await page.goto(f"https://www.vidu.cn/feed-detail/{feed_id}", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(5)
        
        print(f"  URL: {page.url}")
        print(f"  Title: {await page.title()}")
        
        # 获取页面上的所有视频元素
        video_info = await page.evaluate("""() => {
            const videos = document.querySelectorAll('video');
            const results = [];
            for (const v of videos) {
                const sources = v.querySelectorAll('source');
                const style = window.getComputedStyle(v);
                const parent = v.parentElement;
                const parentStyle = parent ? window.getComputedStyle(parent) : null;
                
                results.push({
                    src: v.src || '',
                    currentSrc: v.currentSrc || '',
                    sources: Array.from(sources).map(s => ({src: s.src, type: s.type})),
                    width: v.videoWidth,
                    height: v.videoHeight,
                    clientWidth: v.clientWidth,
                    clientHeight: v.clientHeight,
                    visible: v.offsetParent !== null,
                    autoplay: v.autoplay,
                    loop: v.loop,
                    muted: v.muted,
                    // 检查父元素是否有水印覆盖层
                    parentClass: (parent?.className || '').toString().substring(0, 100),
                    // 找兄弟元素中的水印覆盖
                    siblings: parent ? Array.from(parent.children).map(c => ({
                        tag: c.tagName,
                        class: (c.className || '').toString().substring(0, 80),
                        isVideo: c.tagName === 'VIDEO',
                        hasAbsolutePosition: window.getComputedStyle(c).position === 'absolute',
                        zIndex: window.getComputedStyle(c).zIndex,
                        opacity: window.getComputedStyle(c).opacity,
                        pointerEvents: window.getComputedStyle(c).pointerEvents,
                    })) : []
                });
            }
            return results;
        }""")
        
        for i, v in enumerate(video_info):
            print(f"\n  视频{i+1}:")
            print(f"    src: {v['src'][:120]}")
            print(f"    currentSrc: {v['currentSrc'][:120]}")
            print(f"    尺寸: {v['width']}x{v['height']} (显示: {v['clientWidth']}x{v['clientHeight']})")
            print(f"    可见: {v['visible']}, autoplay: {v['autoplay']}, loop: {v['loop']}")
            print(f"    父class: {v['parentClass'][:80]}")
            print(f"    兄弟元素:")
            for s in v['siblings']:
                if s['hasAbsolutePosition'] or s['zIndex'] not in ['auto', '']:
                    print(f"      ⚠️ {s['tag']} absolute={s['hasAbsolutePosition']} z={s['zIndex']} opacity={s['opacity']} pointer={s['pointerEvents']} class={s['class'][:50]}")
                elif not s['isVideo']:
                    print(f"      {s['tag']} class={s['class'][:50]}")

        # 2. 检查CSS水印层
        print("\n" + "=" * 60)
        print("[2] 检查CSS水印覆盖层...")
        
        watermark_overlay = await page.evaluate("""() => {
            // 搜索所有可能是水印的覆盖层
            const results = [];
            document.querySelectorAll('*').forEach(el => {
                const style = window.getComputedStyle(el);
                const cls = (el.className || '').toString().toLowerCase();
                const text = el.textContent?.trim() || '';
                
                // 检查: absolute/fixed定位 + 高z-index + 在视频区域上方
                if ((style.position === 'absolute' || style.position === 'fixed') && 
                    el.offsetParent !== null) {
                    if (cls.includes('watermark') || cls.includes('water') || cls.includes('mark') ||
                        cls.includes('logo') || cls.includes('overlay') || cls.includes('mask') ||
                        text.includes('vidu') || text.includes('Vidu') || text.includes('VIDU') ||
                        (style.backgroundImage && style.backgroundImage !== 'none' && 
                         (cls.includes('brand') || cls.includes('badge')))) {
                        const rect = el.getBoundingClientRect();
                        results.push({
                            tag: el.tagName,
                            class: cls.substring(0, 80),
                            text: text.substring(0, 50),
                            position: style.position,
                            zIndex: style.zIndex,
                            opacity: style.opacity,
                            pointerEvents: style.pointerEvents,
                            x: Math.round(rect.x),
                            y: Math.round(rect.y),
                            w: Math.round(rect.width),
                            h: Math.round(rect.height),
                            bgImage: style.backgroundImage?.substring(0, 100) || '',
                            display: style.display,
                            visibility: style.visibility,
                        });
                    }
                }
            });
            return results;
        }""")
        
        if watermark_overlay:
            print(f"  找到 {len(watermark_overlay)} 个疑似水印覆盖层:")
            for wo in watermark_overlay:
                print(f"    {wo['tag']} class='{wo['class'][:40]}' text='{wo['text'][:20]}' z={wo['zIndex']} opacity={wo['opacity']} pos=({wo['x']},{wo['y']}) {wo['w']}x{wo['h']}")
        else:
            print("  未找到CSS水印覆盖层")

        # 3. 查看网络请求中的视频URL
        print("\n" + "=" * 60)
        print("[3] 网络请求中的视频URL...")
        
        for vr in video_requests:
            print(f"  [{vr['method']}] {vr['url']}")

        # 4. 检查feed-detail页面的API响应
        print("\n" + "=" * 60)
        print("[4] feed-detail API数据...")
        
        feed_detail = await page.evaluate("""async (feedId) => {
            const paths = [
                `/vidu/v1/feed/${feedId}`,
                `/vidu/v1/feed/detail/${feedId}`,
                `/vidu/v1/share_elements/${feedId}`,
                `/vidu/v1/share_elements/detail/${feedId}`,
                `/craftify/v1/media_asset/${feedId}`,
            ];
            const results = {};
            for (const path of paths) {
                try {
                    const r = await fetch('https://service.vidu.cn' + path, {credentials: 'include'});
                    const text = await r.text();
                    results[path] = {status: r.status, body: text.substring(0, 500)};
                } catch(e) {
                    results[path] = {error: e.message};
                }
            }
            return results;
        }""", feed_id)
        
        for path, data in feed_detail.items():
            status = data.get('status', 'err')
            if status != 404:
                print(f"  {path}: [{status}]")
                if status == 200:
                    try:
                        body = json.loads(data['body'])
                        # 重点找视频URL字段
                        print(f"    keys: {list(body.keys()) if isinstance(body, dict) else 'not dict'}")
                        if isinstance(body, dict):
                            for k, v in body.items():
                                if isinstance(v, str) and ('http' in v or 'mp4' in v or 'video' in v):
                                    print(f"    {k}: {v[:120]}")
                                elif isinstance(v, dict):
                                    for k2, v2 in v.items():
                                        if isinstance(v2, str) and ('http' in v2 or 'mp4' in v2 or 'video' in v2):
                                            print(f"    {k}.{k2}: {v2[:120]}")
                    except:
                        print(f"    raw: {data['body'][:300]}")

        # 5. 页面上的所有按钮 - 找下载相关
        print("\n" + "=" * 60)
        print("[5] feed-detail页面的按钮...")
        
        all_buttons = await page.evaluate("""() => {
            return Array.from(document.querySelectorAll('button, [role="button"], a'))
                .filter(b => b.offsetParent !== null)
                .map(b => ({
                    text: b.textContent?.trim()?.substring(0, 40) || '',
                    tag: b.tagName,
                    href: b.href?.substring(0, 80) || '',
                    class: (b.className||'').toString().substring(0, 60),
                    ariaLabel: b.getAttribute('aria-label') || '',
                    title: b.getAttribute('title') || '',
                }))
                .filter(b => b.text || b.ariaLabel || b.title)
                .slice(0, 30);
        }""")
        
        for b in all_buttons:
            line = f"  '{b['text'][:25]}'"
            if b['ariaLabel']: line += f" aria='{b['ariaLabel']}'"
            if b['title']: line += f" title='{b['title']}'"
            print(line)

        # 6. 试着点击视频播放，等更多网络请求
        print("\n" + "=" * 60)
        print("[6] 点击视频播放，监控更多请求...")
        
        first_video = await page.query_selector('video')
        if first_video:
            try:
                await first_video.click()
                await asyncio.sleep(3)
            except:
                pass
            
            # 检查是否出现了新的视频请求
            print(f"  总视频请求数: {len(video_requests)}")
            for vr in video_requests:
                url = vr['url']
                has_wm = '-wm' in url or 'watermark' in url.lower()
                print(f"  {'[WM]' if has_wm else '[??]'} {url}")

        # 7. 检查是否使用了MediaSource/Blob URL
        print("\n" + "=" * 60)
        print("[7] 检查 MediaSource / Blob URL...")
        
        media_check = await page.evaluate("""() => {
            const videos = document.querySelectorAll('video');
            const results = [];
            for (const v of videos) {
                results.push({
                    src: v.src?.substring(0, 100),
                    isBlob: v.src?.startsWith('blob:'),
                    hasMSE: !!v.mediaKeys || !!window.MediaSource,
                    networkState: v.networkState,
                    readyState: v.readyState,
                    buffered: v.buffered.length > 0 ? {
                        start: v.buffered.start(0),
                        end: v.buffered.end(0)
                    } : null,
                    duration: v.duration,
                });
            }
            // 检查 MediaSource 实例
            return {
                videos: results,
                hasMediaSource: typeof MediaSource !== 'undefined',
            };
        }""")
        print(f"  {json.dumps(media_check, indent=2, ensure_ascii=False)}")

        # 8. 用JS模拟猫抓的行为 - 直接抓取video src下载
        print("\n" + "=" * 60)
        print("[8] 模拟猫抓 - 获取视频实际播放的URL...")
        
        actual_urls = await page.evaluate("""() => {
            const videos = document.querySelectorAll('video');
            return Array.from(videos).map(v => ({
                src: v.src,
                currentSrc: v.currentSrc,
                // 如果是blob URL，我们无法直接访问
                // 猫抓可能拦截的是网络请求而不是video元素
            }));
        }""")
        for au in actual_urls:
            print(f"  src: {au['src'][:150]}")
            print(f"  currentSrc: {au['currentSrc'][:150]}")

        print("\n[完成]")

asyncio.run(main())
