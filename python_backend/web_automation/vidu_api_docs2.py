"""查看VIDU API文档 - 改用domcontentloaded"""
import asyncio
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        pages_to_visit = [
            ("产品定价", "https://platform.vidu.cn/docs/pricing"),
            ("文生视频", "https://platform.vidu.cn/docs/text-to-video"),
            ("FAQ", "https://platform.vidu.cn/docs/faq"),
            ("平台介绍", "https://platform.vidu.cn/docs/introduction"),
        ]

        for name, url in pages_to_visit:
            print("=" * 60)
            print(f"[{name}] {url}")
            try:
                await page.goto(url, wait_until="domcontentloaded", timeout=20000)
                await asyncio.sleep(5)  # 等内容渲染
                
                text = await page.evaluate("() => document.body?.innerText?.substring(0, 5000) || ''")
                lines = text.split('\n')
                for line in lines:
                    line = line.strip()
                    if line and len(line) > 2:
                        # 高亮关键信息
                        if any(k in line for k in ['水印', 'watermark', '无水印', '版权', '商用', '授权']):
                            print(f"  ★★★ {line[:150]}")
                        else:
                            print(f"  {line[:150]}")
            except Exception as e:
                print(f"  错误: {e}")
            print()

        print("[完成]")

asyncio.run(main())
