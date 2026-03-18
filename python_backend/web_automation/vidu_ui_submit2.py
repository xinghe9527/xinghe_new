"""
在投稿弹窗中选择creation并提交，CDP拦截请求获取精确body格式
"""
import asyncio
import json
from playwright.async_api import async_playwright

CDP_URL = "http://localhost:9223"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(CDP_URL)
        context = browser.contexts[0]
        
        # 找到已打开的create页面
        create_page = None
        for page in context.pages:
            if '/create' in page.url:
                create_page = page
                break
        
        if not create_page:
            print("❌ 没有create页面")
            return
        
        print(f"当前页面: {create_page.url}")
        
        # 设置CDP网络拦截
        cdp = await create_page.context.new_cdp_session(create_page)
        await cdp.send("Network.enable")
        
        captured_requests = []
        
        def on_request(params):
            url = params.get("request", {}).get("url", "")
            method = params.get("request", {}).get("method", "")
            if "submit" in url or "share_element" in url or "material" in url:
                post_data = params.get("request", {}).get("postData", "")
                captured_requests.append({
                    "url": url,
                    "method": method,
                    "body": post_data
                })
                print(f"\n🎯 捕获: {method} {url}")
                print(f"   Body: {post_data}")
        
        def on_response(params):
            url = params.get("response", {}).get("url", "")
            status = params.get("response", {}).get("status", 0)
            if "submit" in url or "share_element" in url:
                print(f"📩 响应: [{status}] {url}")
        
        cdp.on("Network.requestWillBeSent", on_request)
        cdp.on("Network.responseReceived", on_response)
        
        # 检查弹窗是否还在
        dialog_exists = await create_page.evaluate("""() => {
            const d = document.querySelector('[role="dialog"]');
            return d ? d.textContent.substring(0, 100) : null;
        }""")
        
        if not dialog_exists or '投稿' not in dialog_exists:
            print("弹窗已关闭，重新打开...")
            submit_btn = await create_page.query_selector('button:has-text("投稿")')
            if submit_btn:
                await submit_btn.click()
                await asyncio.sleep(2)
        
        # 详细分析弹窗中的creation列表
        print("\n分析弹窗中的creation列表...")
        creations_info = await create_page.evaluate("""() => {
            const dialog = document.querySelector('[role="dialog"]');
            if (!dialog) return {error: 'no dialog'};
            
            // 找到所有可能的creation卡片
            const allElements = dialog.querySelectorAll('*');
            const cards = [];
            const clickables = [];
            
            for (const el of allElements) {
                const text = el.textContent || '';
                const cls = el.className || '';
                
                // 找视频卡片 - 通常有缩略图和时长标签
                if ((text.includes('1080p') || text.includes('720p') || text.includes('5s') || text.includes('4s')) 
                    && el.offsetWidth > 50 && el.offsetWidth < 300) {
                    const rect = el.getBoundingClientRect();
                    cards.push({
                        tag: el.tagName,
                        text: text.trim().substring(0, 50),
                        class: cls.substring(0, 80),
                        x: Math.round(rect.x),
                        y: Math.round(rect.y),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height),
                        hasPosted: text.includes('已投稿'),
                        children: el.children.length
                    });
                }
                
                // 找已投稿标记
                if (text === '已投稿' && el.offsetWidth > 0) {
                    const rect = el.getBoundingClientRect();
                    clickables.push({
                        tag: el.tagName,
                        text: '已投稿',
                        x: Math.round(rect.x),
                        y: Math.round(rect.y),
                        parent_class: (el.parentElement?.className || '').substring(0, 60)
                    });
                }
            }
            
            // 找可选的creation - 没有已投稿标记的卡片
            // 查看dialog的结构
            const structure = [];
            const walk = (el, depth) => {
                if (depth > 6) return;
                const rect = el.getBoundingClientRect();
                if (rect.width < 10 || rect.height < 10) return;
                
                const info = {
                    tag: el.tagName,
                    class: (el.className || '').substring(0, 50),
                    text: (el.textContent || '').substring(0, 30),
                    role: el.getAttribute('role'),
                    state: el.getAttribute('data-state'),
                    w: Math.round(rect.width),
                    h: Math.round(rect.height),
                    x: Math.round(rect.x),
                    y: Math.round(rect.y)
                };
                
                // 只记录有意义的元素
                if (el.tagName === 'IMG' || el.tagName === 'VIDEO' || el.tagName === 'BUTTON' 
                    || el.getAttribute('role') || el.getAttribute('data-state')
                    || (el.className && el.className.includes('cursor-pointer'))
                    || (el.className && el.className.includes('select'))
                    || (el.className && el.className.includes('check'))) {
                    structure.push(info);
                }
                
                for (const child of el.children) {
                    walk(child, depth + 1);
                }
            };
            
            const dialogs = document.querySelectorAll('[role="dialog"]');
            if (dialogs.length > 1) {
                walk(dialogs[1], 0); // 第二个dialog是投稿弹窗
            }
            
            return {cards, clickables, structure: structure.slice(0, 30)};
        }""")
        
        print(f"\n视频卡片 ({len(creations_info.get('cards', []))}):")
        for c in creations_info.get('cards', []):
            print(f"  [{c['x']},{c['y']}] {c['w']}x{c['h']} posted={c['hasPosted']} text={c['text']}")
        
        print(f"\n已投稿标记 ({len(creations_info.get('clickables', []))}):")
        for c in creations_info.get('clickables', []):
            print(f"  [{c['x']},{c['y']}] {c['text']} parent={c['parent_class']}")
        
        print(f"\n弹窗结构元素 ({len(creations_info.get('structure', []))}):")
        for s in creations_info.get('structure', []):
            print(f"  {s['tag']} [{s['x']},{s['y']}] {s['w']}x{s['h']} role={s.get('role')} state={s.get('state')} class={s['class'][:40]}")
        
        # 找到未投稿的卡片并点击
        cards = creations_info.get('cards', [])
        unposted_cards = [c for c in cards if not c['hasPosted'] and c['w'] > 50]
        
        if unposted_cards:
            # 选择第一个未投稿的卡片
            target_card = unposted_cards[0]
            click_x = target_card['x'] + target_card['w'] // 2
            click_y = target_card['y'] + target_card['h'] // 2
            print(f"\n点击未投稿卡片: ({click_x}, {click_y})")
            await create_page.mouse.click(click_x, click_y)
            await asyncio.sleep(1)
        else:
            print("\n没有明显的未投稿卡片，尝试通过结构点击...")
            # 直接截图看看弹窗长什么样
            await create_page.screenshot(path="debug_dialog_detail.png")
            
            # 尝试找到创作内容区域并点击
            # 弹窗中应该有缩略图网格
            grid_items = await create_page.evaluate("""() => {
                const dialog = document.querySelectorAll('[role="dialog"]')[1];
                if (!dialog) return [];
                
                // 找所有图片或视频元素
                const media = dialog.querySelectorAll('img, video');
                return [...media].map(m => {
                    const rect = m.getBoundingClientRect();
                    return {
                        tag: m.tagName,
                        src: (m.src || '').substring(0, 60),
                        x: Math.round(rect.x),
                        y: Math.round(rect.y),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height)
                    };
                }).filter(m => m.w > 30);
            }""")
            print(f"\n媒体元素: {json.dumps(grid_items[:10], ensure_ascii=False)}")
            
            if grid_items:
                # 点击第一个缩略图
                target = grid_items[0]
                click_x = target['x'] + target['w'] // 2
                click_y = target['y'] + target['h'] // 2
                print(f"点击缩略图: ({click_x}, {click_y})")
                await create_page.mouse.click(click_x, click_y)
                await asyncio.sleep(1)
        
        # 检查提交按钮状态
        await asyncio.sleep(1)
        submit_state = await create_page.evaluate("""() => {
            const dialog = document.querySelectorAll('[role="dialog"]')[1];
            if (!dialog) return {error: 'no dialog'};
            const buttons = dialog.querySelectorAll('button');
            const result = [];
            for (const b of buttons) {
                result.push({
                    text: b.textContent.trim(),
                    disabled: b.disabled
                });
            }
            return result;
        }""")
        print(f"\n当前按钮状态: {json.dumps(submit_state, ensure_ascii=False)}")
        
        # 截图
        await create_page.screenshot(path="debug_after_select.png")
        
        # 如果提交按钮可用,点击
        submit_enabled = False
        for btn in (submit_state if isinstance(submit_state, list) else []):
            if btn.get('text') == '提交' and not btn.get('disabled'):
                submit_enabled = True
                break
        
        if submit_enabled:
            print("\n✅ 提交按钮已启用，点击提交...")
            await create_page.evaluate("""() => {
                const dialog = document.querySelectorAll('[role="dialog"]')[1];
                const buttons = dialog.querySelectorAll('button');
                for (const b of buttons) {
                    if (b.textContent.trim() === '提交' && !b.disabled) {
                        b.click();
                        return true;
                    }
                }
                return false;
            }""")
            await asyncio.sleep(3)
            
            # 截图
            await create_page.screenshot(path="debug_after_submit.png")
        else:
            print("\n⚠️ 提交按钮仍然禁用")
            # 尝试更详细的分析弹窗
            full_dialog = await create_page.evaluate("""() => {
                const dialog = document.querySelectorAll('[role="dialog"]')[1];
                if (!dialog) return 'no dialog';
                return dialog.innerHTML.substring(0, 3000);
            }""")
            print(f"\n弹窗HTML (前3000字符):\n{full_dialog}")
        
        # 输出所有捕获的请求
        print(f"\n{'='*60}")
        print(f"📋 共捕获 {len(captured_requests)} 个相关请求:")
        for i, req in enumerate(captured_requests):
            print(f"\n  Request {i+1}: {req['method']} {req['url']}")
            if req['body']:
                try:
                    body = json.loads(req['body'])
                    print(f"  BODY:\n{json.dumps(body, indent=2, ensure_ascii=False)}")
                except:
                    print(f"  RAW: {req['body']}")

asyncio.run(main())
