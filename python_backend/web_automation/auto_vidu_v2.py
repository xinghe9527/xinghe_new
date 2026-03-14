#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Vidu 视频生成自动化 V2（并发架构）

架构（参考即梦插件和 auto_jimeng.py）：
1. 常驻浏览器（persistent context），不每次启动/关闭
2. 类封装所有操作
3. submit_generate()（UI 操作，需要锁）+ poll_result()（轮询，不需要锁）分离
4. 支持多任务并发：UI 操作串行排队，等待结果并行

用法：
    python auto_vidu_v2.py "提示词" --save-path output.mp4
"""

import sys
import os
import io
import json
import time
import argparse
import requests
import re
import random
from pathlib import Path

# 确保标准输出使用 UTF-8 编码
if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')
    except:
        pass

# 安全打印（stdout 管道断裂时不抛异常）
_original_print = print
def _safe_print(*args, **kwargs):
    try:
        _original_print(*args, **kwargs)
    except (OSError, IOError, ValueError):
        pass
print = _safe_print

# ============================================================
# 常量配置
# ============================================================

# 浏览器 profile 统一存储在 %APPDATA%/com.example/xinghe_new/user_data/
_APPDATA = os.environ.get('APPDATA', os.path.expanduser('~'))
USER_DATA_ROOT = os.path.join(_APPDATA, 'com.example', 'xinghe_new', 'user_data')
os.makedirs(USER_DATA_ROOT, exist_ok=True)

if getattr(sys, 'frozen', False):
    SCRIPT_DIR = os.path.dirname(os.path.abspath(sys.executable))
    PROJECT_ROOT = SCRIPT_DIR
else:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
VIDU_PROFILE_DIR = os.path.join(USER_DATA_ROOT, 'vidu_profile')
DEFAULT_DOWNLOAD_DIR = os.path.join(SCRIPT_DIR, 'downloads')

# Vidu 工具类型 → URL 映射
VIDU_TOOL_URLS = {
    'text2video': 'https://www.vidu.cn/create/text2video',
    'img2video': 'https://www.vidu.cn/create/img2video',
    'ref2video': 'https://www.vidu.cn/create/character2video',
}


def human_like_delay(min_s=0.5, max_s=2.0):
    """模拟人类操作的随机延迟"""
    time.sleep(random.uniform(min_s, max_s))


def download_video(video_url: str, save_path: str) -> bool:
    """下载视频到本地"""
    print(f"\n📥 下载视频...")
    print(f"   URL: {video_url[:100]}...")
    print(f"   保存: {save_path}")
    try:
        os.makedirs(os.path.dirname(save_path), exist_ok=True)
        resp = requests.get(video_url, stream=True, timeout=120)
        resp.raise_for_status()
        total_size = int(resp.headers.get('content-length', 0))
        downloaded = 0
        with open(save_path, 'wb') as f:
            for chunk in resp.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total_size > 0 and downloaded % (1024 * 1024) < 8192:
                        pct = downloaded * 100 // total_size
                        print(f"   📊 下载进度: {pct}%")
        file_size = os.path.getsize(save_path)
        print(f"   ✅ 下载完成: {file_size / 1024 / 1024:.1f} MB")
        return True
    except Exception as e:
        print(f"   ❌ 下载失败: {e}")
        return False


# ============================================================
# Vidu 页面自动化类
# ============================================================

class ViduAutomation:
    """
    Vidu 网页 UI 自动化（并发架构）
    
    常驻浏览器，支持 submit_generate + poll_result 分离。
    """
    
    def __init__(self, profile_dir: str = None):
        self.profile_dir = profile_dir or VIDU_PROFILE_DIR
        self.pw = None
        self.context = None
        self.page = None
        self._started = False
        # 并发任务追踪
        self._pending_tasks = {}
        self._last_video_count = 0
        # 页面操作锁（线程级），保护所有 self.page 访问
        # submit_generate 和 poll_result 都可能从不同线程访问 page
        import threading
        self._page_lock = threading.Lock()
    
    def start(self) -> bool:
        """
        启动浏览器连接。
        
        优先使用系统浏览器（Edge/Chrome）+ CDP 连接，
        回退到 Playwright persistent context。
        """
        try:
            # 方式1：使用 BrowserManager 连接系统浏览器（推荐）
            try:
                from browser_manager import BrowserManager
                
                print("   🌐 尝试使用系统浏览器（Edge/Chrome）...")
                # Vidu 用不同的 CDP 端口，避免和即梦冲突
                self._browser_mgr = BrowserManager(
                    cdp_port=9223,
                    profile_name='vidu',
                )
                self.page = self._browser_mgr.connect_or_launch(
                    target_url=VIDU_TOOL_URLS['text2video']
                )
                self.context = self._browser_mgr.context
                
                self._started = True
                print(f"   ✅ Vidu 浏览器启动成功，页面: {self.page.url[:60]}")
                return True
                
            except Exception as mgr_err:
                print(f"   ⚠️  系统浏览器连接失败: {mgr_err}")
                print("   🔄 回退到 Playwright 内置浏览器...")
            
            # 方式2：回退到 Playwright persistent context（兼容）
            from playwright.sync_api import sync_playwright
            
            if not os.path.exists(self.profile_dir):
                os.makedirs(self.profile_dir, exist_ok=True)
            
            self.pw = sync_playwright().start()
            
            self.context = self.pw.chromium.launch_persistent_context(
                user_data_dir=self.profile_dir,
                headless=False,
                no_viewport=True,
                locale='zh-CN',
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                args=[
                    '--start-maximized',
                    '--disable-blink-features=AutomationControlled',
                    '--disable-dev-shm-usage',
                    '--no-sandbox',
                ],
            )
            
            # 注入反检测脚本
            self.context.add_init_script("""
                Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
                Object.defineProperty(navigator, 'languages', { get: () => ['zh-CN', 'zh', 'en'] });
            """)
            
            # 获取或创建页面
            if self.context.pages:
                self.page = self.context.pages[0]
            else:
                self.page = self.context.new_page()
            
            # 导航到 Vidu 文生视频页面
            self._ensure_tool_page('text2video')
            
            self._started = True
            print(f"   ✅ Vidu 浏览器启动成功，页面: {self.page.url[:60]}")
            return True
            
        except Exception as e:
            print(f"   ❌ 启动失败: {e}")
            self.stop()
            return False
    
    def stop(self):
        """断开连接（不关闭浏览器）"""
        try:
            # 如果使用 BrowserManager，断开连接但保留浏览器
            if hasattr(self, '_browser_mgr') and self._browser_mgr:
                self._browser_mgr.disconnect()
            else:
                if self.context:
                    self.context.close()
                if self.pw:
                    self.pw.stop()
        except:
            pass
        self._started = False
    
    def _ensure_tool_page(self, tool_type: str, force_reload: bool = False):
        """确保当前在指定工具类型的页面
        
        Args:
            tool_type: 工具类型
            force_reload: 是否强制刷新页面（多次生成时需要刷新以清空旧内容）
        """
        target_url = VIDU_TOOL_URLS.get(tool_type, VIDU_TOOL_URLS['text2video'])
        current_url = self.page.url
        
        # 检查是否已经在目标页面
        url_key_map = {
            'text2video': 'text2video',
            'img2video': 'img2video',
            'ref2video': 'character2video',
        }
        expected_key = url_key_map.get(tool_type, 'text2video')
        
        if 'vidu.cn' not in current_url or expected_key not in current_url:
            print(f"   🌐 导航到 Vidu {tool_type} 页面...", flush=True)
            print(f"      当前URL: {current_url[:80]}", flush=True)
            print(f"      目标URL: {target_url}", flush=True)
            self.page.goto(target_url, wait_until='domcontentloaded', timeout=30000)
            print(f"   🌐 页面已加载 (domcontentloaded)", flush=True)
            time.sleep(3)
        elif force_reload:
            # 已在目标页面但需要刷新（多次生成时清空旧的提示词和主体选择）
            print(f"   🌐 已在目标页面，刷新以清空旧内容...", flush=True)
            self.page.reload(wait_until='domcontentloaded', timeout=30000)
            print(f"   🌐 页面已刷新", flush=True)
            time.sleep(3)
        else:
            print(f"   🌐 已在目标页面: {current_url[:80]}", flush=True)

    
    def check_login(self) -> bool:
        """检查是否已登录"""
        try:
            # 检查页面上是否有输入框（已登录才能看到）
            textarea = self.page.query_selector('textarea:visible')
            if textarea:
                print("   ✅ 已登录（检测到输入框）")
                return True
            
            # 检查 contenteditable 编辑器
            editor = self.page.query_selector('div.ProseMirror[contenteditable="true"]:visible')
            if editor:
                print("   ✅ 已登录（检测到编辑器）")
                return True
            
            # 检查是否有登录按钮
            login_btn = self.page.query_selector('text=登录')
            if login_btn and login_btn.is_visible():
                print("   ❌ 未登录")
                return False
            
            print("   ⚠️  无法确认登录状态，继续执行")
            return True
        except Exception as e:
            print(f"   ⚠️  检查登录异常: {e}")
            return True
    
    # ============================================================
    # 清空之前的提示词（多次生成时必须先清空）
    # ============================================================
    
    def clear_previous_prompt(self, tool_type: str = 'text2video') -> bool:
        """
        清空之前的提示词内容。
        
        Vidu 页面在生成完成后，提示词不会自动清空。
        如果不清空就直接输入新提示词，会导致内容叠加，实际生成的还是旧内容。
        
        策略：
        1. 优先点击 "一键清空" 按钮（如果存在）
        2. 尝试点击文本框右下角的删除按钮（SVG 图标按钮）
        3. 回退到键盘 Ctrl+A → Delete 清空
        """
        print("   🧹 清空之前的提示词...", flush=True)
        
        try:
            # 策略1：通过 JS 查找并点击 "一键清空" 或删除按钮
            cleared = self.page.evaluate("""
                () => {
                    // 方法1：查找包含 "一键清空" 文本的按钮/元素
                    const allElements = document.querySelectorAll('button, div[role="button"], span, a');
                    for (const el of allElements) {
                        const text = (el.textContent || '').trim();
                        if (text === '一键清空' || text.includes('一键清空')) {
                            const rect = el.getBoundingClientRect();
                            if (rect.width > 0 && rect.height > 0) {
                                el.click();
                                return { method: 'clear_all_button', text: text };
                            }
                        }
                    }
                    
                    // 方法2：查找 textarea 或输入区域附近的删除/清空按钮
                    // 通常是一个小的 SVG 图标按钮，位于文本框右下角
                    const textarea = document.querySelector('textarea:not([style*="display: none"])');
                    if (textarea) {
                        const textareaRect = textarea.getBoundingClientRect();
                        // 查找 textarea 附近（下方或右侧）的按钮
                        const nearbyButtons = document.querySelectorAll('button, div[role="button"], [class*="clear"], [class*="delete"], [class*="close"], [class*="remove"]');
                        for (const btn of nearbyButtons) {
                            const btnRect = btn.getBoundingClientRect();
                            // 在 textarea 下方且水平范围内
                            if (btnRect.top >= textareaRect.bottom - 40 && 
                                btnRect.top <= textareaRect.bottom + 60 &&
                                btnRect.left >= textareaRect.left - 20 &&
                                btnRect.right <= textareaRect.right + 20 &&
                                btnRect.width > 0 && btnRect.width < 80) {
                                btn.click();
                                return { method: 'nearby_button', x: Math.round(btnRect.left), y: Math.round(btnRect.top) };
                            }
                        }
                        
                        // 方法3：查找 textarea 容器内的 SVG 删除图标
                        const parent = textarea.closest('div[class]') || textarea.parentElement;
                        if (parent) {
                            const svgBtns = parent.querySelectorAll('svg, [class*="icon"]');
                            for (const svg of svgBtns) {
                                const clickTarget = svg.closest('button') || svg.closest('div[role="button"]') || svg.parentElement;
                                if (clickTarget && clickTarget !== parent) {
                                    const svgRect = clickTarget.getBoundingClientRect();
                                    // 只点击小尺寸的图标按钮（避免误点大按钮）
                                    if (svgRect.width > 0 && svgRect.width < 60 && svgRect.height < 60) {
                                        clickTarget.click();
                                        return { method: 'svg_icon', x: Math.round(svgRect.left), y: Math.round(svgRect.top) };
                                    }
                                }
                            }
                        }
                    }
                    
                    // 方法4：查找 ProseMirror 编辑器附近的删除按钮（ref2video）
                    const editor = document.querySelector('div.ProseMirror[contenteditable="true"]');
                    if (editor) {
                        const editorRect = editor.getBoundingClientRect();
                        const nearbyBtns = document.querySelectorAll('button, div[role="button"]');
                        for (const btn of nearbyBtns) {
                            const btnRect = btn.getBoundingClientRect();
                            if (btnRect.top >= editorRect.bottom - 40 &&
                                btnRect.top <= editorRect.bottom + 60 &&
                                btnRect.left >= editorRect.left - 20 &&
                                btnRect.right <= editorRect.right + 20 &&
                                btnRect.width > 0 && btnRect.width < 80) {
                                btn.click();
                                return { method: 'editor_nearby_button', x: Math.round(btnRect.left), y: Math.round(btnRect.top) };
                            }
                        }
                    }
                    
                    return null;
                }
            """)
            
            if cleared:
                print(f"   ✅ 已清空提示词（{cleared.get('method', 'unknown')}）", flush=True)
                time.sleep(1)
                
                # 如果弹出了确认对话框，点击确认
                try:
                    confirm_btn = self.page.locator('button:has-text("确认"):visible, button:has-text("确定"):visible, button:has-text("删除"):visible').first
                    if confirm_btn.is_visible(timeout=2000):
                        confirm_btn.click()
                        print("   ✅ 已确认清空", flush=True)
                        time.sleep(1)
                except:
                    pass
                
                return True
            
            # 策略2（回退）：用键盘清空
            print("   ⚠️  未找到清空按钮，尝试键盘清空...", flush=True)
            if tool_type == 'ref2video':
                input_selectors = [
                    'div.ProseMirror[contenteditable="true"]:visible',
                    'div[contenteditable="true"]:visible',
                ]
            else:
                input_selectors = [
                    'textarea:visible',
                ]
            
            for selector in input_selectors:
                try:
                    el = self.page.locator(selector).first
                    if el.is_visible(timeout=3000):
                        el.click(force=True)
                        time.sleep(0.3)
                        self.page.keyboard.press('Control+a')
                        time.sleep(0.2)
                        self.page.keyboard.press('Delete')
                        time.sleep(0.3)
                        self.page.keyboard.press('Backspace')
                        time.sleep(0.3)
                        print("   ✅ 已通过键盘清空", flush=True)
                        return True
                except:
                    continue
            
            print("   ⚠️  清空操作未能执行，继续输入...", flush=True)
            return False
            
        except Exception as e:
            print(f"   ⚠️  清空提示词异常: {e}", flush=True)
            return False
    
    # ============================================================
    # 输入提示词
    # ============================================================
    
    def input_prompt(self, prompt: str, tool_type: str = 'text2video') -> bool:
        """输入提示词"""
        print(f"   📝 输入提示词: {prompt[:60]}...")
        
        try:
            if tool_type == 'ref2video':
                # ref2video 使用 contenteditable div
                input_selectors = [
                    'div.ProseMirror[contenteditable="true"]:visible',
                    'div[contenteditable="true"]:visible',
                ]
            else:
                input_selectors = [
                    'textarea:visible',
                    'textarea[placeholder*="描述"]:visible',
                    'textarea[placeholder*="提示词"]:visible',
                ]
            
            for selector in input_selectors:
                try:
                    el = self.page.locator(selector).first
                    if not el.is_visible(timeout=5000):
                        continue
                    
                    # 判断是否是 contenteditable
                    is_ce = False
                    try:
                        is_ce = el.get_attribute('contenteditable') == 'true'
                    except:
                        pass
                    
                    # 点击聚焦
                    el.click(force=True)
                    time.sleep(0.5)
                    
                    if is_ce:
                        if tool_type == 'ref2video':
                            # 不清空，追加到末尾
                            self.page.keyboard.press('Control+End')
                            time.sleep(0.2)
                            self.page.keyboard.type(prompt, delay=random.randint(30, 80))
                        else:
                            self.page.keyboard.press('Control+a')
                            time.sleep(0.2)
                            self.page.keyboard.press('Delete')
                            time.sleep(0.3)
                            self.page.keyboard.type(prompt, delay=random.randint(30, 80))
                    else:
                        # 标准 textarea
                        el.fill('', force=True)
                        time.sleep(0.2)
                        try:
                            el.type(prompt, delay=random.randint(50, 100))
                        except:
                            el.fill(prompt, force=True)
                    
                    time.sleep(1)
                    print(f"   ✅ 提示词已输入")
                    return True
                except:
                    continue
            
            print("   ❌ 未找到提示词输入框")
            return False
        except Exception as e:
            print(f"   ❌ 输入提示词失败: {e}")
            return False
    
    # ============================================================
    # 设置视频参数（复用 auto_vidu_complete 的逻辑）
    # ============================================================
    
    def set_video_parameters(self, aspect_ratio=None, resolution=None, duration=None, model=None):
        """设置视频参数，调用 auto_vidu_complete 中的函数"""
        try:
            from auto_vidu_complete import set_video_parameters
            set_video_parameters(self.page, aspect_ratio=aspect_ratio, resolution=resolution, duration=duration, model=model)
        except Exception as e:
            print(f"   ⚠️  设置参数失败: {e}")
    
    # ============================================================
    # 上传参考文件（复用 auto_vidu_complete 的逻辑）
    # ============================================================
    
    def upload_reference_file(self, file_path: str) -> bool:
        """上传参考文件"""
        try:
            from auto_vidu_complete import upload_reference_file
            return upload_reference_file(self.page, file_path)
        except Exception as e:
            print(f"   ❌ 上传参考文件失败: {e}")
            return False
    
    # ============================================================
    # 选择主体库角色（复用 auto_vidu_complete 的逻辑）
    # ============================================================
    
    def select_character(self, character_name: str) -> int:
        """从主体库选择角色"""
        try:
            from auto_vidu_complete import select_character_from_library
            names = [n.strip() for n in character_name.split(',') if n.strip()]
            print(f"   🎭 select_character: 解析后的名称列表 = {names}", flush=True)
            # 截图记录选择前的页面状态
            import os, time as _t
            SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
            self.page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_before_char_select_{int(_t.time())}.png'))
            result = select_character_from_library(self.page, names)
            print(f"   🎭 select_character: 返回结果 = {result}", flush=True)
            return result
        except Exception as e:
            import traceback
            print(f"   ⚠️  选择角色失败: {e}", flush=True)
            traceback.print_exc()
            return 0

    
    # ============================================================
    # 点击创作按钮
    # ============================================================
    
    def click_create(self) -> bool:
        """点击创作按钮"""
        print("   🚀 点击创作按钮...")
        
        try:
            # 记录当前视频数量
            try:
                self._last_video_count = len(self.page.locator('video').all())
            except:
                self._last_video_count = 0
            
            # 用 JS 查找并点击创作按钮
            result = self.page.evaluate("""
                () => {
                    const buttons = document.querySelectorAll('button');
                    for (const btn of buttons) {
                        if (btn.textContent.includes('创作')) {
                            const rect = btn.getBoundingClientRect();
                            if (rect.left < 500 && rect.width > 50) {
                                // 检查是否 disabled
                                const isDisabled = btn.disabled || 
                                    btn.getAttribute('disabled') !== null ||
                                    window.getComputedStyle(btn).opacity < 0.5;
                                if (!isDisabled) {
                                    btn.click();
                                    return { clicked: true, text: btn.textContent.trim().substring(0, 20) };
                                }
                                return { clicked: false, disabled: true, text: btn.textContent.trim().substring(0, 20) };
                            }
                        }
                    }
                    return { clicked: false, notFound: true };
                }
            """)
            
            if result and result.get('clicked'):
                print(f"   ✅ 已点击创作按钮: {result.get('text', '')}")
                time.sleep(2)
                return True
            
            if result and result.get('disabled'):
                # 按钮禁用，等待变为可用
                print("   ⚠️  创作按钮禁用，等待...")
                for i in range(15):
                    time.sleep(1)
                    clicked = self.page.evaluate("""
                        () => {
                            const buttons = document.querySelectorAll('button');
                            for (const btn of buttons) {
                                if (btn.textContent.includes('创作')) {
                                    const rect = btn.getBoundingClientRect();
                                    if (rect.left < 500 && rect.width > 50 && !btn.disabled) {
                                        btn.click();
                                        return true;
                                    }
                                }
                            }
                            return false;
                        }
                    """)
                    if clicked:
                        print(f"   ✅ 创作按钮已可用并点击（等待 {i+1}s）")
                        time.sleep(2)
                        return True
                print("   ❌ 创作按钮一直禁用")
                return False
            
            # 备用：Playwright locator
            try:
                btn = self.page.locator('button:has-text("创作"):visible').first
                if btn.is_visible(timeout=3000):
                    btn.click(timeout=5000, force=True)
                    print("   ✅ 已点击创作按钮（Playwright）")
                    time.sleep(2)
                    return True
            except:
                pass
            
            print("   ❌ 未找到创作按钮")
            return False
            
        except Exception as e:
            print(f"   ❌ 点击创作失败: {e}")
            return False
    
    # ============================================================
    # 提交生成（仅 UI 操作，需要浏览器锁）
    # ============================================================
    
    def submit_generate(
        self,
        prompt: str,
        tool_type: str = 'text2video',
        model: str = None,
        aspect_ratio: str = None,
        resolution: str = None,
        duration: str = None,
        reference_file: str = None,
        character_name: str = None,
    ) -> dict:
        """
        仅执行 UI 操作提交生成任务，不等待结果。
        
        Returns:
            {'success': True, 'initial_video_count': N}
            或 {'success': False, 'error': '...'}
        """
        print(f"\n{'='*60}", flush=True)
        print(f"  🎬 Vidu 提交生成（并发模式）", flush=True)
        print(f"{'='*60}", flush=True)
        print(f"   工具: {tool_type}", flush=True)
        if model:
            print(f"   模型: {model}", flush=True)
        print(f"   提示词: {prompt[:80]}...", flush=True)
        
        try:
            # 整个 submit 过程需要页面锁（UI 操作不可并发）
            print(f"   🔒 等待 _page_lock...", flush=True)
            with self._page_lock:
                print(f"   🔓 获取到 _page_lock", flush=True)
                return self._submit_generate_impl(
                    prompt=prompt, tool_type=tool_type, model=model,
                    aspect_ratio=aspect_ratio, resolution=resolution,
                    duration=duration, reference_file=reference_file,
                    character_name=character_name,
                )
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def _submit_generate_impl(
        self,
        prompt: str,
        tool_type: str = 'text2video',
        model: str = None,
        aspect_ratio: str = None,
        resolution: str = None,
        duration: str = None,
        reference_file: str = None,
        character_name: str = None,
    ) -> dict:
        """submit_generate 的内部实现（调用时已持有 _page_lock）"""
        try:
            # 1. 导航到对应页面（多次生成时刷新页面以清空旧内容）
            print(f"   [STEP 1] 开始导航到 {tool_type} 页面...", flush=True)
            self._ensure_tool_page(tool_type, force_reload=True)
            print(f"   [STEP 1] ✅ 页面导航完成，当前URL: {self.page.url[:80]}", flush=True)
            time.sleep(2)
            
            # 等待输入框加载
            print(f"   [STEP 2] 等待输入框加载 (tool_type={tool_type})...", flush=True)
            try:
                if tool_type == 'ref2video':
                    self.page.wait_for_selector('div.ProseMirror[contenteditable="true"]:visible, div[contenteditable="true"]:visible', timeout=10000)
                    print("   [STEP 2] ✅ 检测到 contenteditable 编辑器", flush=True)
                else:
                    self.page.wait_for_selector('textarea:visible', timeout=10000)
                    print("   [STEP 2] ✅ 检测到 textarea", flush=True)
            except Exception as e:
                print(f"   [STEP 2] ⚠️  输入框加载超时: {e}", flush=True)
                print("   继续尝试...", flush=True)
            
            time.sleep(1)
            
            # 2. 关闭弹窗
            if tool_type != 'ref2video':
                print("   [STEP 3] 🧹 准备关闭弹窗...", flush=True)
                try:
                    from auto_vidu_complete import close_popups_and_blockers
                    close_popups_and_blockers(self.page)
                    print("   [STEP 3] ✅ 弹窗处理完成", flush=True)
                except Exception as e:
                    print(f"   [STEP 3] ⚠️  弹窗处理异常: {e}", flush=True)
            
            # 3. 上传参考文件（ref2video）
            print(f"   [STEP 4] 📋 参数: tool_type={tool_type}, reference_file={reference_file}, character_name={character_name}", flush=True)
            if tool_type == 'ref2video' and reference_file:
                if not self.upload_reference_file(reference_file):
                    print("   ⚠️  参考文件上传失败，继续...")
                time.sleep(1)
            elif tool_type == 'ref2video' and character_name:
                print(f"   🎭 准备从主体库选择角色: {character_name}")
                result_count = self.select_character(character_name)
                print(f"   🎭 主体选择完成，成功数量: {result_count}")
                time.sleep(1)
            else:
                print(f"   ℹ️ 跳过主体选择（tool_type={tool_type}, has_ref={bool(reference_file)}, has_char={bool(character_name)}）")
            
            # 4.5 清空之前的提示词（作为额外保险，页面刷新后通常已是干净状态）
            # 注意：STEP 1 已通过 force_reload=True 刷新了页面，通常不需要再清空
            # ⚠️ ref2video 模式下，主体以 chip 形式嵌入编辑器中，绝不能清空编辑器！
            if tool_type != 'ref2video':
                print(f"   [STEP 4.5] 🧹 检查并清空残留提示词...", flush=True)
                self.clear_previous_prompt(tool_type)
                print(f"   [STEP 4.5] ✅ 清空检查完成", flush=True)
            else:
                print(f"   [STEP 4.5] ℹ️ ref2video 模式，跳过清空（主体 chip 在编辑器中）", flush=True)
            
            # 5. 输入提示词
            print(f"   [STEP 5] 📝 输入提示词...", flush=True)
            if not self.input_prompt(prompt, tool_type):
                return {'success': False, 'error': '输入提示词失败'}
            print(f"   [STEP 5] ✅ 提示词输入完成", flush=True)
            
            # 5. 设置视频参数
            print(f"   [STEP 6] ⚙️ 设置视频参数...", flush=True)
            self.set_video_parameters(
                aspect_ratio=aspect_ratio,
                resolution=resolution,
                duration=duration,
                model=model,
            )
            
            print(f"   [STEP 6] ✅ 视频参数设置完成", flush=True)
            
            # 6. 记录当前视频数量
            try:
                initial_video_count = len(self.page.locator('video').all())
            except:
                initial_video_count = 0
            print(f"   [STEP 7] 当前视频数: {initial_video_count}", flush=True)
            
            # 7. 点击创作
            print(f"   [STEP 8] 🖱️ 点击创作按钮...", flush=True)
            if not self.click_create():
                return {'success': False, 'error': '点击创作按钮失败'}
            
            # 8. 验证是否触发了生成
            generation_triggered = False
            for i in range(10):
                for indicator in [':has-text("排队中")', ':has-text("生成中")', ':has-text("预计等待")']:
                    try:
                        el = self.page.locator(indicator).first
                        if el.is_visible(timeout=1000):
                            generation_triggered = True
                            break
                    except:
                        continue
                if generation_triggered:
                    break
                time.sleep(2)
            
            if not generation_triggered:
                print("   [STEP 9] ⚠️  未检测到生成触发标识，但继续...", flush=True)
            else:
                print("   [STEP 9] ✅ 检测到生成已触发", flush=True)
            
            # 生成任务 ID（用时间戳，因为 Vidu 没有返回 history_id）
            task_key = f"vidu_{int(time.time())}_{random.randint(1000, 9999)}"
            self._pending_tasks[task_key] = {
                'status': 'generating',
                'initial_video_count': initial_video_count,
                'video_url': None,
            }
            
            print(f"   ✅ 提交成功，task_key={task_key}, 初始视频数={initial_video_count}", flush=True)
            return {'success': True, 'task_key': task_key, 'initial_video_count': initial_video_count}
        
        except Exception as e:
            import traceback
            print(f"   ❌ _submit_generate_impl 异常: {e}", flush=True)
            traceback.print_exc()
            import sys; sys.stdout.flush(); sys.stderr.flush()
            return {'success': False, 'error': str(e)}

    
    # ============================================================
    # 轮询结果（不需要浏览器锁，可并发）
    # ============================================================
    
    def poll_result(self, task_key: str = '', initial_video_count: int = 0, max_wait: int = 900, save_path: str = None) -> dict:
        """
        轮询生成结果。
        
        通过检测页面上"排队中/生成中"状态消失 + 新增视频元素来判断完成。
        每次 DOM 查询都获取 _page_lock 短锁，查询完立即释放，
        这样不会阻塞下一个任务的 submit_generate。
        
        Returns:
            {'success': True, 'video_url': '...', 'video_path': '...'}
            或 {'success': False, 'error': '...'}
        """
        print(f"\n⏳ Vidu 轮询结果（最长 {max_wait}s）...", flush=True)
        if task_key:
            print(f"   📍 追踪 task_key: {task_key}", flush=True)
        
        start_time = time.time()
        poll_interval = 8
        
        # 先等几秒让页面更新
        time.sleep(5)
        
        generating_indicators = [
            ':has-text("排队中")',
            ':has-text("生成中")',
            ':has-text("预计等待")',
            ':has-text("队列中")',
            ':has-text("处理中")',
        ]
        
        while time.time() - start_time < max_wait:
            elapsed = int(time.time() - start_time)
            
            # 短锁内检查页面状态
            check_result = self._poll_check_page_status(generating_indicators, initial_video_count)
            
            if check_result['status'] == 'generating':
                # 还在生成中，继续等待
                if elapsed > 0 and elapsed % 60 == 0:
                    indicator = check_result.get('indicator', '')
                    print(f"   ⏳ 已等待 {elapsed}s，仍在生成中... (匹配指标: {indicator})")
            elif check_result['status'] == 'failed':
                return {'success': False, 'error': check_result.get('error', '生成失败')}
            elif check_result['status'] == 'done':
                # 生成完成，获取视频 URL
                print(f"   ✅ 生成完成 ({elapsed}s)，获取视频 URL...")
                time.sleep(3)
                
                # 短锁内获取视频 URL
                with self._page_lock:
                    video_url = self._get_video_url(initial_video_count)
                
                if video_url:
                    # 下载不需要锁
                    if save_path:
                        if download_video(video_url, save_path):
                            return {'success': True, 'video_path': save_path, 'video_url': video_url, 'task_key': task_key}
                        else:
                            return {'success': False, 'error': '下载视频失败', 'video_url': video_url}
                    return {'success': True, 'video_url': video_url, 'task_key': task_key}
                else:
                    # 可能还没渲染完，再等一会
                    time.sleep(5)
                    with self._page_lock:
                        video_url = self._get_video_url(initial_video_count)
                    if video_url:
                        if save_path:
                            if download_video(video_url, save_path):
                                return {'success': True, 'video_path': save_path, 'video_url': video_url, 'task_key': task_key}
                        return {'success': True, 'video_url': video_url, 'task_key': task_key}
                    
                    print(f"   ⚠️  二次尝试仍未找到视频 URL")
                    # 截图辅助调试
                    try:
                        self.page.screenshot(path=os.path.join(SCRIPT_DIR, f'debug_no_video_url_{int(time.time())}.png'))
                    except:
                        pass
                    return {'success': False, 'error': '未找到视频 URL'}
            
            time.sleep(poll_interval)
        
        return {'success': False, 'error': f'等待超时 ({max_wait}s)'}
    
    def _poll_check_page_status(self, generating_indicators: list, initial_video_count: int) -> dict:
        """
        在短锁内检查页面生成状态。
        
        Returns:
            {'status': 'generating'} - 还在生成中
            {'status': 'failed', 'error': '...'} - 生成失败
            {'status': 'done'} - 生成完成
        """
        with self._page_lock:
            # 检查是否还在生成中
            still_generating = False
            matched_indicator = ''
            check_errors = 0
            for indicator in generating_indicators:
                try:
                    el = self.page.locator(indicator).first
                    if el.is_visible(timeout=2000):
                        still_generating = True
                        matched_indicator = indicator
                        break
                except Exception as e:
                    error_msg = str(e)
                    if 'cannot switch to a different thread' in error_msg or 'thread' in error_msg.lower():
                        print(f"   ❌ [poll] 线程错误: {error_msg[:80]}", flush=True)
                        return {'status': 'generating', 'indicator': f'线程错误(重试中)'}
                    check_errors += 1
                    continue
            
            # 如果所有检查都报错，可能是页面访问有问题，不要误判为完成
            if not still_generating and check_errors >= len(generating_indicators):
                print(f"   ⚠️  [poll] 所有指标检查都失败 ({check_errors}个错误)，视为仍在生成", flush=True)
                return {'status': 'generating', 'indicator': f'检查异常({check_errors}错误)'}
            
            if still_generating:
                # 安全检查：即使生成指标仍可见，如果页面上已经出现新视频，
                # 说明可能是其他任务/历史记录的指标文字导致误判
                try:
                    current_video_count = self.page.evaluate("() => document.querySelectorAll('video').length")
                    if initial_video_count > 0 and current_video_count > initial_video_count:
                        print(f"   🎥 检测到新视频 ({current_video_count} > {initial_video_count})，虽然仍有生成指标: {matched_indicator}")
                        return {'status': 'done'}
                except:
                    pass
                return {'status': 'generating', 'indicator': matched_indicator}
            
            # 检查失败标识
            for fail_text in ['生成失败', '任务失败']:
                try:
                    el = self.page.locator(f':has-text("{fail_text}")').first
                    if el.is_visible(timeout=1000):
                        return {'status': 'failed', 'error': f'页面显示: {fail_text}'}
                except:
                    continue
            
            # 额外验证：检查页面上的视频数量（辅助判断）
            try:
                video_count = self.page.evaluate("() => document.querySelectorAll('video').length")
                print(f"   📊 生成指标消失，页面视频数量: {video_count} (初始: {initial_video_count})")
            except:
                pass
            
            return {'status': 'done'}
    
    def _get_video_url(self, initial_video_count: int = 0) -> str:
        """从页面获取最新生成的视频 URL"""
        try:
            video_info = self.page.evaluate("""
                () => {
                    const videos = document.querySelectorAll('video');
                    const results = [];
                    for (const video of videos) {
                        const rect = video.getBoundingClientRect();
                        const src = video.src || video.currentSrc || '';
                        let sourceSrc = '';
                        const sourceEl = video.querySelector('source');
                        if (sourceEl) sourceSrc = sourceEl.src || '';
                        
                        // 也检查 data-src 或 poster
                        const dataSrc = video.getAttribute('data-src') || '';
                        const poster = video.poster || '';
                        
                        results.push({
                            src: src,
                            sourceSrc: sourceSrc,
                            dataSrc: dataSrc,
                            poster: poster,
                            x: Math.round(rect.left),
                            y: Math.round(rect.top),
                            width: Math.round(rect.width),
                            height: Math.round(rect.height),
                            visible: rect.width > 0 && rect.height > 0,
                        });
                    }
                    
                    // 同时查找页面中的下载链接
                    const downloadLinks = [];
                    const links = document.querySelectorAll('a[download], a[href*=".mp4"]');
                    for (const link of links) {
                        downloadLinks.push(link.href || '');
                    }
                    
                    return { total: videos.length, videos: results, downloadLinks: downloadLinks };
                }
            """)
            
            if not video_info:
                print("   ⚠️  _get_video_url: 页面没有返回视频信息")
                return ''
            
            total = video_info.get('total', 0)
            videos = video_info.get('videos', [])
            download_links = video_info.get('downloadLinks', [])
            
            print(f"   🎥 视频元素数量: {total} (初始: {initial_video_count})")
            for i, v in enumerate(videos):
                src = v.get('src', '') or v.get('sourceSrc', '')
                print(f"      [{i}] src={src[:80] if src else '(空)'} x={v.get('x')} y={v.get('y')} visible={v.get('visible')}")
            if download_links:
                print(f"   📥 下载链接: {download_links}")
            
            # 从下载链接获取
            for dl in download_links:
                if dl and '.mp4' in dl and 'blob:' not in dl:
                    print(f"   ✅ 使用下载链接: {dl[:80]}")
                    return dl
            
            # 如果有新增视频
            if total > initial_video_count and initial_video_count > 0:
                for v in videos:
                    src = v.get('src', '') or v.get('sourceSrc', '')
                    if src and 'blob:' not in src and v.get('visible'):
                        return src
            
            # 取右侧面板最上面的视频（最新的）
            right_videos = [v for v in videos if v.get('x', 0) > 300 and v.get('visible')]
            right_videos.sort(key=lambda v: v.get('y', 9999))
            if right_videos:
                src = right_videos[0].get('src', '') or right_videos[0].get('sourceSrc', '')
                if src and 'blob:' not in src:
                    return src
            
            # 从页面源码提取 mp4 URL
            content = self.page.content()
            mp4_urls = re.findall(r'https?://[^\s<>"\']+?\.mp4[^\s<>"\']*', content)
            if mp4_urls:
                unique_urls = list(dict.fromkeys(mp4_urls))
                print(f"   🔗 从页面源码找到 {len(unique_urls)} 个 mp4 URL")
                for u in unique_urls[-3:]:
                    print(f"      {u[:100]}")
                return unique_urls[-1]
            
            # 尝试从 Performance API 获取视频请求 URL
            try:
                perf_urls = self.page.evaluate("""
                    () => {
                        const entries = performance.getEntriesByType('resource');
                        const videoUrls = [];
                        for (const entry of entries) {
                            if (entry.name.includes('.mp4') || entry.name.includes('video') || entry.name.includes('media')) {
                                videoUrls.push(entry.name);
                            }
                        }
                        return videoUrls;
                    }
                """)
                if perf_urls:
                    print(f"   🔗 从 Performance API 找到 {len(perf_urls)} 个视频 URL")
                    for u in perf_urls:
                        print(f"      {u[:100]}")
                    # 选最后一个 mp4 URL
                    mp4_perf = [u for u in perf_urls if '.mp4' in u]
                    if mp4_perf:
                        return mp4_perf[-1]
                    # 没有 mp4 就选最后一个视频相关 URL
                    if perf_urls:
                        return perf_urls[-1]
            except Exception as e:
                print(f"   ⚠️  Performance API 查询失败: {e}")
            
            # 最后尝试：如果有 blob URL 的视频，截图并返回空（让上层知道）
            blob_videos = [v for v in videos if 'blob:' in (v.get('src', '') or v.get('sourceSrc', '')) and v.get('visible')]
            if blob_videos:
                print(f"   ⚠️  仅找到 blob URL 视频 ({len(blob_videos)} 个)，无法直接下载")
                print(f"   💡 尝试从页面提取实际视频地址...")
                # 尝试从 Vidu 页面的内部状态获取
                try:
                    vidu_urls = self.page.evaluate("""
                        () => {
                            // 查找所有包含视频 URL 的元素属性
                            const patterns = [];
                            const allEls = document.querySelectorAll('*');
                            for (const el of allEls) {
                                for (const attr of el.attributes) {
                                    if (attr.value && typeof attr.value === 'string' && 
                                        (attr.value.includes('.mp4') || attr.value.includes('vidu')) && 
                                        attr.value.startsWith('http')) {
                                        patterns.push(attr.value);
                                    }
                                }
                            }
                            // 也检查 __NEXT_DATA__ 等框架数据
                            const nextData = document.querySelector('#__NEXT_DATA__');
                            if (nextData) {
                                const text = nextData.textContent || '';
                                const urlMatches = text.match(/https?:\\/\\/[^"'\\s]+?\\.mp4[^"'\\s]*/g);
                                if (urlMatches) patterns.push(...urlMatches);
                            }
                            return [...new Set(patterns)];
                        }
                    """)
                    if vidu_urls:
                        print(f"   🔗 从页面属性找到 {len(vidu_urls)} 个 URL")
                        for u in vidu_urls:
                            print(f"      {u[:100]}")
                        return vidu_urls[-1]
                except Exception as e:
                    print(f"   ⚠️  页面属性查询失败: {e}")
            
            print("   ❌ 所有方法均未找到可下载的视频 URL")
            
        except Exception as e:
            print(f"   ⚠️  获取视频 URL 失败: {e}")
        
        return ''
    
    # ============================================================
    # 完整生成流程（兼容旧接口，串行模式）
    # ============================================================
    
    def generate(
        self,
        prompt: str,
        tool_type: str = 'text2video',
        model: str = None,
        aspect_ratio: str = None,
        resolution: str = None,
        duration: str = None,
        reference_file: str = None,
        character_name: str = None,
        save_path: str = None,
        max_wait: int = 900,
    ) -> dict:
        """完整的视频生成流程（串行模式，兼容旧接口）"""
        submit_result = self.submit_generate(
            prompt=prompt,
            tool_type=tool_type,
            model=model,
            aspect_ratio=aspect_ratio,
            resolution=resolution,
            duration=duration,
            reference_file=reference_file,
            character_name=character_name,
        )
        
        if not submit_result.get('success'):
            return submit_result
        
        return self.poll_result(
            task_key=submit_result.get('task_key', ''),
            initial_video_count=submit_result.get('initial_video_count', 0),
            max_wait=max_wait,
            save_path=save_path,
        )


# ============================================================
# 命令行入口
# ============================================================

def main():
    parser = argparse.ArgumentParser(description='Vidu 视频生成自动化 V2（并发架构）')
    parser.add_argument('prompt', help='视频提示词')
    parser.add_argument('--save-path', required=True, help='视频保存路径')
    parser.add_argument('--tool-type', default='text2video', choices=['text2video', 'img2video', 'ref2video'])
    parser.add_argument('--model', default=None, help='模型名称')
    parser.add_argument('--aspect-ratio', default=None, help='宽高比')
    parser.add_argument('--resolution', default=None, help='分辨率')
    parser.add_argument('--duration', default=None, help='时长')
    parser.add_argument('--reference-file', default=None, help='参考文件路径')
    parser.add_argument('--character-name', default=None, help='主体库角色名称')
    parser.add_argument('--max-wait', default='10', help='最大等待时间（分钟）')
    parser.add_argument('--profile', default=None, help='浏览器 profile 目录')
    
    args = parser.parse_args()
    
    max_wait = int(args.max_wait)
    if max_wait <= 30:
        max_wait = max_wait * 60
    
    auto = ViduAutomation(profile_dir=args.profile or VIDU_PROFILE_DIR)
    
    if not auto.start():
        result = {"success": False, "error": "无法启动浏览器"}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1
    
    try:
        if not auto.check_login():
            result = {"success": False, "error": "未登录"}
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 1
        
        result = auto.generate(
            prompt=args.prompt,
            tool_type=args.tool_type,
            model=args.model,
            aspect_ratio=args.aspect_ratio,
            resolution=args.resolution,
            duration=args.duration,
            reference_file=args.reference_file,
            character_name=args.character_name,
            save_path=args.save_path,
            max_wait=max_wait,
        )
        
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result.get('success') else 1
    
    except Exception as e:
        result = {"success": False, "error": str(e)}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1
    finally:
        auto.stop()


if __name__ == '__main__':
    sys.exit(main())
