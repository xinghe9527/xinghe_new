"""
验证投稿结果：检查creation状态，获取无水印视频URL
"""
import asyncio
import json
from playwright.async_api import async_playwright

CDP_URL = "http://localhost:9223"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(CDP_URL)
        context = browser.contexts[0]
        page = context.pages[0]
        
        print("=== 1. 检查刚才投稿的creation状态 ===")
        # 查看最近的创作历史
        tasks = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?page_no=1&page_size=5', {
                credentials: 'include'
            });
            const data = await r.json();
            const results = [];
            for (const task of (data.tasks || [])) {
                for (const c of (task.creations || [])) {
                    results.push({
                        task_id: task.id,
                        creation_id: c.id,
                        is_posted: c.is_posted,
                        grade: c.grade,
                        nomark_uri: c.nomark_uri || '(empty)',
                        uri_short: (c.uri || '').substring(0, 80)
                    });
                }
            }
            return results;
        }""")
        
        for t in tasks:
            status = "✅已投稿" if t['is_posted'] else "⬜未投稿"
            print(f"  {status} creation={t['creation_id']} nomark={t['nomark_uri'][:60]}")
        
        print("\n=== 2. 检查用户的share_elements ===")
        # 查看用户的分享元素（投稿后应该有了）
        my_elements = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/material/share_elements/my?page_no=1&page_size=10', {
                credentials: 'include'
            });
            return await r.json();
        }""")
        print(f"  share_elements/my: {json.dumps(my_elements, indent=2, ensure_ascii=False)[:1000]}")
        
        print("\n=== 3. 检查用户的inspirations ===")
        # 查看inspirations
        inspirations = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/inspirations/media-assets/my?page_no=1&page_size=10', {
                credentials: 'include'
            });
            if (r.ok) return await r.json();
            return {status: r.status, statusText: r.statusText};
        }""")
        print(f"  inspirations/my: {json.dumps(inspirations, indent=2, ensure_ascii=False)[:1000]}")
        
        print("\n=== 4. 用户profile页面的视频 ===")
        user_id = "3209556353473214"
        persona = await page.evaluate("""async (uid) => {
            const r = await fetch(`https://service.vidu.cn/vidu/v1/material/share_elements/persona/${uid}?page_no=1&page_size=10`, {
                credentials: 'include'
            });
            return await r.json();
        }""", user_id)
        print(f"  persona elements: total={persona.get('total', 0)}")
        
        elements = persona.get('share_elements', [])
        for el in elements:
            print(f"\n  --- Share Element ---")
            print(f"  id: {el.get('id')}")
            print(f"  type: {el.get('type')}")
            print(f"  status: {el.get('status')}")
            # 查看media相关字段
            for key in ['uri', 'video_uri', 'media_uri', 'nomark_uri', 'download_uri']:
                if key in el:
                    val = el[key]
                    if val:
                        print(f"  {key}: {val[:100]}")
            # 查看所有keys
            print(f"  keys: {list(el.keys())}")
            # 查看creation相关字段
            if 'creation' in el:
                c = el['creation']
                print(f"  creation.id: {c.get('id')}")
                print(f"  creation.uri: {(c.get('uri') or '')[:100]}")
                print(f"  creation.nomark_uri: {c.get('nomark_uri', '(empty)')}")
            if 'media' in el:
                m = el['media']
                print(f"  media: {json.dumps(m, ensure_ascii=False)[:200]}")
            # 看看video相关的字段
            for key, val in el.items():
                if isinstance(val, str) and 'vidu.cn' in val:
                    print(f"  {key}(url): {val[:120]}")
                elif isinstance(val, dict):
                    for k2, v2 in val.items():
                        if isinstance(v2, str) and 'vidu.cn' in v2:
                            print(f"  {key}.{k2}(url): {v2[:120]}")
        
        print("\n=== 5. 检查feed-detail页面 ===")
        # 如果有share_element，访问其feed-detail
        if elements:
            el_id = elements[0]['id']
            print(f"  访问 feed-detail/{el_id}")
            feed_data = await page.evaluate("""async (eid) => {
                const r = await fetch(`https://service.vidu.cn/vidu/v1/material/share_elements/${eid}`, {
                    credentials: 'include'
                });
                return await r.json();
            }""", el_id)
            print(f"  feed data: {json.dumps(feed_data, indent=2, ensure_ascii=False)[:2000]}")
        
        print("\n=== 6. 直接查看inspirations列表 ===")
        # 尝试其他路径
        for path in [
            '/vidu/v1/inspirations/my?page_no=1&page_size=10',
            '/vidu/v1/inspirations/media-assets?page_no=1&page_size=10',
            '/vidu/v1/material/inspirations/my?page_no=1&page_size=10',
        ]:
            resp = await page.evaluate("""async (path) => {
                const r = await fetch(`https://service.vidu.cn${path}`, {
                    credentials: 'include'
                });
                return {status: r.status, body: await r.text()};
            }""", path)
            print(f"  {path}: [{resp['status']}] {resp['body'][:200]}")

asyncio.run(main())
