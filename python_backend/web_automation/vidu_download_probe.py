#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
VIDU 下载按钮交互探测 + 看广告流程分析
1. 导航到创作历史页面
2. 点击一个已完成视频的下载按钮
3. 捕获弹出的选项（有水印/无水印）
4. 分析看广告去水印的完整流程
"""

import sys
import json
import time
sys.stdout.reconfigure(encoding='utf-8')

from playwright.sync_api import sync_playwright

def main():
    pw = sync_playwright().start()
    browser = pw.chromium.connect_over_cdp('http://127.0.0.1:9223')
    ctx = browser.contexts[0]
    vidu_page = [p for p in ctx.pages if 'vidu' in p.url][0]
    
    print(f'连接: {vidu_page.url[:60]}')
    
    # 设置网络监听，捕获所有 API 调用
    captured_requests = []
    def on_request(request):
        url = request.url
        if 'vidu' in url and ('service.' in url or 'api.' in url):
            captured_requests.append({
                'method': request.method,
                'url': url,
                'time': time.time()
            })
    
    captured_responses = []
    def on_response(response):
        url = response.url
        if 'vidu' in url and ('service.' in url or 'api.' in url):
            try:
                body = response.text()
            except:
                body = '<binary>'
            captured_responses.append({
                'status': response.status,
                'url': url,
                'body': body[:500] if isinstance(body, str) else '',
                'time': time.time()
            })
    
    vidu_page.on('request', on_request)
    vidu_page.on('response', on_response)
    
    # ============================================================
    # 第一步：分析当前页面的下载相关元素
    # ============================================================
    print('\n' + '='*60)
    print('[1] 分析页面上的下载/视频相关元素...')
    
    # 先导航到创作历史
    print('  导航到 /my-creations...')
    vidu_page.goto('https://www.vidu.cn/my-creations', wait_until='networkidle', timeout=30000)
    time.sleep(3)
    
    # 截图看看页面
    vidu_page.screenshot(path='debug_my_creations.png')
    print('  已截图 debug_my_creations.png')
    
    # 查找视频卡片
    cards_info = vidu_page.evaluate("""
        () => {
            const result = { cards: [], buttons: [] };
            
            // 查找视频卡片（通常是带缩略图的容器）
            const videos = document.querySelectorAll('video, [data-testid*="creation"], [class*="creation"], [class*="card"]');
            for (const v of videos) {
                const rect = v.getBoundingClientRect();
                if (rect.width > 50 && rect.height > 50) {
                    result.cards.push({
                        tag: v.tagName,
                        class: (v.className || '').toString().slice(0, 80),
                        x: Math.round(rect.left),
                        y: Math.round(rect.top),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height),
                        text: (v.textContent || '').slice(0, 30)
                    });
                }
            }
            
            // 查找所有可见按钮
            const buttons = document.querySelectorAll('button, [role="button"], a');
            for (const btn of buttons) {
                const rect = btn.getBoundingClientRect();
                const text = (btn.textContent || '').trim();
                if (rect.width > 0 && rect.height > 0 && text.length > 0 && text.length < 30) {
                    // 排过大、位于视口外的
                    if (rect.top < 0 || rect.left < 0) continue;
                    if (rect.width > 500) continue;
                    result.buttons.push({
                        text: text,
                        x: Math.round(rect.left + rect.width / 2),
                        y: Math.round(rect.top + rect.height / 2),
                        tag: btn.tagName,
                        class: (btn.className || '').toString().slice(0, 60),
                        href: btn.href || ''
                    });
                }
            }
            
            return result;
        }
    """)
    
    print(f'  找到 {len(cards_info.get("cards", []))} 个卡片, {len(cards_info.get("buttons", []))} 个按钮')
    
    # 显示按钮信息
    dl_buttons = [b for b in cards_info.get('buttons', []) if any(kw in b['text'].lower() for kw in ['下载', 'download', '⬇', '保存'])]
    if dl_buttons:
        print(f'  ✅ 找到 {len(dl_buttons)} 个下载按钮:')
        for b in dl_buttons:
            print(f'    "{b["text"]}" at ({b["x"]}, {b["y"]})')
    else:
        print('  未找到明显的下载按钮')
    
    # 显示有用的按钮
    interesting = [b for b in cards_info.get('buttons', []) if any(kw in b['text'] for kw in ['下载', '分享', '投稿', '发布', '水印', '广告', 'VIP', '会员'])]
    if interesting:
        print(f'  其他相关按钮:')
        for b in interesting:
            print(f'    "{b["text"]}" at ({b["x"]}, {b["y"]})')
    
    # ============================================================
    # 第二步：点击第一个视频卡片打开详情
    # ============================================================
    print('\n' + '='*60)
    print('[2] 尝试点击第一个视频卡片...')
    
    # 查找可点击的视频/图片缩略图
    clickable = vidu_page.evaluate("""
        () => {
            // 查找所有图片（可能是视频缩略图）
            const imgs = document.querySelectorAll('img');
            const candidates = [];
            for (const img of imgs) {
                const rect = img.getBoundingClientRect();
                // 寻找合理大小的缩略图
                if (rect.width > 80 && rect.width < 500 && rect.height > 80 && rect.height < 500) {
                    if (rect.top > 0 && rect.left > 0) {
                        candidates.push({
                            src: (img.src || '').slice(0, 100),
                            alt: img.alt || '',
                            x: Math.round(rect.left + rect.width / 2),
                            y: Math.round(rect.top + rect.height / 2),
                            w: Math.round(rect.width),
                            h: Math.round(rect.height)
                        });
                    }
                }
            }
            // 也检查 video 元素
            const vids = document.querySelectorAll('video');
            for (const v of vids) {
                const rect = v.getBoundingClientRect();
                if (rect.width > 80 && rect.height > 80) {
                    candidates.push({
                        src: 'VIDEO',
                        alt: '',
                        x: Math.round(rect.left + rect.width / 2),
                        y: Math.round(rect.top + rect.height / 2),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height)
                    });
                }
            }
            return candidates;
        }
    """)
    
    print(f'  找到 {len(clickable)} 个可点击的缩略图')
    for c in clickable[:5]:
        print(f'    {c["w"]}x{c["h"]} at ({c["x"]}, {c["y"]}) src={c["src"][:60]}')
    
    if clickable:
        # 点击第一个缩略图
        target = clickable[0]
        print(f'  点击: ({target["x"]}, {target["y"]})')
        vidu_page.mouse.click(target['x'], target['y'])
        time.sleep(3)
        
        # 截图
        vidu_page.screenshot(path='debug_creation_detail.png')
        print('  已截图 debug_creation_detail.png')
        
        # ============================================================
        # 第三步：在详情页找下载按钮
        # ============================================================
        print('\n' + '='*60)
        print('[3] 在详情页查找下载相关元素...')
        
        detail_elements = vidu_page.evaluate("""
            () => {
                const result = { buttons: [], icons: [], dialogs: [] };
                
                // 查找所有可见元素，包含下载/水印相关文本或图标
                const allEls = document.querySelectorAll('button, [role="button"], a, svg, span, div');
                for (const el of allEls) {
                    const rect = el.getBoundingClientRect();
                    if (rect.width === 0 || rect.height === 0) continue;
                    
                    const text = (el.textContent || '').trim();
                    const ariaLabel = el.getAttribute('aria-label') || '';
                    const title = el.getAttribute('title') || '';
                    const className = (el.className || '').toString();
                    
                    // 匹配下载/水印/分享相关
                    const combined = (text + ' ' + ariaLabel + ' ' + title + ' ' + className).toLowerCase();
                    if (combined.includes('download') || combined.includes('下载') || 
                        combined.includes('watermark') || combined.includes('水印') ||
                        combined.includes('share') || combined.includes('分享') ||
                        combined.includes('save') || combined.includes('保存')) {
                        result.buttons.push({
                            text: text.slice(0, 40),
                            ariaLabel: ariaLabel,
                            title: title,
                            tag: el.tagName.toLowerCase(),
                            x: Math.round(rect.left + rect.width / 2),
                            y: Math.round(rect.top + rect.height / 2),
                            w: Math.round(rect.width),
                            h: Math.round(rect.height),
                            class: className.toString().slice(0, 80)
                        });
                    }
                }
                
                // 查找弹窗/overlay
                const modals = document.querySelectorAll('[role="dialog"], [class*="modal"], [class*="overlay"], [class*="popup"]');
                for (const m of modals) {
                    const rect = m.getBoundingClientRect();
                    result.dialogs.push({
                        tag: m.tagName,
                        class: (m.className || '').toString().slice(0, 80),
                        visible: rect.width > 0 && rect.height > 0,
                        text: (m.textContent || '').slice(0, 100)
                    });
                }
                
                return result;
            }
        """)
        
        dl_btns = detail_elements.get('buttons', [])
        print(f'  找到 {len(dl_btns)} 个下载/水印/分享相关元素:')
        for b in dl_btns[:20]:
            print(f'    [{b["tag"]}] "{b["text"]}" aria="{b["ariaLabel"]}" title="{b["title"]}" at ({b["x"]}, {b["y"]}) {b["w"]}x{b["h"]}')
        
        dialogs = detail_elements.get('dialogs', [])
        if dialogs:
            print(f'  弹窗: {len(dialogs)} 个')
            for d in dialogs:
                print(f'    visible={d["visible"]}: {d["text"][:60]}')
        
        # ============================================================
        # 第四步：点击下载按钮看弹出什么
        # ============================================================
        if dl_btns:
            # 找最小的下载按钮（通常是图标按钮）
            download_cands = [b for b in dl_btns if ('download' in (b['text'] + b['ariaLabel'] + b['title']).lower() or '下载' in (b['text'] + b['ariaLabel'] + b['title']))]
            if not download_cands:
                download_cands = dl_btns
            
            # 选一个合理大小的按钮
            download_cands.sort(key=lambda b: b['w'] * b['h'])
            target_btn = download_cands[0]
            
            print(f'\n  点击下载按钮: "{target_btn["text"]}" at ({target_btn["x"]}, {target_btn["y"]})')
            
            # 清空之前的网络记录
            captured_requests.clear()
            captured_responses.clear()
            
            vidu_page.mouse.click(target_btn['x'], target_btn['y'])
            time.sleep(2)
            
            # 截图看弹出了什么
            vidu_page.screenshot(path='debug_download_dialog.png')
            print('  已截图 debug_download_dialog.png')
            
            # 检查弹出的菜单/对话框
            popup_info = vidu_page.evaluate("""
                () => {
                    const popups = [];
                    
                    // 查找所有可能的弹出菜单
                    const allEls = document.querySelectorAll('[role="menu"], [role="dialog"], [role="listbox"], [class*="dropdown"], [class*="popover"], [class*="popup"], [class*="menu"], [class*="modal"]');
                    for (const el of allEls) {
                        const rect = el.getBoundingClientRect();
                        if (rect.width > 0 && rect.height > 0) {
                            popups.push({
                                role: el.getAttribute('role') || '',
                                class: (el.className || '').toString().slice(0, 100),
                                text: (el.textContent || '').slice(0, 300),
                                x: Math.round(rect.left),
                                y: Math.round(rect.top),
                                w: Math.round(rect.width),
                                h: Math.round(rect.height)
                            });
                        }
                    }
                    
                    // 也查找最近出现的覆盖层
                    const overlays = document.querySelectorAll('[class*="overlay"][style*="opacity"]');
                    for (const o of overlays) {
                        const rect = o.getBoundingClientRect();
                        popups.push({
                            role: 'overlay',
                            class: (o.className || '').toString().slice(0, 100),
                            text: 'overlay',
                            w: Math.round(rect.width),
                            h: Math.round(rect.height)
                        });
                    }
                    
                    return popups;
                }
            """)
            
            print(f'\n  弹出的菜单/对话框: {len(popup_info)} 个')
            for p in popup_info:
                print(f'    [{p.get("role", "?")}] {p.get("w")}x{p.get("h")} at ({p.get("x", "?")}, {p.get("y", "?")})')
                text = p.get('text', '').replace('\n', ' | ')
                print(f'      文本: {text[:200]}')
            
            # 打印捕获的网络请求
            if captured_requests:
                print(f'\n  捕获 {len(captured_requests)} 个API请求:')
                for req in captured_requests:
                    print(f'    {req["method"]} {req["url"][-80:]}')
            
            if captured_responses:
                print(f'\n  捕获 {len(captured_responses)} 个API响应:')
                for resp in captured_responses:
                    print(f'    [{resp["status"]}] {resp["url"][-80:]}')
                    if resp['body']:
                        print(f'      {resp["body"][:150]}')
    
    # ============================================================
    # 第五步：搜索 JS 中 share_elements 的请求格式
    # ============================================================
    print('\n' + '='*60)
    print('[5] 深入搜索 share_elements/submit 的请求格式...')
    
    share_format = vidu_page.evaluate("""
        async () => {
            const results = [];
            const scripts = Array.from(document.querySelectorAll('script[src]'));
            const jsUrls = scripts.map(s => s.src).filter(u => u.includes('_next') || u.includes('chunk'));
            
            for (const url of jsUrls) {
                try {
                    const resp = await fetch(url);
                    const text = await resp.text();
                    
                    // 搜索 share_elements 附近的代码，扩大范围到 1000 字符
                    let idx = 0;
                    while (true) {
                        idx = text.indexOf('share_elements', idx);
                        if (idx < 0) break;
                        const context = text.substring(Math.max(0, idx - 800), Math.min(text.length, idx + 800));
                        results.push({
                            file: url.split('/').pop().split('?')[0],
                            context: context,
                            pos: idx
                        });
                        idx += 14;
                    }
                    
                    // 搜索 submit 请求（通常用 fetch/axios）
                    const submitIdx = text.indexOf('material/share');
                    if (submitIdx >= 0) {
                        const ctx2 = text.substring(Math.max(0, submitIdx - 500), Math.min(text.length, submitIdx + 500));
                        results.push({
                            file: url.split('/').pop().split('?')[0],
                            context: ctx2,
                            pos: submitIdx,
                            type: 'material_share'
                        });
                    }
                    
                } catch(e) {}
            }
            return results;
        }
    """)
    
    if share_format:
        print(f'  找到 {len(share_format)} 个匹配:')
        for r in share_format:
            tp = r.get('type', 'share_elements')
            ctx = r['context'].replace('\n', ' ').replace('\r', '')
            print(f'\n  [{tp}] in {r["file"]} @{r["pos"]}:')
            print(f'    {ctx[:600]}')
    else:
        print('  未找到匹配')
    
    pw.stop()
    print('\n[完成]')


if __name__ == '__main__':
    main()
