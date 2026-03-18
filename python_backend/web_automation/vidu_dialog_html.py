"""
分析投稿弹窗的详细HTML结构
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
            if '/create' in pg.url:
                page = pg
                break
        
        if not page:
            print("打开create页面...")
            page = await context.new_page()
            await page.goto("https://www.vidu.cn/create?taskId=3210210266177612")
            await page.wait_for_load_state("networkidle")
            await asyncio.sleep(3)
        
        print(f"页面: {page.url}")
        
        # 检查弹窗
        dialog_exists = await page.evaluate("""() => {
            const d = document.querySelectorAll('[role="dialog"]');
            return d.length;
        }""")
        
        if dialog_exists < 2:
            print("重新打开投稿弹窗...")
            btn = await page.query_selector('button:has-text("投稿")')
            if btn:
                await btn.click()
                await asyncio.sleep(2)
        
        # 获取弹窗完整HTML
        html = await page.evaluate("""() => {
            const dialogs = document.querySelectorAll('[role="dialog"]');
            const dialog = dialogs[dialogs.length - 1];
            if (!dialog) return 'NO DIALOG';
            return dialog.innerHTML;
        }""")
        
        print(f"\n弹窗HTML长度: {len(html)}")
        print(f"\n{'='*60}")
        # 分段输出
        chunk_size = 2000
        for i in range(0, min(len(html), 10000), chunk_size):
            print(html[i:i+chunk_size])
            print(f"\n--- chunk {i//chunk_size + 1} ---\n")
        
        # 找弹窗中所有有尺寸的元素
        elements = await page.evaluate("""() => {
            const dialogs = document.querySelectorAll('[role="dialog"]');
            const dialog = dialogs[dialogs.length - 1];
            if (!dialog) return [];
            
            const result = [];
            const all = dialog.querySelectorAll('*');
            for (const el of all) {
                const rect = el.getBoundingClientRect();
                // 只记录有尺寸且在可见区域的元素
                if (rect.width > 40 && rect.height > 40 && rect.width < 200 && rect.height < 200) {
                    const style = window.getComputedStyle(el);
                    const bg = style.backgroundImage;
                    result.push({
                        tag: el.tagName,
                        class: (el.className || '').substring(0, 80),
                        x: Math.round(rect.x),
                        y: Math.round(rect.y),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height),
                        hasBg: bg !== 'none' ? bg.substring(0, 60) : null,
                        text: (el.textContent || '').substring(0, 30).trim(),
                        role: el.getAttribute('role'),
                        cursor: style.cursor
                    });
                }
            }
            return result.slice(0, 50);
        }""")
        
        print(f"\n\n有尺寸的元素 ({len(elements)}):")
        for e in elements:
            cursor = f" cursor={e['cursor']}" if e['cursor'] == 'pointer' else ""
            bg = f" BG={e['hasBg']}" if e['hasBg'] else ""
            print(f"  {e['tag']} [{e['x']},{e['y']}] {e['w']}x{e['h']} text='{e['text'][:20]}'{cursor}{bg}")

asyncio.run(main())
