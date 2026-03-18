"""
点击未投稿卡片 → 提交 → CDP拦截精确body格式
"""
import asyncio
import json
from playwright.async_api import async_playwright

CDP_URL = "http://localhost:9223"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(CDP_URL)
        context = browser.contexts[0]
        
        # 找create页面
        page = None
        for pg in context.pages:
            if 'vidu.cn' in pg.url:
                page = pg
                break
        
        if not page:
            print("❌ 无页面")
            return
        
        print(f"页面: {page.url}")
        
        # 设置CDP拦截 - 这次拦截所有请求
        cdp = await context.new_cdp_session(page)
        await cdp.send("Network.enable")
        
        captured = []
        responses = {}
        
        def on_request(params):
            url = params.get("request", {}).get("url", "")
            method = params.get("request", {}).get("method", "")
            req_id = params.get("requestId", "")
            if method == "POST" and "service.vidu.cn" in url:
                post_data = params.get("request", {}).get("postData", "")
                captured.append({
                    "url": url,
                    "method": method,
                    "body": post_data,
                    "requestId": req_id
                })
                print(f"\n🎯 POST: {url}")
                print(f"   Body: {post_data[:500]}")
        
        async def get_response_body(req_id):
            try:
                result = await cdp.send("Network.getResponseBody", {"requestId": req_id})
                return result.get("body", "")
            except:
                return ""
        
        def on_response(params):
            url = params.get("response", {}).get("url", "")
            status = params.get("response", {}).get("status", 0)
            req_id = params.get("requestId", "")
            if "service.vidu.cn" in url and ("submit" in url or "share_element" in url or "material" in url):
                responses[req_id] = {"url": url, "status": status}
                print(f"📩 响应: [{status}] {url}")
        
        cdp.on("Network.requestWillBeSent", on_request)
        cdp.on("Network.responseReceived", on_response)
        
        # 检查弹窗状态
        dialog_count = await page.evaluate("document.querySelectorAll('[role=\"dialog\"]').length")
        print(f"当前dialog数量: {dialog_count}")
        
        if dialog_count < 2:
            # 需要重新打开投稿弹窗
            # 首先确认在create页面
            if '/create' not in page.url:
                print("不在create页面，导航...")
                await page.goto("https://www.vidu.cn/create")
                await page.wait_for_load_state("networkidle")
                await asyncio.sleep(3)
            
            btn = await page.query_selector('button:has-text("投稿")')
            if btn:
                print("点击投稿按钮...")
                await btn.click()
                await asyncio.sleep(2)
            else:
                print("❌ 找不到投稿按钮")
                return
        
        # 确认弹窗中有未投稿的卡片
        card_info = await page.evaluate("""() => {
            const dialogs = document.querySelectorAll('[role="dialog"]');
            const dialog = dialogs[dialogs.length - 1];
            if (!dialog) return {error: 'no dialog'};
            
            // 找所有卡片容器（带 aspect-square 的div）
            const cards = dialog.querySelectorAll('.aspect-square');
            const result = [];
            for (const card of cards) {
                const rect = card.getBoundingClientRect();
                const text = card.textContent || '';
                const opacity = card.className.includes('opacity-40');
                result.push({
                    x: Math.round(rect.x + rect.width/2),
                    y: Math.round(rect.y + rect.height/2),
                    w: Math.round(rect.width),
                    h: Math.round(rect.height),
                    posted: text.includes('已投稿'),
                    opacity40: opacity
                });
            }
            return {cards: result};
        }""")
        
        cards = card_info.get('cards', [])
        print(f"\n卡片列表 ({len(cards)}):")
        for i, c in enumerate(cards):
            status = "已投稿" if c['posted'] else "未投稿"
            dim = " (dimmed)" if c['opacity40'] else ""
            print(f"  [{i}] ({c['x']},{c['y']}) {c['w']}x{c['h']} {status}{dim}")
        
        # 选择未投稿的卡片
        unposted = [c for c in cards if not c['posted'] and not c['opacity40']]
        if not unposted:
            unposted = [c for c in cards if not c['posted']]
        if not unposted:
            print("\n⚠️ 所有卡片都已投稿！")
            # 注意：已投稿的也可以点，看看是什么效果
            unposted = [c for c in cards if c['opacity40']]
        
        if not unposted:
            print("❌ 无可选卡片")
            return
        
        # 点击第一个未投稿卡片
        target = unposted[0]
        print(f"\n点击卡片: ({target['x']}, {target['y']})")
        await page.mouse.click(target['x'], target['y'])
        await asyncio.sleep(1)
        
        # 截图确认选中
        await page.screenshot(path="debug_card_selected.png")
        
        # 检查提交按钮
        btn_state = await page.evaluate("""() => {
            const dialogs = document.querySelectorAll('[role="dialog"]');
            const dialog = dialogs[dialogs.length - 1];
            if (!dialog) return [];
            return [...dialog.querySelectorAll('button')].map(b => ({
                text: b.textContent.trim(),
                disabled: b.disabled
            }));
        }""")
        print(f"\n按钮状态: {json.dumps(btn_state, ensure_ascii=False)}")
        
        submit_ok = any(b['text'] == '提交' and not b['disabled'] for b in btn_state)
        
        if not submit_ok:
            # 可能需要选择更多卡片或者点击位置不对
            print("\n提交按钮仍禁用，检查是否需要选中...")
            
            # 检查有没有选中标记变化
            check_info = await page.evaluate("""() => {
                const dialogs = document.querySelectorAll('[role="dialog"]');
                const dialog = dialogs[dialogs.length - 1];
                if (!dialog) return 'no dialog';
                
                // 找所有SVG勾选标记
                const svgs = dialog.querySelectorAll('svg');
                const visible_checks = [];
                for (const svg of svgs) {
                    const cls = svg.className?.baseVal || svg.getAttribute('class') || '';
                    if (cls.includes('absolute') && cls.includes('top-1') && cls.includes('left-1')) {
                        const style = window.getComputedStyle(svg);
                        visible_checks.push({
                            class: cls.substring(0, 60),
                            display: style.display,
                            visibility: style.visibility,
                            hidden: cls.includes('hidden')
                        });
                    }
                }
                return visible_checks;
            }""")
            print(f"勾选标记: {json.dumps(check_info, ensure_ascii=False)}")
            
            # 可能需要直接点击里面的cursor-pointer元素
            print("\n尝试直接点击cursor-pointer元素...")
            clicked = await page.evaluate("""(coords) => {
                const el = document.elementFromPoint(coords.x, coords.y);
                if (el) {
                    el.click();
                    return {tag: el.tagName, class: (el.className || '').substring(0, 60)};
                }
                return null;
            }""", {"x": target['x'], "y": target['y']})
            print(f"点击到: {clicked}")
            await asyncio.sleep(1)
            
            # 再检查一次
            btn_state2 = await page.evaluate("""() => {
                const dialogs = document.querySelectorAll('[role="dialog"]');
                const dialog = dialogs[dialogs.length - 1];
                if (!dialog) return [];
                return [...dialog.querySelectorAll('button')].map(b => ({
                    text: b.textContent.trim(),
                    disabled: b.disabled
                }));
            }""")
            print(f"再次检查: {json.dumps(btn_state2, ensure_ascii=False)}")
            submit_ok = any(b['text'] == '提交' and not b['disabled'] for b in btn_state2)
        
        if submit_ok:
            print("\n✅ 提交按钮已启用！")
            
            # 点击提交
            print("点击提交...")
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
            
            # 等待请求
            await asyncio.sleep(5)
            await page.screenshot(path="debug_after_submit_final.png")
        else:
            print("\n❌ 提交仍然禁用")
        
        # 输出捕获结果
        print(f"\n{'='*60}")
        print(f"📋 捕获了 {len(captured)} 个POST请求:")
        for i, req in enumerate(captured):
            print(f"\n  [{i+1}] {req['url']}")
            if req['body']:
                try:
                    body = json.loads(req['body'])
                    print(f"  BODY:\n{json.dumps(body, indent=2, ensure_ascii=False)}")
                except:
                    print(f"  RAW: {req['body'][:500]}")
        
        # 尝试获取响应
        for req_id, resp_info in responses.items():
            print(f"\n  响应 [{resp_info['status']}] {resp_info['url']}")
            try:
                body = await get_response_body(req_id)
                print(f"  响应Body: {body[:500]}")
            except Exception as e:
                print(f"  获取响应失败: {e}")

asyncio.run(main())
