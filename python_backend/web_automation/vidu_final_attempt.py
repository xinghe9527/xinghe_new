"""验证watch_ad_watermark + 个人主页 + 下载入口"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 查询watch_ad_watermark的可用性
        print("=" * 60)
        print("[1] 查询 watch_ad_watermark 是否可用...")
        
        await page.goto("https://www.vidu.cn/create", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        watermark_quota = await page.evaluate("""async () => {
            try {
                const r1 = await fetch('https://service.vidu.cn/vidu/v1/missions/quota?mission_type=watch_ad_watermark', {credentials: 'include'});
                const d1 = await r1.json().catch(() => r1.text());
                
                const r2 = await fetch('https://service.vidu.cn/vidu/v1/missions/quota?mission_type=watch_ad_credit', {credentials: 'include'});
                const d2 = await r2.json().catch(() => r2.text());
                
                // 也检查available nexus
                const r3 = await fetch('https://service.vidu.cn/credit/v1/nexus/available?rule_set=mission_watch_ad_credit&rule_set=mission_watch_ad_watermark', {credentials: 'include'});
                const d3 = await r3.json().catch(() => r3.text());
                
                // 区域信息
                const r4 = await fetch('https://service.vidu.cn/vidu/v1/region', {credentials: 'include'});
                const d4 = await r4.json().catch(() => r4.text());
                
                return {
                    watermark_quota: {status: r1.status, data: d1},
                    credit_quota: {status: r2.status, data: d2},
                    nexus_available: {status: r3.status, data: d3},
                    region: {status: r4.status, data: d4}
                };
            } catch(e) {
                return {error: e.message};
            }
        }""")
        print(f"  {json.dumps(watermark_quota, indent=2, ensure_ascii=False)}")

        # 2. 访问个人主页
        print("\n" + "=" * 60)
        print("[2] 访问个人主页...")
        
        await page.goto("https://www.vidu.cn/profile", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        print(f"  URL: {page.url}")
        
        profile_content = await page.evaluate("""() => {
            return {
                title: document.title,
                videos: document.querySelectorAll('video').length,
                text: document.body?.innerText?.substring(0, 1000) || '',
                allButtons: Array.from(document.querySelectorAll('button'))
                    .filter(b => b.offsetParent !== null)
                    .map(b => ({text: b.textContent?.trim()?.substring(0, 30) || '', class: (b.className||'').toString().substring(0,50)}))
                    .filter(b => b.text)
                    .slice(0, 20)
            };
        }""")
        print(f"  标题: {profile_content['title']}")
        print(f"  视频数: {profile_content['videos']}")
        print(f"  按钮: {[b['text'][:20] for b in profile_content.get('allButtons', [])]}")
        print(f"  内容:\n{profile_content['text'][:500]}")

        # 3. 试试导航到用户的某个创作详情页
        print("\n" + "=" * 60)
        print("[3] 尝试访问创作详情页...")
        
        # 获取用户的tasks（通过与cookie的fetch）
        tasks_data = await page.evaluate("""async () => {
            // 尝试多种可能的task API路径
            const paths = [
                '/vidu/v1/tasks?limit=2',
                '/vidu/v1/tasks?pager.page_sz=2', 
                '/vidu/v1/tasks/history/me?limit=2',
                '/vidu/v1/tasks/history/me?pager.page_sz=2',
                '/vidu/v1/tasks/me?limit=2',
            ];
            const results = {};
            for (const path of paths) {
                try {
                    const r = await fetch('https://service.vidu.cn' + path, {credentials: 'include'});
                    const d = await r.json().catch(() => null);
                    results[path] = {status: r.status, hasData: !!d, keys: d ? Object.keys(d) : []};
                    if (d && (d.tasks || d.data)) {
                        const tasks = d.tasks || d.data;
                        if (Array.isArray(tasks) && tasks.length > 0) {
                            results[path].firstTask = {
                                id: tasks[0].id,
                                type: tasks[0].type,
                                state: tasks[0].state,
                                creation_id: tasks[0].creations?.[0]?.id,
                                uri: tasks[0].creations?.[0]?.uri?.substring(0, 80),
                                nomark_uri: tasks[0].creations?.[0]?.nomark_uri || '(empty)'
                            };
                        }
                    }
                } catch(e) {
                    results[path] = {error: e.message};
                }
            }
            return results;
        }""")
        
        for path, data in tasks_data.items():
            print(f"  {path}: [{data.get('status', 'err')}] keys={data.get('keys', [])} err={data.get('error', '')}")
            if 'firstTask' in data:
                print(f"    task: {json.dumps(data['firstTask'], ensure_ascii=False)}")

        # 4. 尝试用JS直接修改region变量来触发watch_ad_watermark
        print("\n" + "=" * 60)
        print("[4] 尝试修改region变量...")
        
        # 找到region变量并修改
        region_hack = await page.evaluate("""() => {
            // 搜索window上的所有对象，找region相关
            const results = [];
            
            // 尝试直接覆盖Next.js的状态
            if (window.__NEXT_DATA__) {
                const str = JSON.stringify(window.__NEXT_DATA__);
                if (str.includes('china') || str.includes('region')) {
                    results.push({source: '__NEXT_DATA__', hasChina: str.includes('china'), hasRegion: str.includes('region')});
                }
            }
            
            // 搜索React根组件的状态
            const root = document.getElementById('__next');
            if (root && root._reactRootContainer) {
                results.push({source: 'reactRoot', found: true});
            }
            
            // 尝试找全局状态管理器中的region
            for (const key of Object.keys(window)) {
                try {
                    const val = window[key];
                    if (val && typeof val === 'object' && val.Ey) {
                        results.push({source: 'window.' + key, Ey: val.Ey});
                    }
                } catch(e) {}
            }
            
            return results;
        }""")
        print(f"  {json.dumps(region_hack, indent=2, ensure_ascii=False)}")

        # 5. 找到实际的下载入口 - 需要先生成一个视频
        print("\n" + "=" * 60)
        print("[5] 检查创建页面上是否有任务结果UI...")
        
        await page.goto("https://www.vidu.cn/create/text2video", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(3)
        
        create_ui = await page.evaluate("""() => {
            return {
                url: window.location.href,
                title: document.title,
                // 搜索页面上的所有可见文本元素
                sections: Array.from(document.querySelectorAll('div, section'))
                    .filter(d => {
                        const rect = d.getBoundingClientRect();
                        return rect.width > 200 && rect.height > 100 && rect.top < 2000;
                    })
                    .map(d => ({
                        class: (d.className || '').toString().substring(0, 60),
                        text: (d.textContent || '').trim().substring(0, 80),
                        x: Math.round(d.getBoundingClientRect().x),
                        y: Math.round(d.getBoundingClientRect().y),
                        w: Math.round(d.getBoundingClientRect().width),
                        h: Math.round(d.getBoundingClientRect().height),
                    }))
                    .filter(d => {
                        const t = d.text.toLowerCase();
                        return t.includes('下载') || t.includes('download') || 
                               t.includes('视频') || t.includes('结果') ||
                               t.includes('任务') || t.includes('task') ||
                               t.includes('生成') || t.includes('历史');
                    })
                    .slice(0, 10)
            };
        }""")
        print(f"  URL: {create_ui['url']}")
        if create_ui['sections']:
            print(f"  相关区域:")
            for s in create_ui['sections']:
                print(f"    '{s['text'][:60]}' class={s['class'][:40]} at ({s['x']},{s['y']}) {s['w']}x{s['h']}")
        else:
            print("  未找到任务/下载/历史相关UI区域")

        # 6. 最后：尝试直接用CDP fetch带cookie的tasks API
        print("\n" + "=" * 60)
        print("[6] CDP直接请求tasks API...")
        
        cdp = await ctx.new_cdp_session(page)
        
        # 获取vidu.cn域名的所有cookies
        cookies = await cdp.send("Network.getCookies", {"urls": ["https://service.vidu.cn"]})
        vidu_cookies = {c['name']: c['value'][:60] for c in cookies.get('cookies', [])}
        print(f"  service.vidu.cn cookies: {list(vidu_cookies.keys())}")
        
        jwt = vidu_cookies.get('JWT', '')
        if jwt:
            print(f"  JWT: {jwt[:50]}...")
            
            # 用CDP发送请求
            result = await cdp.send("Network.enable")
            
            # 使用page.evaluate + credentials:include
            tasks_result = await page.evaluate("""async () => {
                const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.page_sz=3', {
                    credentials: 'include'
                });
                const text = await r.text();
                return {status: r.status, body: text.substring(0, 1000)};
            }""")
            print(f"  tasks/history/me: [{tasks_result['status']}]")
            print(f"  body: {tasks_result['body'][:500]}")

        print("\n[完成]")

asyncio.run(main())
