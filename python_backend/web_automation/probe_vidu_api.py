"""
VIDU API 探测工具
目的：用浏览器登录凭证直接调用 VIDU API，查看视频详情中是否有无水印下载链接
"""

import json
import sys
from playwright.sync_api import sync_playwright


def main():
    print("🔍 VIDU API 探测工具")
    print("="*60)
    
    with sync_playwright() as pw:
        print("\n📡 连接到 CDP 端口 9223...")
        try:
            browser = pw.chromium.connect_over_cdp("http://127.0.0.1:9223")
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return
        
        contexts = browser.contexts
        if not contexts:
            print("❌ 没有浏览器上下文")
            return
        
        context = contexts[0]
        vidu_page = None
        for page in context.pages:
            if 'vidu' in page.url:
                vidu_page = page
                break
        
        if not vidu_page:
            print("❌ 没有找到 VIDU 页面")
            return
        
        print(f"✅ VIDU 页面: {vidu_page.url[:80]}")
        
        # ====== 第一步：获取 Cookies 和 Auth Token ======
        print("\n" + "="*60)
        print("📋 第一步：获取认证信息")
        print("="*60)
        
        cookies = context.cookies("https://www.vidu.cn")
        print(f"\n🍪 Cookies ({len(cookies)} 个):")
        auth_cookie = None
        for c in cookies:
            # 只显示 cookie 名和长度，不泄露值
            val_preview = c['value'][:20] + '...' if len(c['value']) > 20 else c['value']
            print(f"   {c['name']} = {val_preview} (domain: {c['domain']})")
            if 'token' in c['name'].lower() or 'auth' in c['name'].lower() or 'session' in c['name'].lower():
                auth_cookie = c
                print(f"      ↑ 可能是认证 Cookie!")
        
        # 检查 localStorage 中的 token
        auth_info = vidu_page.evaluate("""
            () => {
                const result = {};
                // 搜索 localStorage 中所有可能的 token
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    if (key.toLowerCase().includes('token') || 
                        key.toLowerCase().includes('auth') ||
                        key.toLowerCase().includes('user') ||
                        key.toLowerCase().includes('session') ||
                        key.toLowerCase().includes('jwt') ||
                        key.toLowerCase().includes('access')) {
                        const val = localStorage.getItem(key);
                        result[key] = val ? val.slice(0, 50) + '...' : '';
                    }
                }
                return result;
            }
        """)
        
        print(f"\n🔑 LocalStorage 认证信息:")
        for k, v in auth_info.items():
            print(f"   {k} = {v}")
        
        # ====== 第二步：通过浏览器内的 fetch 调用 VIDU API ======
        print("\n" + "="*60)
        print("📡 第二步：调用 VIDU API 获取任务历史")
        print("="*60)
        
        # 调用任务历史 API（在浏览器页面内执行 fetch，自动带上认证信息）
        api_result = vidu_page.evaluate("""
            async () => {
                try {
                    const resp = await fetch('https://service.vidu.cn/vidu/v1/tasks/history/me?pager.pagesz=5&scene_mode=none&types=img2video&types=character2video&types=text2video&types=reference2image&types=text2image', {
                        credentials: 'include',
                    });
                    const data = await resp.json();
                    return {
                        status: resp.status,
                        data: data,
                    };
                } catch(e) {
                    return { error: e.message };
                }
            }
        """)
        
        if api_result.get('error'):
            print(f"❌ API 调用失败: {api_result['error']}")
            return
        
        print(f"✅ API 响应状态: {api_result['status']}")
        
        data = api_result.get('data', {})
        
        # 保存完整响应到文件以便分析
        with open('vidu_api_response.json', 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"💾 完整 API 响应已保存到 vidu_api_response.json")
        
        # 解析任务列表
        tasks = data.get('data', data.get('tasks', data.get('results', [])))
        if isinstance(data, dict) and 'data' in data and isinstance(data['data'], dict):
            tasks = data['data'].get('list', data['data'].get('tasks', data['data'].get('items', [])))
        
        if not isinstance(tasks, list):
            print(f"⚠️ 无法解析任务列表，数据结构:")
            print(json.dumps(data, ensure_ascii=False, indent=2)[:2000])
            # 递归搜索任何看起来是列表的东西
            def find_list(obj, depth=0):
                if depth > 3:
                    return None
                if isinstance(obj, list) and len(obj) > 0:
                    return obj
                if isinstance(obj, dict):
                    for v in obj.values():
                        result = find_list(v, depth + 1)
                        if result:
                            return result
                return None
            tasks = find_list(data) or []
        
        print(f"\n📋 找到 {len(tasks)} 个任务")
        
        # ====== 第三步：分析每个任务的 URL ======
        print("\n" + "="*60)
        print("🔍 第三步：分析每个任务的视频/图片 URL")
        print("="*60)
        
        for i, task in enumerate(tasks[:5]):
            if not isinstance(task, dict):
                continue
            
            task_type = task.get('type', '未知')
            task_id = task.get('id', task.get('task_id', '未知'))
            status = task.get('state', task.get('status', '未知'))
            
            print(f"\n{'─'*60}")
            print(f"📝 任务 #{i+1}: 类型={task_type}, ID={str(task_id)[:20]}, 状态={status}")
            
            # 搜索所有包含 URL 的字段
            def find_urls(obj, path="", depth=0):
                if depth > 5:
                    return
                if isinstance(obj, str):
                    if ('http' in obj and ('mp4' in obj or 'video' in obj or 'image' in obj or 'files' in obj or 'jpeg' in obj or 'png' in obj or 'webp' in obj)):
                        wm_indicator = "🔴 有水印" if '-wm' in obj else "🟢 无水印标记"
                        print(f"   [{path}] {wm_indicator}")
                        print(f"      URL: {obj[:150]}")
                        if '-wm' in obj:
                            # 显示不带 wm 的版本
                            no_wm = obj.replace('-wm.mp4', '.mp4').replace('-wm.jpeg', '.jpeg').replace('-wm.png', '.png').replace('-wm.webp', '.webp')
                            print(f"      去掉-wm: {no_wm[:150]}")
                elif isinstance(obj, dict):
                    for k, v in obj.items():
                        find_urls(v, f"{path}.{k}" if path else k, depth + 1)
                elif isinstance(obj, list):
                    for j, item in enumerate(obj[:10]):
                        find_urls(item, f"{path}[{j}]", depth + 1)
            
            find_urls(task)
        
        # ====== 第四步：尝试获取单个任务的详情（可能有更多 URL） ======
        if tasks:
            first_task = tasks[0] if isinstance(tasks[0], dict) else {}
            task_id = first_task.get('id', first_task.get('task_id', ''))
            
            if task_id:
                print(f"\n{'='*60}")
                print(f"📡 第四步：获取单个任务详情 (ID: {str(task_id)[:20]})")
                print("="*60)
                
                # 尝试几种可能的详情 API
                detail_apis = [
                    f'https://service.vidu.cn/vidu/v1/tasks/{task_id}',
                    f'https://service.vidu.cn/vidu/v1/tasks/{task_id}/detail',
                    f'https://service.vidu.cn/vidu/v1/tasks/{task_id}/download',
                    f'https://service.vidu.cn/vidu/v1/tasks/{task_id}/creations',
                ]
                
                for api_url in detail_apis:
                    detail = vidu_page.evaluate(f"""
                        async () => {{
                            try {{
                                const resp = await fetch('{api_url}', {{
                                    credentials: 'include',
                                }});
                                if (resp.ok) {{
                                    const data = await resp.json();
                                    return {{ status: resp.status, url: '{api_url}', data: data }};
                                }}
                                return {{ status: resp.status, url: '{api_url}', error: resp.statusText }};
                            }} catch(e) {{
                                return {{ error: e.message, url: '{api_url}' }};
                            }}
                        }}
                    """)
                    
                    status = detail.get('status', '?')
                    print(f"\n   📡 {api_url.split('/')[-1] or 'detail'} → {status}")
                    
                    if status == 200 and detail.get('data'):
                        detail_data = detail['data']
                        # 保存详情
                        filename = f"vidu_task_detail_{api_url.split('/')[-1]}.json"
                        with open(filename, 'w', encoding='utf-8') as f:
                            json.dump(detail_data, f, ensure_ascii=False, indent=2)
                        print(f"   💾 已保存到 {filename}")
                        
                        # 搜索 URL
                        def find_urls_detail(obj, path="", depth=0):
                            if depth > 5:
                                return
                            if isinstance(obj, str):
                                if ('http' in obj and ('mp4' in obj or 'video' in obj or 'jpeg' in obj or 'png' in obj or 'webp' in obj or 'files' in obj)):
                                    wm_indicator = "🔴 有水印(-wm)" if '-wm' in obj else "🟢 无-wm标记"
                                    print(f"      [{path}] {wm_indicator}")
                                    print(f"         {obj[:150]}")
                                elif 'download' in obj.lower():
                                    print(f"      [{path}] 📥 下载相关: {obj[:150]}")
                            elif isinstance(obj, dict):
                                for k, v in obj.items():
                                    find_urls_detail(v, f"{path}.{k}" if path else k, depth + 1)
                            elif isinstance(obj, list):
                                for j, item in enumerate(obj[:10]):
                                    find_urls_detail(item, f"{path}[{j}]", depth + 1)
                        
                        find_urls_detail(detail_data)
                    elif detail.get('error'):
                        print(f"   ❌ {detail['error']}")
        
        print(f"\n{'='*60}")
        print("✅ API 探测完成")
        print("="*60)


if __name__ == '__main__':
    main()
