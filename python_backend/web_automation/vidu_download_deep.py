"""深入分析下载机制 + 尝试直接触发下载"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 深入分析下载函数的完整逻辑
        print("=" * 60)
        print("[1] 提取完整下载函数逻辑...")
        
        download_logic = await page.evaluate("""async () => {
            const results = [];
            const scripts = performance.getEntriesByType('resource').filter(r => r.name.includes('.js'));
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    
                    // 找watermarkMode相关的完整代码
                    const wIdx = text.indexOf('watermarkMode');
                    if (wIdx > -1) {
                        // 往前找函数开始
                        let funcStart = wIdx;
                        let braceCount = 0;
                        for (let k = wIdx; k >= Math.max(0, wIdx - 2000); k--) {
                            if (text[k] === '}') braceCount++;
                            if (text[k] === '{') {
                                braceCount--;
                                if (braceCount < 0) { funcStart = k; break; }
                            }
                        }
                        const ctx = text.substring(funcStart, Math.min(text.length, wIdx + 800));
                        results.push({type: 'watermarkMode_func', file: s.name.split('/').pop(), code: ctx});
                    }
                    
                    // 找 download 弹窗/对话框组件
                    const dlgPatterns = ['DownloadDialog', 'download-dialog', 'downloadDialog', 'DownloadModal', 'download_modal'];
                    for (const pat of dlgPatterns) {
                        const idx = text.indexOf(pat);
                        if (idx > -1) {
                            const ctx = text.substring(Math.max(0, idx - 300), Math.min(text.length, idx + 600));
                            results.push({type: 'download_dialog', pattern: pat, file: s.name.split('/').pop(), code: ctx});
                        }
                    }
                    
                    // 找 blob: 或 createObjectURL（直接下载方式）
                    const blobIdx = text.indexOf('createObjectURL');
                    if (blobIdx > -1) {
                        const ctx = text.substring(Math.max(0, blobIdx - 300), Math.min(text.length, blobIdx + 400));
                        results.push({type: 'blob_download', file: s.name.split('/').pop(), code: ctx});
                    }
                    
                    // 找 a.download 或 link.download（链接下载方式）
                    const aDownloadIdx = text.indexOf('.download=');
                    if (aDownloadIdx > -1) {
                        const ctx = text.substring(Math.max(0, aDownloadIdx - 300), Math.min(text.length, aDownloadIdx + 300));
                        results.push({type: 'link_download', file: s.name.split('/').pop(), code: ctx});
                    }
                    
                } catch(e) {}
            }
            return results;
        }""")
        
        for r in download_logic:
            print(f"\n  [{r['type']}] {r.get('pattern', '')} in {r['file']}:")
            code = r['code']
            print(f"    {code[:500]}")

        # 2. 获取用户VIP状态和水印相关信息
        print("\n" + "=" * 60)
        print("[2] 查看用户VIP/套餐状态...")
        
        user_plan = await page.evaluate("""async () => {
            const token = document.cookie.split(';').map(c => c.trim())
                .find(c => c.startsWith('token='));
            if (!token) return 'no token';
            const tk = token.split('=')[1];
            
            const results = {};
            
            // 用户信息
            try {
                const r = await fetch('https://service.vidu.cn/vidu/v1/user', {
                    headers: {'Authorization': 'Bearer ' + tk}
                });
                results.user = await r.json();
            } catch(e) { results.user_error = e.message; }
            
            // 套餐信息
            try {
                const r = await fetch('https://service.vidu.cn/vidu/v1/user/subscription', {
                    headers: {'Authorization': 'Bearer ' + tk}
                });
                results.subscription = await r.json();
            } catch(e) { results.sub_error = e.message; }
            
            // 尝试获取creation详情（看水印字段）
            try {
                const r = await fetch('https://service.vidu.cn/vidu/v1/tasks?limit=1', {
                    headers: {'Authorization': 'Bearer ' + tk}
                });
                const data = await r.json();
                if (data.tasks && data.tasks[0]) {
                    const task = data.tasks[0];
                    const creation = task.creations?.[0];
                    results.sample_creation = {
                        id: creation?.id,
                        uri: creation?.uri?.substring(0, 80),
                        nomark_uri: creation?.nomark_uri,
                        has_copyright: creation?.has_copyright,
                        resolution: creation?.resolution,
                        type: task.type,
                        state: task.state
                    };
                }
            } catch(e) { results.task_error = e.message; }
            
            return results;
        }""")
        print(f"  {json.dumps(user_plan, indent=2, ensure_ascii=False)}")

        # 3. 试试用JS直接调用前端的下载函数
        print("\n" + "=" * 60)
        print("[3] 尝试从create页面点击视频触发下载弹窗...")
        
        await page.goto("https://www.vidu.cn/create", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(3)
        
        # 找到第一个视频，点击它看看会不会弹出操作菜单
        videos = await page.query_selector_all("video")
        if videos:
            # 不hover而是直接点击视频
            box = await videos[0].bounding_box()
            if box:
                print(f"  点击视频 @ ({box['x'] + box['width']/2}, {box['y'] + box['height']/2})")
                
                download_responses = []
                async def on_response(resp):
                    url = resp.url
                    if any(k in url.lower() for k in ['download', '.mp4', 'nomark', 'watermark', 'creation', 'task']):
                        try:
                            body = await resp.text()
                            download_responses.append({'url': url[:150], 'status': resp.status, 'body': body[:200]})
                        except:
                            download_responses.append({'url': url[:150], 'status': resp.status})
                
                page.on("response", on_response)
                await page.mouse.click(box['x'] + box['width']/2, box['y'] + box['height']/2)
                await asyncio.sleep(3)
                
                # 检查是否出现了新的弹窗/对话框
                dialogs = await page.evaluate("""() => {
                    const modals = document.querySelectorAll('[role="dialog"], [class*="modal"], [class*="dialog"], [class*="popup"], [class*="overlay"][class*="open"], [class*="drawer"]');
                    return Array.from(modals).map(m => ({
                        tag: m.tagName,
                        className: (m.className || '').toString().substring(0, 100),
                        text: (m.textContent || '').trim().substring(0, 200),
                        visible: m.offsetParent !== null || getComputedStyle(m).display !== 'none'
                    }));
                }""")
                print(f"  弹窗/对话框: {len(dialogs)}")
                for d in dialogs:
                    if d['visible']:
                        print(f"    [{d['tag']}] class='{d['className'][:60]}' text='{d['text'][:100]}'")
                
                # 检查是否URL变了（导航到详情页）
                print(f"  当前URL: {page.url}")
                
                page.remove_listener("response", on_response)
                if download_responses:
                    print(f"  网络请求:")
                    for r in download_responses[:5]:
                        print(f"    {r}")

        # 4. 直接尝试访问视频无水印URL
        print("\n" + "=" * 60)
        print("[4] 测试直接构造无水印URL...")
        
        url_test = await page.evaluate("""async () => {
            const token = document.cookie.split(';').map(c => c.trim())
                .find(c => c.startsWith('token='));
            const tk = token ? token.split('=')[1] : '';
            
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks?limit=1', {
                headers: {'Authorization': 'Bearer ' + tk}
            });
            const data = await r.json();
            const creation = data.tasks?.[0]?.creations?.[0];
            if (!creation) return 'no creation';
            
            const uri = creation.uri || '';
            const results = {original_uri: uri.substring(0, 100)};
            
            // 尝试把watermarked替换为其他路径
            if (uri.includes('watermarked')) {
                const try1 = uri.replace('watermarked.mp4', 'output.mp4');
                const try2 = uri.replace('watermarked.mp4', 'video.mp4');
                const try3 = uri.replace('watermarked.mp4', 'original.mp4');
                const try4 = uri.replace('/watermarked.mp4', '.mp4');
                
                for (const [name, url] of [['output', try1], ['video', try2], ['original', try3], ['no_suffix', try4]]) {
                    try {
                        const resp = await fetch(url, {method: 'HEAD'});
                        results[name] = {status: resp.status, size: resp.headers.get('content-length')};
                    } catch(e) {
                        results[name] = {error: e.message};
                    }
                }
            }
            
            return results;
        }""")
        print(f"  {json.dumps(url_test, indent=2, ensure_ascii=False)}")

        # 5. 检查视频播放器实际使用的源
        print("\n" + "=" * 60)
        print("[5] 检查页面上视频播放器的实际src...")
        
        video_sources = await page.evaluate("""() => {
            const videos = document.querySelectorAll('video');
            return Array.from(videos).map(v => ({
                src: v.src?.substring(0, 150) || '',
                currentSrc: v.currentSrc?.substring(0, 150) || '',
                poster: v.poster?.substring(0, 100) || '',
                sources: Array.from(v.querySelectorAll('source')).map(s => s.src?.substring(0, 150))
            }));
        }""")
        for i, vs in enumerate(video_sources):
            print(f"  视频{i}: src={vs['src'][:100]}")
            if vs['currentSrc'] and vs['currentSrc'] != vs['src']:
                print(f"         currentSrc={vs['currentSrc'][:100]}")

        # 6. 尝试vidu.studio全球版
        print("\n" + "=" * 60)
        print("[6] 测试 vidu.studio 全球版接口...")
        
        global_test = await page.evaluate("""async () => {
            const token = document.cookie.split(';').map(c => c.trim())
                .find(c => c.startsWith('token='));
            const tk = token ? token.split('=')[1] : '';
            const results = {};
            
            // 尝试用同一个token访问全球版API
            try {
                const r = await fetch('https://service.vidu.studio/vidu/v1/tasks?limit=1', {
                    headers: {'Authorization': 'Bearer ' + tk}
                });
                results.global_tasks = {status: r.status};
                if (r.ok) {
                    const data = await r.json();
                    results.global_tasks.data = JSON.stringify(data).substring(0, 300);
                }
            } catch(e) {
                results.global_tasks = {error: e.message};
            }
            
            // 尝试全球版用户信息
            try {
                const r = await fetch('https://service.vidu.studio/vidu/v1/user', {
                    headers: {'Authorization': 'Bearer ' + tk}
                });
                results.global_user = {status: r.status};
                if (r.ok) {
                    const data = await r.json();
                    results.global_user.plan = data.subs_plan;
                }
            } catch(e) {
                results.global_user = {error: e.message};
            }
            
            return results;
        }""")
        print(f"  {json.dumps(global_test, indent=2, ensure_ascii=False)}")

        print("\n[完成]")

asyncio.run(main())
