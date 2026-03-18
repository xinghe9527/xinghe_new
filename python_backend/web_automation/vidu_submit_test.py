"""用正确的body格式调用submit API"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        await page.goto("https://www.vidu.cn/create", wait_until="domcontentloaded", timeout=20000)
        await asyncio.sleep(2)

        # 获取creation信息
        task_info = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.page_sz=1', {credentials: 'include'});
            const d = await r.json();
            if (d.tasks?.[0]) {
                const task = d.tasks[0];
                const creation = task.creations?.[0];
                return {
                    task_id: task.id,
                    task_type: task.type,
                    creation_id: creation?.id,
                    creation_type: creation?.type,
                    uri: creation?.uri,
                    cover_uri: creation?.cover_uri,
                    resolution: creation?.resolution,
                    duration: creation?.duration,
                    is_posted: creation?.is_posted,
                    grade: creation?.grade,
                    has_copyright: creation?.has_copyright,
                    style: creation?.style,
                    has_audio: creation?.has_audio,
                };
            }
            return null;
        }""")
        
        print(f"Creation信息:")
        print(json.dumps(task_info, indent=2, ensure_ascii=False))

        # 尝试不同的submit body格式
        print("\n" + "=" * 60)
        print("测试submit API...")
        
        creation_id = task_info['creation_id']
        task_id = task_info['task_id']
        
        bodies = [
            # 格式1: 标准格式（从JS代码中找到的）
            {
                "share": {
                    "category": ["others"],
                    "creations": [{"id": creation_id}],
                    "introduce": "",
                    "series": ""
                }
            },
            # 格式2: 带element
            {
                "element": {
                    "type": "media_asset",
                    "id": creation_id
                },
                "share": {
                    "category": ["others"],
                    "creations": [{"id": creation_id}],
                    "introduce": "",
                    "series": ""
                }
            },
            # 格式3: creations包含更多信息
            {
                "share": {
                    "category": ["others"],
                    "creations": [{
                        "id": creation_id,
                        "task_id": task_id,
                        "type": "video"
                    }],
                    "introduce": "",
                    "series": ""
                }
            },
            # 格式4: creations用creation_id字段
            {
                "share": {
                    "category": ["others"],
                    "creations": [{
                        "creation_id": creation_id,
                        "task_id": task_id
                    }],
                    "introduce": "",
                    "series": ""
                }
            },
            # 格式5: element包含task信息
            {
                "element": {
                    "type": "video",
                    "task_id": task_id,
                    "creation_id": creation_id
                },
                "share": {
                    "category": ["others"],
                    "creations": [creation_id],
                    "introduce": "",
                    "series": ""
                }
            },
            # 格式6: 只有share，creations是ID数组
            {
                "share": {
                    "category": ["others"],
                    "creations": [creation_id],
                    "introduce": "",
                    "series": ""
                }
            },
        ]
        
        for i, body in enumerate(bodies):
            result = await page.evaluate("""async (body) => {
                try {
                    const r = await fetch('https://service.vidu.cn/vidu/v1/material/share_elements/submit', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        credentials: 'include',
                        body: JSON.stringify(body)
                    });
                    const text = await r.text();
                    return {status: r.status, body: text.substring(0, 400)};
                } catch(e) {
                    return {error: e.message};
                }
            }""", body)
            
            status = result.get('status', 'err')
            emoji = "✅" if status == 200 else ("⚠️" if status != 400 else "❌")
            print(f"\n{emoji} 格式{i+1}: [{status}]")
            print(f"  body: {json.dumps(body, ensure_ascii=False)[:200]}")
            print(f"  resp: {result.get('body', result.get('error', ''))[:200]}")
            
            # 如果成功了就停止
            if status == 200:
                print(f"\n🎉 投稿成功！")
                break

        # 如果都失败了，用另一种方式 - 直接用浏览器UI操作投稿
        print("\n\n" + "=" * 60)
        print("备选方案: 通过UI操作投稿...")
        
        # 先看"投稿"按钮在哪里（之前发现在create页面 x=1829, y=473）
        # 但投稿按钮是在生成结果旁边的
        
        # 检查当前页面是否可以看到创作结果
        ui_state = await page.evaluate("""() => {
            // 搜索"投稿"按钮
            const btns = [];
            document.querySelectorAll('*').forEach(el => {
                if (el.offsetParent !== null) {
                    const t = el.textContent?.trim();
                    if (t === '投稿' || t === '发布' || t === 'Post' || t === 'Publish') {
                        btns.push({
                            tag: el.tagName,
                            text: t,
                            x: Math.round(el.getBoundingClientRect().x),
                            y: Math.round(el.getBoundingClientRect().y),
                            w: Math.round(el.getBoundingClientRect().width),
                            h: Math.round(el.getBoundingClientRect().height),
                            class: (el.className||'').toString().substring(0, 60),
                        });
                    }
                }
            });
            return {buttons: btns};
        }""")
        
        print(f"  投稿按钮: {ui_state['buttons']}")

        print("\n[完成]")

asyncio.run(main())
