"""
完整UI投稿流程：打开create页面→点投稿→选creation→提交，CDP全程拦截
"""
import asyncio
import json
from playwright.async_api import async_playwright

CDP_URL = "http://localhost:9223"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(CDP_URL)
        context = browser.contexts[0]
        
        # 获取一个未投稿的creation
        any_page = context.pages[0]
        tasks_data = await any_page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?page_no=1&page_size=5', {
                credentials: 'include'
            });
            return await r.json();
        }""")
        
        target = None
        for task in tasks_data.get('tasks', []):
            for c in task.get('creations', []):
                if not c.get('is_posted'):
                    target = {'task_id': task['id'], 'creation_id': c['id'], 'grade': c.get('grade')}
                    break
            if target:
                break
        
        if not target:
            print("❌ 没有未投稿的creation")
            return
        
        print(f"目标: task={target['task_id']}, creation={target['creation_id']}, grade={target['grade']}")
        
        # 打开create页面
        page = await context.new_page()
        url = f"https://www.vidu.cn/create?taskId={target['task_id']}"
        print(f"打开: {url}")
        await page.goto(url)
        await page.wait_for_load_state("networkidle")
        await asyncio.sleep(3)
        
        # 设置CDP拦截
        cdp = await context.new_cdp_session(page)
        await cdp.send("Network.enable")
        
        captured = []
        
        def on_request(params):
            url = params.get("request", {}).get("url", "")
            method = params.get("request", {}).get("method", "")
            if "submit" in url or "share_element" in url:
                post_data = params.get("request", {}).get("postData", "")
                captured.append({"url": url, "method": method, "body": post_data})
                print(f"\n🎯 捕获: {method} {url}")
                print(f"   Body: {post_data}")
        
        cdp.on("Network.requestWillBeSent", on_request)
        
        # 点击投稿按钮
        print("\n查找投稿按钮...")
        await page.wait_for_selector('button:has-text("投稿")', timeout=10000)
        submit_btn = await page.query_selector('button:has-text("投稿")')
        print(f"投稿按钮: found={submit_btn is not None}")
        
        await submit_btn.click()
        await asyncio.sleep(2)
        
        # 截图弹窗
        await page.screenshot(path="debug_step1_dialog.png")
        
        # 分析弹窗中的媒体元素（缩略图）
        media_info = await page.evaluate("""() => {
            const dialogs = document.querySelectorAll('[role="dialog"]');
            const dialog = dialogs[dialogs.length - 1]; // 最后一个dialog
            if (!dialog) return {error: 'no dialog'};
            
            // 找所有图片（creation缩略图）
            const imgs = dialog.querySelectorAll('img');
            const imgList = [];
            for (const img of imgs) {
                const rect = img.getBoundingClientRect();
                if (rect.width > 30 && rect.height > 30) {
                    // 检查父元素是否有"已投稿"标记
                    let parent = img.parentElement;
                    let hasPosted = false;
                    let clickTarget = img;
                    for (let i = 0; i < 5 && parent; i++) {
                        if (parent.textContent.includes('已投稿')) {
                            hasPosted = true;
                        }
                        // 找可点击的容器
                        if (parent.className && (parent.className.includes('cursor') || parent.onclick)) {
                            clickTarget = parent;
                        }
                        parent = parent.parentElement;
                    }
                    imgList.push({
                        src: (img.src || '').substring(0, 80),
                        x: Math.round(rect.x + rect.width/2),
                        y: Math.round(rect.y + rect.height/2),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height),
                        posted: hasPosted
                    });
                }
            }
            
            // 找按钮状态
            const buttons = [];
            for (const b of dialog.querySelectorAll('button')) {
                buttons.push({text: b.textContent.trim(), disabled: b.disabled});
            }
            
            return {images: imgList, buttons};
        }""")
        
        print(f"\n缩略图 ({len(media_info.get('images', []))}):")
        for img in media_info.get('images', []):
            status = "已投稿" if img['posted'] else "未投稿"
            print(f"  [{img['x']},{img['y']}] {img['w']}x{img['h']} {status}")
        
        print(f"\n按钮: {json.dumps(media_info.get('buttons', []), ensure_ascii=False)}")
        
        # 点击未投稿的缩略图
        unposted_imgs = [i for i in media_info.get('images', []) if not i['posted']]
        if not unposted_imgs:
            print("⚠️ 所有缩略图都标记已投稿，尝试点击第一个...")
            unposted_imgs = media_info.get('images', [])
        
        if unposted_imgs:
            target_img = unposted_imgs[0]
            print(f"\n点击缩略图: ({target_img['x']}, {target_img['y']})")
            await page.mouse.click(target_img['x'], target_img['y'])
            await asyncio.sleep(1)
            
            # 截图看选中效果
            await page.screenshot(path="debug_step2_selected.png")
            
            # 检查提交按钮状态
            btn_state = await page.evaluate("""() => {
                const dialogs = document.querySelectorAll('[role="dialog"]');
                const dialog = dialogs[dialogs.length - 1];
                if (!dialog) return [];
                return [...dialog.querySelectorAll('button')].map(b => ({
                    text: b.textContent.trim(),
                    disabled: b.disabled
                }));
            }""")
            print(f"\n选中后按钮状态: {json.dumps(btn_state, ensure_ascii=False)}")
            
            # 检查提交是否启用
            submit_enabled = any(b['text'] == '提交' and not b['disabled'] for b in btn_state)
            
            if not submit_enabled:
                print("\n提交仍然禁用，尝试多选几个...")
                # 再点几个
                for img in unposted_imgs[1:3]:
                    print(f"  额外点击: ({img['x']}, {img['y']})")
                    await page.mouse.click(img['x'], img['y'])
                    await asyncio.sleep(0.5)
                
                await asyncio.sleep(1)
                btn_state2 = await page.evaluate("""() => {
                    const dialogs = document.querySelectorAll('[role="dialog"]');
                    const dialog = dialogs[dialogs.length - 1];
                    if (!dialog) return [];
                    return [...dialog.querySelectorAll('button')].map(b => ({
                        text: b.textContent.trim(),
                        disabled: b.disabled
                    }));
                }""")
                print(f"多选后按钮: {json.dumps(btn_state2, ensure_ascii=False)}")
                submit_enabled = any(b['text'] == '提交' and not b['disabled'] for b in btn_state2)
            
            if submit_enabled:
                print("\n✅ 提交按钮已启用！点击提交...")
                await page.evaluate("""() => {
                    const dialogs = document.querySelectorAll('[role="dialog"]');
                    const dialog = dialogs[dialogs.length - 1];
                    for (const b of dialog.querySelectorAll('button')) {
                        if (b.textContent.trim() === '提交' && !b.disabled) {
                            b.click();
                            return true;
                        }
                    }
                    return false;
                }""")
                
                # 等待网络请求
                await asyncio.sleep(5)
                await page.screenshot(path="debug_step3_after_submit.png")
            else:
                print("\n⚠️ 提交按钮仍然禁用，输出弹窗HTML...")
                html = await page.evaluate("""() => {
                    const dialogs = document.querySelectorAll('[role="dialog"]');
                    const dialog = dialogs[dialogs.length - 1];
                    return dialog ? dialog.innerHTML.substring(0, 5000) : 'no dialog';
                }""")
                print(html[:3000])
        
        # 输出捕获的请求
        print(f"\n{'='*60}")
        print(f"📋 共捕获 {len(captured)} 个请求:")
        for i, req in enumerate(captured):
            print(f"\n  [{i+1}] {req['method']} {req['url']}")
            if req['body']:
                try:
                    body = json.loads(req['body'])
                    print(f"  BODY:\n{json.dumps(body, indent=2, ensure_ascii=False)}")
                except:
                    print(f"  RAW: {req['body']}")
        
        # 关闭新页面
        await page.close()

asyncio.run(main())
