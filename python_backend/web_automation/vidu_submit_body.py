"""找到投稿body构建函数 e_(k) 的完整代码"""
import asyncio, json
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9223")
        ctx = browser.contexts[0]
        page = ctx.pages[0]

        # 1. 找publish_reference_confirm调用的前后文 + e_ 函数
        print("=" * 60)
        print("[1] 找投稿body构建函数...")
        
        result = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            const results = [];
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    const filename = s.src.split('/').pop();
                    
                    // 找 handleSubmit 附近的代码 - 这个是投稿弹窗的确认按钮触发的
                    if (code.includes('handleSubmit') && code.includes('share_element') && code.includes('creations')) {
                        // 找 handleSubmit 的定义
                        const patterns = ['handleSubmit:', 'handleSubmit=', 'handleSubmit('];
                        for (const pat of patterns) {
                            let idx = code.indexOf(pat);
                            while (idx !== -1) {
                                // 获取更大范围的上下文
                                const start = Math.max(0, idx - 200);
                                const end = Math.min(code.length, idx + 800);
                                const snippet = code.substring(start, end);
                                if (snippet.includes('submit') || snippet.includes('post') || snippet.includes('creation')) {
                                    results.push({file: filename, pattern: pat, code: snippet});
                                }
                                idx = code.indexOf(pat, idx + 1);
                            }
                        }
                    }
                } catch(e) {}
            }
            return results;
        }""")
        
        for r in result[:5]:
            print(f"\n  [{r['pattern']}] in {r['file']}:")
            print(f"  {r['code'][:600]}")

        # 2. 找 eT 函数（构建submit body的函数，从之前的代码看到了这个名字）
        print("\n\n" + "=" * 60)
        print("[2] 找body构建函数 eT...")
        
        body_builder = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    
                    // 搜索 eT= 的定义（在5925文件中发现的）
                    if (code.includes('share_elements/submit') || code.includes('media_asset')) {
                        // 找所有包含 tutorial/short_film/media_asset 的函数
                        const idx = code.indexOf('tutorial:t,short_film:n,media_asset:r');
                        if (idx !== -1) {
                            const start = Math.max(0, idx - 100);
                            const end = Math.min(code.length, idx + 1500);
                            return {
                                file: s.src.split('/').pop(),
                                code: code.substring(start, end)
                            };
                        }
                    }
                } catch(e) {}
            }
            return null;
        }""")
        
        if body_builder:
            print(f"  文件: {body_builder['file']}")
            print(f"  代码:\n{body_builder['code'][:1500]}")

        # 3. 找完整的submit POST调用链
        print("\n\n" + "=" * 60)
        print("[3] 找submit调用链...")
        
        call_chain = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    
                    // 在layout文件中搜索handleSubmit的实际实现
                    if (code.includes('投稿弹窗') || code.includes('postsModal')) {
                        // 找handleSubmit
                        const idx = code.indexOf('handleSubmit');
                        if (idx !== -1) {
                            // 找包含handleSubmit的大范围代码
                            // 回溯找到函数开始
                            let searchStart = idx;
                            // 向前找更多上下文
                            for (let i = idx; i > Math.max(0, idx - 3000); i--) {
                                if (code.substring(i, i + 20).includes('forwardRef') || 
                                    code.substring(i, i + 20).includes('function(') ||
                                    code.substring(i, i + 12).includes('module.exports')) {
                                    searchStart = i;
                                    break;
                                }
                            }
                            return {
                                file: s.src.split('/').pop(),
                                code: code.substring(Math.max(0, searchStart), Math.min(code.length, idx + 2000))
                            };
                        }
                    }
                } catch(e) {}
            }
            return null;
        }""")
        
        if call_chain:
            print(f"  文件: {call_chain['file']}")
            # 太长了，只打印handleSubmit附近
            code = call_chain['code']
            hs_idx = code.find('handleSubmit')
            if hs_idx != -1:
                print(f"  ...{code[max(0,hs_idx-200):hs_idx+500]}...")

        # 4. 直接搜索投稿body结构 - 找包含introduce/creations的JSON构造
        print("\n\n" + "=" * 60)
        print("[4] 搜索body构造代码...")
        
        body_code = await page.evaluate("""async () => {
            const scripts = document.querySelectorAll('script[src*="_next/static"]');
            const results = [];
            
            for (const s of scripts) {
                try {
                    const r = await fetch(s.src);
                    const code = await r.text();
                    const filename = s.src.split('/').pop();
                    
                    // 搜索同时包含 introduce 和 creations 的区域
                    let idx = 0;
                    while ((idx = code.indexOf('introduce', idx)) !== -1) {
                        // 检查前后200字符是否也有creations
                        const context = code.substring(Math.max(0, idx - 300), Math.min(code.length, idx + 300));
                        if (context.includes('creation') && (context.includes('categor') || context.includes('series') || context.includes('social'))) {
                            results.push({file: filename, code: context});
                        }
                        idx++;
                    }
                } catch(e) {}
            }
            return results;
        }""")
        
        for r in body_code[:5]:
            print(f"\n  {r['file']}:")
            print(f"  {r['code'][:500]}")

        # 5. 获取categories列表
        print("\n\n" + "=" * 60)
        print("[5] 获取share_elements categories...")
        
        categories = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/material/share_elements/categories', {credentials: 'include'});
            const text = await r.text();
            return {status: r.status, body: text.substring(0, 1000)};
        }""")
        print(f"  [{categories['status']}] {categories['body']}")

        print("\n[完成]")

asyncio.run(main())
