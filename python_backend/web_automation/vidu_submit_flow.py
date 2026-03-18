"""研究投稿流程：
1. 找到"投稿"按钮并分析其触发的API
2. 通过CDP拦截投稿请求
3. 理解从生成到投稿的完整流程
"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]
        cdp = await ctx.new_cdp_session(page)
        await cdp.send("Network.enable")

        # 1. 深入分析投稿相关的JS代码
        print("=" * 60)
        print("[1] 分析投稿/submit的完整JS代码...")
        
        submit_analysis = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            const results = [];
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    const filename = s.src.split('/').pop();
                    
                    // 搜索投稿相关的所有代码
                    const searchTerms = [
                        'share_elements/submit',
                        'publish_reference',
                        'PostType',
                        'submit_post',
                        'craftify',
                        'media_asset',
                        'submitPost',
                        'postCreation',
                        'onPublish',
                        'handlePublish',
                        'handleSubmit',
                        'share_element_id',
                    ];
                    
                    for (const term of searchTerms) {
                        let idx = code.indexOf(term);
                        while (idx !== -1 && results.length < 50) {
                            const start = Math.max(0, idx - 80);
                            const end = Math.min(code.length, idx + 200);
                            results.push({
                                file: filename,
                                term: term,
                                context: code.substring(start, end)
                            });
                            idx = code.indexOf(term, idx + term.length + 50);
                        }
                    }
                } catch(e) {}
            }
            return results;
        }""")
        
        # 按term分组
        by_term = {}
        for r in submit_analysis:
            term = r['term']
            if term not in by_term:
                by_term[term] = []
            by_term[term].append(r)
        
        for term, items in by_term.items():
            if len(items) > 0:
                print(f"\n  [{term}] ({len(items)}处):")
                for item in items[:3]:
                    print(f"    {item['file']}: ...{item['context'][:180]}...")

        # 2. 找submit请求的body格式
        print("\n\n" + "=" * 60)
        print("[2] 分析submit请求的body格式...")
        
        body_format = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    
                    // 找 share_elements/submit 附近的body构造代码
                    let idx = code.indexOf('share_elements/submit');
                    if (idx !== -1) {
                        // 向前搜索函数开头（找 function 或 => 或 {）
                        let funcStart = idx;
                        let braceCount = 0;
                        for (let i = idx; i > Math.max(0, idx - 2000); i--) {
                            if (code[i] === '}') braceCount++;
                            if (code[i] === '{') {
                                braceCount--;
                                if (braceCount < 0) {
                                    funcStart = i;
                                    break;
                                }
                            }
                        }
                        
                        // 向后搜索函数结尾
                        let funcEnd = idx;
                        braceCount = 0;
                        for (let i = idx; i < Math.min(code.length, idx + 2000); i++) {
                            if (code[i] === '{') braceCount++;
                            if (code[i] === '}') {
                                braceCount--;
                                if (braceCount < 0) {
                                    funcEnd = i + 1;
                                    break;
                                }
                            }
                        }
                        
                        return code.substring(funcStart, funcEnd);
                    }
                } catch(e) {}
            }
            return null;
        }""")
        
        if body_format:
            print(f"  Submit函数代码 ({len(body_format)} chars):")
            print(f"  {body_format[:1000]}")

        # 3. 找将creation变为share_element的完整流程代码
        print("\n\n" + "=" * 60)
        print("[3] 找投稿流程的完整代码...")
        
        flow_code = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    
                    // 找 publish_reference_confirm 附近的代码
                    let idx = code.indexOf('publish_reference_confirm');
                    if (idx !== -1) {
                        return {
                            file: s.src.split('/').pop(),
                            before: code.substring(Math.max(0, idx - 500), idx),
                            after: code.substring(idx, Math.min(code.length, idx + 1000))
                        };
                    }
                } catch(e) {}
            }
            return null;
        }""")
        
        if flow_code:
            print(f"  文件: {flow_code['file']}")
            print(f"  前文: ...{flow_code['before'][-300:]}")
            print(f"  -----")
            print(f"  后文: {flow_code['after'][:500]}...")

        # 4. 找投稿对话框/弹窗的代码
        print("\n\n" + "=" * 60) 
        print("[4] 找投稿对话框代码...")
        
        dialog_code = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            const results = [];
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    const filename = s.src.split('/').pop();
                    
                    // 投稿弹窗相关关键词
                    const terms = ['PostDialog', 'PostModal', 'SubmitModal', 'publishDialog', 'postPopup',
                                   '投稿', 'e_(k)', 'ep(e_', 'onPost', 'handlePost'];
                    
                    for (const term of terms) {
                        let idx = code.indexOf(term);
                        if (idx !== -1) {
                            results.push({
                                file: filename,
                                term: term,
                                context: code.substring(Math.max(0, idx - 100), Math.min(code.length, idx + 300))
                            });
                        }
                    }
                } catch(e) {}
            }
            return results;
        }""")
        
        for r in dialog_code:
            print(f"\n  [{r['term']}] in {r['file']}:")
            print(f"    {r['context'][:350]}")

        # 5. 获取投稿所需的参数 - creation信息
        print("\n\n" + "=" * 60)
        print("[5] 获取creation的完整信息...")
        
        creation_info = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.page_sz=1', {credentials: 'include'});
            const d = await r.json();
            if (d.tasks?.[0]) {
                const task = d.tasks[0];
                return {
                    task_id: task.id,
                    type: task.type,
                    state: task.state,
                    creation: task.creations?.[0] || {},
                    input: {
                        prompts: task.input?.prompts?.map(p => ({type: p.type, content: p.content?.substring(0, 50)})),
                    },
                    // 完整task字段列表
                    taskKeys: Object.keys(task),
                    creationKeys: task.creations?.[0] ? Object.keys(task.creations[0]) : [],
                };
            }
            return null;
        }""")
        
        if creation_info:
            print(f"  task_id: {creation_info['task_id']}")
            print(f"  type: {creation_info['type']}")
            print(f"  creation keys: {creation_info['creationKeys']}")
            print(f"  creation: {json.dumps(creation_info['creation'], indent=2, ensure_ascii=False)[:800]}")

        # 6. 尝试最简单的submit调用
        print("\n\n" + "=" * 60)
        print("[6] 试验submit API...")
        
        if creation_info:
            creation = creation_info['creation']
            task_id = creation_info['task_id']
            creation_id = creation.get('id', '')
            
            # 尝试不同的body格式
            bodies = [
                # 格式1: 最简格式
                {"creation_id": creation_id},
                # 格式2: 带task_id
                {"creation_id": creation_id, "task_id": task_id},
                # 格式3: 带type
                {"creation_id": creation_id, "task_id": task_id, "type": "video"},
                # 格式4: 标准投稿格式
                {"creations": [{"creation_id": creation_id, "task_id": task_id}]},
                # 格式5: material格式
                {"element": {"type": "video", "components": [{"creation_id": creation_id}]}},
            ]
            
            submit_results = await page.evaluate("""async (bodies) => {
                const results = [];
                for (const body of bodies) {
                    try {
                        const r = await fetch('https://service.vidu.cn/vidu/v1/material/share_elements/submit', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            credentials: 'include',
                            body: JSON.stringify(body)
                        });
                        const text = await r.text();
                        results.push({
                            body: JSON.stringify(body).substring(0, 100),
                            status: r.status,
                            response: text.substring(0, 200)
                        });
                    } catch(e) {
                        results.push({body: JSON.stringify(body).substring(0, 100), error: e.message});
                    }
                }
                return results;
            }""", bodies)
            
            for r in submit_results:
                print(f"  [{r.get('status', 'err')}] body: {r['body']}")
                print(f"    resp: {r.get('response', r.get('error', ''))[:150]}")

        print("\n[完成]")

asyncio.run(main())
