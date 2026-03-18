#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
深入搜索 VIDU JS 中 share_elements/submit 的调用处和参数格式
以及看广告去水印的完整流程
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
    
    # ============================================================
    # 第一步：找到 submit 函数的调用处（搜索变量名）
    # ============================================================
    print('\n' + '='*60)
    print('[1] 搜索 submit 调用处和 body 参数...')
    
    result = vidu_page.evaluate("""
        async () => {
            const findings = [];
            const scripts = Array.from(document.querySelectorAll('script[src]'));
            const jsUrls = scripts.map(s => s.src).filter(u => u.includes('_next') || u.includes('chunk'));
            
            for (const url of jsUrls) {
                try {
                    const resp = await fetch(url);
                    const text = await resp.text();
                    
                    // 策略1: 搜索 share_elements/submit 附近的完整函数体（2000字符范围）
                    let idx = text.indexOf('share_elements/submit');
                    if (idx >= 0) {
                        const bigCtx = text.substring(Math.max(0, idx - 1500), Math.min(text.length, idx + 1500));
                        findings.push({ 
                            type: 'submit_context',
                            file: url.split('/').pop().split('?')[0],
                            text: bigCtx
                        });
                    }
                    
                    // 策略2: 搜索包含 body 和 share 的模式
                    const patterns = [
                        /body:\s*\{[^}]*share/gi,
                        /body:\s*\{[^}]*element/gi,
                        /share_info/gi,
                        /shareInfo/gi,
                        /submitShare/gi,
                        /handleSubmit.*share/gi,
                        /handlePost.*creation/gi,
                    ];
                    
                    for (const pat of patterns) {
                        const matches = text.matchAll(pat);
                        for (const m of matches) {
                            const start = Math.max(0, m.index - 300);
                            const end = Math.min(text.length, m.index + m[0].length + 300);
                            findings.push({
                                type: 'body_pattern',
                                file: url.split('/').pop().split('?')[0],
                                pattern: pat.source,
                                text: text.substring(start, end)
                            });
                        }
                    }
                    
                    // 策略3: 找所有包含 "element" 和 "creation" 的对象字面量
                    const elemCreation = /\{[^{}]*element[^{}]*creation[^{}]*\}/gi;
                    const ecMatches = text.matchAll(elemCreation);
                    for (const m of ecMatches) {
                        findings.push({
                            type: 'element_creation',
                            file: url.split('/').pop().split('?')[0],
                            text: text.substring(Math.max(0, m.index - 200), Math.min(text.length, m.index + m[0].length + 200))
                        });
                    }
                    
                } catch(e) {}
            }
            return findings;
        }
    """)
    
    if result:
        print(f'  找到 {len(result)} 个匹配')
        for r in result:
            ctx = r['text'].replace('\n', ' ').replace('\r', '')
            print(f'\n  [{r["type"]}] in {r.get("file", "?")} pattern={r.get("pattern", "")}:')
            print(f'    {ctx[:600]}')
    else:
        print('  未找到匹配')
    
    # ============================================================
    # 第二步：找到看广告去水印的完整代码路径
    # ============================================================
    print('\n' + '='*60)
    print('[2] 分析看广告去水印的API调用路径...')
    
    ad_result = vidu_page.evaluate("""
        async () => {
            const findings = [];
            const scripts = Array.from(document.querySelectorAll('script[src]'));
            const jsUrls = scripts.map(s => s.src).filter(u => u.includes('_next') || u.includes('chunk'));
            
            for (const url of jsUrls) {
                try {
                    const resp = await fetch(url);
                    const text = await resp.text();
                    
                    // 搜索 remove_watermark_ad_popup 的上下文
                    let idx = text.indexOf('remove_watermark_ad_popup');
                    if (idx >= 0) {
                        findings.push({
                            type: 'ad_popup_def',
                            file: url.split('/').pop().split('?')[0],
                            text: text.substring(Math.max(0, idx - 1000), Math.min(text.length, idx + 2000))
                        });
                    }
                    
                    // 搜索 reportAdCompleted / rewardedSlotGranted
                    for (const kw of ['reportAdCompleted', 'rewardedSlotGranted', 'adCompleted', 'grantReward']) {
                        idx = text.indexOf(kw);
                        if (idx >= 0) {
                            findings.push({
                                type: 'ad_callback',
                                keyword: kw,
                                file: url.split('/').pop().split('?')[0],
                                text: text.substring(Math.max(0, idx - 500), Math.min(text.length, idx + 800))
                            });
                        }
                    }
                    
                    // 搜索 credit 相关的 API 调用（通常看完广告后会调积分API）
                    for (const kw of ['credit/v1', 'credits/claim', 'credits/reward', 'nexus/claim']) {
                        idx = text.indexOf(kw);
                        if (idx >= 0) {
                            findings.push({
                                type: 'credit_api',
                                keyword: kw,
                                file: url.split('/').pop().split('?')[0],
                                text: text.substring(Math.max(0, idx - 300), Math.min(text.length, idx + 500))
                            });
                        }
                    }
                    
                    // 搜索下载无水印相关函数
                    for (const kw of ['downloadNoWatermark', 'downloadWithout', 'noMarkDownload', 'freeDownload']) {
                        idx = text.indexOf(kw);
                        if (idx >= 0) {
                            findings.push({
                                type: 'download_func',
                                keyword: kw,
                                file: url.split('/').pop().split('?')[0],
                                text: text.substring(Math.max(0, idx - 300), Math.min(text.length, idx + 600))
                            });
                        }
                    }
                    
                } catch(e) {}
            }
            return findings;
        }
    """)
    
    if ad_result:
        print(f'  找到 {len(ad_result)} 个匹配')
        for r in ad_result:
            ctx = r['text'].replace('\n', ' ').replace('\r', '')
            kw = r.get('keyword', '')
            print(f'\n  [{r["type"]}] {kw} in {r.get("file", "?")}:')
            # 只打前600字符
            print(f'    {ctx[:600]}')
    else:
        print('  未找到匹配')
    
    # ============================================================
    # 第三步：检查积分系统API
    # ============================================================
    print('\n' + '='*60)
    print('[3] 检查积分系统...')
    
    # 查看当前积分
    credit_result = vidu_page.evaluate("""
        async () => {
            const results = {};
            
            // 1. 积分余额
            try {
                const resp = await fetch('https://service.vidu.cn/credit/v1/balance', { credentials: 'include' });
                results.balance = await resp.json();
            } catch(e) { results.balance_error = e.message; }
            
            // 2. 积分任务列表
            try {
                const resp = await fetch('https://service.vidu.cn/credit/v1/nexus/history', { credentials: 'include' });
                results.nexus = await resp.json();
            } catch(e) { results.nexus_error = e.message; }
            
            // 3. 用户配额信息
            try {
                const resp = await fetch('https://service.vidu.cn/vidu/v1/user/quota', { credentials: 'include' });
                results.quota = await resp.json();
            } catch(e) { results.quota_error = e.message; }
            
            // 4. 免费积分任务
            try {
                const resp = await fetch('https://service.vidu.cn/credit/v1/nexus/free_tasks', { credentials: 'include' });
                results.free_tasks = await resp.json();
            } catch(e) { results.free_tasks_error = e.message; }
            
            // 5. 广告奖励状态
            try {
                const resp = await fetch('https://service.vidu.cn/credit/v1/ad/status', { credentials: 'include' });
                results.ad_status = await resp.json();
            } catch(e) { results.ad_status_error = e.message; }
            
            // 6. 试探更多积分API
            const creditApis = [
                'https://service.vidu.cn/credit/v1/ad/reward',
                'https://service.vidu.cn/credit/v1/ad/claim',
                'https://service.vidu.cn/credit/v1/watermark/remove',
                'https://service.vidu.cn/credit/v1/download/free',
            ];
            results.probes = {};
            for (const url of creditApis) {
                try {
                    const resp = await fetch(url, { credentials: 'include' });
                    const text = await resp.text();
                    results.probes[url.split('credit/v1/')[1]] = { status: resp.status, body: text.slice(0, 200) };
                } catch(e) {
                    results.probes[url.split('credit/v1/')[1]] = { error: e.message };
                }
            }
            
            return results;
        }
    """)
    
    print(json.dumps(credit_result, ensure_ascii=False, indent=2, default=str)[:3000])
    
    # ============================================================
    # 第四步：尝试设置 VPN/区域绕过（检查国际版URL）
    # ============================================================
    print('\n' + '='*60)
    print('[4] 检查国际版 API...')
    
    # VIDU 区分中国和国际版，可能 API endpoint 不同
    # 看看环境变量 C.Ey 是什么
    region_info = vidu_page.evaluate("""
        () => {
            // 查找 window 上的区域配置
            const result = {};
            
            // 检查 __NEXT_DATA__
            const nextData = document.getElementById('__NEXT_DATA__');
            if (nextData) {
                try {
                    const data = JSON.parse(nextData.textContent);
                    result.runtimeConfig = data.runtimeConfig || {};
                    result.buildId = data.buildId || '';
                    result.locale = data.locale || '';
                    // 寻找区域相关的配置
                    const cfg = data.runtimeConfig || {};
                    for (const [k, v] of Object.entries(cfg)) {
                        if (typeof v === 'string' && v.length < 100) {
                            result['config_' + k] = v;
                        }
                    }
                } catch(e) {}
            }
            
            // 检查 cookie 中的区域信息
            result.cookies_region = document.cookie.split(';').filter(c => 
                c.toLowerCase().includes('region') || 
                c.toLowerCase().includes('locale') || 
                c.toLowerCase().includes('country') ||
                c.toLowerCase().includes('geo')
            ).map(c => c.trim());
            
            // 检查 URL
            result.currentUrl = window.location.href;
            result.hostname = window.location.hostname;
            
            return result;
        }
    """)
    
    print(json.dumps(region_info, ensure_ascii=False, indent=2, default=str)[:2000])
    
    pw.stop()
    print('\n[完成]')


if __name__ == '__main__':
    main()
