"""直接访问VIDU API开放平台"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 访问platform.vidu.cn
        print("=" * 60)
        print("[1] 访问 platform.vidu.cn ...")
        
        await page.goto("https://platform.vidu.cn", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(3)
        print(f"  URL: {page.url}")
        
        content = await page.evaluate("""() => {
            return {
                title: document.title,
                text: document.body?.innerText?.substring(0, 3000) || ''
            };
        }""")
        print(f"  标题: {content['title']}")
        print(f"  内容:\n{content['text'][:2000]}")

        # 2. 找文档/价格链接
        print("\n" + "=" * 60)
        print("[2] 找文档和价格链接...")
        
        links = await page.evaluate("""() => {
            return Array.from(document.querySelectorAll('a[href]'))
                .filter(a => a.textContent?.trim())
                .map(a => ({text: a.textContent.trim().substring(0, 50), href: a.href}))
                .filter(a => a.href.startsWith('http'))
                .slice(0, 30);
        }""")
        for l in links:
            print(f"  [{l['text'][:30]}] → {l['href'][:80]}")

        # 3. 找API文档入口
        doc_url = None
        for l in links:
            text_lower = l['text'].lower()
            href_lower = l['href'].lower()
            if any(k in text_lower or k in href_lower for k in ['文档', 'doc', 'docs', 'api-doc', 'reference']):
                doc_url = l['href']
                print(f"\n  => 文档入口: {doc_url}")
                break
        
        if not doc_url:
            # 尝试常见路径
            for path in ['/docs', '/api-docs', '/documentation', '/reference', '/help']:
                try:
                    test_url = f"https://platform.vidu.cn{path}"
                    resp = await page.evaluate(f"""async () => {{
                        const r = await fetch('{test_url}');
                        return {{status: r.status, url: r.url}};
                    }}""")
                    if resp['status'] == 200:
                        doc_url = test_url
                        print(f"  => 找到: {doc_url}")
                        break
                except:
                    pass

        # 4. 访问API文档
        if doc_url:
            print("\n" + "=" * 60)
            print(f"[3] 访问API文档: {doc_url}")
            
            await page.goto(doc_url, wait_until="networkidle", timeout=30000)
            await asyncio.sleep(2)
            
            doc_content = await page.evaluate("""() => {
                return {
                    title: document.title,
                    text: document.body?.innerText?.substring(0, 3000) || '',
                    url: window.location.href
                };
            }""")
            print(f"  URL: {doc_content['url']}")
            print(f"  标题: {doc_content['title']}")
            print(f"  内容:\n{doc_content['text'][:2000]}")

        # 5. 查看价格/套餐
        print("\n" + "=" * 60)
        print("[4] 查看API定价...")
        
        pricing_url = None
        for l in links:
            if any(k in l['text'] or k in l['href'] for k in ['价格', 'pricing', '套餐', 'plan', '计费', 'billing', '订阅']):
                pricing_url = l['href']
                break
        
        if pricing_url:
            await page.goto(pricing_url, wait_until="networkidle", timeout=30000)
            await asyncio.sleep(2)
            pricing = await page.evaluate("""() => document.body?.innerText?.substring(0, 2000) || ''""")
            print(f"  {pricing[:1500]}")
        else:
            # 在当前页面搜索价格信息
            pricing_info = await page.evaluate("""() => {
                const text = document.body?.innerText || '';
                const lines = text.split('\\n');
                return lines.filter(l => 
                    l.includes('价格') || l.includes('积分') || l.includes('credit') ||
                    l.includes('元') || l.includes('¥') || l.includes('$') ||
                    l.includes('套餐') || l.includes('plan') || l.includes('免费')
                ).slice(0, 20);
            }""")
            if pricing_info:
                print("  价格相关:")
                for l in pricing_info:
                    print(f"    {l.strip()[:100]}")

        # 6. 关键：搜索API输出中的视频URL格式（是否有水印）
        print("\n" + "=" * 60)
        print("[5] 搜索API关于水印/视频输出的说明...")
        
        # 访问API文档的视频生成部分
        generation_pages = []
        for l in links:
            if any(k in (l['text'] + l['href']).lower() for k in ['generate', 'video', '生成', 'create', 'task']):
                generation_pages.append(l)
        
        if generation_pages:
            for gp in generation_pages[:3]:
                print(f"\n  访问: {gp['text']} → {gp['href']}")
                try:
                    await page.goto(gp['href'], wait_until="networkidle", timeout=20000)
                    await asyncio.sleep(2)
                    gen_content = await page.evaluate("""() => document.body?.innerText?.substring(0, 2000) || ''""")
                    # 搜索水印相关
                    lines = gen_content.split('\n')
                    relevant = [l for l in lines if any(k in l.lower() for k in ['水印', 'watermark', 'nomark', 'uri', 'url', 'video_url', 'download', '下载', 'output'])]
                    if relevant:
                        print("  水印/输出相关:")
                        for l in relevant[:10]:
                            print(f"    {l.strip()[:120]}")
                    else:
                        print(f"  内容概要: {gen_content[:400]}")
                except Exception as e:
                    print(f"  访问失败: {e}")

        print("\n[完成]")

asyncio.run(main())
