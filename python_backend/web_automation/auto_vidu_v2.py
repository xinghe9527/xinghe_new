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

# ============================================================
# 常量配置
# ============================================================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
USER_DATA_ROOT = os.path.join(PROJECT_ROOT, 'python_backend', 'user_data')
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
    
    def _ensure_tool_page(self, tool_type: str):
        """确保当前在指定工具类型的页面"""
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
            print(f"   🌐 导航到 Vidu {tool_type} 页面...")
            self.page.goto(target_url, wait_until='domcontentloaded', timeout=30000)
            time.sleep(3)

    
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
            return select_character_from_library(self.page, names)
        except Exception as e:
            print(f"   ⚠️  选择角色失败: {e}")
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
        print(f"\n{'='*60}")
        print(f"  🎬 Vidu 提交生成（并发模式）")
        print(f"{'='*60}")
        print(f"   工具: {tool_type}")
        if model:
            print(f"   模型: {model}")
        print(f"   提示词: {prompt[:80]}...")
        
        try:
            # 整个 submit 过程需要页面锁（UI 操作不可并发）
            with self._page_lock:
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
            # 1. 导航到对应页面
            self._ensure_tool_page(tool_type)
            time.sleep(2)
            
            # 等待输入框加载
            try:
                if tool_type == 'ref2video':
                    self.page.wait_for_selector('div.ProseMirror[contenteditable="true"]:visible, div[contenteditable="true"]:visible', timeout=10000)
                else:
                    self.page.wait_for_selector('textarea:visible', timeout=10000)
            except:
                print("   ⚠️  输入框加载超时，继续尝试...")
            
            time.sleep(1)
            
            # 2. 关闭弹窗
            if tool_type != 'ref2video':
                try:
                    from auto_vidu_complete import close_popups_and_blockers
                    close_popups_and_blockers(self.page)
                except:
                    pass
            
            # 3. 上传参考文件（ref2video）
            if tool_type == 'ref2video' and reference_file:
                if not self.upload_reference_file(reference_file):
                    print("   ⚠️  参考文件上传失败，继续...")
                time.sleep(1)
            elif tool_type == 'ref2video' and character_name:
                self.select_character(character_name)
                time.sleep(1)
            
            # 4. 输入提示词
            if not self.input_prompt(prompt, tool_type):
                return {'success': False, 'error': '输入提示词失败'}
            
            # 5. 设置视频参数
            self.set_video_parameters(
                aspect_ratio=aspect_ratio,
                resolution=resolution,
                duration=duration,
                model=model,
            )
            
            # 6. 记录当前视频数量
            try:
                initial_video_count = len(self.page.locator('video').all())
            except:
                initial_video_count = 0
            
            # 7. 点击创作
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
                print("   ⚠️  未检测到生成触发标识，但继续...")
            
            # 生成任务 ID（用时间戳，因为 Vidu 没有返回 history_id）
            task_key = f"vidu_{int(time.time())}_{random.randint(1000, 9999)}"
            self._pending_tasks[task_key] = {
                'status': 'generating',
                'initial_video_count': initial_video_count,
                'video_url': None,
            }
            
            print(f"   ✅ 提交成功，task_key={task_key}, 初始视频数={initial_video_count}")
            return {'success': True, 'task_key': task_key, 'initial_video_count': initial_video_count}
        
        except Exception as e:
            return {'success': False, 'error': str(e)}

    
    # ============================================================
    # 轮询结果（不需要浏览器锁，可并发）
    # ============================================================
    
    def poll_result(self, task_key: str = '', initial_video_count: int = 0, max_wait: int = 600, save_path: str = None) -> dict:
        """
        轮询生成结果。
        
        通过检测页面上"排队中/生成中"状态消失 + 新增视频元素来判断完成。
        每次 DOM 查询都获取 _page_lock 短锁，查询完立即释放，
        这样不会阻塞下一个任务的 submit_generate。
        
        Returns:
            {'success': True, 'video_url': '...', 'video_path': '...'}
            或 {'success': False, 'error': '...'}
        """
        print(f"\n⏳ Vidu 轮询结果（最长 {max_wait}s）...")
        if task_key:
            print(f"   📍 追踪 task_key: {task_key}")
        
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
                pass
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
                    
                    return {'success': False, 'error': '未找到视频 URL'}
            
            if elapsed > 0 and elapsed % 30 == 0:
                print(f"   ⏳ 已等待 {elapsed}s...")
            
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
            for indicator in generating_indicators:
                try:
                    el = self.page.locator(indicator).first
                    if el.is_visible(timeout=2000):
                        still_generating = True
                        break
                except:
                    continue
            
            if still_generating:
                return {'status': 'generating'}
            
            # 检查失败标识
            for fail_text in ['生成失败', '任务失败']:
                try:
                    el = self.page.locator(f':has-text("{fail_text}")').first
                    if el.is_visible(timeout=1000):
                        return {'status': 'failed', 'error': f'页面显示: {fail_text}'}
                except:
                    continue
            
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
                        results.push({
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
            
            if not video_info:
                return ''
            
            total = video_info.get('total', 0)
            videos = video_info.get('videos', [])
            
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
                return list(dict.fromkeys(mp4_urls))[-1]
            
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
        max_wait: int = 600,
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
