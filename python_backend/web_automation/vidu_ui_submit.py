"""
通过UI操作投稿，同时用CDP拦截网络请求，获取精确的body格式
"""
import asyncio
import json
from playwright.async_api import async_playwright

CDP_URL = "http://localhost:9223"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(CDP_URL)
        context = browser.contexts[0]
        
        # 找到create页面
        create_page = None
        for page in context.pages:
            if '/create' in page.url:
                create_page = page
                break
        
        if not create_page:
            print("❌ 没找到create页面，尝试打开...")
            create_page = await context.new_page()
            await create_page.goto("https://www.vidu.cn/create")
            await create_page.wait_for_load_state("networkidle")
        
        print(f"当前页面: {create_page.url}")
        
        # 先检查是否已有未投稿的creation
        # 获取task历史
        cookies = await context.cookies()
        cookie_str = "; ".join(f"{c['name']}={c['value']}" for c in cookies)
        
        # 看看哪些creation还没投稿
        resp = await create_page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?page_no=1&page_size=5', {
                credentials: 'include'
            });
            const data = await r.json();
            // 找未投稿的creation
            const results = [];
            for (const task of (data.tasks || [])) {
                for (const c of (task.creations || [])) {
                    results.push({
                        task_id: task.id,
                        task_type: task.type,
                        creation_id: c.id,
                        is_posted: c.is_posted,
                        grade: c.grade,
                        type: c.type,
                        has_copyright: c.has_copyright,
                        uri: c.uri ? c.uri.substring(0, 80) : null,
                        nomark_uri: c.nomark_uri || '(empty)'
                    });
                }
            }
            return results;
        }""")
        
        print(f"\n最近的creations:")
        unposted = []
        for c in resp:
            status = "✅已投稿" if c['is_posted'] else "⬜未投稿"
            print(f"  {status} creation={c['creation_id']} task={c['task_id']} grade={c['grade']}")
            if not c['is_posted']:
                unposted.append(c)
        
        if not unposted:
            print("\n⚠️ 没有未投稿的creation！需要先生成一个新视频。")
            # 看看有没有已投稿的，可以再投一次？
            return
        
        target = unposted[0]
        print(f"\n选择目标: creation={target['creation_id']}, task={target['task_id']}")
        
        # 确保在对应task的页面上
        task_url = f"https://www.vidu.cn/create?taskId={target['task_id']}"
        if target['task_id'] not in create_page.url:
            print(f"导航到: {task_url}")
            await create_page.goto(task_url)
            await create_page.wait_for_load_state("networkidle")
            await asyncio.sleep(2)
        
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
                    "body": post_data,
                    "headers": params.get("request", {}).get("headers", {})
                })
                print(f"\n🎯 捕获请求: {method} {url}")
                print(f"   Body: {post_data}")
        
        cdp.on("Network.requestWillBeSent", on_request)
        
        # 找到投稿按钮并点击
        print("\n查找投稿按钮...")
        
        # 先找投稿按钮
        submit_btn = await create_page.query_selector('button:has-text("投稿")')
        if not submit_btn:
            # 尝试其他选择器
            buttons = await create_page.query_selector_all('button')
            for btn in buttons:
                text = await btn.text_content()
                if '投稿' in (text or ''):
                    submit_btn = btn
                    break
        
        if not submit_btn:
            print("❌ 没找到投稿按钮！")
            # 截图看看
            await create_page.screenshot(path="debug_create_page.png")
            print("已截图到 debug_create_page.png")
            return
        
        # 检查按钮是否禁用
        is_disabled = await submit_btn.is_disabled()
        print(f"投稿按钮: 找到, disabled={is_disabled}")
        
        if is_disabled:
            print("⚠️ 投稿按钮被禁用，可能需要选择一个creation")
            # 尝试选择creation - 点击视频缩略图
            await create_page.screenshot(path="debug_before_select.png")
            print("截图已保存，查看页面状态...")
            
            # 尝试点击视频元素
            video_items = await create_page.query_selector_all('[class*="creation"], [class*="video"], [class*="result"]')
            print(f"找到 {len(video_items)} 个可能的视频元素")
            for item in video_items[:5]:
                cls = await item.get_attribute("class")
                print(f"  class: {cls}")
        
        # 点击投稿按钮
        print("\n点击投稿按钮...")
        await submit_btn.click()
        await asyncio.sleep(2)
        
        # 截图查看弹窗
        await create_page.screenshot(path="debug_submit_dialog.png")
        print("弹窗截图已保存到 debug_submit_dialog.png")
        
        # 查看弹窗内容
        dialog_content = await create_page.evaluate("""() => {
            // 查找modal/dialog
            const modals = document.querySelectorAll('[role="dialog"], [class*="modal"], [class*="dialog"], [class*="popup"], [class*="overlay"]');
            const results = [];
            for (const m of modals) {
                results.push({
                    tag: m.tagName,
                    class: m.className,
                    visible: m.offsetParent !== null || m.style.display !== 'none',
                    text: m.textContent.substring(0, 500),
                    inputs: [...m.querySelectorAll('input, textarea, select')].map(i => ({
                        type: i.type,
                        name: i.name,
                        placeholder: i.placeholder,
                        value: i.value
                    })),
                    buttons: [...m.querySelectorAll('button')].map(b => ({
                        text: b.textContent.trim(),
                        disabled: b.disabled
                    })),
                    checkboxes: [...m.querySelectorAll('[role="checkbox"], input[type="checkbox"]')].map(c => ({
                        text: c.textContent || c.parentElement?.textContent?.trim().substring(0, 50),
                        checked: c.getAttribute('data-state') || c.checked
                    }))
                });
            }
            return results;
        }""")
        
        print(f"\n弹窗内容 ({len(dialog_content)} 个dialog):")
        for i, d in enumerate(dialog_content):
            print(f"\n  Dialog {i}: class={d['class'][:80]}")
            print(f"  Visible: {d['visible']}")
            print(f"  Text: {d['text'][:200]}")
            print(f"  Inputs: {json.dumps(d['inputs'], ensure_ascii=False)}")
            print(f"  Buttons: {json.dumps(d['buttons'], ensure_ascii=False)}")
            print(f"  Checkboxes: {json.dumps(d['checkboxes'], ensure_ascii=False)}")
        
        # 如果有弹窗，尝试选择分类并提交
        if dialog_content:
            # 选择一个分类 - 通常是checkbox或tag
            print("\n尝试选择分类...")
            
            # 查找分类标签
            categories = await create_page.evaluate("""() => {
                const items = document.querySelectorAll('[class*="category"], [class*="tag"], [data-state]');
                return [...items].map(i => ({
                    tag: i.tagName,
                    text: i.textContent.trim().substring(0, 30),
                    class: i.className.substring(0, 60),
                    state: i.getAttribute('data-state'),
                    role: i.getAttribute('role')
                }));
            }""")
            print(f"分类元素: {json.dumps(categories[:10], ensure_ascii=False)}")
            
            # 点击一个分类
            cat_clicked = await create_page.evaluate("""() => {
                // 找到分类checkbox
                const checkboxes = document.querySelectorAll('[role="checkbox"]');
                for (const cb of checkboxes) {
                    const text = cb.textContent || cb.parentElement?.textContent || '';
                    if (text.includes('others') || text.includes('其他') || text.includes('scene') || text.includes('effects')) {
                        cb.click();
                        return {clicked: true, text: text.trim().substring(0, 30)};
                    }
                }
                // 备选：找带tag样式的元素
                const tags = document.querySelectorAll('[class*="tag"], [class*="category"]');
                for (const t of tags) {
                    if (t.textContent.includes('others') || t.textContent.includes('其他')) {
                        t.click();
                        return {clicked: true, text: t.textContent.trim().substring(0, 30)};
                    }
                }
                return {clicked: false};
            }""")
            print(f"分类选择: {cat_clicked}")
            
            await asyncio.sleep(1)
            
            # 查找并点击确认/提交按钮
            print("\n查找确认按钮...")
            confirm_info = await create_page.evaluate("""() => {
                const dialogs = document.querySelectorAll('[role="dialog"], [class*="modal"], [class*="dialog"]');
                for (const d of dialogs) {
                    const buttons = d.querySelectorAll('button');
                    const btnList = [];
                    for (const b of buttons) {
                        btnList.push({
                            text: b.textContent.trim(),
                            disabled: b.disabled,
                            class: b.className.substring(0, 60)
                        });
                    }
                    return btnList;
                }
                return [];
            }""")
            print(f"弹窗中的按钮: {json.dumps(confirm_info, ensure_ascii=False)}")
            
            # 截图当前状态
            await create_page.screenshot(path="debug_before_confirm.png")
            
            # 点击确认按钮
            confirmed = await create_page.evaluate("""() => {
                const dialogs = document.querySelectorAll('[role="dialog"], [class*="modal"], [class*="dialog"]');
                for (const d of dialogs) {
                    const buttons = d.querySelectorAll('button');
                    for (const b of buttons) {
                        const text = b.textContent.trim();
                        if ((text.includes('确认') || text.includes('提交') || text.includes('投稿') || text.includes('发布') || text === 'Submit' || text === 'Post') && !b.disabled) {
                            b.click();
                            return {clicked: text};
                        }
                    }
                }
                return {clicked: false};
            }""")
            print(f"确认按钮: {confirmed}")
            
            # 等待网络请求
            await asyncio.sleep(3)
            
            # 截图
            await create_page.screenshot(path="debug_after_confirm.png")
        
        # 输出所有捕获的请求
        print(f"\n{'='*60}")
        print(f"📋 共捕获 {len(captured_requests)} 个相关请求:")
        for i, req in enumerate(captured_requests):
            print(f"\n  Request {i+1}: {req['method']} {req['url']}")
            print(f"  Body: {req['body']}")
            # 尝试解析JSON
            if req['body']:
                try:
                    body = json.loads(req['body'])
                    print(f"  Parsed: {json.dumps(body, indent=2, ensure_ascii=False)}")
                except:
                    pass
        
        # 额外等待看看还有没有后续请求
        await asyncio.sleep(3)
        if len(captured_requests) > 0:
            print(f"\n最终捕获 {len(captured_requests)} 个请求")
            for req in captured_requests:
                print(f"  {req['method']} {req['url']}")
                if req['body']:
                    try:
                        body = json.loads(req['body'])
                        print(f"  BODY: {json.dumps(body, indent=2, ensure_ascii=False)}")
                    except:
                        print(f"  RAW: {req['body']}")

asyncio.run(main())
