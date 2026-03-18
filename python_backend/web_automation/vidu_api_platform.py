"""探索VIDU官方API平台 - 反代API的秘密"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 找VIDU官方API平台入口
        print("=" * 60)
        print("[1] 探索VIDU官方API平台...")
        
        # 先检查几个可能的API平台地址
        api_urls = [
            "https://www.vidu.cn/api",
            "https://api.vidu.cn",
            "https://open.vidu.cn",
            "https://platform.vidu.cn",
            "https://developer.vidu.cn",
            "https://www.vidu.cn/developers",
        ]
        
        for url in api_urls:
            try:
                resp = await page.evaluate("""async (url) => {
                    try {
                        const r = await fetch(url, {method: 'GET', redirect: 'follow'});
                        return {url: url, status: r.status, finalUrl: r.url, type: r.headers.get('content-type')};
                    } catch(e) {
                        return {url: url, error: e.message};
                    }
                }""", url)
                print(f"  {resp.get('url')}: [{resp.get('status', 'err')}] {resp.get('finalUrl', resp.get('error', ''))[:80]}")
            except:
                pass

        # 2. 从vidu.cn页面找API平台链接
        print("\n" + "=" * 60)
        print("[2] 从页面找API平台链接...")
        
        await page.goto("https://www.vidu.cn", wait_until="networkidle", timeout=30000)
        await asyncio.sleep(2)
        
        api_links = await page.evaluate("""() => {
            const links = document.querySelectorAll('a[href]');
            return Array.from(links)
                .filter(a => {
                    const text = (a.textContent || '').toLowerCase();
                    const href = (a.href || '').toLowerCase();
                    return text.includes('api') || text.includes('开放') || text.includes('开发') ||
                           href.includes('api') || href.includes('open') || href.includes('developer');
                })
                .map(a => ({
                    text: a.textContent?.trim()?.substring(0, 50),
                    href: a.href
                }));
        }""")
        print(f"  API相关链接:")
        for link in api_links:
            print(f"    [{link['text']}] → {link['href']}")

        # 3. 导航到API开放平台
        print("\n" + "=" * 60)
        print("[3] 访问API开放平台...")
        
        api_platform_url = None
        for link in api_links:
            if 'api' in link['href'].lower() and link['href'].startswith('http'):
                api_platform_url = link['href']
                break
        
        if api_platform_url:
            print(f"  导航到: {api_platform_url}")
            await page.goto(api_platform_url, wait_until="networkidle", timeout=30000)
            await asyncio.sleep(3)
            print(f"  最终URL: {page.url}")
            
            # 提取页面关键信息
            page_content = await page.evaluate("""() => {
                return {
                    title: document.title,
                    headings: Array.from(document.querySelectorAll('h1, h2, h3')).map(h => h.textContent?.trim()).filter(t => t),
                    bodyText: document.body?.innerText?.substring(0, 2000) || '',
                    links: Array.from(document.querySelectorAll('a[href]'))
                        .filter(a => a.textContent?.trim())
                        .map(a => ({text: a.textContent.trim().substring(0, 40), href: a.href}))
                        .slice(0, 30)
                };
            }""")
            print(f"  标题: {page_content['title']}")
            print(f"  标题列表: {page_content['headings'][:10]}")
            print(f"  页面文本:")
            print(f"    {page_content['bodyText'][:1000]}")
            
            # 找价格/套餐/定价信息
            pricing_links = [l for l in page_content.get('links', []) if any(k in (l['text'] + l['href']).lower() for k in ['价格', 'pricing', '套餐', 'plan', 'credit', '积分', 'watermark', '水印'])]
            if pricing_links:
                print(f"  价格相关链接:")
                for l in pricing_links:
                    print(f"    [{l['text']}] → {l['href']}")
        else:
            print("  未找到API平台链接，尝试直接搜索...")
            # 尝试直接访问可能的API文档
            try:
                await page.goto("https://developer.vidu.cn", wait_until="networkidle", timeout=15000)
                print(f"  developer.vidu.cn → {page.url}")
            except:
                pass

        # 4. 搜索VIDU API文档中关于watermark的信息
        print("\n" + "=" * 60)
        print("[4] 在API平台搜索watermark/水印相关...")
        
        wm_info = await page.evaluate("""() => {
            const text = document.body?.innerText || '';
            const lines = text.split('\\n');
            const relevant = lines.filter(l => 
                l.includes('水印') || l.includes('watermark') || 
                l.includes('nomark') || l.includes('无水印') ||
                l.includes('下载') || l.includes('download') ||
                l.includes('视频') || l.includes('video') ||
                l.includes('限制') || l.includes('limit')
            );
            return relevant.slice(0, 20);
        }""")
        if wm_info:
            print("  水印相关内容:")
            for line in wm_info:
                print(f"    {line.strip()[:100]}")

        # 5. 检查VIDU API的调用方式和是否需要VIP
        print("\n" + "=" * 60)
        print("[5] 查看API调用文档...")
        
        # 找文档/quickstart链接
        doc_links = await page.evaluate("""() => {
            const links = document.querySelectorAll('a[href]');
            return Array.from(links)
                .filter(a => {
                    const text = (a.textContent || '').toLowerCase();
                    const href = (a.href || '').toLowerCase();
                    return text.includes('文档') || text.includes('doc') || text.includes('快速') ||
                           text.includes('start') || text.includes('guide') || text.includes('接入');
                })
                .map(a => ({text: a.textContent?.trim()?.substring(0, 50), href: a.href}))
                .slice(0, 10);
        }""")
        
        if doc_links:
            print("  文档链接:")
            for l in doc_links:
                print(f"    [{l['text']}] → {l['href']}")
            
            # 访问第一个文档链接
            if doc_links[0]['href'].startswith('http'):
                await page.goto(doc_links[0]['href'], wait_until="networkidle", timeout=30000)
                await asyncio.sleep(2)
                print(f"\n  文档页面: {page.url}")
                doc_content = await page.evaluate("""() => {
                    return document.body?.innerText?.substring(0, 2000) || '';
                }""")
                print(f"  文档内容:")
                print(f"    {doc_content[:1500]}")

        # 6. 搜索已知的VIDU API中转服务
        print("\n" + "=" * 60)
        print("[6] 从JS代码中查找反代API域名或配置...")
        
        proxy_info = await page.evaluate("""async () => {
            const results = [];
            const scripts = performance.getEntriesByType('resource')
                .filter(r => r.name.includes('.js'));
            
            for (const s of scripts) {
                try {
                    const resp = await fetch(s.name);
                    const text = await resp.text();
                    
                    // 搜索API Key相关配置
                    for (const pat of ['api_key', 'apiKey', 'api-key', 'app_id', 'appId', 'client_id', 'clientId', 'access_key', 'accessKey', 'secret']) {
                        const idx = text.indexOf(pat);
                        if (idx > -1) {
                            const ctx = text.substring(Math.max(0, idx - 100), Math.min(text.length, idx + 200));
                            if (!ctx.includes('google') && !ctx.includes('sentry') && !ctx.includes('bytedance')) {
                                results.push({pattern: pat, file: s.name.split('/').pop(), code: ctx});
                            }
                        }
                    }
                } catch(e) {}
                if (results.length > 10) break;
            }
            return results.slice(0, 5);
        }""")
        for r in proxy_info:
            print(f"\n  [{r['pattern']}] in {r['file']}:")
            print(f"    {r['code'][:250]}")

        print("\n[完成]")

asyncio.run(main())
