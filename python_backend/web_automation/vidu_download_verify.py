"""下载投稿后的视频文件到本地 + 研究投稿API流程
验证：video-propogated-wm.mp4 是否真的有水印？
"""
import asyncio, json, os, struct
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        download_dir = os.path.join(os.path.dirname(__file__), 'downloads')
        os.makedirs(download_dir, exist_ok=True)

        # 1. 下载探索页面上某个视频（别人的）
        print("=" * 60)
        print("[1] 下载社区视频（别人发布的）...")
        
        await page.goto("https://www.vidu.cn/explore", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        video_src = await page.evaluate("document.querySelector('video')?.src || ''")
        if video_src:
            print(f"  URL: {video_src[:150]}...")
            
            # 直接用Python下载
            import urllib.request, ssl
            ssl_ctx = ssl.create_default_context()
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE
            
            community_file = os.path.join(download_dir, 'community_video.mp4')
            try:
                urllib.request.urlretrieve(video_src, community_file)
                size = os.path.getsize(community_file)
                print(f"  下载完成: {community_file} ({size} bytes)")
            except Exception as e:
                print(f"  下载失败: {e}")

        # 2. 下载用户自己发布的视频
        print("\n" + "=" * 60)
        print("[2] 下载用户自己发布的视频...")
        
        await page.goto("https://www.vidu.cn/profile", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        tabs = await page.query_selector_all("text=已发布")
        for tab in tabs:
            if await tab.is_visible():
                await tab.click()
                await asyncio.sleep(2)
                break
        
        my_video_src = await page.evaluate("document.querySelector('video')?.src || ''")
        if my_video_src:
            print(f"  URL: {my_video_src[:150]}...")
            my_file = os.path.join(download_dir, 'my_published_video.mp4')
            try:
                urllib.request.urlretrieve(my_video_src, my_file)
                size = os.path.getsize(my_file)
                print(f"  下载完成: {my_file} ({size} bytes)")
            except Exception as e:
                print(f"  下载失败: {e}")

        # 3. 下载任务创建的水印版
        print("\n" + "=" * 60)
        print("[3] 下载任务创建的水印版...")
        
        task_uri = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.page_sz=1', {credentials: 'include'});
            const d = await r.json();
            if (d.tasks?.[0]?.creations?.[0]) {
                return d.tasks[0].creations[0].uri;
            }
            return null;
        }""")
        
        if task_uri:
            print(f"  URL: {task_uri[:150]}...")
            task_file = os.path.join(download_dir, 'task_watermarked_video.mp4')
            try:
                urllib.request.urlretrieve(task_uri, task_file)
                size = os.path.getsize(task_file)
                print(f"  下载完成: {task_file} ({size} bytes)")
            except Exception as e:
                print(f"  下载失败: {e}")

        # 4. 对比文件
        print("\n" + "=" * 60)
        print("[4] 对比文件...")
        
        for fn in ['community_video.mp4', 'my_published_video.mp4', 'task_watermarked_video.mp4']:
            fp = os.path.join(download_dir, fn)
            if os.path.exists(fp):
                size = os.path.getsize(fp)
                # 读取文件头
                with open(fp, 'rb') as f:
                    header = f.read(32)
                    # 检查mp4 ftyp box
                    ftyp = header[4:8]
                    brand = header[8:12]
                print(f"  {fn}: {size} bytes, ftyp={ftyp}, brand={brand}")
            else:
                print(f"  {fn}: 不存在")

        # 5. 研究投稿（submit/publish）的JS流程
        print("\n" + "=" * 60)
        print("[5] 研究投稿API流程...")
        
        submit_flow = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            const results = [];
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    
                    // 搜索投稿/发布/submit相关代码
                    const patterns = ['share_elements/submit', 'publish', 'recommend', '投稿', '发布'];
                    
                    for (const pat of patterns) {
                        let idx = code.indexOf(pat);
                        if (idx !== -1) {
                            const filename = s.src.split('/').pop();
                            const ctx = code.substring(Math.max(0, idx - 100), Math.min(code.length, idx + 200));
                            results.push({file: filename, pattern: pat, context: ctx});
                        }
                    }
                } catch(e) {}
            }
            return results;
        }""")
        
        for r in submit_flow[:10]:
            print(f"\n  [{r['pattern']}] in {r['file']}:")
            print(f"    {r['context'][:250]}")

        # 6. 查找投稿UI入口
        print("\n" + "=" * 60)
        print("[6] 查找投稿UI入口...")
        
        # 回到创建页面生成后的状态
        await page.goto("https://www.vidu.cn/create", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        # 搜索页面中所有与"投稿""发布""推荐"相关的元素
        publish_elements = await page.evaluate("""() => {
            const results = [];
            document.querySelectorAll('*').forEach(el => {
                if (el.children.length === 0 && el.offsetParent !== null) {
                    const t = el.textContent?.trim();
                    if (t && (t.includes('投稿') || t.includes('发布') || t.includes('推荐') || 
                              t.includes('分享') || t.includes('publish') || t.includes('submit') ||
                              t.includes('做同款') || t.includes('灵感'))) {
                        results.push({
                            tag: el.tagName,
                            text: t.substring(0, 40),
                            class: (el.className||'').toString().substring(0, 50),
                            visible: el.offsetParent !== null,
                            x: Math.round(el.getBoundingClientRect().x),
                            y: Math.round(el.getBoundingClientRect().y),
                        });
                    }
                }
            });
            return results.slice(0, 15);
        }""")
        
        for el in publish_elements:
            print(f"  '{el['text']}' {el['tag']} at ({el['x']},{el['y']}) class={el['class'][:30]}")

        # 7. 检查share_elements/submit API的正确请求格式
        print("\n" + "=" * 60)
        print("[7] 分析submit API的正确格式...")
        
        submit_code = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    
                    // 找submit函数的完整定义
                    if (code.includes('share_elements/submit')) {
                        const idx = code.indexOf('share_elements/submit');
                        // 往前找函数开头
                        let start = idx;
                        for (let i = idx; i > Math.max(0, idx - 500); i--) {
                            if (code[i] === '{' && code[i-1] === '>' || code[i] === '(' && code.substring(i-5, i).includes('post')) {
                                start = i;
                                break;
                            }
                        }
                        start = Math.max(0, start - 50);
                        return code.substring(start, Math.min(code.length, idx + 300));
                    }
                } catch(e) {}
            }
            return null;
        }""")
        
        if submit_code:
            print(f"  Submit代码: {submit_code[:500]}")

        # 8. 另一个关键测试：用户的第二个feed-detail
        print("\n" + "=" * 60)
        print("[8] 尝试用户第二个发布视频...")
        
        await page.goto("https://www.vidu.cn/feed-detail/3210273079224399", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(5)
        
        content = await page.evaluate("""() => {
            return {
                title: document.title,
                bodyText: document.body?.innerText?.substring(0, 300) || '',
                videos: document.querySelectorAll('video').length,
                videoSrc: document.querySelector('video')?.src?.substring(0, 150) || '',
            };
        }""")
        print(f"  标题: {content['title']}")
        print(f"  视频数: {content['videos']}")
        print(f"  视频src: {content['videoSrc']}")
        print(f"  内容: {content['bodyText'][:200]}")

        print("\n[完成]")

asyncio.run(main())
