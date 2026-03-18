"""查看VIDU API文档 - 定价和视频输出格式"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 查看产品定价
        print("=" * 60)
        print("[1] 产品定价...")
        
        await page.goto("https://platform.vidu.cn/docs/pricing", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(2)
        
        pricing = await page.evaluate("""() => document.body?.innerText?.substring(0, 4000) || ''""")
        # 过滤出价格相关内容
        lines = pricing.split('\n')
        for line in lines:
            line = line.strip()
            if line and len(line) > 2:
                print(f"  {line[:120]}")

        # 2. 查看文生视频API文档
        print("\n" + "=" * 60)
        print("[2] 文生视频API文档...")
        
        await page.goto("https://platform.vidu.cn/docs/text-to-video", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(2)
        
        doc = await page.evaluate("""() => document.body?.innerText?.substring(0, 5000) || ''""")
        lines = doc.split('\n')
        in_response = False
        for line in lines:
            line = line.strip()
            if not line or len(line) < 2:
                continue
            # 重点关注响应字段
            lower = line.lower()
            if any(k in lower for k in ['response', '响应', '返回', 'output', 'result', 'video_url', 'uri', 'url', 'watermark', '水印', 'nomark', 'download']):
                in_response = True
            if in_response or any(k in lower for k in ['video', 'uri', 'url', 'result']):
                print(f"  {line[:150]}")
                in_response = True
            if in_response and ('请求' in line or 'request' in lower):
                in_response = False

        # 3. FAQ常见问题
        print("\n" + "=" * 60)
        print("[3] FAQ - 常见问题...")
        
        await page.goto("https://platform.vidu.cn/docs/faq", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(2)
        
        faq = await page.evaluate("""() => document.body?.innerText?.substring(0, 4000) || ''""")
        lines = faq.split('\n')
        for line in lines:
            line = line.strip()
            if line and len(line) > 2:
                if any(k in line for k in ['水印', 'watermark', '下载', 'download', '版权', '商用', '授权']):
                    print(f"  *** {line[:120]}")
                elif len(line) > 5:
                    print(f"  {line[:120]}")

        # 4. 创建视频任务的完整文档
        print("\n" + "=" * 60)
        print("[4] 创建视频任务 - 完整响应字段...")
        
        await page.goto("https://platform.vidu.cn/docs/text-to-video", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(2)
        
        full_doc = await page.evaluate("""() => document.body?.innerText || ''""")
        print(full_doc[:5000])

        print("\n[完成]")

asyncio.run(main())
