"""
VIDU 水印 URL 诊断工具
用途：抓包分析 VIDU 下载链接是否包含水印参数

使用方式：
1. 确保 VIDU 浏览器已通过 api_server 启动（CDP 端口 9223）
2. 在浏览器中打开包含已完成视频/图片的 VIDU 页面
3. 运行此脚本
4. 在浏览器中点击 "下载" 按钮
5. 查看控制台输出的 URL 分析结果
"""

import sys
import time
from urllib.parse import urlparse, parse_qs
from playwright.sync_api import sync_playwright


def analyze_url(url: str, label: str = ""):
    """解析并显示 URL 的完整结构"""
    parsed = urlparse(url)
    params = parse_qs(parsed.query)
    
    print(f"\n{'='*80}")
    if label:
        print(f"📌 {label}")
    print(f"🔗 完整 URL: {url[:200]}")
    print(f"   主机: {parsed.hostname}")
    print(f"   路径: {parsed.path}")
    if params:
        print(f"   查询参数 ({len(params)} 个):")
        for k, v in params.items():
            # 高亮可能与水印相关的参数
            flag = ""
            if any(w in k.lower() for w in ['water', 'wm', 'mark', 'logo', 'stamp', 'overlay', 'token', 'sign', 'auth', 'download']):
                flag = " ⚠️ 可能相关!"
            print(f"      {k} = {v[0][:80]}{flag}")
    else:
        print(f"   查询参数: 无")
    print(f"{'='*80}")


def main():
    print("🔍 VIDU 水印 URL 诊断工具")
    print("="*60)
    
    captured_urls = []
    
    with sync_playwright() as pw:
        # 连接到已运行的浏览器 (CDP 端口 9223)
        print("\n📡 连接到 CDP 端口 9223 的浏览器...")
        try:
            browser = pw.chromium.connect_over_cdp("http://127.0.0.1:9223")
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            print("请确保 VIDU 浏览器已启动（通过 api_server）")
            return
        
        contexts = browser.contexts
        if not contexts:
            print("❌ 没有找到浏览器上下文")
            return
        
        context = contexts[0]
        pages = context.pages
        
        # 找到 VIDU 页面
        vidu_page = None
        for page in pages:
            if 'vidu' in page.url:
                vidu_page = page
                break
        
        if not vidu_page:
            print("❌ 没有找到 VIDU 页面，当前页面:")
            for p in pages:
                print(f"   - {p.url}")
            return
        
        print(f"✅ 找到 VIDU 页面: {vidu_page.url[:80]}")
        
        # ========== 第一步：收集页面上现有的视频/图片 URL ==========
        print("\n" + "="*60)
        print("📊 第一步：分析页面上现有的视频/图片 URL")
        print("="*60)
        
        existing = vidu_page.evaluate("""
            () => {
                const result = {videos: [], images: [], downloads: [], allMedia: []};
                
                // 1. video 元素
                document.querySelectorAll('video').forEach(v => {
                    const src = v.src || v.currentSrc || '';
                    const sourceSrc = v.querySelector('source')?.src || '';
                    if (src && !src.startsWith('blob:')) result.videos.push({type: 'video-src', url: src});
                    if (sourceSrc && !sourceSrc.startsWith('blob:')) result.videos.push({type: 'video-source', url: sourceSrc});
                    if (v.poster) result.images.push({type: 'video-poster', url: v.poster});
                });
                
                // 2. img 元素（仅 vidu CDN 的）
                document.querySelectorAll('img').forEach(img => {
                    if (img.src && (img.src.includes('vidu') || img.src.includes('files.'))) {
                        result.images.push({type: 'img-src', url: img.src});
                    }
                });
                
                // 3. 下载链接
                document.querySelectorAll('a[download], a[href*=".mp4"], a[href*="download"]').forEach(a => {
                    if (a.href) result.downloads.push({type: 'download-link', url: a.href, text: a.textContent?.trim()});
                });
                
                // 4. 按钮/链接含"下载"文字
                document.querySelectorAll('button, a, [role="button"]').forEach(el => {
                    const text = el.textContent?.trim() || '';
                    if (text.includes('下载') || text.includes('Download')) {
                        const href = el.href || el.getAttribute('data-url') || '';
                        result.downloads.push({
                            type: 'download-button',
                            url: href, 
                            text: text.slice(0, 50),
                            classes: el.className?.slice(0, 100),
                            tag: el.tagName,
                        });
                    }
                });
                
                // 5. Performance API 中的媒体资源
                try {
                    performance.getEntriesByType('resource').forEach(e => {
                        if (e.name.includes('.mp4') || e.name.includes('.webm') || 
                            (e.name.includes('video') && !e.name.includes('.js') && !e.name.includes('.css'))) {
                            result.allMedia.push({type: 'perf-video', url: e.name});
                        }
                    });
                } catch(e) {}
                
                return result;
            }
        """)
        
        print(f"\n🎥 视频元素: {len(existing.get('videos', []))} 个")
        for v in existing.get('videos', []):
            analyze_url(v['url'], f"视频 ({v['type']})")
        
        print(f"\n🖼️ 图片: {len(existing.get('images', []))} 个 (仅 VIDU CDN)")
        for img in existing.get('images', [])[:5]:
            analyze_url(img['url'], f"图片 ({img['type']})")
        
        print(f"\n📥 下载相关元素: {len(existing.get('downloads', []))} 个")
        for dl in existing.get('downloads', []):
            if dl.get('url'):
                analyze_url(dl['url'], f"下载 ({dl['type']}) - {dl.get('text', '')}")
            else:
                print(f"   📋 {dl['type']}: 文字='{dl.get('text')}' 标签={dl.get('tag')} 无直接URL")
        
        print(f"\n📡 网络请求中的媒体: {len(existing.get('allMedia', []))} 个")
        for m in existing.get('allMedia', [])[:10]:
            analyze_url(m['url'], f"Performance ({m['type']})")
        
        # ========== 第二步：监听网络请求 ==========
        print("\n" + "="*60)
        print("📡 第二步：实时监听网络请求")
        print("   请在浏览器中点击 '下载' 按钮")
        print("   等待 30 秒后自动结束...")
        print("="*60)
        
        def on_response(response):
            url = response.url
            content_type = response.headers.get('content-type', '')
            
            # 捕获视频/图片下载
            is_media = any(ext in url for ext in ['.mp4', '.webm', '.mov', '.jpg', '.png', '.webp'])
            is_video_type = 'video' in content_type or 'octet-stream' in content_type
            is_download = 'download' in url.lower()
            is_vidu = 'vidu' in url or 'files.' in url
            
            if (is_media or is_video_type or is_download) and is_vidu:
                content_length = response.headers.get('content-length', '未知')
                captured_urls.append({
                    'url': url,
                    'status': response.status,
                    'content_type': content_type,
                    'content_length': content_length,
                    'method': response.request.method,
                })
                print(f"\n   🎯 捕获! {response.request.method} {url[:100]}")
                print(f"      状态={response.status} 类型={content_type} 大小={content_length}")
                analyze_url(url, f"实时捕获 ({response.request.method})")
            
            # 也捕获 API 响应（可能包含下载 URL）
            if 'vidu' in url and 'json' in content_type:
                try:
                    body = response.json()
                    body_str = str(body)
                    # 搜索响应中是否包含视频 URL
                    if '.mp4' in body_str or 'download' in body_str or 'video_url' in body_str:
                        print(f"\n   📋 API含视频URL: {url[-60:]}")
                        # 提取所有看起来像 URL 的字符串
                        import re
                        urls_in_body = re.findall(r'https?://[^\s"\'\\]+\.(?:mp4|webm|mov|jpg|png|webp)[^\s"\'\\]*', body_str)
                        for u in urls_in_body:
                            analyze_url(u, "API响应中的媒体URL")
                except Exception:
                    pass
        
        vidu_page.on('response', on_response)
        
        try:
            for i in range(30):
                time.sleep(1)
                if captured_urls:
                    print(f"\n   ⏱️ 已捕获 {len(captured_urls)} 个 URL, 继续监听... ({30-i}s)")
                elif i % 5 == 0:
                    print(f"   ⏱️ 等待中... 请点击下载按钮 ({30-i}s)")
        except KeyboardInterrupt:
            print("\n⏹️ 手动停止")
        
        # ========== 汇总报告 ==========
        print("\n" + "="*60)
        print("📊 汇总报告")
        print("="*60)
        
        if captured_urls:
            print(f"\n共捕获 {len(captured_urls)} 个媒体请求:")
            for i, cap in enumerate(captured_urls):
                analyze_url(cap['url'], f"捕获 #{i+1} ({cap['method']})")
            
            # 分析水印相关参数
            print("\n🔍 水印参数分析:")
            watermark_keywords = ['water', 'wm', 'mark', 'logo', 'stamp', 'overlay', 'free', 'vip', 'premium', 'quality', 'hd', 'sd']
            found_any = False
            for cap in captured_urls:
                parsed = urlparse(cap['url'])
                params = parse_qs(parsed.query)
                for k in params:
                    if any(w in k.lower() for w in watermark_keywords):
                        print(f"   ⚠️ 发现可疑参数: {k} = {params[k]}")
                        found_any = True
            
            if not found_any:
                print("   ❌ 未发现明显的水印/质量/会员区分参数")
                print("   💡 这意味着水印可能是在服务端渲染时直接嵌入到视频/图片文件中的")
                print("   💡 无法通过修改 URL 参数来去除水印")
        else:
            print("⚠️ 未捕获到任何媒体请求")
            print("可能原因：")
            print("   1. 没有在浏览器中点击下载")
            print("   2. 下载使用了 blob URL（无法抓包）")
            print("   3. 页面上没有可下载的内容")
        
        print("\n✅ 诊断完成")


if __name__ == '__main__':
    main()
