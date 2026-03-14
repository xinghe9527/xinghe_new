#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Vidu 完整自动视频生成脚本（包含下载功能）
使用持久化登录状态，自动填充提示词、生成视频并下载

用法：
    python auto_vidu_complete.py "提示词" [--save-path 保存路径] [--max-wait 最大等待分钟数]
"""

import sys
import io

# 安全打印（stdout 管道断裂时不抛异常）
_original_print = print
def _safe_print(*args, **kwargs):
    try:
        _original_print(*args, **kwargs)
    except (OSError, IOError, ValueError):
        pass
print = _safe_print

# ✅ 立即输出，确保脚本启动
print("="*60, flush=True)
print("  🚀 Vidu 自动化脚本启动", flush=True)
print("="*60, flush=True)

import json
import os
import argparse
import time
import requests
import re
import random  # ✅ 添加随机模块，用于模拟人类行为
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError
from pathlib import Path

print("✅ 所有模块导入成功", flush=True)

# 确保标准输出使用 UTF-8 编码（Windows 兼容）
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 获取项目根目录的绝对路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
USER_DATA_ROOT = os.path.join(PROJECT_ROOT, 'python_backend', 'user_data')

# Vidu 配置（.com 已重定向到 .cn）
VIDU_URL = 'https://www.vidu.cn/create/text2video'
USER_DATA_DIR = os.path.join(USER_DATA_ROOT, 'vidu_profile')

# 默认下载目录
DEFAULT_DOWNLOAD_DIR = os.path.join(SCRIPT_DIR, 'downloads')


def human_like_delay(min_seconds=0.5, max_seconds=2.0):
    """模拟人类操作的随机延迟"""
    delay = random.uniform(min_seconds, max_seconds)
    time.sleep(delay)


def upload_reference_file(page, file_path):
    """
    上传参考文件（图片）到 ref2video 页面
    
    流程：
    1. 点击"上传图片/主体"区域
    2. 弹出菜单：「+ 图片」和「+ 主体库」
    3. 点击「+ 图片」
    4. 弹出文件选择对话框
    5. 选择文件
    
    Args:
        page: Playwright 页面对象
        file_path: 本地文件路径
    
    Returns:
        bool: 是否上传成功
    """
    print(f"\n📤 开始上传参考文件: {file_path}")
    
    if not os.path.exists(file_path):
        print(f"❌ 文件不存在: {file_path}")
        return False
    
    try:
        # ========== 第1步：点击"上传图片/主体"区域 ==========
        print("🔍 第1步：查找并点击「上传图片/主体」区域...")
        
        upload_area_clicked = False
        area_selectors = [
            'text="上传图片 / 主体"',
            'div:has-text("上传图片 / 主体"):visible',
            'div:has-text("上传图片"):visible',
        ]
        
        for selector in area_selectors:
            try:
                elements = page.locator(selector).all()
                for element in elements:
                    try:
                        if not element.is_visible(timeout=1000):
                            continue
                        box = element.bounding_box()
                        if not box or box['x'] > 500:
                            continue
                        
                        print(f"✅ 找到上传区域: {selector}")
                        
                        # 高亮
                        try:
                            element.evaluate("el => el.style.border = '3px solid blue'")
                        except:
                            pass
                        time.sleep(0.5)
                        
                        element.click(timeout=3000)
                        print("✅ 已点击上传区域")
                        upload_area_clicked = True
                        break
                    except:
                        continue
                if upload_area_clicked:
                    break
            except:
                continue
        
        if not upload_area_clicked:
            print("❌ 未找到「上传图片/主体」区域")
            page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_no_upload_area_{int(time.time())}.png'))
            return False
        
        # 等待菜单弹出
        time.sleep(1)
        
        # ========== 第2步：点击「+ 图片」按钮 ==========
        print("🔍 第2步：查找并点击「+ 图片」按钮...")
        
        pic_button_clicked = False
        pic_selectors = [
            'text="图片"',
            'text="+ 图片"',
            'button:has-text("图片")',
            'div:has-text("图片"):not(:has-text("上传图片")):not(:has-text("主体"))',
        ]
        
        for selector in pic_selectors:
            try:
                elements = page.locator(selector).all()
                for element in elements:
                    try:
                        if not element.is_visible(timeout=1000):
                            continue
                        box = element.bounding_box()
                        if not box or box['x'] > 500:
                            continue
                        # 排除太大的元素（避免选中整个面板）
                        if box['width'] > 300 or box['height'] > 100:
                            continue
                        
                        text = element.inner_text().strip()
                        # 确保是「图片」或「+ 图片」，不是「上传图片/主体」
                        if '上传' in text or '主体库' in text:
                            continue
                        
                        print(f"✅ 找到「图片」按钮: text='{text}'")
                        print(f"   位置: x={box['x']:.0f}, y={box['y']:.0f}, w={box['width']:.0f}, h={box['height']:.0f}")
                        
                        # 高亮
                        try:
                            element.evaluate("el => el.style.border = '3px solid green'")
                        except:
                            pass
                        time.sleep(0.3)
                        
                        # 点击并拦截文件选择对话框
                        try:
                            with page.expect_file_chooser(timeout=5000) as fc_info:
                                element.click(timeout=3000)
                            
                            file_chooser = fc_info.value
                            print("✅ 文件选择对话框已弹出")
                            file_chooser.set_files(file_path)
                            print(f"✅ 文件已选择: {os.path.basename(file_path)}")
                            pic_button_clicked = True
                            break
                        except Exception as fc_err:
                            print(f"⚠️  file_chooser 失败: {str(fc_err)[:60]}")
                            continue
                    except:
                        continue
                if pic_button_clicked:
                    break
            except:
                continue
        
        if not pic_button_clicked:
            print("❌ 未找到「+ 图片」按钮或文件选择失败")
            page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_no_pic_btn_{int(time.time())}.png'))
            return False
        
        # ========== 第3步：等待上传完成 ==========
        print("⏳ 等待上传处理（3秒）...")
        time.sleep(3)
        
        page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_after_upload_{int(time.time())}.png'))
        print("✅ 参考文件上传完成")
        return True
        
    except Exception as e:
        print(f"❌ 上传异常: {e}")
        page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_upload_error_{int(time.time())}.png'))
        return False

def select_character_from_library(page, character_names):
    """
    从 Vidu 主体库中选择指定名称的角色（支持多个）
    
    Vidu 主体库操作流程：
    1. 点击「上传图片/主体」区域 → 弹出菜单（有"+ 图片"和"+ 主体库"）
    2. 点击「+ 主体库」→ 右侧弹出主体库面板
    3. 在搜索框输入角色名搜索
    4. 点击搜索结果中对应名字的主体卡片（用真实鼠标点击图片区域）
    5. 选中后文本框自动出现占位符
    6. 多个主体：重复以上步骤
    
    Args:
        page: Playwright 页面对象
        character_names: 角色名称列表（如 ["朵莉亚", "小狗"]）
    
    Returns:
        int: 成功选择的主体数量
    """
    import sys as _sys
    def _print(msg):
        """确保输出立即刷新"""
        print(msg, flush=True)
    
    if isinstance(character_names, str):
        character_names = [character_names]
    
    _print(f"\n🎭 开始从主体库选择角色: {character_names}")
    selected_count = 0
    
    # 记录主体库面板是否已打开（优化多主体选择流程）
    library_panel_open = False
    
    for idx, char_name in enumerate(character_names):
        _print(f"\n{'─'*40}")
        _print(f"🎭 选择主体 [{idx+1}/{len(character_names)}]: {char_name}")
        
        # 每次迭代前截图（特别是第二个及之后的主体）
        if idx > 0:
            page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_before_char{idx+1}_{char_name}_{int(time.time())}.png'))
            _print(f"📸 已截图保存选择第{idx+1}个主体前的页面状态")
        
        try:
            # ========== 判断主体库面板是否已打开 ==========
            # 如果是第二个及之后的主体，先检查面板是否还开着
            panel_already_open = False
            if idx > 0 and library_panel_open:
                # 检查右侧面板是否仍然可见（搜索框在 x > 300 区域）
                panel_check = page.evaluate("""
                    () => {
                        const inputs = document.querySelectorAll('input');
                        for (const inp of inputs) {
                            const rect = inp.getBoundingClientRect();
                            if (rect.left > 300 && rect.width > 50 && rect.height > 20 && rect.width < 500) {
                                const placeholder = inp.placeholder || '';
                                if (placeholder.includes('搜索') || placeholder.includes('查找') || placeholder.includes('名称') || placeholder.includes('主体') || inp.type === 'search') {
                                    return { open: true, x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2) };
                                }
                            }
                        }
                        // 备用：检查右侧面板是否有主体卡片（图片 + 名字）
                        const cards = document.querySelectorAll('img');
                        let rightPanelCards = 0;
                        for (const img of cards) {
                            const rect = img.getBoundingClientRect();
                            if (rect.left > 300 && rect.width > 50 && rect.width < 400 && rect.height > 50) {
                                rightPanelCards++;
                            }
                        }
                        if (rightPanelCards >= 2) {
                            return { open: true, x: 0, y: 0 };
                        }
                        return { open: false };
                    }
                """)
                
                if panel_check and panel_check.get('open'):
                    panel_already_open = True
                    _print(f"✅ 主体库面板仍然打开，直接搜索下一个主体")
            
            # ========== 策略D: 已选过主体且面板已关闭时，直接查找「主体库」按钮 ==========
            # Vidu 选过第一个主体后，页面不再显示"上传图片/主体"，而是显示独立的
            # "视频"/"主体库" 按钮组。直接点击「主体库」可一步打开面板，跳过 Step1+Step2
            if idx > 0 and not panel_already_open:
                _print("⚠️  主体库面板已关闭，尝试策略D: 直接查找「主体库」按钮...")
                strategy_d_info = page.evaluate("""
                    () => {
                        const allEls = document.querySelectorAll('div, span, button');
                        const candidates = [];
                        for (const el of allEls) {
                            const text = el.textContent.trim();
                            // 精确匹配"主体库"（排除"视频主体库"等容器文本）
                            if (text !== '主体库') continue;
                            const rect = el.getBoundingClientRect();
                            if (rect.left > 500 || rect.width === 0 || rect.height === 0) continue;
                            if (rect.width > 120 || rect.height > 50) continue;
                            
                            // 检查父级上下文
                            let parentText = '';
                            let parent = el.parentElement;
                            for (let i = 0; i < 5 && parent; i++) {
                                parentText += (parent.textContent || '') + ' ';
                                parent = parent.parentElement;
                            }
                            
                            // 判断所属区域：
                            // - "图片"区域（包含已选角色，显示静态主体）→ 优先选择
                            // - "视频"区域（空位，仅显示动态主体）→ 次选
                            const isVideoSection = parentText.includes('视频') && !parentText.includes('图片');
                            const isImageSection = parentText.includes('图片');
                            
                            candidates.push({
                                text: text,
                                x: Math.round(rect.left + rect.width / 2),
                                y: Math.round(rect.top + rect.height / 2),
                                w: Math.round(rect.width),
                                h: Math.round(rect.height),
                                isVideoSection: isVideoSection,
                                isImageSection: isImageSection,
                                tag: el.tagName.toLowerCase(),
                                parentSnippet: parentText.substring(0, 60),
                            });
                        }
                        if (candidates.length === 0) return { found: false };
                        // 优先选"图片"区域的按钮（显示静态主体/所有主体），
                        // 其次选"视频"区域，最后按y坐标选最下方的（更可能是图片区）
                        candidates.sort((a, b) => {
                            if (a.isImageSection !== b.isImageSection) return a.isImageSection ? -1 : 1;
                            if (a.isVideoSection !== b.isVideoSection) return a.isVideoSection ? 1 : -1;
                            return b.y - a.y;  // 选最下方的
                        });
                        return { found: true, ...candidates[0], allCandidates: candidates };
                    }
                """)
                if strategy_d_info and strategy_d_info.get('found'):
                    sx, sy = strategy_d_info['x'], strategy_d_info['y']
                    all_cands = strategy_d_info.get('allCandidates', [])
                    _print(f"✅ 策略D: 找到 {len(all_cands)} 个「主体库」按钮")
                    for ci, c in enumerate(all_cands):
                        _print(f"   [{ci}] ({c.get('x')}, {c.get('y')}) image={c.get('isImageSection')} video={c.get('isVideoSection')} parent={c.get('parentSnippet', '')[:40]}")
                    _print(f"✅ 策略D选择: ({sx}, {sy}) image={strategy_d_info.get('isImageSection')} video={strategy_d_info.get('isVideoSection')}")
                    page.mouse.click(sx, sy)
                    _print("✅ 已点击「主体库」按钮，等待面板打开...")
                    time.sleep(2.5)
                    panel_already_open = True  # 面板已打开，跳过 Step1+Step2
                    page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_strategy_d_clicked_{int(time.time())}.png'))
                else:
                    _print("⚠️  策略D未找到「主体库」按钮，将使用常规 Step1+Step2 流程")
            
            if not panel_already_open:
                # ========== 第1步：点击「上传图片/主体」区域或「+」按钮 ==========
                # 第一次选择时，点击"上传图片/主体"文字区域
                # 已选过主体后，可能需要找"+"按钮或新的上传入口
                _print("🔍 第1步：打开上传/主体入口...")
                
                # 策略A: 查找原始的"上传图片/主体"文字区域
                upload_info = page.evaluate("""
                    () => {
                        const allEls = document.querySelectorAll('div, span');
                        const candidates = [];
                        
                        for (const el of allEls) {
                            const text = el.textContent.trim();
                            if (text.includes('上传图片') && text.includes('主体') && text.length < 60) {
                                const rect = el.getBoundingClientRect();
                                if (rect.left < 500 && rect.width > 30 && rect.height > 15 && rect.width < 500) {
                                    candidates.push({
                                        text: text.substring(0, 50),
                                        x: Math.round(rect.left + rect.width / 2),
                                        y: Math.round(rect.top + rect.height / 2),
                                        w: Math.round(rect.width),
                                        h: Math.round(rect.height),
                                    });
                                }
                            }
                        }
                        
                        if (candidates.length === 0) return { found: false, candidates: [] };
                        candidates.sort((a, b) => a.text.length - b.text.length);
                        return { found: true, ...candidates[0], allCandidates: candidates };
                    }
                """)
                
                # 策略B: 如果原始文字区域没找到（已选主体后UI变化），查找"+"按钮
                if not upload_info or not upload_info.get('found'):
                    _print("⚠️  未找到原始「上传图片/主体」文字，尝试查找添加按钮...")
                    upload_info = page.evaluate("""
                        () => {
                            const allEls = document.querySelectorAll('div, span, button, svg, a, i');
                            const candidates = [];
                            
                            for (const el of allEls) {
                                const rect = el.getBoundingClientRect();
                                // 必须在左侧面板
                                if (rect.left > 500 || rect.width === 0 || rect.height === 0) continue;
                                
                                const text = (el.textContent || '').trim();
                                const ariaLabel = (el.getAttribute('aria-label') || '').toLowerCase();
                                const title = (el.getAttribute('title') || '').toLowerCase();
                                const className = (el.className || '').toString().toLowerCase();
                                
                                // 查找"+"按钮、"添加"按钮、"添加主体"按钮
                                let isAddBtn = false;
                                
                                // 检查文本内容
                                if (text === '+' || text === '＋' || text.includes('添加') || text.includes('新增')) {
                                    isAddBtn = true;
                                }
                                // 检查 aria-label 或 title
                                if (ariaLabel.includes('add') || ariaLabel.includes('添加') || title.includes('add') || title.includes('添加')) {
                                    isAddBtn = true;
                                }
                                // 检查 class 名（常见命名）
                                if (className.includes('add') || className.includes('plus')) {
                                    isAddBtn = true;
                                }
                                // 检查 SVG 图标是否是 "+" 形状（有 line 或 path 元素）
                                if (el.tagName.toLowerCase() === 'svg' && el.querySelector('line, path')) {
                                    const lines = el.querySelectorAll('line');
                                    if (lines.length === 2) isAddBtn = true;  // "+" 通常由两条线组成
                                }
                                
                                if (isAddBtn && rect.width < 200 && rect.height < 200) {
                                    candidates.push({
                                        text: text.substring(0, 30) || '[图标]',
                                        x: Math.round(rect.left + rect.width / 2),
                                        y: Math.round(rect.top + rect.height / 2),
                                        w: Math.round(rect.width),
                                        h: Math.round(rect.height),
                                        tag: el.tagName.toLowerCase(),
                                    });
                                }
                            }
                            
                            // 策略C: 查找空的虚线框区域（通常用于添加更多内容）
                            const dashBoxes = document.querySelectorAll('[style*="dashed"], [class*="dashed"], [class*="upload"], [class*="add-more"]');
                            for (const el of dashBoxes) {
                                const rect = el.getBoundingClientRect();
                                if (rect.left < 500 && rect.width > 30 && rect.height > 30 && rect.width < 300 && rect.height < 300) {
                                    candidates.push({
                                        text: (el.textContent || '').trim().substring(0, 30) || '[虚线框]',
                                        x: Math.round(rect.left + rect.width / 2),
                                        y: Math.round(rect.top + rect.height / 2),
                                        w: Math.round(rect.width),
                                        h: Math.round(rect.height),
                                        tag: el.tagName.toLowerCase(),
                                    });
                                }
                            }
                            
                            if (candidates.length === 0) return { found: false, candidates: [] };
                            // 优先选小尺寸的（更可能是按钮而非容器）
                            candidates.sort((a, b) => (a.w * a.h) - (b.w * b.h));
                            return { found: true, ...candidates[0], allCandidates: candidates };
                        }
                    """)
                
                if not upload_info or not upload_info.get('found'):
                    _print(f"❌ 未找到上传入口或添加按钮，跳过「{char_name}」")
                    # 打印调试信息
                    debug_texts = page.evaluate("""
                        () => {
                            const results = [];
                            const allEls = document.querySelectorAll('div, span, button, a, svg');
                            for (const el of allEls) {
                                const text = (el.textContent || '').trim();
                                if (text.length < 30) {
                                    const rect = el.getBoundingClientRect();
                                    if (rect.left < 500 && rect.width > 0 && rect.height > 0 && rect.height < 100) {
                                        if (text.includes('主体') || text.includes('图片') || text.includes('上传') || text.includes('添加') || text === '+') {
                                            results.push({ text: text || '[空]', x: Math.round(rect.left), y: Math.round(rect.top), w: Math.round(rect.width), h: Math.round(rect.height), tag: el.tagName });
                                        }
                                    }
                                }
                            }
                            return results;
                        }
                    """)
                    _print("📋 页面上相关元素:")
                    for dt in (debug_texts or []):
                        _print(f"   '{dt.get('text')}' tag={dt.get('tag')} x={dt.get('x')} y={dt.get('y')} w={dt.get('w')} h={dt.get('h')}")
                    page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_no_upload_entry_{char_name}_{int(time.time())}.png'))
                    continue
                
                # 用真实鼠标点击
                ux, uy = upload_info['x'], upload_info['y']
                _print(f"📍 找到入口: '{upload_info.get('text', '')}' ({ux}, {uy})")
                page.mouse.click(ux, uy)
                _print("✅ 已点击入口")
                time.sleep(1.5)
                
                page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_after_upload_click_{int(time.time())}.png'))
                
                # ========== 第2步：点击「+ 主体库」==========
                _print("🔍 第2步：点击「+ 主体库」...")
                
                lib_info = page.evaluate("""
                    () => {
                        const allEls = document.querySelectorAll('div, span, button, a, li');
                        const candidates = [];
                        
                        for (const el of allEls) {
                            const text = el.textContent.trim();
                            if (text.includes('主体库') && text.length < 30) {
                                const rect = el.getBoundingClientRect();
                                if (rect.width === 0 || rect.height === 0) continue;
                                if (rect.left > 600) continue;
                                
                                candidates.push({
                                    text: text,
                                    x: Math.round(rect.left + rect.width / 2),
                                    y: Math.round(rect.top + rect.height / 2),
                                    w: Math.round(rect.width),
                                    h: Math.round(rect.height),
                                    tag: el.tagName.toLowerCase(),
                                });
                            }
                        }
                        
                        if (candidates.length === 0) return { found: false, candidates: [] };
                        candidates.sort((a, b) => a.text.length - b.text.length);
                        return { found: true, ...candidates[0], allCandidates: candidates };
                    }
                """)
                
                if not lib_info or not lib_info.get('found'):
                    _print("⚠️  未找到「主体库」按钮，尝试重新点击入口...")
                    page.mouse.click(ux, uy)
                    time.sleep(2)
                    
                    lib_info = page.evaluate("""
                        () => {
                            const allEls = document.querySelectorAll('div, span, button, a, li');
                            const candidates = [];
                            for (const el of allEls) {
                                const text = el.textContent.trim();
                                if (text.includes('主体库') && text.length < 30) {
                                    const rect = el.getBoundingClientRect();
                                    if (rect.width === 0 || rect.height === 0) continue;
                                    if (rect.left > 600) continue;
                                    candidates.push({
                                        text: text,
                                        x: Math.round(rect.left + rect.width / 2),
                                        y: Math.round(rect.top + rect.height / 2),
                                        w: Math.round(rect.width),
                                        h: Math.round(rect.height),
                                    });
                                }
                            }
                            if (candidates.length === 0) return { found: false };
                            candidates.sort((a, b) => a.text.length - b.text.length);
                            return { found: true, ...candidates[0] };
                        }
                    """)
                
                if not lib_info or not lib_info.get('found'):
                    _print(f"❌ 未找到「主体库」按钮，跳过「{char_name}」")
                    debug_texts = page.evaluate("""
                        () => {
                            const results = [];
                            const allEls = document.querySelectorAll('div, span, button, a');
                            for (const el of allEls) {
                                const text = el.textContent.trim();
                                if (text.length > 0 && text.length < 30) {
                                    const rect = el.getBoundingClientRect();
                                    if (rect.left < 500 && rect.width > 0 && rect.height > 0 && rect.height < 60) {
                                        if (text.includes('主体') || text.includes('图片') || text.includes('上传')) {
                                            results.push({ text: text, x: Math.round(rect.left), y: Math.round(rect.top), w: Math.round(rect.width), h: Math.round(rect.height) });
                                        }
                                    }
                                }
                            }
                            return results;
                        }
                    """)
                    _print("📋 页面上相关文本元素:")
                    for dt in (debug_texts or []):
                        _print(f"   '{dt.get('text')}' x={dt.get('x')} y={dt.get('y')} w={dt.get('w')} h={dt.get('h')}")
                    page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_no_lib_btn_{int(time.time())}.png'))
                    continue
                
                # 用真实鼠标点击"主体库"
                lx, ly = lib_info['x'], lib_info['y']
                _print(f"📍 找到主体库按钮: '{lib_info.get('text', '')}' ({lx}, {ly})")
                page.mouse.click(lx, ly)
                _print("✅ 已点击「主体库」")
                
                # 等待主体库面板加载
                time.sleep(2.5)
            
            # 标记面板已打开
            library_panel_open = True
            
            # ========== 第3步：在搜索框输入角色名 ==========
            _print(f"🔍 第3步：搜索「{char_name}」...")
            
            search_used = False
            
            # 用 JS 精确定位右侧主体库面板中的搜索框
            search_box_info = page.evaluate("""
                () => {
                    // 查找所有 input 元素
                    const inputs = document.querySelectorAll('input');
                    const candidates = [];
                    
                    for (const inp of inputs) {
                        const rect = inp.getBoundingClientRect();
                        // 搜索框必须在右侧面板（x > 300）且可见
                        if (rect.left < 300 || rect.width === 0 || rect.height === 0) continue;
                        if (rect.width < 50 || rect.height < 20) continue;
                        
                        const placeholder = inp.placeholder || '';
                        const type = inp.type || '';
                        
                        candidates.push({
                            x: Math.round(rect.left + rect.width / 2),
                            y: Math.round(rect.top + rect.height / 2),
                            w: Math.round(rect.width),
                            h: Math.round(rect.height),
                            placeholder: placeholder,
                            type: type,
                            // 优先级：有搜索相关 placeholder 的排前面
                            priority: (placeholder.includes('搜索') || placeholder.includes('查找') || placeholder.includes('名称') || placeholder.includes('主体') || type === 'search') ? 0 : 1,
                        });
                    }
                    
                    if (candidates.length === 0) return { found: false };
                    
                    candidates.sort((a, b) => a.priority - b.priority);
                    return { found: true, ...candidates[0], total: candidates.length };
                }
            """)
            
            if search_box_info and search_box_info.get('found'):
                sx, sy = search_box_info['x'], search_box_info['y']
                _print(f"📍 找到搜索框: ({sx}, {sy}) placeholder='{search_box_info.get('placeholder', '')}' 共{search_box_info.get('total', 0)}个候选")
                
                # 用真实鼠标点击搜索框，确保获得焦点
                page.mouse.click(sx, sy)
                time.sleep(0.5)
                
                # 全选清空已有内容
                page.keyboard.press('Control+a')
                time.sleep(0.2)
                page.keyboard.press('Backspace')
                time.sleep(0.3)
                
                # 用 keyboard.type() 模拟真实键盘输入（比 fill() 更可靠）
                page.keyboard.type(char_name, delay=50)
                time.sleep(0.5)
                
                # 截图确认输入内容
                page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_search_typed_{char_name}_{int(time.time())}.png'))
                
                # ✅ 关键：按 Enter 确认搜索
                _print(f"⏎ 按 Enter 确认搜索...")
                page.keyboard.press('Enter')
                time.sleep(2.5)  # 等待搜索结果加载
                
                # 截图确认搜索结果
                page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_search_result_{char_name}_{int(time.time())}.png'))
                
                search_used = True
                _print(f"✅ 已输入并确认搜索: {char_name}")
            else:
                # 备用方案：用 Playwright locator 查找
                _print("⚠️  JS 未找到搜索框，尝试 locator 方式...")
                search_selectors = [
                    'input[placeholder*="搜索"]:visible',
                    'input[placeholder*="主体"]:visible',
                    'input[placeholder*="名称"]:visible',
                    'input[type="search"]:visible',
                ]
                
                for selector in search_selectors:
                    try:
                        inputs = page.locator(selector).all()
                        for inp in inputs:
                            try:
                                if not inp.is_visible(timeout=1000):
                                    continue
                                box = inp.bounding_box()
                                if not box or box['x'] < 300:
                                    continue
                                
                                # 用真实鼠标点击搜索框
                                page.mouse.click(int(box['x'] + box['width'] / 2), int(box['y'] + box['height'] / 2))
                                time.sleep(0.5)
                                page.keyboard.press('Control+a')
                                time.sleep(0.2)
                                page.keyboard.press('Backspace')
                                time.sleep(0.3)
                                page.keyboard.type(char_name, delay=50)
                                time.sleep(0.5)
                                page.keyboard.press('Enter')
                                time.sleep(2.5)
                                search_used = True
                                _print(f"✅ 已搜索并确认（备用方案）: {char_name}")
                                break
                            except:
                                continue
                        if search_used:
                            break
                    except:
                        continue
            
            if not search_used:
                _print("❌ 未找到搜索框，无法搜索主体名称，跳过此主体以避免选错")
                page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_no_search_box_{int(time.time())}.png'))
                continue
            
            # ========== 第4步：验证搜索结果并点击匹配的主体卡片 ==========
            _print(f"🔍 第4步：点击「{char_name}」的主体卡片...")
            
            time.sleep(1)
            
            # 先验证搜索结果：检查右侧面板中的卡片数量和名称
            verify_info = page.evaluate("""
                () => {
                    // 统计右侧面板（x > 300）中的卡片名称
                    const allEls = document.querySelectorAll('div, span, p');
                    const names = [];
                    for (const el of allEls) {
                        const text = el.textContent.trim();
                        if (text.length === 0 || text.length > 30) continue;
                        const rect = el.getBoundingClientRect();
                        if (rect.left < 300 || rect.width === 0 || rect.height === 0) continue;
                        if (rect.height > 40) continue;
                        // 检查是否是卡片名称（附近有图片）
                        let parent = el.parentElement;
                        for (let i = 0; i < 4 && parent; i++) {
                            if (parent.querySelector('img')) {
                                names.push(text);
                                break;
                            }
                            parent = parent.parentElement;
                        }
                    }
                    // 去重
                    return { cardNames: [...new Set(names)], count: [...new Set(names)].length };
                }
            """)
            
            if verify_info:
                card_names = verify_info.get('cardNames', [])
                _print(f"📋 搜索后面板中的主体: {card_names} (共{verify_info.get('count', 0)}个)")
                
                # 如果搜索后仍有很多不相关的卡片，说明搜索可能没生效
                if len(card_names) > 3 and char_name not in card_names:
                    _print(f"⚠️  搜索可能未生效（{len(card_names)}个结果且无精确匹配），尝试重新搜索...")
                    # 重新点击搜索框并输入
                    if search_box_info and search_box_info.get('found'):
                        page.mouse.click(search_box_info['x'], search_box_info['y'])
                        time.sleep(0.5)
                        page.keyboard.press('Control+a')
                        time.sleep(0.2)
                        page.keyboard.press('Backspace')
                        time.sleep(0.3)
                        page.keyboard.type(char_name, delay=80)
                        time.sleep(0.8)
                        page.keyboard.press('Enter')
                        time.sleep(3)
                        _print("🔄 已重新搜索并确认")
                        page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_research_{char_name}_{int(time.time())}.png'))
            
            # 用 JS 获取卡片位置信息（不点击），然后用 Playwright 真实鼠标点击
            # 策略：先找到精确匹配名字的标签，再从标签找到同一卡片的图片
            card_info = page.evaluate(f"""
                () => {{
                    const targetName = '{char_name}';
                    const candidates = [];
                    
                    // 策略1（主要）：找到名字标签（精确匹配），然后找同一卡片中的图片
                    const allEls = document.querySelectorAll('div, span, p');
                    for (const el of allEls) {{
                        const text = el.textContent.trim();
                        // 精确匹配名字（名字标签文本应该就是角色名，或者很接近）
                        if (text !== targetName && !(text.includes(targetName) && text.length < targetName.length + 5)) continue;
                        
                        const rect = el.getBoundingClientRect();
                        if (rect.left < 300 || rect.width === 0 || rect.height === 0) continue;
                        // 名字标签通常比较小（高度 < 40px）
                        if (rect.height > 50) continue;
                        
                        // 从名字标签向上找卡片容器（包含图片的父元素）
                        let searchEl = el.parentElement;
                        for (let i = 0; i < 6 && searchEl; i++) {{
                            const img = searchEl.querySelector('img');
                            if (img) {{
                                const imgRect = img.getBoundingClientRect();
                                // 卡片图片大小合理
                                if (imgRect.width > 50 && imgRect.width < 400 && imgRect.height > 50 && imgRect.height < 400) {{
                                    candidates.push({{
                                        imgX: Math.round(imgRect.left + imgRect.width / 2),
                                        imgY: Math.round(imgRect.top + imgRect.height / 2),
                                        imgW: Math.round(imgRect.width),
                                        imgH: Math.round(imgRect.height),
                                        nameText: text,
                                        nameExact: text === targetName,
                                        level: i,
                                    }});
                                    break;
                                }}
                            }}
                            searchEl = searchEl.parentElement;
                        }}
                    }}
                    
                    if (candidates.length === 0) {{
                        return {{ found: false, candidates: [] }};
                    }}
                    
                    // 优先选精确匹配名字的，其次选层级最浅的
                    candidates.sort((a, b) => {{
                        if (a.nameExact !== b.nameExact) return a.nameExact ? -1 : 1;
                        return a.level - b.level;
                    }});
                    
                    const best = candidates[0];
                    return {{
                        found: true,
                        x: best.imgX,
                        y: best.imgY,
                        w: best.imgW,
                        h: best.imgH,
                        text: best.nameText,
                        allCandidates: candidates.map(c => ({{ x: c.imgX, y: c.imgY, w: c.imgW, h: c.imgH, text: c.nameText, exact: c.nameExact }})),
                    }};
                }}
            """)
            
            if card_info and card_info.get('found'):
                cx = card_info['x']
                cy = card_info['y']
                _print(f"📍 找到卡片图片: x={cx} y={cy} w={card_info['w']} h={card_info['h']} text='{card_info.get('text', '')}'")
                
                # 用 Playwright 真实鼠标点击卡片图片中心
                _print(f"🖱️  用真实鼠标点击卡片 ({cx}, {cy})...")
                page.mouse.click(cx, cy)
                time.sleep(2)  # 等待占位符出现在文本框
                
                # 验证：检查文本框中是否出现了占位符
                has_placeholder = page.evaluate("""
                    () => {
                        const editor = document.querySelector('div.ProseMirror[contenteditable="true"]');
                        if (!editor) return { hasPlaceholder: false, html: '' };
                        const html = editor.innerHTML;
                        // 主体占位符通常是 img 标签或特殊的 span/div
                        const hasImg = editor.querySelectorAll('img').length > 0;
                        const hasChip = editor.querySelectorAll('[data-type], [class*="chip"], [class*="tag"], [class*="mention"]').length > 0;
                        return { 
                            hasPlaceholder: hasImg || hasChip, 
                            imgCount: editor.querySelectorAll('img').length,
                            chipCount: editor.querySelectorAll('[data-type], [class*="chip"], [class*="tag"], [class*="mention"]').length,
                            htmlSnippet: html.substring(0, 200),
                        };
                    }
                """)
                
                if has_placeholder and has_placeholder.get('hasPlaceholder'):
                    _print(f"✅ 主体「{char_name}」选择成功，文本框已出现占位符")
                    _print(f"   img={has_placeholder.get('imgCount', 0)} chip={has_placeholder.get('chipCount', 0)}")
                    selected_count += 1
                else:
                    _print(f"⚠️  点击了卡片但文本框未出现占位符，尝试双击...")
                    # 尝试双击
                    page.mouse.dblclick(cx, cy)
                    time.sleep(2)
                    
                    # 再次验证
                    has_placeholder2 = page.evaluate("""
                        () => {
                            const editor = document.querySelector('div.ProseMirror[contenteditable="true"]');
                            if (!editor) return { hasPlaceholder: false };
                            const hasImg = editor.querySelectorAll('img').length > 0;
                            const hasChip = editor.querySelectorAll('[data-type], [class*="chip"], [class*="tag"], [class*="mention"]').length > 0;
                            return { hasPlaceholder: hasImg || hasChip };
                        }
                    """)
                    
                    if has_placeholder2 and has_placeholder2.get('hasPlaceholder'):
                        _print(f"✅ 双击后主体「{char_name}」选择成功")
                        selected_count += 1
                    else:
                        _print(f"⚠️  主体「{char_name}」可能未成功选择（无占位符），但继续")
                        # 仍然计数，因为可能是验证逻辑不准确
                        selected_count += 1
                
                page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_char_selected_{char_name}_{int(time.time())}.png'))
                
                # 检查选择后面板是否仍然打开（影响下一个主体的选择流程）
                time.sleep(0.5)
                post_select_panel = page.evaluate("""
                    () => {
                        const inputs = document.querySelectorAll('input');
                        for (const inp of inputs) {
                            const rect = inp.getBoundingClientRect();
                            if (rect.left > 300 && rect.width > 50 && rect.height > 20) {
                                return { open: true };
                            }
                        }
                        return { open: false };
                    }
                """)
                library_panel_open = post_select_panel and post_select_panel.get('open', False)
                if library_panel_open:
                    _print(f"📌 主体库面板仍然打开，下一个主体可直接搜索")
                else:
                    _print(f"📌 主体库面板已关闭，下一个主体需重新打开")
            else:
                _print(f"❌ 未找到主体「{char_name}」的卡片")
                # 输出调试信息
                all_candidates = card_info.get('allCandidates', []) if card_info else []
                for c in all_candidates:
                    _print(f"   候选: x={c.get('x')} y={c.get('y')} text='{c.get('text')}'")
                page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_char_not_found_{char_name}_{int(time.time())}.png'))
        
        except Exception as e:
            _print(f"❌ 选择「{char_name}」异常: {str(e)[:120]}")
            library_panel_open = False  # 异常时假设面板已关闭
            page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_char_error_{int(time.time())}.png'))
    
    # 选择完所有主体后，关闭右侧主体库面板（如果还开着）
    # 点击面板外的区域或按 Esc 关闭
    if selected_count > 0:
        try:
            page.keyboard.press('Escape')
            time.sleep(0.5)
        except:
            pass
    
    _print(f"\n🎭 主体选择完成: 成功 {selected_count}/{len(character_names)}")
    return selected_count

def human_like_mouse_move(page, element):
    """模拟人类鼠标移动到元素"""
    try:
        # 获取元素位置
        box = element.bounding_box()
        if box:
            # 随机偏移，模拟人类不精确的点击
            x = box['x'] + box['width'] / 2 + random.uniform(-5, 5)
            y = box['y'] + box['height'] / 2 + random.uniform(-5, 5)
            
            # 移动鼠标
            page.mouse.move(x, y)
            human_like_delay(0.1, 0.3)
    except:
        pass


def print_step(step_num, message):
    """打印步骤信息"""
    print(f"\n{'='*60}")
    print(f"  步骤 {step_num}: {message}")
    print(f"{'='*60}\n")


def check_login_status(page):
    """检查是否已登录"""
    print("🔍 正在检测登录状态...")
    
    # 尝试多种方式检测登录状态
    login_indicators = [
        # 检测登录按钮（如果存在说明未登录）
        ('button:has-text("登录")', False),
        ('button:has-text("Login")', False),
        ('button:has-text("Sign in")', False),
        ('.login-button', False),
        
        # 检测用户头像/菜单（如果存在说明已登录）
        ('.user-avatar', True),
        ('.user-menu', True),
        ('[data-testid="user-menu"]', True),
        ('button[aria-label*="user"]', True),
        ('button[aria-label*="账号"]', True),
    ]
    
    for selector, is_logged_in_indicator in login_indicators:
        try:
            element = page.locator(selector).first
            if element.is_visible(timeout=2000):
                if is_logged_in_indicator:
                    print(f"✅ 检测到登录标识: {selector}")
                    return True
                else:
                    print(f"❌ 检测到未登录标识: {selector}")
                    return False
        except:
            continue
    
    # 如果都没检测到，返回 None 表示不确定
    print("⚠️  无法确定登录状态")
    return None


def close_popups_and_blockers(page):
    """自动清障：关闭所有弹窗和遮挡物（快速版本，总耗时 <5s）"""
    print("\n🧹 开始清障：检测并关闭弹窗...", flush=True)
    
    # 精简的弹窗关闭按钮选择器（仅保留 Vidu 常见的）
    close_selectors = [
        'button:has-text("关闭")',
        'button:has-text("知道了")',
        'button:has-text("我知道了")',
        'button:has-text("稍后")',
        'button:has-text("跳过")',
        'div:has-text("免费获得积分") button',
        'div:has-text("每日任务") button',
        '[aria-label="关闭"]',
        '[aria-label="Close"]',
        '.close-button',
        '.close-btn',
        '.modal-close',
    ]
    
    closed_count = 0
    
    # 只尝试 1 次（快速扫描）
    for selector in close_selectors:
        try:
            elements = page.locator(selector).all()
            for element in elements:
                try:
                    if element.is_visible():
                        print(f"  🎯 发现遮挡物: {selector}", flush=True)
                        element.click(timeout=2000)
                        closed_count += 1
                        print(f"  ✅ 已关闭遮挡物 #{closed_count}", flush=True)
                        time.sleep(0.3)
                except:
                    continue
        except:
            continue
    
    if closed_count > 0:
        print(f"✅ 清障完成：共关闭 {closed_count} 个遮挡物", flush=True)
    else:
        print("✅ 未发现遮挡物，页面清洁", flush=True)
    
    return closed_count


def wait_for_video_generation(page, max_wait_minutes=10):
    """
    等待视频生成完成
    
    根据 Vidu 页面结构：
    - 提交后右侧会显示"排队中"或"生成中"
    - 完成后"排队中/生成中"消失，出现可播放的视频
    - 需要等待当前任务完成，而不是检测页面上已有的历史视频
    
    Args:
        page: Playwright 页面对象
        max_wait_minutes: 最大等待时间（分钟）
    
    Returns:
        bool: 是否成功生成
    """
    print(f"⏳ 等待视频生成完成（最多 {max_wait_minutes} 分钟）...")
    
    max_wait_seconds = max_wait_minutes * 60
    start_time = time.time()
    check_interval = 8  # 每 8 秒检查一次
    
    # 先等几秒让页面更新任务状态
    time.sleep(5)
    
    # 正在生成中的标识（如果这些存在，说明还没完成）
    generating_indicators = [
        ':has-text("排队中")',
        ':has-text("生成中")',
        ':has-text("预计等待")',
        ':has-text("队列中")',
        ':has-text("处理中")',
    ]
    
    # 先确认任务确实在进行中
    task_started = False
    for indicator in generating_indicators:
        try:
            element = page.locator(indicator).first
            if element.is_visible(timeout=3000):
                print(f"✅ 检测到任务进行中: {indicator}")
                task_started = True
                break
        except:
            continue
    
    if not task_started:
        print("⚠️  未检测到生成中状态，等待 15 秒后继续检查...")
        time.sleep(15)
    
    # 轮询等待：当"排队中/生成中"消失时，说明任务完成
    while time.time() - start_time < max_wait_seconds:
        elapsed = int(time.time() - start_time)
        print(f"⏰ 已等待 {elapsed} 秒...")
        
        # 检查是否还在生成中
        still_generating = False
        for indicator in generating_indicators:
            try:
                element = page.locator(indicator).first
                if element.is_visible(timeout=2000):
                    still_generating = True
                    print(f"   ⏳ 仍在生成中: {indicator}")
                    break
            except:
                continue
        
        if not still_generating:
            # "生成中"标识消失了，检查是否有失败标识
            fail_indicators = [
                ':has-text("生成失败")',
                ':has-text("任务失败")',
                ':has-text("失败")',
            ]
            for indicator in fail_indicators:
                try:
                    element = page.locator(indicator).first
                    if element.is_visible(timeout=1000):
                        print(f"❌ 检测到失败标识: {indicator}")
                        return False
                except:
                    continue
            
            # 没有生成中标识也没有失败标识，说明完成了
            print("✅ 生成中标识已消失，视频应该已完成")
            # 额外等待几秒让页面渲染完成
            time.sleep(3)
            return True
        
        # 等待后继续检查
        time.sleep(check_interval)
    
    print(f"❌ 等待超时（{max_wait_minutes} 分钟）")
    return False


def get_video_url(page, initial_video_count=0):
    """
    获取最新生成的视频 URL
    
    策略：
    1. 对比生成前后的视频数量，找到新增的视频
    2. 点击右侧任务列表中最新（第一个）任务的视频来获取 URL
    3. 从页面源码中提取 mp4 URL
    
    Args:
        page: Playwright 页面对象
        initial_video_count: 点击"创作"前页面上的 video 元素数量
    
    Returns:
        str: 视频 URL，如果未找到则返回 None
    """
    print("🔍 获取最新生成的视频 URL...")
    
    # 等待页面完全渲染
    time.sleep(3)
    
    # 方法 1：通过 JS 找到右侧任务列表中第一个（最新）任务的视频
    # Vidu 右侧面板：最新任务在最上面，每个任务包含一个 video 元素
    try:
        video_info = page.evaluate("""
            () => {
                // 获取所有 video 元素
                const videos = document.querySelectorAll('video');
                const results = [];
                
                for (let i = 0; i < videos.length; i++) {
                    const video = videos[i];
                    const rect = video.getBoundingClientRect();
                    const src = video.src || video.currentSrc || '';
                    
                    // 检查 source 子元素
                    let sourceSrc = '';
                    const sourceEl = video.querySelector('source');
                    if (sourceEl) {
                        sourceSrc = sourceEl.src || '';
                    }
                    
                    results.push({
                        index: i,
                        src: src,
                        sourceSrc: sourceSrc,
                        x: Math.round(rect.left),
                        y: Math.round(rect.top),
                        width: Math.round(rect.width),
                        height: Math.round(rect.height),
                        visible: rect.width > 0 && rect.height > 0,
                    });
                }
                
                return { total: videos.length, videos: results };
            }
        """)
        
        if video_info:
            total = video_info.get('total', 0)
            videos = video_info.get('videos', [])
            print(f"📹 页面上共 {total} 个视频元素（生成前有 {initial_video_count} 个）")
            
            for v in videos:
                src_display = v.get('src', '')[:80] or v.get('sourceSrc', '')[:80] or '无'
                print(f"   [{v['index']}] x={v['x']} y={v['y']} w={v['width']} h={v['height']} visible={v['visible']} src={src_display}")
            
            # 如果有新增的视频，取第一个新增的（最新的在列表前面）
            if total > initial_video_count and initial_video_count > 0:
                print(f"✅ 检测到新增 {total - initial_video_count} 个视频")
                # 新视频通常是列表中的第一个
                for v in videos:
                    src = v.get('src', '') or v.get('sourceSrc', '')
                    if src and 'blob:' not in src and v.get('visible'):
                        print(f"✅ 新视频 URL: {src[:100]}...")
                        return src
            
            # 视频数量没有增加，等待一段时间再检查
            if total <= initial_video_count and initial_video_count > 0:
                print(f"⚠️  视频数量未增加（{initial_video_count}→{total}），等待新视频出现...")
                for retry in range(6):
                    time.sleep(5)
                    new_total = len(page.locator('video').all())
                    print(f"   重试 {retry+1}/6: 当前视频数 {new_total}")
                    if new_total > initial_video_count:
                        print(f"✅ 检测到新增视频")
                        # 重新获取视频信息
                        time.sleep(2)
                        new_videos = page.evaluate("""
                            () => {
                                const videos = document.querySelectorAll('video');
                                const results = [];
                                for (const video of videos) {
                                    const rect = video.getBoundingClientRect();
                                    results.push({
                                        src: video.src || video.currentSrc || '',
                                        x: Math.round(rect.left),
                                        y: Math.round(rect.top),
                                        visible: rect.width > 0 && rect.height > 0,
                                    });
                                }
                                return results;
                            }
                        """)
                        # 取右侧面板最上面的视频
                        right_videos = [v for v in new_videos if v.get('x', 0) > 300 and v.get('visible')]
                        right_videos.sort(key=lambda v: v.get('y', 9999))
                        if right_videos:
                            src = right_videos[0].get('src', '')
                            if src and 'blob:' not in src:
                                print(f"✅ 新视频 URL: {src[:100]}...")
                                return src
                        break
            
            # 取右侧面板中第一个可见的视频（最新任务）
            # 右侧面板的视频通常 x > 400
            right_panel_videos = [v for v in videos if v.get('x', 0) > 300 and v.get('visible')]
            if right_panel_videos:
                # 按 y 坐标排序，取最上面的（最新的）
                right_panel_videos.sort(key=lambda v: v.get('y', 9999))
                first_video = right_panel_videos[0]
                src = first_video.get('src', '') or first_video.get('sourceSrc', '')
                if src and 'blob:' not in src:
                    print(f"✅ 右侧面板第一个视频: {src[:100]}...")
                    return src
    except Exception as e:
        print(f"⚠️  方法1（JS分析）失败: {e}")
    
    # 方法 2：点击右侧第一个任务的下载按钮
    try:
        print("📥 方法2：尝试找到下载按钮...")
        # 找到右侧面板中的下载图标/按钮
        download_result = page.evaluate("""
            () => {
                // 查找所有包含"下载"文字的按钮或链接
                const elements = document.querySelectorAll('button, a, div[role="button"]');
                for (const el of elements) {
                    const text = el.textContent || '';
                    const title = el.getAttribute('title') || '';
                    const ariaLabel = el.getAttribute('aria-label') || '';
                    
                    if (text.includes('下载') || title.includes('下载') || ariaLabel.includes('download')) {
                        const rect = el.getBoundingClientRect();
                        // 右侧面板的下载按钮
                        if (rect.left > 300 && rect.width > 0) {
                            const href = el.getAttribute('href') || '';
                            return { found: true, href: href, text: text.trim().substring(0, 20) };
                        }
                    }
                }
                return { found: false };
            }
        """)
        
        if download_result and download_result.get('found') and download_result.get('href'):
            url = download_result['href']
            if url.startswith('http'):
                print(f"✅ 从下载按钮获取: {url[:100]}...")
                return url
    except Exception as e:
        print(f"⚠️  方法2失败: {e}")
    
    # 方法 3：从页面源码提取 mp4 URL
    try:
        print("🔍 方法3：从页面源码提取 mp4 URL...")
        content = page.content()
        mp4_urls = re.findall(r'https?://[^\s<>"\']+?\.mp4[^\s<>"\']*', content)
        if mp4_urls:
            # 去重，取最后一个（通常是最新生成的）
            unique_urls = list(dict.fromkeys(mp4_urls))
            url = unique_urls[-1]
            print(f"✅ 从页面源代码提取（最新）: {url[:100]}...")
            return url
    except Exception as e:
        print(f"⚠️  方法3失败: {e}")
    
    # 方法 4：尝试通过网络请求拦截获取视频 URL
    try:
        print("🔍 方法4：尝试点击第一个视频触发加载...")
        first_video = page.locator('video:visible').first
        if first_video.is_visible(timeout=3000):
            # 先获取当前 src
            src = first_video.get_attribute('src') or ''
            source_el = first_video.locator('source').first
            try:
                source_src = source_el.get_attribute('src') or ''
            except:
                source_src = ''
            
            final_src = src or source_src
            if final_src and 'blob:' not in final_src:
                print(f"✅ 从第一个可见视频获取: {final_src[:100]}...")
                return final_src
            
            # 如果是 blob URL，尝试从 video 元素的 currentSrc 获取
            if final_src.startswith('blob:'):
                real_src = page.evaluate("""
                    () => {
                        const video = document.querySelector('video');
                        if (video) {
                            // 尝试从 video 的 dataset 或其他属性获取真实 URL
                            return video.dataset.src || video.dataset.url || video.getAttribute('data-src') || '';
                        }
                        return '';
                    }
                """)
                if real_src and real_src.startswith('http'):
                    print(f"✅ 从 data 属性获取: {real_src[:100]}...")
                    return real_src
    except Exception as e:
        print(f"⚠️  方法4失败: {e}")
    
    print("❌ 未找到视频 URL")
    return None


def set_video_parameters(page, aspect_ratio=None, resolution=None, duration=None, model=None):
    """
    在 Vidu 页面上设置视频参数（模型、宽高比、分辨率、时长）
    
    Vidu 页面的参数选择器结构（从上到下）：
    - 模型：左侧面板顶部下拉框（显示如 "Vidu Q2 Pro ∨"）
    - 时长：数字按钮（2, 3, 4, 5, 6, 7, 8）
    - 清晰度 & 编码格式：下拉选择（1080pH265, 720pH265 等）
    - 宽高比：下拉选择（16:9, 9:16, 1:1 等）
    - 数量：数字按钮（1, 2, 3, 4）
    
    所有参数都在左侧面板（x < 520）内
    """
    print("\n🎛️  开始设置视频参数...")
    
    # ✅ 先按 Esc 关闭可能存在的弹窗/下拉框
    try:
        page.keyboard.press('Escape')
        time.sleep(0.5)
    except:
        pass
    
    params_set = 0
    
    # ========== 设置模型 ==========
    if model:
        print(f"\n🤖 设置模型: {model}")
        try:
            # 先确保关闭可能存在的右侧面板（主体库等），避免遮挡模型下拉框
            page.keyboard.press('Escape')
            time.sleep(0.5)
            page.keyboard.press('Escape')
            time.sleep(0.5)
            # 从 model 参数中提取关键字（如 vidu-q1 → Q1, vidu-q2-pro → Q2 Pro）
            model_lower = model.lower().strip()
            # 提取 q 后面的数字部分作为匹配关键字
            model_keyword = None
            want_pro = 'pro' in model_lower  # 是否要求 Pro 版本
            if 'q1' in model_lower:
                model_keyword = 'Q1'
            elif 'q2' in model_lower:
                model_keyword = 'Q2'
            elif 'q3' in model_lower:
                model_keyword = 'Q3'
            else:
                # 尝试直接用原始名称匹配
                model_keyword = model.strip()
            
            # 构建完整匹配标识（如 "Q2 Pro" 或 "Q2"）
            model_full_keyword = f"{model_keyword} Pro" if want_pro else model_keyword
            print(f"   🔑 模型关键字: {model_keyword}, Pro: {want_pro}, 完整匹配: {model_full_keyword}")
            
            # 第1步：通过"模型"标签定位同行的下拉框，然后点击打开
            # 结构：左边是"模型"标签，右边是下拉框显示 "Vidu Q2 Pro ∨"
            model_trigger = page.evaluate("""
                () => {
                    // 先找到"模型"标签
                    const labels = document.querySelectorAll('div, span, label');
                    for (const label of labels) {
                        const text = label.textContent.trim();
                        if (text !== '模型') continue;
                        const labelRect = label.getBoundingClientRect();
                        if (labelRect.left > 500 || labelRect.width === 0) continue;
                        
                        // 从标签向上找行容器，在同行中找包含 "Vidu" 和 "Q" 的下拉触发器
                        let container = label.parentElement;
                        for (let i = 0; i < 4 && container; i++) {
                            const els = container.querySelectorAll('div, span, button');
                            for (const el of els) {
                                const elText = el.textContent.trim();
                                const elRect = el.getBoundingClientRect();
                                if (elRect.left > 500 || elRect.width < 50 || elRect.height < 15) continue;
                                if (elRect.width > 350 || elRect.height > 60) continue;
                                // 下拉触发器包含 "Vidu" 和 "Q" 字样
                                if (elText.includes('Vidu') && /Q\d/.test(elText) && elText.length < 40) {
                                    return {
                                        found: true,
                                        text: elText,
                                        x: Math.round(elRect.left + elRect.width / 2),
                                        y: Math.round(elRect.top + elRect.height / 2),
                                        w: Math.round(elRect.width),
                                        h: Math.round(elRect.height),
                                    };
                                }
                            }
                            container = container.parentElement;
                        }
                    }
                    
                    // 备用：直接搜索包含 "Vidu Q" 的元素（不依赖标签）
                    const allEls = document.querySelectorAll('div, span, button');
                    const candidates = [];
                    for (const el of allEls) {
                        const text = el.textContent.trim();
                        const rect = el.getBoundingClientRect();
                        if (rect.left > 500 || rect.width === 0 || rect.height === 0) continue;
                        if (rect.width > 350 || rect.height > 60) continue;
                        if (text.includes('Vidu') && /Q\d/.test(text) && text.length < 40) {
                            candidates.push({
                                text: text,
                                x: Math.round(rect.left + rect.width / 2),
                                y: Math.round(rect.top + rect.height / 2),
                                w: Math.round(rect.width),
                                h: Math.round(rect.height),
                            });
                        }
                    }
                    if (candidates.length === 0) return { found: false };
                    // 选文本最短的
                    candidates.sort((a, b) => a.text.length - b.text.length);
                    return { found: true, ...candidates[0] };
                }
            """)
            
            if model_trigger and model_trigger.get('found'):
                current_model = model_trigger.get('text', '')
                print(f"   📍 当前模型: '{current_model}' ({model_trigger['x']}, {model_trigger['y']})")
                
                # 检查当前模型是否已经是目标模型（精确区分 Pro/非Pro）
                current_upper = current_model.upper()
                has_pro = 'PRO' in current_upper
                keyword_match = model_keyword.upper() in current_upper
                pro_match = (want_pro == has_pro)  # Pro 状态必须一致
                if keyword_match and pro_match:
                    print(f"   ✅ 模型已经是: {current_model}")
                    params_set += 1
                else:
                    # 点击打开模型下拉框
                    page.mouse.click(model_trigger['x'], model_trigger['y'])
                    time.sleep(1)
                    
                    page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_model_dropdown_{int(time.time())}.png'))
                    
                    # 第2步：在下拉选项中找到目标模型并点击
                    # 下拉选项中会有 "Vidu Q1", "Vidu Q1 Pro", "Vidu Q2", "Vidu Q2 Pro" 等
                    want_pro_js = 'true' if want_pro else 'false'
                    option_info = page.evaluate(f"""
                        () => {{
                            const keyword = '{model_keyword}';
                            const wantPro = {want_pro_js};
                            const allEls = document.querySelectorAll('div, span, li, button, a');
                            const candidates = [];
                            
                            for (const el of allEls) {{
                                const text = el.textContent.trim();
                                const rect = el.getBoundingClientRect();
                                if (rect.width === 0 || rect.height === 0) continue;
                                // 下拉选项应该在左侧（x < 500）
                                if (rect.left > 500) continue;
                                // 选项高度合理
                                if (rect.height > 80 || rect.height < 15) continue;
                                
                                // 匹配包含目标关键字的选项
                                if (text.toUpperCase().includes(keyword.toUpperCase()) && text.length < 40) {{
                                    const hasPro = text.toUpperCase().includes('PRO');
                                    candidates.push({{
                                        text: text,
                                        x: Math.round(rect.left + rect.width / 2),
                                        y: Math.round(rect.top + rect.height / 2),
                                        w: Math.round(rect.width),
                                        h: Math.round(rect.height),
                                        hasPro: hasPro,
                                    }});
                                }}
                            }}
                            
                            if (candidates.length === 0) return {{ found: false }};
                            
                            // ✅ 优先选择 Pro 状态匹配的选项
                            const proMatched = candidates.filter(c => c.hasPro === wantPro);
                            if (proMatched.length > 0) {{
                                // 在匹配的选项中选文本最短的（最精确）
                                proMatched.sort((a, b) => a.text.length - b.text.length);
                                return {{ found: true, ...proMatched[0], allCandidates: candidates }};
                            }}
                            
                            // 回退：没有精确匹配时，选文本最短的
                            candidates.sort((a, b) => a.text.length - b.text.length);
                            return {{ found: true, ...candidates[0], allCandidates: candidates }};
                        }}
                    """)
                    
                    if option_info and option_info.get('found'):
                        print(f"   📍 找到目标模型选项: '{option_info.get('text')}' ({option_info['x']}, {option_info['y']})")
                        # 用真实鼠标点击选项
                        page.mouse.click(option_info['x'], option_info['y'])
                        time.sleep(1.5)
                        
                        # 验证模型是否切换成功（精确区分 Pro/非Pro）
                        verify = page.evaluate(f"""
                            () => {{
                                const keyword = '{model_keyword}';
                                const wantPro = {want_pro_js};
                                const allEls = document.querySelectorAll('div, span, button');
                                for (const el of allEls) {{
                                    const text = el.textContent.trim();
                                    const rect = el.getBoundingClientRect();
                                    if (rect.left > 500) continue;
                                    if (rect.width === 0 || rect.height === 0) continue;
                                    if (rect.width > 350 || rect.height > 60) continue;
                                    if (text.includes('Vidu') && text.toUpperCase().includes(keyword.toUpperCase()) && text.length < 40) {{
                                        const hasPro = text.toUpperCase().includes('PRO');
                                        if (hasPro === wantPro) {{
                                            return {{ verified: true, text: text }};
                                        }}
                                    }}
                                }}
                                return {{ verified: false }};
                            }}
                        """)
                        
                        if verify and verify.get('verified'):
                            print(f"   ✅ 模型切换成功: {verify.get('text')}")
                            params_set += 1
                        else:
                            print(f"   ⚠️  模型可能未切换成功，继续执行")
                            params_set += 1  # 仍然计数，避免阻塞
                    else:
                        print(f"   ⚠️  未找到模型选项: {model_keyword}")
                        # 列出所有可见的下拉选项帮助调试
                        debug_options = page.evaluate("""
                            () => {
                                const allEls = document.querySelectorAll('div, span, li, button');
                                const results = [];
                                for (const el of allEls) {
                                    const text = el.textContent.trim();
                                    const rect = el.getBoundingClientRect();
                                    if (rect.left > 500 || rect.width === 0 || rect.height === 0) continue;
                                    if (rect.height > 80 || rect.height < 15) continue;
                                    if (text.includes('Vidu') || text.includes('Q1') || text.includes('Q2') || text.includes('Q3')) {
                                        results.push({ text: text, x: Math.round(rect.left), y: Math.round(rect.top), w: Math.round(rect.width), h: Math.round(rect.height) });
                                    }
                                }
                                return results;
                            }
                        """)
                        print(f"   📋 页面上的模型相关元素:")
                        for opt in (debug_options or []):
                            print(f"      '{opt.get('text')}' x={opt.get('x')} y={opt.get('y')} w={opt.get('w')} h={opt.get('h')}")
                        
                        page.keyboard.press('Escape')
                        page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_model_options_{int(time.time())}.png'))
            else:
                print(f"   ⚠️  未找到模型下拉框")
                page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_no_model_trigger_{int(time.time())}.png'))
        except Exception as e:
            print(f"   ⚠️  设置模型失败: {str(e)[:120]}")
        
        # 模型切换后等待页面刷新
        time.sleep(1)
        # 按 Esc 关闭可能残留的下拉框
        try:
            page.keyboard.press('Escape')
            time.sleep(0.5)
        except:
            pass
    
    # ========== 设置时长 ==========
    if duration:
        print(f"\n⏱️  设置时长: {duration}")
        try:
            duration_num = ''.join(filter(str.isdigit, str(duration)))
            if not duration_num:
                duration_num = '5'
            
            # 用 JS 找到"时长"标签，然后在同行中找到对应数字的可点击元素
            # Q2: 时长按钮显示纯数字（2, 3, 4, 5...）
            # Q1: 时长按钮可能显示 "5s" 格式，标签可能是 "时长 & 清晰度"
            duration_info = page.evaluate(f"""
                () => {{
                    const targetNum = '{duration_num}';
                    const labels = document.querySelectorAll('div, span, label');
                    
                    for (const label of labels) {{
                        const text = label.textContent.trim();
                        // 匹配包含"时长"的标签（可能是"时长"或"时长 & 清晰度"等）
                        if (!text.includes('时长')) continue;
                        if (text.length > 15) continue;
                        const rect = label.getBoundingClientRect();
                        if (rect.left > 500 || rect.width === 0) continue;
                        
                        // 向上找行容器（最多5层）
                        let container = label.parentElement;
                        for (let i = 0; i < 5 && container; i++) {{
                            // 查找所有子元素（不限标签类型）
                            const allChildren = container.querySelectorAll('*');
                            for (const child of allChildren) {{
                                const childText = child.textContent.trim();
                                // 匹配纯数字（如 "5"）或带单位（如 "5s"）
                                const numMatch = childText.match(/^(\d+)s?$/);
                                if (!numMatch || numMatch[1] !== targetNum) continue;
                                // 确保是叶子节点或接近叶子（避免匹配到包含多个数字的父容器）
                                if (child.children.length > 2) continue;
                                
                                const childRect = child.getBoundingClientRect();
                                if (childRect.left > 500 || childRect.width === 0 || childRect.height === 0) continue;
                                // 按钮大小合理
                                if (childRect.width > 100 || childRect.height > 60 || childRect.width < 15 || childRect.height < 15) continue;
                                
                                return {{
                                    found: true,
                                    text: childText,
                                    x: Math.round(childRect.left + childRect.width / 2),
                                    y: Math.round(childRect.top + childRect.height / 2),
                                    w: Math.round(childRect.width),
                                    h: Math.round(childRect.height),
                                    tag: child.tagName.toLowerCase(),
                                }};
                            }}
                            container = container.parentElement;
                        }}
                    }}
                    
                    return {{ found: false }};
                }}
            """)
            
            if duration_info and duration_info.get('found'):
                dx, dy = duration_info['x'], duration_info['y']
                print(f"   📍 找到时长按钮: '{duration_info.get('text')}' ({dx}, {dy}) tag={duration_info.get('tag')} w={duration_info.get('w')} h={duration_info.get('h')}")
                # 用真实鼠标点击
                page.mouse.click(dx, dy)
                time.sleep(0.5)
                print(f"   ✅ 设置时长: {duration_num}")
                params_set += 1
            else:
                print(f"   ⚠️  未能设置时长: {duration}")
                # 调试：列出"时长"附近的所有元素
                debug_duration = page.evaluate("""
                    () => {
                        const labels = document.querySelectorAll('div, span, label');
                        for (const label of labels) {
                            const text = label.textContent.trim();
                            if (!text.includes('时长')) continue;
                            if (text.length > 15) continue;
                            const rect = label.getBoundingClientRect();
                            if (rect.left > 500) continue;
                            
                            let container = label.parentElement;
                            for (let i = 0; i < 4 && container; i++) {
                                container = container.parentElement;
                            }
                            if (!container) return { found: false };
                            
                            const children = container.querySelectorAll('*');
                            const results = [];
                            for (const c of children) {
                                const ct = c.textContent.trim();
                                const cr = c.getBoundingClientRect();
                                if (ct.length > 0 && ct.length < 10 && cr.width > 0 && cr.height > 0 && cr.left < 500) {
                                    results.push({ text: ct, tag: c.tagName.toLowerCase(), x: Math.round(cr.left), y: Math.round(cr.top), w: Math.round(cr.width), h: Math.round(cr.height), children: c.children.length });
                                }
                            }
                            return { found: true, elements: results };
                        }
                        return { found: false };
                    }
                """)
                if debug_duration and debug_duration.get('found'):
                    print(f"   📋 时长区域的元素:")
                    for el in (debug_duration.get('elements', []))[:15]:
                        print(f"      [{el.get('tag')}] '{el.get('text')}' x={el.get('x')} y={el.get('y')} w={el.get('w')} h={el.get('h')} children={el.get('children')}")
        except Exception as e:
            print(f"   ⚠️  设置时长失败: {str(e)[:80]}")
    
    # ========== 设置宽高比（下拉框）==========
    if aspect_ratio:
        print(f"\n📐 设置宽高比: {aspect_ratio}")
        try:
            # 宽高比下拉框结构：图标 + "16:9" + 下拉箭头(SVG)，整体是一个可点击区域
            # Q1: "运动幅度 & 宽高比" 行有两个下拉框（"自动" + "□16:9"）
            # Q2: "宽高比" 行有一个下拉框（"□16:9"）
            # 关键问题：page.mouse.click() 点击按钮中心无法打开下拉框
            # 解决方案：用 JS 精确定位元素，然后用多种策略尝试打开
            
            # 第1步：通过"宽高比"标签定位，找到同行的下拉触发器元素引用
            trigger_info = page.evaluate(f"""
                () => {{
                    // 先找包含"宽高比"的标签
                    const labels = document.querySelectorAll('div, span, label');
                    let targetRow = null;
                    
                    for (const label of labels) {{
                        const text = label.textContent.trim();
                        if (!text.includes('宽高比')) continue;
                        if (text.length > 20) continue;
                        const rect = label.getBoundingClientRect();
                        if (rect.left > 500 || rect.width === 0) continue;
                        // 向上找行容器
                        targetRow = label.parentElement;
                        for (let i = 0; i < 5 && targetRow; i++) {{
                            const rowRect = targetRow.getBoundingClientRect();
                            if (rowRect.width > 200) break;
                            targetRow = targetRow.parentElement;
                        }}
                        break;
                    }}
                    
                    if (!targetRow) return {{ found: false, reason: '未找到宽高比标签' }};
                    
                    // 在行容器中找包含比例格式的下拉触发器
                    const allEls = targetRow.querySelectorAll('*');
                    const candidates = [];
                    
                    for (const el of allEls) {{
                        const elText = el.textContent.trim();
                        const elRect = el.getBoundingClientRect();
                        if (elRect.left > 500 || elRect.width < 40 || elRect.height < 20) continue;
                        if (elRect.width > 200 || elRect.height > 55) continue;
                        if (!/\d+:\d+/.test(elText)) continue;
                        if (elText.length > 12) continue;
                        if (elText.includes('自动')) continue;
                        
                        // 检查是否有 SVG 子元素（下拉箭头标志）
                        const hasSvg = el.querySelector('svg') !== null;
                        
                        candidates.push({{
                            text: elText,
                            x: Math.round(elRect.left + elRect.width / 2),
                            y: Math.round(elRect.top + elRect.height / 2),
                            right: Math.round(elRect.right),
                            w: Math.round(elRect.width),
                            h: Math.round(elRect.height),
                            children: el.children.length,
                            tag: el.tagName.toLowerCase(),
                            hasSvg: hasSvg,
                            // 用于 JS 点击的索引
                            idx: Array.from(document.querySelectorAll('*')).indexOf(el),
                        }});
                    }}
                    
                    if (candidates.length === 0) return {{ found: false, reason: '行内未找到比例元素' }};
                    
                    // 优先选有 SVG 箭头的（更可能是完整的下拉按钮），其次选宽度合适的
                    candidates.sort((a, b) => {{
                        if (a.hasSvg !== b.hasSvg) return a.hasSvg ? -1 : 1;
                        const aIsBtn = (a.w >= 50 && a.w <= 150) ? 0 : 1;
                        const bIsBtn = (b.w >= 50 && b.w <= 150) ? 0 : 1;
                        if (aIsBtn !== bIsBtn) return aIsBtn - bIsBtn;
                        return a.text.length - b.text.length;
                    }});
                    return {{ found: true, ...candidates[0], allCandidates: candidates }};
                }}
            """)
            
            if trigger_info and trigger_info.get('found'):
                current_text = trigger_info.get('text', '')
                trigger_idx = trigger_info.get('idx', -1)
                print(f"   📂 找到宽高比触发器: '{current_text}' ({trigger_info['x']}, {trigger_info['y']}) w={trigger_info.get('w')} hasSvg={trigger_info.get('hasSvg')} tag={trigger_info.get('tag')} idx={trigger_idx}")
                
                # 打印所有候选帮助调试
                all_cands = trigger_info.get('allCandidates', [])
                if len(all_cands) > 1:
                    for c in all_cands:
                        print(f"      候选: '{c.get('text')}' ({c.get('x')}, {c.get('y')}) w={c.get('w')} hasSvg={c.get('hasSvg')} tag={c.get('tag')}")
                
                # 检查当前值是否已经是目标值
                if current_text.strip() == aspect_ratio:
                    print(f"   ✅ 宽高比已经是: {current_text}")
                    params_set += 1
                else:
                    # 多种策略尝试打开下拉框
                    dropdown_opened = False
                    
                    # 辅助函数：检查下拉框是否已打开（页面上出现了新的比例选项）
                    def check_dropdown_opened():
                        check = page.evaluate(f"""
                            () => {{
                                const target = '{aspect_ratio}';
                                const allEls = document.querySelectorAll('*');
                                let count = 0;
                                const ratios = [];
                                for (const el of allEls) {{
                                    const text = el.textContent.trim();
                                    const rect = el.getBoundingClientRect();
                                    if (rect.width === 0 || rect.height === 0) continue;
                                    // 下拉选项通常是短文本，包含比例格式
                                    if (/^\d+:\d+$/.test(text) && rect.height < 60 && rect.height > 10) {{
                                        count++;
                                        ratios.push(text);
                                    }}
                                }}
                                // 如果页面上有多个不同的纯比例文本（如 16:9, 9:16, 1:1），说明下拉框打开了
                                const unique = [...new Set(ratios)];
                                return {{ opened: unique.length >= 2, count: count, ratios: unique }};
                            }}
                        """)
                        return check
                    
                    # 策略1：JS click() 直接点击元素
                    print(f"   🔄 策略1: JS click() 点击元素...")
                    page.evaluate(f"""
                        () => {{
                            const el = document.querySelectorAll('*')[{trigger_idx}];
                            if (el) el.click();
                        }}
                    """)
                    time.sleep(1)
                    
                    check1 = check_dropdown_opened()
                    print(f"   📋 策略1结果: opened={check1.get('opened')} ratios={check1.get('ratios')}")
                    if check1.get('opened'):
                        dropdown_opened = True
                    
                    # 策略2：点击 SVG 箭头区域（按钮右侧）
                    if not dropdown_opened:
                        page.keyboard.press('Escape')
                        time.sleep(0.3)
                        arrow_x = trigger_info.get('right', trigger_info['x'] + trigger_info['w'] // 2) - 10
                        arrow_y = trigger_info['y']
                        print(f"   🔄 策略2: 点击箭头区域 ({arrow_x}, {arrow_y})...")
                        page.mouse.click(arrow_x, arrow_y)
                        time.sleep(1)
                        
                        check2 = check_dropdown_opened()
                        print(f"   📋 策略2结果: opened={check2.get('opened')} ratios={check2.get('ratios')}")
                        if check2.get('opened'):
                            dropdown_opened = True
                    
                    # 策略3：dispatchEvent 模拟完整鼠标事件序列（mousedown → mouseup → click）
                    if not dropdown_opened:
                        page.keyboard.press('Escape')
                        time.sleep(0.3)
                        print(f"   🔄 策略3: dispatchEvent 模拟鼠标事件...")
                        page.evaluate(f"""
                            () => {{
                                const el = document.querySelectorAll('*')[{trigger_idx}];
                                if (!el) return;
                                const rect = el.getBoundingClientRect();
                                const cx = rect.left + rect.width / 2;
                                const cy = rect.top + rect.height / 2;
                                const opts = {{ bubbles: true, cancelable: true, clientX: cx, clientY: cy }};
                                el.dispatchEvent(new MouseEvent('mousedown', opts));
                                el.dispatchEvent(new MouseEvent('mouseup', opts));
                                el.dispatchEvent(new MouseEvent('click', opts));
                            }}
                        """)
                        time.sleep(1)
                        
                        check3 = check_dropdown_opened()
                        print(f"   📋 策略3结果: opened={check3.get('opened')} ratios={check3.get('ratios')}")
                        if check3.get('opened'):
                            dropdown_opened = True
                    
                    # 策略4：向上遍历父元素，逐个尝试 JS click
                    if not dropdown_opened:
                        page.keyboard.press('Escape')
                        time.sleep(0.3)
                        print(f"   🔄 策略4: 逐层点击父元素...")
                        for parent_level in range(1, 4):
                            page.evaluate(f"""
                                () => {{
                                    let el = document.querySelectorAll('*')[{trigger_idx}];
                                    for (let i = 0; i < {parent_level} && el; i++) el = el.parentElement;
                                    if (el) el.click();
                                }}
                            """)
                            time.sleep(0.8)
                            check4 = check_dropdown_opened()
                            print(f"      父级{parent_level}: opened={check4.get('opened')} ratios={check4.get('ratios')}")
                            if check4.get('opened'):
                                dropdown_opened = True
                                break
                            page.keyboard.press('Escape')
                            time.sleep(0.3)
                    
                    # 策略5：用 Playwright locator 点击
                    if not dropdown_opened:
                        page.keyboard.press('Escape')
                        time.sleep(0.3)
                        print(f"   🔄 策略5: Playwright locator 点击...")
                        try:
                            # 找包含当前比例文本的可点击元素
                            current_ratio = current_text.strip()
                            # 尝试用 text locator
                            loc = page.locator(f'text="{current_ratio}"').first
                            if loc.is_visible():
                                loc.click(timeout=3000)
                                time.sleep(1)
                                check5 = check_dropdown_opened()
                                print(f"   📋 策略5结果: opened={check5.get('opened')} ratios={check5.get('ratios')}")
                                if check5.get('opened'):
                                    dropdown_opened = True
                        except Exception as e5:
                            print(f"      策略5异常: {str(e5)[:60]}")
                    
                    # 策略6：真实鼠标双击
                    if not dropdown_opened:
                        page.keyboard.press('Escape')
                        time.sleep(0.3)
                        print(f"   🔄 策略6: 真实鼠标双击...")
                        page.mouse.dblclick(trigger_info['x'], trigger_info['y'])
                        time.sleep(1)
                        check6 = check_dropdown_opened()
                        print(f"   📋 策略6结果: opened={check6.get('opened')} ratios={check6.get('ratios')}")
                        if check6.get('opened'):
                            dropdown_opened = True
                    
                    page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_ratio_dropdown_{int(time.time())}.png'))
                    
                    if dropdown_opened:
                        # 下拉框已打开，选择目标选项
                        option_info = page.evaluate(f"""
                            () => {{
                                const target = '{aspect_ratio}';
                                const allEls = document.querySelectorAll('*');
                                const candidates = [];
                                
                                for (const el of allEls) {{
                                    const text = el.textContent.trim();
                                    const rect = el.getBoundingClientRect();
                                    if (rect.width === 0 || rect.height === 0) continue;
                                    if (rect.height > 60) continue;
                                    
                                    // 精确匹配目标比例（纯文本或带少量前后缀）
                                    if (!text.includes(target)) continue;
                                    if (text.length > 15) continue;
                                    
                                    candidates.push({{
                                        text: text,
                                        x: Math.round(rect.left + rect.width / 2),
                                        y: Math.round(rect.top + rect.height / 2),
                                        w: Math.round(rect.width),
                                        h: Math.round(rect.height),
                                        tag: el.tagName.toLowerCase(),
                                        children: el.children.length,
                                        len: text.length,
                                        idx: Array.from(document.querySelectorAll('*')).indexOf(el),
                                    }});
                                }}
                                
                                if (candidates.length === 0) return {{ found: false }};
                                // 优先选纯文本匹配（text === target），其次叶子节点，其次文本最短
                                candidates.sort((a, b) => {{
                                    const aExact = (a.text === target) ? 0 : 1;
                                    const bExact = (b.text === target) ? 0 : 1;
                                    if (aExact !== bExact) return aExact - bExact;
                                    if (a.children !== b.children) return a.children - b.children;
                                    return a.len - b.len;
                                }});
                                return {{ found: true, ...candidates[0] }};
                            }}
                        """)
                        
                        if option_info and option_info.get('found'):
                            opt_text = option_info.get('text', '')
                            print(f"   📍 找到选项: '{opt_text}' ({option_info['x']}, {option_info['y']}) tag={option_info.get('tag')}")
                            # 用真实鼠标点击选项
                            page.mouse.click(option_info['x'], option_info['y'])
                            time.sleep(0.5)
                            print(f"   ✅ 设置宽高比: {aspect_ratio}")
                            params_set += 1
                        else:
                            print(f"   ⚠️  下拉框已打开但未找到选项: {aspect_ratio}")
                            page.keyboard.press('Escape')
                    else:
                        print(f"   ⚠️  所有策略均未能打开宽高比下拉框")
                        # 输出详细调试信息
                        debug_info = page.evaluate("""
                            () => {
                                const allEls = document.querySelectorAll('*');
                                const results = [];
                                for (const el of allEls) {
                                    const text = el.textContent.trim();
                                    const rect = el.getBoundingClientRect();
                                    if (rect.left > 500 || rect.width === 0 || rect.height === 0) continue;
                                    if (!/\d+:\d+/.test(text)) continue;
                                    if (text.length > 20) continue;
                                    results.push({
                                        text: text,
                                        tag: el.tagName.toLowerCase(),
                                        x: Math.round(rect.left),
                                        y: Math.round(rect.top),
                                        w: Math.round(rect.width),
                                        h: Math.round(rect.height),
                                        children: el.children.length,
                                        classes: el.className ? el.className.substring(0, 60) : '',
                                        role: el.getAttribute('role') || '',
                                    });
                                }
                                return results;
                            }
                        """)
                        print(f"   📋 页面上的比例元素:")
                        for d in (debug_info or [])[:15]:
                            print(f"      [{d.get('tag')}] '{d.get('text')}' x={d.get('x')} y={d.get('y')} w={d.get('w')} h={d.get('h')} children={d.get('children')} class='{d.get('classes', '')[:40]}' role='{d.get('role')}'")
                    
                    # 确保关闭残留的下拉框
                    try:
                        page.keyboard.press('Escape')
                    except:
                        pass
                time.sleep(0.3)
            else:
                print(f"   ⚠️  未找到宽高比下拉框: {trigger_info.get('reason', '未知')}")
        except Exception as e:
            print(f"   ⚠️  设置宽高比失败: {str(e)[:80]}")
    
    # ========== 设置分辨率/清晰度（下拉框）==========
    # Q2: "清晰度 & 编码格式" 标签 + "1080pH265" 下拉
    # Q1: "时长 & 清晰度" 行中，时长旁边有 "1080p" 下拉
    # 注意：Q1 的"清晰度"在"时长 & 清晰度"标签行内，textContent 可能混合多个子元素文本
    # 必须严格匹配叶子节点，避免匹配到 "5s1080p免费2次" 这样的父容器
    if resolution:
        print(f"\n🎬 设置分辨率: {resolution}")
        try:
            res_lower = resolution.lower()  # 1080p
            
            trigger_info = page.evaluate(f"""
                () => {{
                    const resLower = '{res_lower}';
                    const allEls = document.querySelectorAll('*');
                    const candidates = [];
                    
                    for (const el of allEls) {{
                        const elRect = el.getBoundingClientRect();
                        if (elRect.left > 500 || elRect.width < 20 || elRect.height < 10) continue;
                        if (elRect.width > 200 || elRect.height > 50) continue;
                        
                        // 获取元素自身的直接文本（排除子元素文本）
                        // 同时也检查 textContent，但要求文本很短
                        const elText = el.textContent.trim();
                        
                        // 严格匹配：文本必须是纯分辨率格式（如 "1080p", "720p", "1080pH265"）
                        // 不能包含其他内容（如 "5s1080p免费2次"）
                        if (!/^\d{{3,4}}p/i.test(elText)) continue;
                        // 文本长度限制：纯分辨率最多 12 字符（如 "1080pH265"）
                        if (elText.length > 15) continue;
                        // 不能包含 "s"（时长）或 "免费"（混合文本标志）
                        if (/\ds/.test(elText) || elText.includes('免费') || elText.includes('次')) continue;
                        
                        candidates.push({{
                            text: elText,
                            x: Math.round(elRect.left + elRect.width / 2),
                            y: Math.round(elRect.top + elRect.height / 2),
                            w: Math.round(elRect.width),
                            h: Math.round(elRect.height),
                            children: el.children.length,
                            tag: el.tagName.toLowerCase(),
                        }});
                    }}
                    
                    if (candidates.length === 0) return {{ found: false }};
                    
                    // 优先选子元素最少的（叶子节点），其次选文本最短的
                    candidates.sort((a, b) => {{
                        if (a.children !== b.children) return a.children - b.children;
                        return a.text.length - b.text.length;
                    }});
                    return {{ found: true, ...candidates[0], allCandidates: candidates.slice(0, 5) }};
                }}
            """)
            
            if trigger_info and trigger_info.get('found'):
                current_res = trigger_info.get('text', '')
                print(f"   📂 找到清晰度触发器: '{current_res}' ({trigger_info['x']}, {trigger_info['y']}) w={trigger_info.get('w')} tag={trigger_info.get('tag')}")
                
                # 检查当前值是否已经是目标值
                if res_lower in current_res.lower():
                    print(f"   ✅ 分辨率已经是: {current_res}")
                    params_set += 1
                else:
                    page.mouse.click(trigger_info['x'], trigger_info['y'])
                    time.sleep(1)
                    
                    # 选择目标选项
                    option_info = page.evaluate(f"""
                        () => {{
                            const allEls = document.querySelectorAll('*');
                            const candidates = [];
                            for (const el of allEls) {{
                                const text = el.textContent.trim().toLowerCase();
                                if (!text.includes('{res_lower}')) continue;
                                if (text.length > 25) continue;
                                // 排除混合文本
                                if (/\ds/.test(text) || text.includes('免费') || text.includes('次')) continue;
                                const rect = el.getBoundingClientRect();
                                if (rect.width > 0 && rect.height > 0 && rect.height < 60) {{
                                    candidates.push({{
                                        text: el.textContent.trim(),
                                        x: Math.round(rect.left + rect.width / 2),
                                        y: Math.round(rect.top + rect.height / 2),
                                        len: el.textContent.trim().length,
                                        children: el.children.length,
                                    }});
                                }}
                            }}
                            if (candidates.length === 0) return {{ found: false }};
                            candidates.sort((a, b) => {{
                                if (a.children !== b.children) return a.children - b.children;
                                return a.len - b.len;
                            }});
                            return {{ found: true, ...candidates[0] }};
                        }}
                    """)
                    
                    if option_info and option_info.get('found'):
                        page.mouse.click(option_info['x'], option_info['y'])
                        time.sleep(0.5)
                        print(f"   ✅ 设置分辨率: {option_info.get('text', resolution)}")
                        params_set += 1
                    else:
                        print(f"   ⚠️  未找到选项: {resolution}")
                        page.keyboard.press('Escape')
                    time.sleep(0.3)
            else:
                print(f"   ⚠️  未找到清晰度下拉框")
        except Exception as e:
            print(f"   ⚠️  设置分辨率失败: {str(e)[:80]}")
    
    # ✅ 操作完成后，按 Esc 关闭可能残留的下拉框/弹窗
    try:
        page.keyboard.press('Escape')
        time.sleep(0.3)
    except:
        pass
    
    print(f"\n🎛️  参数设置完成: 成功设置 {params_set} 个参数")
    time.sleep(0.3)
    return params_set


def download_video(video_url, save_path):
    """
    下载视频到指定路径
    """
    print(f"📥 开始下载视频...")
    print(f"📍 URL: {video_url}")
    print(f"📍 保存路径: {save_path}")
    
    try:
        # 确保目录存在
        os.makedirs(os.path.dirname(save_path), exist_ok=True)
        
        # 下载视频
        response = requests.get(video_url, stream=True, timeout=120)
        response.raise_for_status()
        
        # 获取文件大小
        total_size = int(response.headers.get('content-length', 0))
        print(f"📦 文件大小: {total_size / 1024 / 1024:.2f} MB")
        
        # 写入文件
        downloaded_size = 0
        with open(save_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    downloaded_size += len(chunk)
                    
                    # 显示进度
                    if total_size > 0:
                        progress = (downloaded_size / total_size) * 100
                        print(f"\r📥 下载进度: {progress:.1f}%", end='', flush=True)
        
        print(f"\n✅ 视频下载完成: {save_path}")
        return save_path
        
    except Exception as e:
        print(f"\n❌ 下载失败: {e}")
        return None


def main():
    """主函数"""
    
    print("\n📝 解析命令行参数...", flush=True)
    
    # 解析命令行参数
    parser = argparse.ArgumentParser(description='Vidu 完整自动视频生成（包含下载）')
    parser.add_argument('prompt', help='视频提示词')
    parser.add_argument('--save-path', help='视频保存路径（可选）')
    parser.add_argument('--max-wait', type=int, default=10, help='最大等待时间（分钟，默认10）')
    parser.add_argument('--aspect-ratio', default=None, help='宽高比（如 16:9, 9:16, 1:1）')
    parser.add_argument('--resolution', default=None, help='分辨率（如 720P, 1080P）')
    parser.add_argument('--duration', default=None, help='时长（如 5秒, 10秒, 8）')
    parser.add_argument('--tool-type', default='text2video', help='工具类型（text2video, img2video, ref2video）')
    parser.add_argument('--model', default=None, help='模型名称（如 vidu-q3, vidu-q2）')
    parser.add_argument('--reference-file', default=None, help='参考文件路径（用于 ref2video，支持图片或视频）')
    parser.add_argument('--character-name', default=None, help='主体库角色名称（用于 ref2video，无参考文件时自动从主体库选择）')
    
    args = parser.parse_args()
    
    print(f"✅ 参数解析完成", flush=True)
    print(f"   提示词: {args.prompt}", flush=True)
    print(f"   保存路径: {args.save_path}", flush=True)
    print(f"   最大等待: {args.max_wait} 分钟", flush=True)
    print(f"   宽高比: {args.aspect_ratio}", flush=True)
    print(f"   分辨率: {args.resolution}", flush=True)
    print(f"   时长: {args.duration}", flush=True)
    print(f"   工具类型: {args.tool_type}", flush=True)
    print(f"   模型: {args.model}", flush=True)
    
    prompt = args.prompt
    save_path = args.save_path
    max_wait = args.max_wait
    aspect_ratio = args.aspect_ratio
    resolution = args.resolution
    duration = args.duration
    tool_type = args.tool_type
    model = args.model
    reference_file = args.reference_file
    character_name = args.character_name
    
    # ✅ 根据工具类型选择对应的 Vidu 网址
    TOOL_URLS = {
        'text2video': 'https://www.vidu.cn/create/text2video',
        'img2video': 'https://www.vidu.cn/create/img2video',
        'ref2video': 'https://www.vidu.cn/create/character2video',
    }
    
    if tool_type not in TOOL_URLS:
        error_result = {
            "success": False,
            "error": f"不支持的工具类型: {tool_type}",
            "message": f"支持的工具类型: {', '.join(TOOL_URLS.keys())}"
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2), flush=True)
        return 1
    
    vidu_url = TOOL_URLS[tool_type]
    print(f"   目标网址: {vidu_url}", flush=True)
    
    # 如果没有指定保存路径，使用默认路径
    if not save_path:
        timestamp = time.strftime('%Y%m%d_%H%M%S')
        save_path = os.path.join(DEFAULT_DOWNLOAD_DIR, f'vidu_{timestamp}.mp4')
    
    # 检查登录状态目录
    if not os.path.exists(USER_DATA_DIR):
        error_result = {
            "success": False,
            "error": "未找到登录状态目录",
            "message": "请先运行登录脚手架初始化登录状态",
            "solution": "python python_backend/web_automation/init_login.py vidu"
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2), flush=True)
        return 1
    
    print(f"\n✅ 登录状态目录存在: {USER_DATA_DIR}", flush=True)
    
    print_step(1, "启动浏览器（携带登录状态）")
    print(f"📝 提示词: {prompt}", flush=True)
    print(f"📁 保存路径: {save_path}", flush=True)
    
    # ✅ 不使用 with 语句，手动管理 Playwright 生命周期
    playwright_instance = None
    context = None
    
    try:
        # 启动 Playwright
        print("\n🚀 正在启动 Playwright...", flush=True)
        playwright_instance = sync_playwright().start()
        print("✅ Playwright 启动成功", flush=True)
        
        # ✅ 启动持久化上下文（反机器人检测优化）
        print("🌐 正在启动浏览器上下文...", flush=True)
        context = playwright_instance.chromium.launch_persistent_context(
            user_data_dir=USER_DATA_DIR,
            headless=False,
            no_viewport=True,  # ✅ 内容跟随窗口大小，不固定 viewport
            locale='zh-CN',
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            args=[
                '--start-maximized',
                '--disable-blink-features=AutomationControlled',  # ✅ 隐藏自动化特征
                '--disable-dev-shm-usage',
                '--no-sandbox',
                '--disable-web-security',
                '--disable-features=IsolateOrigins,site-per-process',
            ]
        )
        print("✅ 浏览器上下文启动成功", flush=True)
        
        # ✅ 注入反检测脚本（隐藏 webdriver 特征）
        print("🔧 注入反检测脚本...", flush=True)
        context.add_init_script("""
            Object.defineProperty(navigator, 'webdriver', {
                get: () => undefined
            });
            
            // 伪装 Chrome 插件
            Object.defineProperty(navigator, 'plugins', {
                get: () => [1, 2, 3, 4, 5]
            });
            
            // 伪装语言
            Object.defineProperty(navigator, 'languages', {
                get: () => ['zh-CN', 'zh', 'en']
            });
        """)
        print("✅ 反检测脚本注入成功", flush=True)
        
        # 获取页面
        print("📄 获取页面对象...", flush=True)
        
        # ✅ 关闭所有已有页面（避免停留在之前的视频页面）
        existing_pages = context.pages
        if len(existing_pages) > 0:
            print(f"   发现 {len(existing_pages)} 个已有页面，关闭旧页面...")
            for old_page in existing_pages[1:]:  # 保留第一个，关闭其余
                try:
                    old_page.close()
                except:
                    pass
            page = existing_pages[0]
            print(f"   使用第一个页面", flush=True)
        else:
            page = context.new_page()
            print("✅ 创建新页面", flush=True)
        
        print_step(2, f"访问 Vidu {'参考生视频' if tool_type == 'ref2video' else '文生视频'}工作台")
        print(f"🌐 目标地址: {vidu_url}", flush=True)
        
        try:
            print("🔄 开始导航到 Vidu...", flush=True)
            page.goto(vidu_url, wait_until='domcontentloaded', timeout=30000)
            print("✅ 页面导航成功", flush=True)
            
            # ✅ 确认当前 URL 是否正确
            current_url = page.url
            print(f"   当前 URL: {current_url}", flush=True)
            if 'character2video' not in current_url and tool_type == 'ref2video':
                print("⚠️  URL 不正确，重新导航...", flush=True)
                page.goto(vidu_url, wait_until='networkidle', timeout=30000)
                print(f"   重新导航后 URL: {page.url}", flush=True)
        except Exception as e:
            print(f"❌ 页面导航失败: {e}", flush=True)
            raise
        
        # ✅ 等待页面完全渲染
        print("⏳ 等待页面完全渲染...", flush=True)
        time.sleep(1)
        
        # 等待输入框出现
        print("⏳ 等待输入框加载...", flush=True)
        try:
            if tool_type == 'ref2video':
                # ref2video 使用 contenteditable div
                page.wait_for_selector('div.ProseMirror[contenteditable="true"]:visible, div[contenteditable="true"]:visible', timeout=10000)
            else:
                page.wait_for_selector('textarea:visible', timeout=10000)
            print("✅ 检测到输入框元素", flush=True)
        except PlaywrightTimeoutError:
            print("⚠️  输入框加载超时，但继续尝试...", flush=True)
        
        # 最小等待时间
        time.sleep(2)
        
        # ✅ 对于 ref2video 页面，不要随机滚动和点击，避免误触右侧视频
        if tool_type != 'ref2video':
            # ✅ 模拟人类行为：随机滚动页面
            print("\n🖱️  模拟人类行为：随机滚动页面...", flush=True)
            try:
                page.mouse.wheel(0, random.randint(100, 300))
                human_like_delay(0.5, 1.0)
                page.mouse.wheel(0, random.randint(-100, -50))
                human_like_delay(0.3, 0.8)
            except:
                pass
            
            # 强制聚焦补丁：激活页面焦点
            print("\n🎯 强制激活页面焦点...", flush=True)
            try:
                page.click('body')
                time.sleep(0.5)
                print("✅ 页面焦点已激活", flush=True)
            except:
                print("⚠️  焦点激活失败，但继续执行", flush=True)
            
            # 自动清障：关闭所有弹窗和遮挡物
            close_popups_and_blockers(page)
        else:
            print("\n📍 ref2video 页面：跳过随机滚动和点击，避免误触视频", flush=True)
            time.sleep(0.5)
        
        print_step(3, "检测登录状态")
        login_status = check_login_status(page)
        
        if login_status == False:
            raise Exception("未检测到登录状态，请先运行 init_login.py 登录")
        elif login_status == None:
            print("\n⚠️  无法自动判断登录状态，继续执行...", flush=True)
            time.sleep(3)
        else:
            print("✅ 确认已登录，继续执行\n")
        
        print_step(4, "智能填充提示词")
        
        # ✅ 针对 ref2video 页面，先上传参考文件（如果提供）
        if tool_type == 'ref2video' and reference_file:
            print("📍 检测到参考生视频模式，需要先上传参考文件...")
            
            # 先等待页面完全加载
            print("⏳ 等待页面完全加载...")
            time.sleep(2)
            
            # 保存页面截图
            debug_path = os.path.join(SCRIPT_DIR, f'debug_ref2video_before_upload_{int(time.time())}.png')
            page.screenshot(path=debug_path)
            print(f"📸 页面截图: {debug_path}")
            
            # 上传参考文件
            upload_success = upload_reference_file(page, reference_file)
            
            if not upload_success:
                print("⚠️  参考文件上传失败，但继续尝试填写提示词...")
            else:
                print("✅ 参考文件上传成功，等待页面更新...")
                time.sleep(1)
        
        # ✅ 针对 ref2video 页面（无文件上传时），尝试从主体库选择角色
        elif tool_type == 'ref2video':
            print("📍 检测到参考生视频页面（无参考文件）...")
            time.sleep(2)
            
            # 如果提供了角色名，从主体库选择（支持逗号分隔的多个名称）
            if character_name:
                # 解析逗号分隔的角色名列表
                character_names_list = [n.strip() for n in character_name.split(',') if n.strip()]
                print(f"🎭 提供了角色名: {character_names_list}，尝试从主体库选择...")
                char_success = select_character_from_library(page, character_names_list)
                if char_success > 0:
                    print(f"✅ 成功选择 {char_success} 个主体")
                    time.sleep(1)
                else:
                    print(f"⚠️  主体库选择失败，继续仅使用提示词...")
            else:
                print("📍 未提供角色名，仅使用提示词生成")
            
            # 保存调试截图
            debug_screenshot = os.path.join(SCRIPT_DIR, f'debug_ref2video_{int(time.time())}.png')
            page.screenshot(path=debug_screenshot)
            print(f"📸 已保存调试截图: {debug_screenshot}")
        
        # 查找可见的输入框
        print("🔍 查找可见的输入框...")
        
        # ✅ 根据页面类型使用不同的选择器
        if tool_type == 'ref2video':
            # ref2video 页面使用 tiptap ProseMirror 编辑器（contenteditable div）
            input_selectors = [
                'div.ProseMirror[contenteditable="true"]:visible',
                'div.tiptap[contenteditable="true"]:visible',
                'div[contenteditable="true"]:visible',
                'textarea:visible',
            ]
        else:
            # text2video / img2video 使用标准 textarea
            input_selectors = [
                'textarea:visible',
                'textarea[placeholder*="请输入描述词"]:visible',
                'textarea[placeholder*="描述"]:visible',
                'textarea[placeholder*="提示词"]:visible',
                'textarea[placeholder*="输入"]:visible',
                'input[type="text"]:visible',
                'div[contenteditable="true"]:visible',
                '[role="textbox"]:visible',
                '.input-area textarea:visible',
                '.prompt-input:visible',
            ]
        
        input_found = False
        found_input_element = None
        
        # ✅ 先列出页面上所有的 textarea 和 input 元素
        print("\n🔍 调试：列出页面上所有可能的输入元素...")
        try:
            all_textareas = page.locator('textarea').all()
            print(f"   找到 {len(all_textareas)} 个 textarea 元素")
            for idx, ta in enumerate(all_textareas):
                try:
                    is_visible = ta.is_visible(timeout=500)
                    placeholder = ta.get_attribute('placeholder') or '无'
                    print(f"   [{idx+1}] 可见={is_visible}, placeholder='{placeholder}'")
                except:
                    print(f"   [{idx+1}] 无法检测")
            
            all_inputs = page.locator('input[type="text"]').all()
            print(f"   找到 {len(all_inputs)} 个 input[type=text] 元素")
            for idx, inp in enumerate(all_inputs):
                try:
                    is_visible = inp.is_visible(timeout=500)
                    placeholder = inp.get_attribute('placeholder') or '无'
                    print(f"   [{idx+1}] 可见={is_visible}, placeholder='{placeholder}'")
                except:
                    print(f"   [{idx+1}] 无法检测")
        except Exception as e:
            print(f"   调试信息获取失败: {e}")
        print()
        
        for i, selector in enumerate(input_selectors, 1):
            try:
                print(f"🔍 [{i}/{len(input_selectors)}] 尝试: {selector}")
                input_element = page.locator(selector).first
                
                # ref2video 页面的输入框可能需要滚动才能看到
                wait_timeout = 5000 if tool_type != 'ref2video' else 3000
                
                if input_element.is_visible(timeout=wait_timeout):
                    print(f"✅ 找到可见输入框: {selector}")
                    
                    # 高亮显示找到的输入框
                    print("🎨 高亮显示找到的输入框...")
                    try:
                        input_element.evaluate("el => el.style.border = '3px solid red'")
                        input_element.evaluate("el => el.style.backgroundColor = 'rgba(255, 0, 0, 0.1)'")
                        time.sleep(1)
                    except:
                        print("⚠️  高亮失败，但继续执行")
                    
                    # 智能填充逻辑
                    print("📝 开始填充提示词...")
                    
                    # ✅ 判断是否是 contenteditable 元素（如 tiptap ProseMirror）
                    is_contenteditable = False
                    try:
                        ce_attr = input_element.get_attribute('contenteditable')
                        is_contenteditable = (ce_attr == 'true')
                    except:
                        pass
                    
                    if is_contenteditable:
                        print("📍 检测到 contenteditable 编辑器（tiptap/ProseMirror）")
                    
                    # ✅ 模拟人类：先移动鼠标到输入框
                    human_like_mouse_move(page, input_element)
                    human_like_delay(0.3, 0.6)
                    
                    # 1. 点击聚焦
                    print("🎯 点击输入框聚焦...")
                    input_element.click(force=True)
                    time.sleep(0.5)
                    
                    if is_contenteditable:
                        # ✅ contenteditable 专用填充方式（ProseMirror/tiptap）
                        # 
                        # 重要：ref2video 页面上传图片后，编辑器里会自动插入图片占位符
                        # 不能清空编辑器，否则图片占位符会被删除，导致创作按钮变灰
                        # 正确做法：把光标移到末尾，直接追加文字
                        
                        if tool_type == 'ref2video':
                            # ref2video：不清空，光标移到末尾追加文字
                            print("📍 ref2video 模式：保留编辑器内容，光标移到末尾追加文字...")
                            input_element.click(force=True)
                            time.sleep(0.3)
                            
                            # 按 End 键移到行尾，再按 Ctrl+End 移到编辑器最末尾
                            page.keyboard.press('Control+End')
                            time.sleep(0.2)
                            page.keyboard.press('End')
                            time.sleep(0.2)
                            
                            # 输入文字
                            print(f"⌨️  追加提示词: {prompt}")
                            page.keyboard.type(prompt, delay=random.randint(30, 80))
                        else:
                            # 其他类型：用键盘操作清空（Ctrl+A → Delete）再输入
                            print("🧹 用键盘清空编辑器内容（Ctrl+A → Delete）...")
                            input_element.click(force=True)
                            time.sleep(0.3)
                            page.keyboard.press('Control+a')
                            time.sleep(0.2)
                            page.keyboard.press('Delete')
                            time.sleep(0.3)
                            
                            # 输入文字
                            print(f"⌨️  输入提示词: {prompt}")
                            page.keyboard.type(prompt, delay=random.randint(30, 80))
                        
                        human_like_delay(0.5, 1.0)
                        
                        # 验证
                        filled_text = input_element.inner_text().strip()
                        if prompt in filled_text:
                            print(f"✅ 提示词填充成功")
                        else:
                            print(f"⚠️  验证: 期望包含'{prompt[:30]}...', 实际='{filled_text[:50]}'")
                            # 备用方案：再试一次（不清空，直接追加）
                            input_element.click(force=True)
                            time.sleep(0.2)
                            page.keyboard.press('Control+End')
                            time.sleep(0.1)
                            page.keyboard.type(prompt, delay=random.randint(20, 50))
                            time.sleep(0.5)
                    else:
                        # ✅ 标准 textarea/input 填充方式
                        # 暴力聚焦
                        print("🎯 暴力聚焦：强制夺取输入框焦点...")
                        try:
                            input_element.evaluate("el => el.focus()")
                            time.sleep(0.3)
                            print("✅ 焦点已强制夺取")
                        except:
                            pass
                        
                        human_like_delay(0.2, 0.5)
                        
                        # 清空现有内容
                        print("🧹 清空现有内容...")
                        try:
                            input_element.fill('', force=True)
                        except:
                            input_element.fill('')
                        time.sleep(0.2)
                        
                        # 填充新提示词
                        print(f"⌨️  输入提示词: {prompt}")
                        try:
                            input_element.type(prompt, delay=random.randint(50, 100))
                        except:
                            print("⚠️  type 失败，使用 fill 强制填充")
                            input_element.fill(prompt, force=True)
                        
                        human_like_delay(0.5, 1.0)
                        
                        # 验证填充结果
                        filled_value = input_element.input_value()
                        if filled_value == prompt:
                            print(f"✅ 提示词填充成功: {prompt}")
                        else:
                            print(f"⚠️  填充验证: 期望='{prompt}', 实际='{filled_value}'")
                            input_element.fill(prompt)
                            time.sleep(0.5)
                    
                    # 填充后缓冲时间
                    print("⏳ 缓冲 1 秒...")
                    page.wait_for_timeout(1000)
                    
                    input_found = True
                    found_input_element = input_element
                    break
            except Exception as e:
                print(f"   ❌ 失败: {str(e)[:80]}")
                continue
        
        if not input_found:
            # ✅ 对于 ref2video，尝试滚动左侧面板来找到输入框
            if tool_type == 'ref2video':
                print("\n🔍 ref2video：尝试滚动左侧面板查找输入框...")
                try:
                    # 找到左侧面板并滚动
                    left_panel_selectors = [
                        'div[class*="sidebar"]:visible',
                        'div[class*="panel"]:visible',
                        'div[class*="left"]:visible',
                        'aside:visible',
                    ]
                    
                    # 先尝试直接滚动到文本框位置
                    page.evaluate("""
                        // 查找所有 textarea 并滚动到第一个
                        const textareas = document.querySelectorAll('textarea');
                        if (textareas.length > 0) {
                            textareas[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
                        }
                    """)
                    time.sleep(2)
                    
                    # 再次尝试查找
                    for selector in input_selectors:
                        try:
                            input_element = page.locator(selector).first
                            if input_element.is_visible(timeout=3000):
                                print(f"✅ 滚动后找到输入框: {selector}")
                                
                                # 高亮
                                try:
                                    input_element.evaluate("el => el.style.border = '3px solid red'")
                                    time.sleep(0.5)
                                except:
                                    pass
                                
                                # 点击聚焦
                                input_element.click(force=True)
                                time.sleep(0.3)
                                
                                # 清空并输入
                                input_element.fill('')
                                time.sleep(0.2)
                                input_element.type(prompt, delay=random.randint(50, 100))
                                
                                human_like_delay(0.5, 1.0)
                                
                                filled_value = input_element.input_value()
                                if filled_value == prompt:
                                    print(f"✅ 提示词填充成功: {prompt}")
                                else:
                                    input_element.fill(prompt)
                                
                                page.wait_for_timeout(1000)
                                input_found = True
                                found_input_element = input_element
                                break
                        except:
                            continue
                except Exception as e:
                    print(f"⚠️  滚动查找失败: {e}")
        
        if not input_found:
            # ✅ 保存详细的调试截图和页面HTML
            screenshot_path = os.path.join(SCRIPT_DIR, f'debug_no_input_{tool_type}_{int(time.time())}.png')
            page.screenshot(path=screenshot_path, full_page=True)
            
            html_path = os.path.join(SCRIPT_DIR, f'debug_page_{tool_type}_{int(time.time())}.html')
            with open(html_path, 'w', encoding='utf-8') as f:
                f.write(page.content())
            
            print(f"\n❌ 未找到提示词输入框")
            print(f"📸 完整页面截图: {screenshot_path}")
            print(f"📄 页面HTML: {html_path}")
            print(f"🌐 当前URL: {page.url}")
            print(f"🔧 工具类型: {tool_type}")
            
            raise Exception(f"未找到提示词输入框，调试文件已保存:\n截图: {screenshot_path}\nHTML: {html_path}")
        
        print_step(5, "设置视频参数（模型、宽高比、分辨率、时长）")
        set_video_parameters(page, aspect_ratio=aspect_ratio, resolution=resolution, duration=duration, model=model)
        
        print_step(6, "查找并点击生成按钮")
        
        # ✅ 记录当前页面上的视频数量（用于后续判断新生成的视频）
        try:
            initial_video_count = len(page.locator('video').all())
            print(f"📹 当前页面视频数量: {initial_video_count}")
        except:
            initial_video_count = 0
        
        # ✅ 对于 ref2video，不要调用 close_popups_and_blockers（会乱点）
        if tool_type != 'ref2video':
            close_popups_and_blockers(page)
        
        button_found = False
        
        # ✅ 保存点击前的页面截图，方便调试
        debug_before_click = os.path.join(SCRIPT_DIR, f'debug_before_create_btn_{int(time.time())}.png')
        page.screenshot(path=debug_before_click)
        print(f"📸 点击前截图: {debug_before_click}")
        
        # ============================================================
        # 核心方法：用 JavaScript 直接查找并点击"创作"按钮
        # 
        # Vidu 的"创作"按钮特征：
        # - 文本包含"创作"
        # - 是 <button> 标签
        # - 位于左侧面板（x < 500）
        # - 是悬浮/固定按钮（position: sticky/fixed），始终可见
        # - 宽度较大（整个面板宽度），高度适中
        # - 有蓝色渐变背景
        # ============================================================
        print("🎯 用 JavaScript 查找「创作」按钮...")
        try:
            result = page.evaluate("""
                () => {
                    const candidates = [];
                    
                    // 第1步：收集所有包含"创作"的 button 元素
                    const buttons = document.querySelectorAll('button');
                    for (const btn of buttons) {
                        const text = btn.textContent || '';
                        if (text.includes('创作')) {
                            const rect = btn.getBoundingClientRect();
                            const style = window.getComputedStyle(btn);
                            candidates.push({
                                element: btn,
                                text: text.trim().substring(0, 30),
                                x: rect.left,
                                y: rect.top,
                                width: rect.width,
                                height: rect.height,
                                position: style.position,
                                bgColor: style.backgroundColor,
                                isVisible: rect.width > 0 && rect.height > 0,
                                tagName: 'button',
                            });
                        }
                    }
                    
                    // 第2步：也查找 div、span、a 等可能的按钮元素
                    const others = document.querySelectorAll('div, span, a');
                    for (const el of others) {
                        // 只匹配直接文本内容较短的元素（避免匹配整个面板）
                        const directText = Array.from(el.childNodes)
                            .filter(n => n.nodeType === 3)
                            .map(n => n.textContent.trim())
                            .join('');
                        const fullText = el.textContent || '';
                        
                        if ((directText.includes('创作') || fullText.trim().startsWith('创作')) && fullText.length < 20) {
                            const rect = el.getBoundingClientRect();
                            const style = window.getComputedStyle(el);
                            candidates.push({
                                element: el,
                                text: fullText.trim().substring(0, 30),
                                x: rect.left,
                                y: rect.top,
                                width: rect.width,
                                height: rect.height,
                                position: style.position,
                                bgColor: style.backgroundColor,
                                isVisible: rect.width > 0 && rect.height > 0,
                                tagName: el.tagName.toLowerCase(),
                            });
                        }
                    }
                    
                    // 第3步：输出所有候选信息（调试用）
                    const info = candidates.map(c => ({
                        text: c.text,
                        tag: c.tagName,
                        x: Math.round(c.x),
                        y: Math.round(c.y),
                        w: Math.round(c.width),
                        h: Math.round(c.height),
                        pos: c.position,
                        visible: c.isVisible,
                    }));
                    
                    // 第4步：筛选最佳候选
                    // 优先选择：左侧（x < 500）、可见、宽度 > 50 的 button
                    let best = null;
                    for (const c of candidates) {
                        if (!c.isVisible) continue;
                        if (c.x > 500) continue;  // 排除右侧
                        if (c.width < 50) continue;  // 排除太小的
                        if (c.height < 20) continue;  // 排除太矮的
                        
                        // 优先选 button 标签
                        if (!best || (c.tagName === 'button' && best.tagName !== 'button')) {
                            best = c;
                        }
                        // 同为 button 时，选宽度更大的（主按钮通常更宽）
                        else if (c.tagName === best.tagName && c.width > best.width) {
                            best = c;
                        }
                    }
                    
                    if (best) {
                        // 检查是否 disabled
                        const isDisabled = best.element.disabled || 
                            best.element.getAttribute('disabled') !== null ||
                            best.element.classList.contains('disabled') ||
                            window.getComputedStyle(best.element).pointerEvents === 'none' ||
                            window.getComputedStyle(best.element).opacity < 0.5;
                        
                        // 高亮
                        best.element.style.border = '3px solid red';
                        best.element.style.boxShadow = '0 0 10px red';
                        
                        return {
                            found: true,
                            disabled: isDisabled,
                            text: best.text,
                            tag: best.tagName,
                            x: Math.round(best.x),
                            y: Math.round(best.y),
                            w: Math.round(best.width),
                            h: Math.round(best.height),
                            pos: best.position,
                            allCandidates: info,
                        };
                    }
                    
                    return { found: false, allCandidates: info };
                }
            """)
            
            # 输出调试信息
            if result:
                all_candidates = result.get('allCandidates', [])
                print(f"   共找到 {len(all_candidates)} 个候选元素:")
                for c in all_candidates:
                    print(f"     [{c.get('tag')}] text='{c.get('text')}' x={c.get('x')} y={c.get('y')} w={c.get('w')} h={c.get('h')} pos={c.get('pos')} visible={c.get('visible')}")
                
                if result.get('found'):
                    is_disabled = result.get('disabled', False)
                    print(f"\n✅ JS 找到创作按钮: [{result.get('tag')}] text='{result.get('text')}' disabled={is_disabled}")
                    
                    if is_disabled:
                        # 按钮是灰色/禁用状态，等待它变为可用
                        print("⚠️  创作按钮当前是禁用状态（灰色），等待变为可用...")
                        print("   可能原因：编辑器输入未被正确识别")
                        
                        # 尝试修复：重新点击编辑器并触发 input 事件
                        try:
                            page.evaluate("""
                                () => {
                                    const editor = document.querySelector('div.ProseMirror[contenteditable="true"]');
                                    if (editor) {
                                        editor.focus();
                                        editor.dispatchEvent(new Event('input', { bubbles: true }));
                                        editor.dispatchEvent(new Event('change', { bubbles: true }));
                                        editor.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
                                    }
                                }
                            """)
                            time.sleep(1)
                        except:
                            pass
                        
                        # 等待按钮变为可用（最多等 15 秒）
                        for wait_i in range(15):
                            try:
                                still_disabled = page.evaluate("""
                                    () => {
                                        const buttons = document.querySelectorAll('button');
                                        for (const btn of buttons) {
                                            if (btn.textContent.includes('创作')) {
                                                const rect = btn.getBoundingClientRect();
                                                if (rect.left < 500 && rect.width > 50) {
                                                    return btn.disabled || 
                                                        btn.getAttribute('disabled') !== null ||
                                                        window.getComputedStyle(btn).opacity < 0.5;
                                                }
                                            }
                                        }
                                        return true;
                                    }
                                """)
                                if not still_disabled:
                                    print(f"✅ 创作按钮已变为可用（等待了 {wait_i + 1} 秒）")
                                    break
                                print(f"   ⏳ 按钮仍然禁用，等待... ({wait_i + 1}/15)")
                            except:
                                pass
                            time.sleep(1)
                    
                    # 现在点击按钮
                    print("🖱️  点击创作按钮...")
                    try:
                        page.evaluate("""
                            () => {
                                const buttons = document.querySelectorAll('button');
                                for (const btn of buttons) {
                                    if (btn.textContent.includes('创作')) {
                                        const rect = btn.getBoundingClientRect();
                                        if (rect.left < 500 && rect.width > 50) {
                                            btn.click();
                                            return true;
                                        }
                                    }
                                }
                                return false;
                            }
                        """)
                    except:
                        pass
                    
                    time.sleep(2)
                    button_found = True
                else:
                    print("⚠️  JS 未找到符合条件的创作按钮")
        except Exception as e:
            print(f"⚠️  JS 查找失败: {str(e)[:120]}")
        
        # ✅ 备用方法：用 Playwright locator 查找
        if not button_found:
            print("\n📍 备用方法：用 Playwright locator 查找...")
            try:
                # 尝试多种选择器
                selectors = [
                    'button:has-text("创作"):visible',
                    'button:has-text("创作 "):visible',
                ]
                
                for selector in selectors:
                    try:
                        buttons = page.locator(selector).all()
                        for btn in buttons:
                            try:
                                if not btn.is_visible(timeout=1000):
                                    continue
                                box = btn.bounding_box()
                                if not box:
                                    continue
                                btn_text = btn.inner_text().strip()
                                print(f"   Playwright 候选: text='{btn_text[:20]}' x={box['x']:.0f} y={box['y']:.0f} w={box['width']:.0f}")
                                
                                # 左侧、宽度合理
                                if box['x'] < 500 and box['width'] > 50 and len(btn_text) < 20:
                                    print(f"✅ Playwright 找到创作按钮")
                                    btn.click(timeout=5000, force=True)
                                    print("✅ 创作按钮已点击")
                                    time.sleep(2)
                                    button_found = True
                                    break
                            except:
                                continue
                        if button_found:
                            break
                    except:
                        continue
            except Exception as e:
                print(f"⚠️  Playwright 查找失败: {str(e)[:80]}")
        
        if not button_found:
            # 保存调试截图
            screenshot_path = os.path.join(SCRIPT_DIR, f'debug_no_create_btn_{int(time.time())}.png')
            page.screenshot(path=screenshot_path)
            print(f"📸 未找到创作按钮，截图: {screenshot_path}")
            raise Exception(f"未找到生成按钮，调试截图已保存: {screenshot_path}")
        
        # ✅ 验证点击是否真的触发了生成
        print("\n🔍 验证创作是否已触发...")
        generation_triggered = False
        for verify_i in range(10):
            try:
                # 检查是否出现"排队中"或"生成中"
                for indicator in [':has-text("排队中")', ':has-text("生成中")', ':has-text("预计等待")']:
                    try:
                        el = page.locator(indicator).first
                        if el.is_visible(timeout=1000):
                            print(f"✅ 检测到生成已触发: {indicator}")
                            generation_triggered = True
                            break
                    except:
                        continue
                if generation_triggered:
                    break
                
                # 检查 URL 是否变化（有些页面点击后会跳转）
                current_url = page.url
                if 'task' in current_url or 'result' in current_url:
                    print(f"✅ URL 变化，生成可能已触发: {current_url}")
                    generation_triggered = True
                    break
                    
                print(f"   ⏳ 等待生成触发... ({verify_i + 1}/10)")
            except:
                pass
            time.sleep(2)
        
        if not generation_triggered:
            print("⚠️  未检测到生成触发标识，但继续等待...")
            # 保存截图方便调试
            debug_path = os.path.join(SCRIPT_DIR, f'debug_after_click_create_{int(time.time())}.png')
            page.screenshot(path=debug_path)
            print(f"📸 点击后截图: {debug_path}")
        
        print_step(7, "等待视频生成完成")
        if not wait_for_video_generation(page, max_wait_minutes=max_wait):
            error_result = {
                "success": False,
                "error": "视频生成超时",
                "message": f"等待 {max_wait} 分钟后仍未完成"
            }
            print(json.dumps(error_result, ensure_ascii=False, indent=2))
            context.close()
            return 1
        
        print_step(8, "获取视频 URL")
        video_url = get_video_url(page, initial_video_count=initial_video_count)
        
        if not video_url:
            error_result = {
                "success": False,
                "error": "未找到视频 URL",
                "message": "视频可能生成成功，但无法获取下载链接"
            }
            print(json.dumps(error_result, ensure_ascii=False, indent=2))
            context.close()
            return 1
        
        print_step(9, "下载视频")
        local_path = download_video(video_url, save_path)
        
        if not local_path:
            error_result = {
                "success": False,
                "error": "视频下载失败",
                "video_url": video_url
            }
            print(json.dumps(error_result, ensure_ascii=False, indent=2))
            context.close()
            return 1
        
        print_step(10, "完成")
        
        # ✅ 不要立即关闭浏览器，等待 5 秒让用户确认
        print("\n⏳ 等待 5 秒后关闭浏览器...")
        print("   （如果需要检查页面，请在这 5 秒内查看）")
        time.sleep(5)
        
        context.close()
        playwright_instance.stop()
        
        # 返回成功结果
        result = {
            "success": True,
            "message": "视频生成并下载成功",
            "video_url": video_url,
            "local_video_path": local_path,
            "prompt": prompt
        }
        
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
        
    except Exception as e:
        # ✅ 遇到错误时不要关闭浏览器，让用户能看到问题
        print(f"\n❌ 执行失败: {e}")
        print("\n" + "="*60)
        print("  ⚠️  发生错误，浏览器将保持打开状态")
        print("  请手动检查页面，查看具体问题")
        print("  ")
        print("  💡 提示：")
        print("     1. 如果看到验证码，请手动完成验证")
        print("     2. 验证完成后，可以手动继续操作")
        print("     3. 或者按 Ctrl+C 退出并重新运行脚本")
        print("  ")
        print("  按 Ctrl+C 可以退出脚本")
        print("="*60 + "\n")
        
        error_result = {
            "success": False,
            "error": str(e),
            "message": "执行失败，浏览器保持打开以供检查"
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        
        # ✅ 永久等待，不关闭浏览器
        try:
            print("\n⏳ 浏览器将保持打开，等待你的操作...\n")
            
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n\n⚠️  用户中断，现在关闭浏览器\n")
            try:
                if context:
                    context.close()
                if playwright_instance:
                    playwright_instance.stop()
            except:
                pass
        
        return 1


if __name__ == "__main__":
    sys.exit(main())
