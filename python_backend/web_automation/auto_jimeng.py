#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
即梦（Jimeng）视频生成自动化脚本

架构（参考字字动画插件）：
1. 通过 CDP 连接到常驻浏览器（Edge/Chrome，端口 9222）
2. 或通过 Playwright persistent context 打开浏览器
3. 在即梦网页上操作 UI：选模型 → 上传图片 → 输入提示词 → 点生成
4. 监听网络响应获取生成结果
5. 下载视频到本地

关键设计：
- 浏览器常驻，不每次启动/关闭
- 支持批量任务（通过锁机制排队）
- 通过网络监听精准获取生成结果

用法：
    python auto_jimeng.py "提示词" --save-path output.mp4 --tool-type video_gen
    python auto_jimeng.py "提示词" --save-path output.mp4 --tool-type image_gen
    python auto_jimeng.py "提示词" --save-path output.mp4 --tool-type agent
"""

import sys
import os
import io
import json
import time
import argparse
import requests
import re
from pathlib import Path
from datetime import datetime

# 确保标准输出使用 UTF-8 编码（Windows 兼容）
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
JIMENG_PROFILE_DIR = os.path.join(USER_DATA_ROOT, 'jimeng_profile')

# 即梦 URL
JIMENG_BASE_URL = 'https://jimeng.jianying.com'
JIMENG_VIDEO_URL = f'{JIMENG_BASE_URL}/ai-tool/home?type=video'
JIMENG_IMAGE_URL = f'{JIMENG_BASE_URL}/ai-tool/home?type=image'
JIMENG_AGENT_URL = f'{JIMENG_BASE_URL}/ai-tool/home?type=agentic'

# 工具类型 → URL 映射
JIMENG_TOOL_URLS = {
    'video_gen': JIMENG_VIDEO_URL,
    'image_gen': JIMENG_IMAGE_URL,
    'agent': JIMENG_AGENT_URL,
}

# CDP 端口
CDP_PORT = 9222


# ============================================================
# 即梦页面自动化类
# ============================================================

class JimengAutomation:
    """
    即梦网页 UI 自动化
    
    通过 Playwright 操作即梦网页，实现视频生成。
    支持两种连接方式：
    1. CDP attach：连接到已运行的浏览器（推荐，速度快）
    2. Persistent context：启动新浏览器（首次使用）
    """
    
    def __init__(self, profile_dir: str = None, cdp_port: int = CDP_PORT):
        self.profile_dir = profile_dir or JIMENG_PROFILE_DIR
        self.cdp_port = cdp_port
        self.pw = None
        self.browser = None
        self.context = None
        self.page = None
        self._started = False
        self._use_cdp = False
        # 并发任务追踪：{history_id: {'status': ..., 'video_url': ..., 'error': ...}}
        self._pending_tasks = {}
        # 最近一次生成请求的响应（用于提取 history_id）
        self._last_generate_response = None
        # 兼容旧逻辑
        self._generate_response = None
        self._video_responses = []
        # 页面操作锁（线程级），保护 self.page 的 DOM 访问
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
                from browser_manager import BrowserManager, find_system_browser, get_browser_name
                
                print("   🌐 尝试使用系统浏览器（Edge/Chrome）...")
                self._browser_mgr = BrowserManager(
                    cdp_port=self.cdp_port,
                    profile_name='jimeng',
                )
                self.page = self._browser_mgr.connect_or_launch(target_url=JIMENG_VIDEO_URL)
                self.browser = self._browser_mgr.browser
                self.context = self._browser_mgr.context
                self._use_cdp = True
                
                # 确保在视频生成页面
                self._ensure_video_page()
                
                # 注册网络监听
                self._setup_network_listener()
                
                self._started = True
                return True
                
            except Exception as mgr_err:
                print(f"   ⚠️  系统浏览器连接失败: {mgr_err}")
                print("   🔄 回退到 Playwright 内置浏览器...")
            
            # 方式2：回退到 Playwright persistent context（兼容）
            from playwright.sync_api import sync_playwright
            
            self.pw = sync_playwright().start()
            
            self.context = self.pw.chromium.launch_persistent_context(
                user_data_dir=self.profile_dir,
                headless=False,
                args=[
                    '--disable-gpu',
                    '--no-sandbox',
                    '--disable-blink-features=AutomationControlled',
                    '--start-maximized',
                ],
                viewport={'width': 1920, 'height': 1080},
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36',
                locale='zh-CN',
            )
            
            # 注入反检测脚本
            self.context.add_init_script("""
                Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
            """)
            
            if self.context.pages:
                self.page = self.context.pages[0]
            else:
                self.page = self.context.new_page()
            
            self._use_cdp = False
            
            # 确保在视频生成页面
            self._ensure_video_page()
            
            # 注册网络监听
            self._setup_network_listener()
            
            self._started = True
            return True
            
        except Exception as e:
            print(f"   ❌ 启动失败: {e}")
            self.stop()
            return False
    
    def stop(self):
        """关闭连接（不关闭浏览器本身）"""
        try:
            # 如果使用 BrowserManager，断开连接但保留浏览器
            if hasattr(self, '_browser_mgr') and self._browser_mgr:
                self._browser_mgr.disconnect()
            elif self._use_cdp and self.browser:
                # CDP 模式：只断开连接，不关闭浏览器
                self.browser.close()
            elif self.context and not self._use_cdp:
                # persistent context 模式：关闭浏览器
                self.context.close()
            if self.pw:
                self.pw.stop()
        except:
            pass
        self._started = False
    
    def _ensure_video_page(self):
        """确保当前在视频生成页面"""
        self._ensure_tool_page('video_gen')
    
    def _ensure_tool_page(self, tool_type: str):
        """确保当前在指定工具类型的页面
        
        tool_type: video_gen / image_gen / agent
        对应 URL:
          video_gen → https://jimeng.jianying.com/ai-tool/home?type=video
          image_gen → https://jimeng.jianying.com/ai-tool/home?type=image
          agent     → https://jimeng.jianying.com/ai-tool/home?type=agentic
        """
        # URL 中的 type 参数映射
        type_param_map = {
            'video_gen': 'video',
            'image_gen': 'image',
            'agent': 'agentic',
        }
        expected_type = type_param_map.get(tool_type, 'video')
        target_url = JIMENG_TOOL_URLS.get(tool_type, JIMENG_VIDEO_URL)
        
        current_url = self.page.url
        if 'jimeng.jianying.com' not in current_url or f'type={expected_type}' not in current_url:
            print(f"   🌐 导航到{tool_type}页面...")
            self.page.goto(target_url, wait_until='domcontentloaded', timeout=30000)
            time.sleep(3)
    
    def _switch_to_video_mode(self):
        """切换到视频生成模式

        即梦页面顶部工具栏左侧有一个创作类型按钮（如"视频生成 ∧"），
        点击后展开下拉菜单，包含：Agent 模式、图片生成、视频生成、数字人、配音生成、动作模仿
        """
        try:
            # 策略1：检查 URL 是否已经在视频模式
            if 'type=video' in self.page.url:
                # 检查工具栏上是否已显示"视频生成"
                video_mode_btn = self.page.query_selector('span.lv-select-view-value:has-text("视频生成")')
                if video_mode_btn and video_mode_btn.is_visible():
                    print("   ✅ 已在视频生成模式")
                    return

            # 策略2：查找顶部工具栏的创作类型下拉按钮（lv-select 组件）
            # 即梦用 Arco Design 的 lv-select，按钮显示当前模式名称
            type_selectors = self.page.query_selector_all('.lv-select')
            for sel in type_selectors:
                try:
                    if not sel.is_visible():
                        continue
                    text = sel.inner_text().strip()
                    # 找到包含创作类型的 select（可能显示"视频生成"、"图片生成"等）
                    if any(kw in text for kw in ['生成', 'Agent', '数字人', '模仿', '配音']):
                        if '视频生成' in text:
                            print("   ✅ 已在视频生成模式")
                            return
                        # 点击展开下拉
                        sel.click()
                        time.sleep(1)
                        # 在下拉列表中选择"视频生成"
                        video_option = self.page.query_selector('.lv-select-option:has-text("视频生成")')
                        if not video_option:
                            video_option = self.page.query_selector('[class*="option"]:has-text("视频生成")')
                        if video_option and video_option.is_visible():
                            video_option.click()
                            time.sleep(2)
                            print("   ✅ 已切换到视频生成模式")
                            return
                except:
                    continue

            # 策略3：直接查找底部模式栏（旧版 UI）
            video_option = self.page.query_selector(
                'div[class*="type-home-select-option-label"]:has-text("视频生成")'
            )
            if video_option:
                cls = video_option.evaluate('el => el.className')
                if 'active' not in cls:
                    print("   🔄 切换到视频生成模式...")
                    video_option.click()
                    time.sleep(2)
                else:
                    print("   ✅ 已在视频生成模式")
                return

            # 策略4：直接导航到视频生成 URL
            if 'type=video' not in self.page.url:
                print("   🔄 通过 URL 切换到视频生成模式...")
                self.page.goto(JIMENG_VIDEO_URL, wait_until='domcontentloaded', timeout=30000)
                time.sleep(3)

            print("   ✅ 视频生成模式就绪")

        except Exception as e:
            print(f"   ⚠️  切换视频模式: {e}")


    
    def _setup_network_listener(self):
        """设置网络监听，按 history_id 追踪多个并发任务的生成结果"""
        self._generate_response = None
        self._video_responses = []
        
        def on_response(response):
            url = response.url
            # 捕获生成请求的响应（包含 history_id）
            if '/aigc_draft/generate' in url or '/aigc/draft/generate' in url:
                try:
                    body = response.json()
                    self._generate_response = body
                    self._last_generate_response = body
                    # 从响应中提取 history_id，注册到待追踪任务
                    history_id = self._extract_history_id(body)
                    if history_id:
                        self._pending_tasks[history_id] = {
                            'status': 'generating',
                            'video_url': None,
                            'error': None,
                        }
                        print(f"   📡 捕获生成响应: ret={body.get('ret')}, history_id={history_id}")
                    else:
                        print(f"   📡 捕获生成响应: ret={body.get('ret')} (未提取到 history_id)")
                except:
                    pass
            # 捕获历史记录查询响应（用于获取视频 URL）
            elif '/get_history_by_ids' in url or '/get_aigc_history' in url:
                try:
                    body = response.json()
                    self._video_responses.append(body)
                    # 尝试将视频 URL 关联到对应的 history_id
                    self._match_video_to_task(body)
                except:
                    pass
        
        self.page.on('response', on_response)
    
    def _extract_history_id(self, generate_response: dict) -> str:
        """从生成请求的响应中提取 history_id"""
        try:
            if str(generate_response.get('ret', '')) != '0':
                return ''
            data = generate_response.get('data', {})
            # 路径1: data.history_id
            hid = data.get('history_id', '')
            if hid:
                return str(hid)
            # 路径2: data.draft_id
            did = data.get('draft_id', '')
            if did:
                return str(did)
            # 路径3: data.task_id
            tid = data.get('task_id', '')
            if tid:
                return str(tid)
            # 路径4: data.aigc_data.history_id
            aigc = data.get('aigc_data', {})
            if isinstance(aigc, dict):
                hid2 = aigc.get('history_id', '')
                if hid2:
                    return str(hid2)
        except:
            pass
        return ''
    
    def _match_video_to_task(self, history_response: dict):
        """将历史记录响应中的视频 URL 匹配到对应的待追踪任务"""
        try:
            if str(history_response.get('ret', '')) != '0':
                return
            data = history_response.get('data', {})
            
            # 遍历 history_list
            history_list = data.get('history_list', [])
            if isinstance(history_list, list):
                for history in history_list:
                    hid = str(history.get('history_id', ''))
                    if hid and hid in self._pending_tasks:
                        items = history.get('item_list', [])
                        for item in items:
                            video_url = item.get('video_info', {}).get('url', '')
                            if not video_url:
                                video_url = item.get('video_info', {}).get('download_url', '')
                            if video_url:
                                self._pending_tasks[hid]['status'] = 'success'
                                self._pending_tasks[hid]['video_url'] = video_url
                                print(f"   📡 任务 {hid} 视频就绪: {video_url[:80]}...")
                                return
                            # 检查是否失败
                            status = item.get('status', '')
                            if status in ('failed', 'error', 'rejected'):
                                self._pending_tasks[hid]['status'] = 'failed'
                                self._pending_tasks[hid]['error'] = item.get('fail_msg', '生成失败')
                                return
            
            # 路径2: data[history_id].item_list
            for key, val in data.items():
                if isinstance(val, dict) and 'item_list' in val:
                    if key in self._pending_tasks:
                        for item in val['item_list']:
                            video_url = item.get('video_info', {}).get('url', '')
                            if video_url:
                                self._pending_tasks[key]['status'] = 'success'
                                self._pending_tasks[key]['video_url'] = video_url
                                return
        except:
            pass

    # ============================================================
    # 检查登录状态
    # ============================================================
    
    def check_login(self) -> bool:
        """检查是否已登录"""
        try:
            # 检查页面上是否有登录相关的弹窗或按钮
            # 如果有"登录"按钮说明未登录
            login_btn = self.page.query_selector('text=登录')
            if login_btn:
                # 确认是登录按钮而不是其他包含"登录"的文字
                tag = login_btn.evaluate('el => el.tagName')
                if tag in ('BUTTON', 'A', 'SPAN'):
                    # 再确认一下，看看是否有用户头像（已登录的标志）
                    avatar = self.page.query_selector('img[class*="avatar"]')
                    if not avatar:
                        print("   ❌ 未登录")
                        return False
            
            # 检查是否有提示词输入框（已登录才能看到）
            textarea = self.page.query_selector('textarea[class*="prompt-textarea"]')
            if textarea:
                print("   ✅ 已登录（检测到提示词输入框）")
                return True
            
            # 兜底：通过 cookie 检查
            cookies = self.context.cookies([JIMENG_BASE_URL]) if not self._use_cdp else []
            for cookie in cookies:
                if cookie['name'] == 'sessionid' and cookie['value']:
                    print("   ✅ 已登录（检测到 sessionid cookie）")
                    return True
            
            # 如果有输入框，认为已登录
            textarea2 = self.page.query_selector('textarea')
            if textarea2:
                print("   ✅ 已登录（检测到输入框）")
                return True
            
            print("   ⚠️  无法确认登录状态")
            return True  # 默认认为已登录，让后续操作来验证
            
        except Exception as e:
            print(f"   ⚠️  检查登录异常: {e}")
            return True
    
    # ============================================================
    # 选择模型
    # ============================================================
    
    def select_model(self, model: str) -> bool:
        """选择视频生成模型
        
        即梦工具栏上有一个模型名称按钮（如"视频 3.0 Fast"），
        点击后展开下拉列表，包含所有可用模型：
        - Seedance 2.0 Fast
        - Seedance 2.0
        - 视频 3.5 Pro
        - 视频 3.0 Pro
        - 视频 3.0 Fast
        - 视频 3.0
        选中的模型右侧有 ✓ 标记。
        """
        print(f"   🤖 选择模型: {model}")
        
        # 模型名称映射（配置名 → 页面显示名）
        model_display_map = {
            'seedance-2.0': 'Seedance 2.0',
            'seedance-2.0-pro': 'Seedance 2.0',
            'seedance-2.0-fast': 'Seedance 2.0 Fast',
            'seedance-2.0-agent': '__AGENT_MODE__',  # 特殊：需要切换创作类型
            'jimeng-video-3.5-pro': '视频 3.5 Pro',
            'jimeng-video-3.0-pro': '视频 3.0 Pro',
            'jimeng-video-3.0-fast': '视频 3.0 Fast',
            'jimeng-video-3.0': '视频 3.0',
        }
        
        display_name = model_display_map.get(model, model)
        
        try:
            # Agent 模式特殊处理：需要切换创作类型而不是选模型
            if display_name == '__AGENT_MODE__':
                return self._switch_to_agent_mode()
            # 步骤1：找到工具栏上的模型按钮并点击展开下拉
            # 模型按钮在工具栏上，紧跟在创作类型（视频生成）后面
            # 它不是 lv-select，而是一个普通的可点击元素
            model_btn = self._find_model_button()
            if not model_btn:
                print(f"   ⚠️  未找到模型选择按钮，使用默认模型")
                return True
            
            # 检查当前选中的模型是否就是目标
            current_model_text = model_btn.inner_text().strip()
            if display_name in current_model_text:
                print(f"   ✅ 模型已选中: {display_name}")
                return True
            
            # 点击展开模型下拉列表
            model_btn.click()
            time.sleep(1)
            
            # 步骤2：在下拉列表中找到目标模型并点击
            # 下拉列表中每个模型项包含模型名称文字
            target_option = None
            
            # 查找包含目标模型名的可见元素
            candidates = self.page.query_selector_all(f'text="{display_name}"')
            for c in candidates:
                try:
                    if c.is_visible():
                        target_option = c
                        break
                except:
                    continue
            
            if not target_option:
                # 尝试模糊匹配（去掉空格等）
                all_visible_text = self.page.evaluate("""(targetName) => {
                    const els = document.querySelectorAll('*');
                    for (const el of els) {
                        if (el.children.length === 0 && el.offsetParent !== null) {
                            const text = el.innerText?.trim();
                            if (text && text.includes(targetName)) {
                                return {found: true, text: text};
                            }
                        }
                    }
                    return {found: false};
                }""", display_name)
                
                if all_visible_text.get('found'):
                    target_option = self.page.query_selector(f'text="{display_name}"')
            
            if target_option:
                target_option.click()
                time.sleep(1)
                print(f"   ✅ 已选择模型: {display_name}")
                return True
            else:
                # 关闭下拉（点击空白处）
                self.page.keyboard.press('Escape')
                time.sleep(0.5)
                print(f"   ⚠️  下拉列表中未找到 '{display_name}'，使用当前模型: {current_model_text}")
                return True
                
        except Exception as e:
            print(f"   ⚠️  选择模型失败: {e}")
            return True
    
    def _find_model_button(self):
        """查找工具栏上的模型选择按钮
        
        工具栏布局：[视频生成 ∧] [模型名称] [自定义 ∨] [16:9] [720P] [5s]
        模型按钮显示当前模型名（如"视频 3.0 Fast"、"Seedance 2.0"等）
        """
        # 已知的模型名称关键词
        model_keywords = ['Seedance', 'seedance', '视频 3', '视频 2', '即梦']
        
        # 方法1：在工具栏区域查找包含模型名的可点击元素
        # 工具栏通常在页面上方（y < 300）
        for kw in model_keywords:
            els = self.page.query_selector_all(f'text="{kw}"')
            for el in els:
                try:
                    if not el.is_visible():
                        continue
                    rect = el.bounding_box()
                    if not rect:
                        continue
                    # 工具栏元素应该在页面上方区域
                    if rect['y'] < 300:
                        # 找到包含这个文字的可点击父元素
                        clickable = el.evaluate("""el => {
                            let p = el;
                            for (let i = 0; i < 5; i++) {
                                if (!p) break;
                                const style = window.getComputedStyle(p);
                                if (style.cursor === 'pointer' || p.tagName === 'BUTTON' || p.onclick) {
                                    return true;
                                }
                                p = p.parentElement;
                            }
                            return false;
                        }""")
                        if clickable:
                            return el
                except:
                    continue
        
        return None
    
    def _switch_to_agent_mode(self) -> bool:
        """切换到 Agent 模式（Seedance 2.0 全能参考）
        
        Agent 模式是一个独立的创作类型，不在视频生成的模型下拉里。
        需要通过顶部工具栏的创作类型下拉切换到 "Agent 模式"。
        """
        print("   🤖 切换到 Agent 模式（全能参考）...")
        try:
            # 检查是否已经在 Agent 模式
            agent_val = self.page.query_selector('span.lv-select-view-value:has-text("Agent")')
            if agent_val and agent_val.is_visible():
                print("   ✅ 已在 Agent 模式")
                return True
            
            # 也检查 URL
            if 'type=agentic' in self.page.url:
                print("   ✅ 已在 Agent 模式")
                return True
            
            # 方法1：通过创作类型下拉切换
            type_selectors = self.page.query_selector_all('.lv-select')
            for sel in type_selectors:
                try:
                    if not sel.is_visible():
                        continue
                    text = sel.inner_text().strip()
                    if any(kw in text for kw in ['生成', 'Agent', '数字人', '模仿', '配音']):
                        sel.click()
                        time.sleep(1)
                        # 在下拉中选择 Agent 模式
                        agent_opt = self.page.query_selector('.lv-select-option:has-text("Agent")')
                        if not agent_opt:
                            agent_opt = self.page.query_selector('[class*="option"]:has-text("Agent")')
                        if agent_opt and agent_opt.is_visible():
                            agent_opt.click()
                            time.sleep(2)
                            print("   ✅ 已切换到 Agent 模式")
                            return True
                except:
                    continue
            
            # 方法2：通过 URL 直接导航
            agent_url = f'{JIMENG_BASE_URL}/ai-tool/home?type=agentic'
            print("   🔄 通过 URL 切换到 Agent 模式...")
            self.page.goto(agent_url, wait_until='domcontentloaded', timeout=30000)
            time.sleep(3)
            print("   ✅ Agent 模式就绪")
            return True
            
        except Exception as e:
            print(f"   ⚠️  切换 Agent 模式失败: {e}")
            return True
    
    # ============================================================
    # 设置方式（即梦视频生成的"自定义"下拉）
    # ============================================================
    
    def set_mode(self, mode: str) -> bool:
        """设置视频生成方式（自定义下拉：全能参考/首尾帧/智能多帧/主体参考）
        
        工具栏上有一个"自定义 ∨"或"全能参考 ∨"按钮，
        点击后展开下拉：全能参考、首尾帧、智能多帧、主体参考
        """
        # 方式 ID → 页面显示名
        mode_display_map = {
            'all_ref': '全能参考',
            'first_last_frame': '首尾帧',
            'smart_multi_frame': '智能多帧',
            'subject_ref': '主体参考',
        }
        display_name = mode_display_map.get(mode, mode)
        print(f"   🎯 设置方式: {display_name}")
        
        try:
            # 查找"自定义"下拉按钮（工具栏上，y < 300 区域）
            # 按钮可能显示"自定义"、"全能参考"、"首尾帧"等当前方式名
            mode_keywords = ['自定义', '全能参考', '首尾帧', '智能多帧', '主体参考']
            mode_btn = None
            
            for kw in mode_keywords:
                els = self.page.query_selector_all(f'text="{kw}"')
                for el in els:
                    try:
                        if not el.is_visible():
                            continue
                        rect = el.bounding_box()
                        if rect and rect['y'] < 300:
                            mode_btn = el
                            break
                    except:
                        continue
                if mode_btn:
                    break
            
            if not mode_btn:
                print(f"   ⚠️  未找到方式选择按钮")
                return True
            
            # 检查当前方式是否已是目标
            current_text = mode_btn.inner_text().strip()
            if display_name in current_text:
                print(f"   ✅ 方式已选中: {display_name}")
                return True
            
            # 点击展开下拉
            mode_btn.click()
            time.sleep(1)
            
            # 在下拉中找到目标方式
            target = self.page.query_selector(f'text="{display_name}"')
            if target and target.is_visible():
                target.click()
                time.sleep(1)
                print(f"   ✅ 已设置方式: {display_name}")
                return True
            else:
                # 关闭下拉
                self.page.keyboard.press('Escape')
                time.sleep(0.5)
                print(f"   ⚠️  下拉中未找到 '{display_name}'")
                return True
                
        except Exception as e:
            print(f"   ⚠️  设置方式失败: {e}")
            return True
    
    # ============================================================
    # 设置宽高比
    # ============================================================
    
    def set_aspect_ratio(self, aspect_ratio: str) -> bool:
        """设置宽高比"""
        print(f"   📐 设置宽高比: {aspect_ratio}")
        
        try:
            # 查找宽高比按钮
            ratio_el = self.page.query_selector(f'text="{aspect_ratio}"')
            if ratio_el:
                ratio_el.click()
                time.sleep(0.5)
                print(f"   ✅ 已设置宽高比: {aspect_ratio}")
                return True
            else:
                # 尝试点击宽高比区域展开选项
                ratio_btn = self.page.query_selector('button:has-text("16:9"), button:has-text("9:16"), button:has-text("1:1")')
                if ratio_btn:
                    ratio_btn.click()
                    time.sleep(0.5)
                    # 再找目标比例
                    target = self.page.query_selector(f'text="{aspect_ratio}"')
                    if target:
                        target.click()
                        time.sleep(0.5)
                        print(f"   ✅ 已设置宽高比: {aspect_ratio}")
                        return True
                
                print(f"   ⚠️  未找到宽高比选项 '{aspect_ratio}'")
                return True
                
        except Exception as e:
            print(f"   ⚠️  设置宽高比失败: {e}")
            return True
    
    # ============================================================
    # 设置时长
    # ============================================================
    
    def set_duration(self, duration: int) -> bool:
        """设置视频时长"""
        print(f"   ⏱️  设置时长: {duration}s")
        
        try:
            duration_text = f'{duration}s'
            duration_el = self.page.query_selector(f'text="{duration_text}"')
            if duration_el:
                duration_el.click()
                time.sleep(0.5)
                print(f"   ✅ 已设置时长: {duration_text}")
                return True
            else:
                print(f"   ⚠️  未找到时长选项 '{duration_text}'")
                return True
                
        except Exception as e:
            print(f"   ⚠️  设置时长失败: {e}")
            return True

    # ============================================================
    # 上传参考图片
    # ============================================================
    
    def upload_reference_image(self, file_path: str) -> bool:
        """上传参考图片（首帧/尾帧/参考图）"""
        print(f"   📤 上传参考图片: {os.path.basename(file_path)}")
        
        if not os.path.exists(file_path):
            print(f"   ❌ 文件不存在: {file_path}")
            return False
        
        try:
            # 查找文件上传 input（parent class 包含 reference-upload）
            file_inputs = self.page.query_selector_all('input[type="file"]')
            
            if not file_inputs:
                print("   ❌ 未找到文件上传元素")
                return False
            
            # 使用第一个可用的 file input
            file_input = file_inputs[0]
            file_input.set_input_files(file_path)
            
            # 等待上传完成
            time.sleep(3)
            print(f"   ✅ 图片已上传")
            return True
            
        except Exception as e:
            print(f"   ❌ 上传图片失败: {e}")
            return False
    
    # ============================================================
    # 输入提示词
    # ============================================================
    
    def input_prompt(self, prompt: str) -> bool:
        """输入提示词"""
        print(f"   📝 输入提示词: {prompt[:60]}...")
        
        try:
            # 查找提示词输入框
            textarea = self.page.query_selector('textarea[class*="prompt-textarea"]')
            if not textarea:
                textarea = self.page.query_selector('textarea')
            
            if not textarea:
                print("   ❌ 未找到提示词输入框")
                return False
            
            # 清空现有内容
            textarea.click()
            time.sleep(0.3)
            self.page.keyboard.press('Control+a')
            time.sleep(0.1)
            self.page.keyboard.press('Backspace')
            time.sleep(0.3)
            
            # 输入新提示词
            textarea.fill(prompt)
            time.sleep(0.5)
            
            # 验证输入
            current_value = textarea.input_value()
            if current_value and len(current_value) > 0:
                print(f"   ✅ 提示词已输入 ({len(current_value)} 字)")
                return True
            else:
                # fill 可能不生效，尝试 type
                textarea.click()
                textarea.type(prompt, delay=10)
                time.sleep(0.5)
                print(f"   ✅ 提示词已输入（type 方式）")
                return True
            
        except Exception as e:
            print(f"   ❌ 输入提示词失败: {e}")
            return False
    
    # ============================================================
    # 点击生成按钮
    # ============================================================
    
    def click_generate(self) -> bool:
        """点击生成按钮（兼容旧接口）"""
        result = self.click_generate_and_get_id()
        return result.get('clicked', False)
    
    def click_generate_and_get_id(self) -> dict:
        """点击生成按钮，并等待捕获 history_id
        
        Returns:
            {'clicked': True, 'history_id': '...'} 或 {'clicked': False, 'error': '...'}
        """
        print("   🚀 点击生成按钮...")
        
        try:
            # 重置最近一次生成响应
            self._last_generate_response = None
            self._generate_response = None
            self._video_responses = []
            
            # 查找生成按钮
            gen_btn = self.page.query_selector('div.text-HLQFZY:has-text("生成")')
            
            if not gen_btn:
                gen_btn = self.page.query_selector('button:has-text("生成")')
            
            if not gen_btn:
                candidates = self.page.query_selector_all('text=生成')
                for c in candidates:
                    tag = c.evaluate('el => el.tagName')
                    text = c.inner_text().strip()
                    if text == '生成' and tag in ('DIV', 'SPAN', 'BUTTON'):
                        gen_btn = c
                        break
            
            if not gen_btn:
                print("   ❌ 未找到生成按钮")
                return {'clicked': False, 'error': '未找到生成按钮'}
            
            # 点击生成
            gen_btn.click()
            
            # 等待网络响应，提取 history_id（最多等 10 秒）
            history_id = ''
            for i in range(20):
                time.sleep(0.5)
                if self._last_generate_response:
                    history_id = self._extract_history_id(self._last_generate_response)
                    ret = str(self._last_generate_response.get('ret', ''))
                    if ret != '0':
                        errmsg = self._last_generate_response.get('errmsg', '未知错误')
                        print(f"   ❌ 生成请求失败: ret={ret}, msg={errmsg}")
                        return {'clicked': True, 'error': f'生成请求失败: {errmsg}'}
                    if history_id:
                        break
            
            if history_id:
                print(f"   ✅ 已点击生成，history_id={history_id}")
            else:
                print(f"   ✅ 已点击生成（未捕获到 history_id，将使用页面轮询）")
            
            return {'clicked': True, 'history_id': history_id}
            
        except Exception as e:
            print(f"   ❌ 点击生成失败: {e}")
            return {'clicked': False, 'error': str(e)}
    
    # ============================================================
    # 提交生成（仅 UI 操作，需要浏览器锁）
    # ============================================================
    
    def submit_generate(
        self,
        prompt: str,
        model: str = 'seedance-2.0-fast',
        tool_type: str = 'video_gen',
        mode: str = None,
        aspect_ratio: str = '16:9',
        resolution: str = '720p',
        duration: int = 5,
        reference_file: str = None,
    ) -> dict:
        """
        仅执行 UI 操作提交生成任务，不等待结果。
        
        这个方法需要浏览器锁保护（同一时间只能一个任务操作 UI）。
        返回 history_id 后立即释放锁，后续轮询不需要锁。
        
        Returns:
            {'success': True, 'history_id': '...'} 
            或 {'success': False, 'error': '...'}
        """
        print(f"\n{'='*60}")
        print(f"  🎬 即梦提交生成（并发模式）")
        print(f"{'='*60}")
        print(f"   模型: {model}")
        print(f"   工具: {tool_type}")
        if mode:
            print(f"   方式: {mode}")
        print(f"   比例: {aspect_ratio}")
        print(f"   时长: {duration}s")
        print(f"   提示词: {prompt[:80]}...")
        if reference_file:
            print(f"   参考图: {reference_file}")
        
        try:
            # 整个 submit 过程需要页面锁（UI 操作不可并发）
            with self._page_lock:
                # 1. 导航到对应工具类型的页面
                self._ensure_tool_page(tool_type)
                
                # 2. 选择模型
                if tool_type != 'agent':
                    self.select_model(model)
                
                # 3. 设置方式
                if mode and tool_type == 'video_gen':
                    self.set_mode(mode)
                
                # 4. 设置宽高比
                self.set_aspect_ratio(aspect_ratio)
                
                # 5. 设置时长
                self.set_duration(duration)
                
                # 6. 上传参考图片
                if reference_file and os.path.exists(reference_file):
                    if not self.upload_reference_image(reference_file):
                        return {'success': False, 'error': '上传参考图片失败'}
                
                # 7. 输入提示词
                if not self.input_prompt(prompt):
                    return {'success': False, 'error': '输入提示词失败'}
                
                # 8. 点击生成并获取 history_id
                gen_result = self.click_generate_and_get_id()
                if not gen_result.get('clicked'):
                    return {'success': False, 'error': gen_result.get('error', '点击生成按钮失败')}
                
                if gen_result.get('error'):
                    return {'success': False, 'error': gen_result['error']}
                
                history_id = gen_result.get('history_id', '')
                return {'success': True, 'history_id': history_id}
        
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    # ============================================================
    # 轮询结果（不需要浏览器锁，可并发）
    # ============================================================
    
    def poll_result(self, history_id: str = '', max_wait: int = 600, poll_interval: int = 5, save_path: str = None) -> dict:
        """
        轮询生成结果，不需要浏览器级别的长锁。
        
        如果有 history_id，优先通过网络监听精准匹配（只读字典，无需页面锁）。
        DOM 查询部分使用 _page_lock 短锁保护，避免和 submit_generate 冲突。
        
        Returns:
            {'success': True, 'video_url': '...', 'video_path': '...'} 
            或 {'success': False, 'error': '...'}
        """
        print(f"\n⏳ 轮询生成结果（最长 {max_wait}s）...")
        if history_id:
            print(f"   📍 追踪 history_id: {history_id}")
        
        start_time = time.time()
        last_check = ''
        
        while time.time() - start_time < max_wait:
            elapsed = int(time.time() - start_time)
            
            # 方法1：通过 history_id 精准匹配（优先，只读字典不需要页面锁）
            if history_id and history_id in self._pending_tasks:
                task = self._pending_tasks[history_id]
                if task['status'] == 'success' and task['video_url']:
                    video_url = task['video_url']
                    print(f"   ✅ 通过 history_id 获取到视频 ({elapsed}s)")
                    # 下载视频（不需要锁）
                    if save_path:
                        if download_video(video_url, save_path):
                            return {'success': True, 'video_path': save_path, 'video_url': video_url, 'history_id': history_id}
                        else:
                            return {'success': False, 'error': '下载视频失败', 'video_url': video_url}
                    return {'success': True, 'video_url': video_url, 'history_id': history_id}
                elif task['status'] == 'failed':
                    return {'success': False, 'error': task.get('error', '生成失败'), 'history_id': history_id}
            
            # 方法2：检查生成响应是否有错误（只读字典，不需要页面锁）
            if self._generate_response:
                ret = str(self._generate_response.get('ret', ''))
                if ret != '0':
                    errmsg = self._generate_response.get('errmsg', '未知错误')
                    return {'success': False, 'error': f'生成请求失败: ret={ret}, msg={errmsg}'}
            
            # 方法3：页面 DOM 检测（需要短锁，兼容无 history_id 的情况）
            if not history_id:
                with self._page_lock:
                    try:
                        video_el = self.page.query_selector('video[src]')
                        if video_el:
                            video_src = video_el.get_attribute('src')
                            if video_src and video_src.startswith('http'):
                                print(f"   ✅ 检测到视频元素 ({elapsed}s)")
                                if save_path:
                                    if download_video(video_src, save_path):
                                        return {'success': True, 'video_path': save_path, 'video_url': video_src}
                                return {'success': True, 'video_url': video_src}
                        
                        download_btn = self.page.query_selector('text=下载')
                        if download_btn:
                            video_url = self._extract_video_url_from_page()
                            if video_url:
                                print(f"   ✅ 视频生成完成 ({elapsed}s)")
                                if save_path:
                                    if download_video(video_url, save_path):
                                        return {'success': True, 'video_path': save_path, 'video_url': video_url}
                                return {'success': True, 'video_url': video_url}
                    except:
                        pass
                
                # 检查网络监听的历史记录响应（只读列表，不需要页面锁）
                for resp in self._video_responses:
                    video_url = self._extract_video_url_from_response(resp)
                    if video_url:
                        print(f"   ✅ 从网络响应获取到视频 URL ({elapsed}s)")
                        if save_path:
                            if download_video(video_url, save_path):
                                return {'success': True, 'video_path': save_path, 'video_url': video_url}
                        return {'success': True, 'video_url': video_url}
            
            # 检查页面状态提示（需要短锁）
            with self._page_lock:
                try:
                    error_el = self.page.query_selector('text=生成失败')
                    if error_el:
                        return {'success': False, 'error': '页面显示生成失败'}
                    review_el = self.page.query_selector('text=未通过审核')
                    if not review_el:
                        review_el = self.page.query_selector('text=视频未通过审核')
                    if review_el:
                        return {'success': False, 'error': '内容未通过审核'}
                    
                    queue_el = self.page.query_selector('text=排队中')
                    if queue_el and 'queue' != last_check:
                        print(f"   📊 排队中... ({elapsed}s)")
                        last_check = 'queue'
                    generating_el = self.page.query_selector('text=生成中')
                    if generating_el and 'generating' != last_check:
                        print(f"   📊 生成中... ({elapsed}s)")
                        last_check = 'generating'
                except:
                    pass
            
            if elapsed > 0 and elapsed % 30 == 0 and str(elapsed) != last_check:
                print(f"   ⏳ 已等待 {elapsed}s...")
                last_check = str(elapsed)
            
            time.sleep(poll_interval)
        
        return {'success': False, 'error': f'等待超时 ({max_wait}s)'}
    
    # ============================================================
    # 等待视频生成完成
    # ============================================================
    
    def wait_for_video(self, max_wait: int = 600, poll_interval: int = 5) -> dict:
        """
        等待视频生成完成
        
        通过监听网络响应和检查页面状态来判断是否完成
        
        Returns:
            {'status': 'success', 'video_url': '...'}
            或 {'status': 'failed', 'error': '...'}
        """
        print(f"\n⏳ 等待视频生成（最长 {max_wait}s）...")
        start_time = time.time()
        last_check = ''
        
        while time.time() - start_time < max_wait:
            elapsed = int(time.time() - start_time)
            
            # 方法1：检查网络监听是否捕获到生成响应
            if self._generate_response:
                ret = str(self._generate_response.get('ret', ''))
                if ret != '0':
                    errmsg = self._generate_response.get('errmsg', '未知错误')
                    return {'status': 'failed', 'error': f'生成请求失败: ret={ret}, msg={errmsg}'}
            
            # 方法2：检查页面上是否出现视频预览或下载按钮
            try:
                # 检查是否有视频元素出现
                video_el = self.page.query_selector('video[src]')
                if video_el:
                    video_src = video_el.get_attribute('src')
                    if video_src and video_src.startswith('http'):
                        print(f"   ✅ 检测到视频元素 ({elapsed}s)")
                        return {'status': 'success', 'video_url': video_src}
                
                # 检查是否有"下载"按钮出现（生成完成的标志）
                download_btn = self.page.query_selector('text=下载')
                if download_btn:
                    # 视频已生成，尝试获取 URL
                    video_url = self._extract_video_url_from_page()
                    if video_url:
                        print(f"   ✅ 视频生成完成 ({elapsed}s)")
                        return {'status': 'success', 'video_url': video_url}
                
                # 检查是否有错误提示
                error_el = self.page.query_selector('text=生成失败')
                if error_el:
                    return {'status': 'failed', 'error': '页面显示生成失败'}
                
                # 检查是否有"审核未通过"
                review_el = self.page.query_selector('text=未通过审核')
                if not review_el:
                    review_el = self.page.query_selector('text=视频未通过审核')
                if review_el:
                    return {'status': 'failed', 'error': '内容未通过审核'}
                
                # 检查排队状态
                queue_el = self.page.query_selector('text=排队中')
                if queue_el and 'queue' != last_check:
                    print(f"   📊 排队中... ({elapsed}s)")
                    last_check = 'queue'
                
                # 检查生成中状态
                generating_el = self.page.query_selector('text=生成中')
                if generating_el and 'generating' != last_check:
                    print(f"   📊 生成中... ({elapsed}s)")
                    last_check = 'generating'
                
            except Exception as e:
                # 页面检查出错，继续等待
                pass
            
            # 方法3：检查网络监听的历史记录响应
            for resp in self._video_responses:
                video_url = self._extract_video_url_from_response(resp)
                if video_url:
                    print(f"   ✅ 从网络响应获取到视频 URL ({elapsed}s)")
                    return {'status': 'success', 'video_url': video_url}
            
            # 定期打印等待状态
            if elapsed > 0 and elapsed % 30 == 0 and str(elapsed) != last_check:
                print(f"   ⏳ 已等待 {elapsed}s...")
                last_check = str(elapsed)
            
            time.sleep(poll_interval)
        
        return {'status': 'failed', 'error': f'等待超时 ({max_wait}s)'}
    
    def _extract_video_url_from_page(self) -> str:
        """从页面中提取视频 URL"""
        try:
            # 查找所有 video 元素
            videos = self.page.query_selector_all('video')
            for v in videos:
                src = v.get_attribute('src')
                if src and src.startswith('http'):
                    return src
            
            # 查找 source 元素
            sources = self.page.query_selector_all('video source')
            for s in sources:
                src = s.get_attribute('src')
                if src and src.startswith('http'):
                    return src
            
            # 通过 JS 获取
            url = self.page.evaluate("""
                () => {
                    const videos = document.querySelectorAll('video');
                    for (const v of videos) {
                        if (v.src && v.src.startsWith('http')) return v.src;
                        if (v.currentSrc && v.currentSrc.startsWith('http')) return v.currentSrc;
                    }
                    return '';
                }
            """)
            return url or ''
            
        except:
            return ''
    
    def _extract_video_url_from_response(self, resp_data: dict) -> str:
        """从网络响应数据中提取视频 URL"""
        try:
            if str(resp_data.get('ret', '')) != '0':
                return ''
            
            data = resp_data.get('data', {})
            
            # 尝试多种路径
            # 路径1: data.history_list[0].item_list[0].video_info.url
            history_list = data.get('history_list', [])
            if isinstance(history_list, list):
                for history in history_list:
                    items = history.get('item_list', [])
                    for item in items:
                        url = item.get('video_info', {}).get('url', '')
                        if url:
                            return url
                        url = item.get('video_info', {}).get('download_url', '')
                        if url:
                            return url
            
            # 路径2: data[history_id].item_list
            for key, val in data.items():
                if isinstance(val, dict) and 'item_list' in val:
                    for item in val['item_list']:
                        url = item.get('video_info', {}).get('url', '')
                        if url:
                            return url
            
        except:
            pass
        return ''

    # ============================================================
    # 完整生成流程（兼容旧接口，串行模式）
    # ============================================================
    
    def generate(
        self,
        prompt: str,
        model: str = 'seedance-2.0-fast',
        tool_type: str = 'video_gen',
        mode: str = None,
        aspect_ratio: str = '16:9',
        resolution: str = '720p',
        duration: int = 5,
        reference_file: str = None,
        save_path: str = None,
        max_wait: int = 600,
    ) -> dict:
        """
        完整的视频生成流程（串行模式，兼容旧接口）
        
        内部调用 submit_generate + poll_result。
        
        Returns:
            {'success': True, 'video_path': '...'}
            或 {'success': False, 'error': '...'}
        """
        # 步骤1：提交生成
        submit_result = self.submit_generate(
            prompt=prompt,
            model=model,
            tool_type=tool_type,
            mode=mode,
            aspect_ratio=aspect_ratio,
            resolution=resolution,
            duration=duration,
            reference_file=reference_file,
        )
        
        if not submit_result.get('success'):
            return submit_result
        
        history_id = submit_result.get('history_id', '')
        
        # 步骤2：轮询结果
        return self.poll_result(
            history_id=history_id,
            max_wait=max_wait,
            save_path=save_path,
        )


# ============================================================
# 下载视频
# ============================================================

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
                    if total_size > 0:
                        pct = downloaded * 100 // total_size
                        if pct % 20 == 0:
                            print(f"   📊 下载进度: {pct}%")
        
        file_size = os.path.getsize(save_path)
        print(f"   ✅ 下载完成: {file_size / 1024 / 1024:.1f} MB")
        return True
        
    except Exception as e:
        print(f"   ❌ 下载失败: {e}")
        return False


# ============================================================
# 主入口（CLI）
# ============================================================

def main():
    parser = argparse.ArgumentParser(description='即梦视频生成自动化')
    parser.add_argument('prompt', help='视频提示词')
    parser.add_argument('--save-path', required=True, help='视频保存路径')
    parser.add_argument('--tool-type', default='video_gen',
                       choices=['video_gen', 'image_gen', 'agent'],
                       help='工具类型')
    parser.add_argument('--model', default='seedance-2.0-fast', help='模型名称')
    parser.add_argument('--aspect-ratio', default='16:9', help='宽高比')
    parser.add_argument('--resolution', default='720p', help='分辨率')
    parser.add_argument('--duration', default='5', help='时长（秒）')
    parser.add_argument('--reference-file', help='参考图片文件路径')
    parser.add_argument('--max-wait', default='600', help='最大等待时间（秒）')
    parser.add_argument('--profile', default=None, help='浏览器 profile 目录')
    parser.add_argument('--cdp-port', default=str(CDP_PORT), help='CDP 端口')
    
    args = parser.parse_args()
    
    print("\n" + "=" * 60)
    print("  🎬 即梦视频生成自动化（UI 自动化模式）")
    print("=" * 60)
    
    # 解析参数
    duration = int(''.join(filter(str.isdigit, str(args.duration)))) or 5
    max_wait = int(args.max_wait)
    if max_wait <= 30:
        max_wait = max_wait * 60
    
    profile = args.profile or JIMENG_PROFILE_DIR
    cdp_port = int(args.cdp_port)
    
    # 启动自动化
    auto = JimengAutomation(profile_dir=profile, cdp_port=cdp_port)
    
    if not auto.start():
        print("\n❌ 无法启动浏览器！")
        print("   请先运行: python open_browser_for_login.py jimeng")
        return 1
    
    try:
        # 检查登录
        print(f"\n🔍 检查登录状态...")
        if not auto.check_login():
            print("\n❌ 未登录，请先登录即梦！")
            print("   python open_browser_for_login.py jimeng")
            return 1
        
        # 执行生成
        result = auto.generate(
            prompt=args.prompt,
            model=args.model,
            tool_type=args.tool_type,
            aspect_ratio=args.aspect_ratio,
            resolution=args.resolution,
            duration=duration,
            reference_file=args.reference_file,
            save_path=args.save_path,
            max_wait=max_wait,
        )
        
        if result.get('success'):
            print(f"\n{'='*60}")
            print(f"  ✅ 视频生成完成!")
            if result.get('video_path'):
                print(f"  📁 {result['video_path']}")
            print(f"{'='*60}\n")
            return 0
        else:
            print(f"\n❌ 生成失败: {result.get('error', '未知错误')}")
            return 1
    
    except Exception as e:
        print(f"\n❌ 异常: {e}")
        return 1
    
    finally:
        auto.stop()


if __name__ == '__main__':
    sys.exit(main())
