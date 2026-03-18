"""
获取完整的inspirations数据，找到无水印视频URL
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
        
        print("=== 获取完整的inspirations数据 ===")
        data = await page.evaluate("""async () => {
            const r = await fetch('https://service.vidu.cn/vidu/v1/inspirations/my?page_no=1&page_size=10', {
                credentials: 'include'
            });
            return await r.json();
        }""")
        
        inspirations = data.get('inspirations', [])
        print(f"共 {len(inspirations)} 个inspirations\n")
        
        for i, insp in enumerate(inspirations):
            print(f"--- Inspiration {i+1} ---")
            print(f"  type: {insp.get('type')}")
            
            ma = insp.get('media_asset', {})
            if ma:
                print(f"  media_asset.id: {ma.get('id')}")
                print(f"  media_asset.tag: {ma.get('tag')}")
                print(f"  media_asset.status: {ma.get('status')}")
                
                creation = ma.get('creation', {})
                if creation:
                    print(f"\n  creation.uri:")
                    uri = creation.get('uri', '')
                    print(f"    {uri}")
                    print(f"\n  creation.cover_uri:")
                    cover = creation.get('cover_uri', '')
                    print(f"    {cover}")
                    print(f"\n  creation.nomark_uri: {creation.get('nomark_uri', '(none)')}")
                    
                    # 检查uri中是否包含watermark相关路径
                    if 'propogat' in uri:
                        print(f"\n  ⚡ URI包含 'propogat' → 可能是无水印版本!")
                    if 'watermark' in uri:
                        print(f"  ⚠️ URI包含 'watermark'")
                    
                    # 其他creation字段
                    for key in creation:
                        if key not in ['uri', 'cover_uri', 'nomark_uri']:
                            val = creation[key]
                            if isinstance(val, str) and len(val) > 100:
                                print(f"  creation.{key}: {val[:80]}...")
                            else:
                                print(f"  creation.{key}: {val}")
                
                # 其他media_asset字段
                for key in ma:
                    if key not in ['id', 'tag', 'status', 'creation']:
                        val = ma[key]
                        if isinstance(val, str) and len(val) > 100:
                            print(f"  media_asset.{key}: {val[:100]}...")
                        elif isinstance(val, dict):
                            print(f"  media_asset.{key}: {json.dumps(val, ensure_ascii=False)[:200]}")
                        else:
                            print(f"  media_asset.{key}: {val}")
            
            # 顶层其他字段
            for key in insp:
                if key not in ['type', 'media_asset']:
                    print(f"  {key}: {insp[key]}")
            
            print()
        
        # 如果有craftify URL，尝试下载测试
        if inspirations:
            ma = inspirations[0].get('media_asset', {})
            creation = ma.get('creation', {})
            video_uri = creation.get('uri', '')
            
            if video_uri:
                print(f"\n=== 测试视频URL可访问性 ===")
                print(f"URL: {video_uri[:120]}...")
                
                # 用fetch测试HEAD
                test = await page.evaluate("""async (url) => {
                    try {
                        const r = await fetch(url, {method: 'HEAD'});
                        return {
                            status: r.status,
                            contentType: r.headers.get('content-type'),
                            contentLength: r.headers.get('content-length'),
                        };
                    } catch(e) {
                        return {error: e.message};
                    }
                }""", video_uri)
                print(f"HEAD测试: {json.dumps(test)}")
                
                # 提取文件名
                from urllib.parse import urlparse
                parsed = urlparse(video_uri)
                path = parsed.path
                filename = path.split('/')[-1]
                print(f"文件名: {filename}")
                print(f"路径: {path}")

asyncio.run(main())
