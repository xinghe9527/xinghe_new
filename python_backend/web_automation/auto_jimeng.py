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
JIMENG_VIDEO_URL = f'{JIMENG_BASE_URL}/ai-tool/home?workspace=0&type=video'
JIMENG_GENERATE_URL = f'{JIMENG_BASE_URL}/ai-tool/generate?type=video&workspace=0'

# 工具类型 → URL 映射
JIMENG_TOOL_URLS = {
    'video_gen': JIMENG_GENERATE_URL,
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
        """确保当前在指定工具类型的生成页面（不是 home 页）"""
        target_url = JIMENG_TOOL_URLS.get(tool_type, JIMENG_GENERATE_URL)
        
        current_url = self.page.url
        # 必须在 generate 页面，不能在 home 页
        if '/ai-tool/generate' not in current_url or 'type=video' not in current_url:
            print(f"   🌐 导航到生成页面...")
            self.page.goto(target_url, wait_until='domcontentloaded', timeout=30000)
            self.page.wait_for_load_state('networkidle', timeout=15000)
            time.sleep(2)
    
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
            # 调试：打印 data 的键和值类型
            if isinstance(data, dict):
                print(f"   🔍 生成响应 data keys: {list(data.keys())}")
                for k, v in data.items():
                    if isinstance(v, (str, int, float)):
                        print(f"      {k}: {v}")
                    elif isinstance(v, dict):
                        print(f"      {k}: dict({list(v.keys())[:5]})")
                    elif isinstance(v, list):
                        print(f"      {k}: list[{len(v)}]")
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
            # 路径4: data.aigc_data.history_id 或 history_record_id
            aigc = data.get('aigc_data', {})
            if isinstance(aigc, dict):
                hid2 = aigc.get('history_id', '') or aigc.get('history_record_id', '')
                if hid2:
                    return str(hid2)
            # 路径5: 递归搜索任何包含 history_id 的嵌套字段
            def find_key(d, key):
                if isinstance(d, dict):
                    if key in d and d[key]:
                        return str(d[key])
                    for v in d.values():
                        r = find_key(v, key)
                        if r:
                            return r
                elif isinstance(d, list):
                    for item in d:
                        r = find_key(item, key)
                        if r:
                            return r
                return ''
            hid_deep = find_key(data, 'history_id')
            if hid_deep:
                print(f"   📡 深层搜索找到 history_id: {hid_deep}")
                return hid_deep
        except Exception as e:
            print(f"   ⚠️ 提取 history_id 异常: {e}")
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
                    hid = str(history.get('history_id', '') or history.get('history_record_id', ''))
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
            # 获取页面高度，只在底部工具栏区域找按钮（避免点到历史记录中的文字）
            viewport = self.page.viewport_size
            page_height = viewport['height'] if viewport else 900
            bottom_threshold = page_height * 0.7  # 底部 30% 区域
            
            mode_keywords = ['自定义', '全能参考', '首尾帧', '智能多帧', '主体参考']
            mode_btn = None
            
            for kw in mode_keywords:
                els = self.page.query_selector_all(f'text="{kw}"')
                for el in els:
                    try:
                        if not el.is_visible():
                            continue
                        # 只选择底部区域的元素（工具栏按钮）
                        box = el.bounding_box()
                        if box and box['y'] >= bottom_threshold:
                            mode_btn = el
                            break
                    except:
                        continue
                if mode_btn:
                    break
            
            # 如果底部没找到，放宽到全页面
            if not mode_btn:
                for kw in mode_keywords:
                    els = self.page.query_selector_all(f'text="{kw}"')
                    for el in els:
                        try:
                            if el.is_visible():
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
            target = None
            candidates = self.page.query_selector_all(f'text="{display_name}"')
            for c in candidates:
                try:
                    if c.is_visible():
                        target = c
                        break
                except:
                    continue
            
            if target:
                target.click()
                time.sleep(1)
                # 确保下拉关闭，避免遮挡后续工具栏操作
                self.page.keyboard.press('Escape')
                time.sleep(0.3)
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
        """设置宽高比
        
        即梦底部工具栏的比例和分辨率合并在一个按钮中（如 "21:9 720P"），
        点击后弹出面板，上方是比例选项（21:9, 16:9, 4:3, 1:1, 3:4, 9:16），
        下方是分辨率选项（720P, 1080P）。
        """
        print(f"   📐 设置宽高比: {aspect_ratio}")
        
        all_ratios = ['16:9', '9:16', '1:1', '4:3', '3:4', '21:9', '自动匹配']
        
        try:
            # 获取页面高度，限定只在底部工具栏区域查找
            viewport = self.page.viewport_size
            page_height = viewport['height'] if viewport else 900
            bottom_threshold = page_height * 0.7  # 底部 30% 区域
            
            # 步骤1：找到工具栏上的「比例+分辨率」组合按钮（文本如 "21:9 720P"）
            # 严格限定在底部工具栏区域，避免误匹配页面内容中的比例文字
            ratio_btn = None
            for r in all_ratios:
                candidates = self.page.query_selector_all(f':has-text("{r}")')
                best = None
                best_size = float('inf')
                for c in candidates:
                    try:
                        if not c.is_visible():
                            continue
                        box = c.bounding_box()
                        if not box:
                            continue
                        # 必须在底部工具栏区域
                        if box['y'] < bottom_threshold:
                            continue
                        size = box['width'] * box['height']
                        if 500 < size < 50000 and size < best_size:
                            best = c
                            best_size = size
                    except:
                        continue
                if best:
                    ratio_btn = best
                    break
            
            if ratio_btn:
                btn_text = ratio_btn.inner_text().strip()
                print(f"   📐 工具栏比例按钮文本: '{btn_text}'")
                # 检查当前是否已是目标比例（精确检查：必须是这个比例而不是别的）
                if aspect_ratio in btn_text and all(r not in btn_text or r == aspect_ratio for r in all_ratios if r != aspect_ratio):
                    print(f"   ✅ 宽高比已是: {aspect_ratio}")
                    return True
                
                # 点击展开比例选择面板
                ratio_btn.click()
                time.sleep(1)
                
                # 步骤2：在弹出面板中找「选择比例」区域的目标比例
                # 选最小的匹配元素（即真正的按钮，而非包含该文字的容器div）
                target = None
                target_size = float('inf')
                candidates = self.page.query_selector_all(f'text="{aspect_ratio}"')
                for c in candidates:
                    try:
                        if not c.is_visible():
                            continue
                        box = c.bounding_box()
                        if box:
                            size = box['width'] * box['height']
                            if size < target_size:
                                target = c
                                target_size = size
                    except:
                        continue
                
                if target:
                    target.click()
                    time.sleep(0.5)
                    print(f"   ✅ 已设置宽高比: {aspect_ratio}")
                    # 关闭面板：先试 Escape，再点击页面空白处
                    self.page.keyboard.press('Escape')
                    time.sleep(0.3)
                    try:
                        self.page.mouse.click(200, 400)
                        time.sleep(0.3)
                    except:
                        pass
                    return True
                else:
                    self.page.keyboard.press('Escape')
                    time.sleep(0.3)
                    try:
                        self.page.mouse.click(200, 400)
                        time.sleep(0.3)
                    except:
                        pass
                    print(f"   ⚠️  面板中未找到 '{aspect_ratio}'")
                    return True
            
            # 策略2：JS 查找包含比例文字的叶子元素
            found_el = self.page.evaluate("""(ratios) => {
                const els = document.querySelectorAll('*');
                for (const el of els) {
                    if (el.offsetParent !== null) {
                        const text = (el.innerText || '').trim();
                        for (const r of ratios) {
                            if (text.includes(r) && text.length < 20) {
                                return {found: true, text: text};
                            }
                        }
                    }
                }
                return {found: false};
            }""", all_ratios)
            
            if found_el and found_el.get('found'):
                # 用包含匹配点击该元素
                el_text = found_el['text']
                # 用 JS 直接点击
                self.page.evaluate("""(targetText) => {
                    const els = document.querySelectorAll('*');
                    for (const el of els) {
                        if (el.offsetParent !== null && (el.innerText || '').trim() === targetText) {
                            el.click();
                            return true;
                        }
                    }
                    return false;
                }""", el_text)
                time.sleep(1)
                
                target = self.page.query_selector(f'text="{aspect_ratio}"')
                if target and target.is_visible():
                    target.click()
                    time.sleep(0.5)
                    self.page.keyboard.press('Escape')
                    time.sleep(0.3)
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
            # 先按 Escape 关闭可能残留的下拉面板
            self.page.keyboard.press('Escape')
            time.sleep(0.5)
            
            duration_text = f'{duration}s'
            # 找到底部工具栏中的时长元素
            viewport = self.page.viewport_size
            page_height = viewport['height'] if viewport else 900
            bottom_threshold = page_height * 0.7
            
            candidates = self.page.query_selector_all(f'text="{duration_text}"')
            duration_el = None
            for c in candidates:
                try:
                    if not c.is_visible():
                        continue
                    box = c.bounding_box()
                    if box and box['y'] >= bottom_threshold:
                        duration_el = c
                        break
                except:
                    continue
            
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
    # 多图上传 + @ 引用（全能参考模式专用）
    # ============================================================
    
    def upload_multiple_references(self, file_paths: list) -> int:
        """上传多张参考图片（全能参考模式）
        
        点击"参考内容"区域的"+"按钮触发文件选择器上传图片。
        即梦会自动命名为 图片1, 图片2, ...
        
        Returns:
            成功上传的图片数量
        """
        uploaded = 0
        for i, fp in enumerate(file_paths):
            if not os.path.exists(fp):
                print(f"   ⚠️  文件不存在，跳过: {fp}")
                continue
            
            print(f"   📤 上传参考图 {i+1}/{len(file_paths)}: {os.path.basename(fp)}")
            try:
                success = False
                
                # 策略1：点击"参考内容"/"+"按钮，通过 file_chooser 事件上传
                upload_btn = None
                for selector in [
                    'text="参考内容"',
                    'text="+"',
                    '[class*="reference"] [class*="add"]',
                    '[class*="upload-trigger"]',
                    '[class*="add-resource"]',
                    '[class*="add-ref"]',
                ]:
                    el = self.page.query_selector(selector)
                    if el and el.is_visible():
                        upload_btn = el
                        print(f"   📋 找到上传按钮: {selector}")
                        break
                
                if upload_btn:
                    try:
                        with self.page.expect_file_chooser(timeout=5000) as fc_info:
                            upload_btn.click()
                        file_chooser = fc_info.value
                        file_chooser.set_files(fp)
                        time.sleep(3)
                        uploaded += 1
                        success = True
                        print(f"   ✅ 图片 {uploaded} 已上传（file_chooser 方式）")
                    except Exception as e:
                        print(f"   ⚠️  file_chooser 方式失败: {e}")
                
                # 策略2：直接找 input[type="file"] 并设置文件（回退方案）
                if not success:
                    file_inputs = self.page.query_selector_all('input[type="file"]')
                    if file_inputs:
                        for fi in file_inputs:
                            try:
                                fi.set_input_files(fp)
                                time.sleep(3)
                                uploaded += 1
                                success = True
                                print(f"   ✅ 图片 {uploaded} 已上传（input 方式）")
                                break
                            except Exception:
                                continue
                
                if not success:
                    print(f"   ❌ 上传图片 {i+1} 失败：未找到可用的上传入口")
                    
            except Exception as e:
                print(f"   ❌ 上传图片 {i+1} 失败: {e}")
        
        return uploaded
    
    def input_prompt_with_at_references(self, prompt: str, character_names: list, mode: str = 'all_ref') -> bool:
        """输入提示词并用 @ 关联已上传的参考图片
        
        流程：
        1. 解析 prompt，找到角色名出现的位置
        2. 按顺序输入文本，遇到角色名时：
           - 先输入角色名
           - 然后输入 @，触发下拉菜单
           - 从下拉中选择对应的引用项
        3. 输入剩余文本
        
        Args:
            prompt: 完整提示词文本
            character_names: 角色名列表，顺序与上传图片一一对应
            mode: 生成模式，'subject_ref' 时下拉项为"主体"而非"图片N"
        """
        # 主体参考模式下，下拉项名为"主体"；全能参考模式为"图片N"
        is_subject_mode = mode == 'subject_ref'
        print(f"   📝 输入提示词（含 @ 引用）: {prompt[:60]}...")
        print(f"   🎭 角色映射: {character_names}")
        
        try:
            # 找到提示词输入框（可能是 textarea 或 contenteditable div）
            input_el = None
            for selector in [
                'textarea[class*="prompt"]',
                'textarea',
                '[contenteditable="true"]',
                '[role="textbox"]',
                '[class*="prompt-input"]',
                '[class*="editor"]',
            ]:
                el = self.page.query_selector(selector)
                if el and el.is_visible():
                    input_el = el
                    print(f"   📋 找到输入框: {selector}")
                    break
            
            if not input_el:
                print("   ❌ 未找到提示词输入框")
                return False
            
            # 清空现有内容
            input_el.click()
            time.sleep(0.3)
            self.page.keyboard.press('Control+a')
            time.sleep(0.1)
            self.page.keyboard.press('Backspace')
            time.sleep(0.3)
            
            # 构建 name → 图片索引 映射（去重后的 character_names）
            name_to_index = {}
            for idx, name in enumerate(character_names):
                if name not in name_to_index:
                    name_to_index[name] = idx + 1
            
            # 扫描 prompt 中所有角色名出现位置（同名角色复用同一个图片索引）
            occurrences = []  # [(pos, name, img_index)]
            for name, img_idx in name_to_index.items():
                start = 0
                while True:
                    pos = prompt.find(name, start)
                    if pos == -1:
                        break
                    occurrences.append((pos, name, img_idx))
                    start = pos + len(name)
            
            # 按位置排序
            occurrences.sort(key=lambda x: x[0])
            
            # 构建分段列表
            segments = []
            current_pos = 0
            for pos, name, img_idx in occurrences:
                before = prompt[current_pos:pos]
                segments.append((before, name, img_idx))
                current_pos = pos + len(name)
            # 剩余文本
            if current_pos < len(prompt):
                segments.append((prompt[current_pos:], None, None))
            
            if not segments:
                # 没找到任何角色名，直接正常输入
                self.page.keyboard.type(prompt, delay=10)
                time.sleep(0.5)
                print(f"   ✅ 提示词已输入（无 @ 引用）")
                return True
            
            # 逐段输入
            for before_text, char_name, img_index in segments:
                # 输入角色名前的文本
                if before_text:
                    self.page.keyboard.type(before_text, delay=10)
                    time.sleep(0.2)
                
                if char_name is None:
                    continue
                
                # 输入角色名
                self.page.keyboard.type(char_name, delay=10)
                time.sleep(0.2)
                
                # 输入 @ 触发下拉菜单
                self.page.keyboard.type(' @', delay=50)
                time.sleep(1.5)
                
                # 等待下拉菜单出现并选择对应引用
                if is_subject_mode:
                    target_text = '主体'
                else:
                    target_text = f'图片{img_index}'
                selected = False
                
                # 尝试在下拉菜单中找到目标（排除输入框内已有的引用）
                for attempt in range(5):
                    # 优先在下拉菜单/弹出层中查找
                    found_els = []
                    for selector in [
                        f'[class*="dropdown"] :text("{target_text}")',
                        f'[class*="popup"] :text("{target_text}")',
                        f'[class*="popover"] :text("{target_text}")',
                        f'[class*="mention"] :text("{target_text}")',
                        f'[role="listbox"] :text("{target_text}")',
                        f'[role="option"]:text("{target_text}")',
                    ]:
                        try:
                            els = self.page.query_selector_all(selector)
                            found_els.extend(els)
                        except Exception:
                            pass
                    
                    # 如果精确选择器没找到，回退到通用选择器
                    if not found_els:
                        candidates = self.page.query_selector_all(f'text="{target_text}"')
                        # 取最后一个可见的（下拉菜单通常在 DOM 最后面）
                        for el in reversed(candidates):
                            try:
                                if el.is_visible():
                                    found_els.append(el)
                                    break
                            except Exception:
                                pass
                    
                    if is_subject_mode and found_els:
                        # 主体参考模式：所有下拉项都叫"主体"，按顺序选第 img_index 个
                        # 收集所有可见的"主体"项
                        visible_items = []
                        for el in found_els:
                            try:
                                if el.is_visible():
                                    visible_items.append(el)
                            except Exception:
                                continue
                        # 按 img_index 选择（1-based → 0-based）
                        target_idx = img_index - 1
                        if target_idx < len(visible_items):
                            visible_items[target_idx].click()
                            selected = True
                            time.sleep(0.5)
                            print(f"   ✅ 已 @ 选择: {char_name} → 主体{img_index}")
                    else:
                        for el in found_els:
                            try:
                                if el.is_visible():
                                    el.click()
                                    selected = True
                                    time.sleep(0.5)
                                    print(f"   ✅ 已 @ 选择: {char_name} → {target_text}")
                                    break
                            except Exception:
                                continue
                    if selected:
                        break
                    time.sleep(0.5)
                
                if not selected:
                    print(f"   ⚠️  未找到 @ 下拉中的 {target_text}，跳过")
                    # 删掉已输入的 " @"
                    self.page.keyboard.press('Backspace')
                    self.page.keyboard.press('Backspace')
                    time.sleep(0.3)
                
                time.sleep(0.3)
            
            print(f"   ✅ 提示词已输入（含 {len(character_names)} 个 @ 引用）")
            return True
            
        except Exception as e:
            print(f"   ❌ 输入提示词失败: {e}")
            return False
    
    # ============================================================
    # 输入提示词
    # ============================================================
    
    def input_prompt(self, prompt: str) -> bool:
        """输入提示词"""
        print(f"   📝 输入提示词: {prompt[:60]}...")
        
        try:
            # 查找提示词输入框（可能是 textarea 或 contenteditable div）
            input_el = None
            is_contenteditable = False
            for selector in [
                'textarea[class*="prompt"]',
                'textarea',
                '[contenteditable="true"]',
                '[role="textbox"]',
            ]:
                el = self.page.query_selector(selector)
                if el and el.is_visible():
                    input_el = el
                    is_contenteditable = 'contenteditable' in selector or 'textbox' in selector
                    break
            
            if not input_el:
                print("   ❌ 未找到提示词输入框")
                return False
            
            # 清空现有内容
            input_el.click()
            time.sleep(0.3)
            self.page.keyboard.press('Control+a')
            time.sleep(0.1)
            self.page.keyboard.press('Backspace')
            time.sleep(0.3)
            
            if is_contenteditable:
                # contenteditable 不支持 fill/input_value，用 keyboard.type
                self.page.keyboard.type(prompt, delay=10)
                time.sleep(0.5)
                print(f"   ✅ 提示词已输入（keyboard 方式）")
                return True
            else:
                # textarea 用 fill
                input_el.fill(prompt)
                time.sleep(0.5)
                
                current_value = input_el.input_value()
                if current_value and len(current_value) > 0:
                    print(f"   ✅ 提示词已输入 ({len(current_value)} 字)")
                    return True
                else:
                    input_el.click()
                    input_el.type(prompt, delay=10)
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
            
            gen_btn_clicked = False
            
            # 策略1：在 prompt 输入框附近找圆形可点击按钮（↑按钮用CSS图标，不含SVG）
            try:
                result = self.page.evaluate('''() => {
                    const input = document.querySelector('[contenteditable="true"]');
                    if (!input) return {error: 'no contenteditable'};
                    
                    const inputRect = input.getBoundingClientRect();
                    const diagnostics = [];
                    let best = null;
                    let bestRight = -1;
                    
                    const all = document.querySelectorAll('*');
                    for (const el of all) {
                        const rect = el.getBoundingClientRect();
                        // 尺寸 25-80px（生成按钮可能较大）
                        if (rect.width < 25 || rect.width > 80) continue;
                        if (rect.height < 25 || rect.height > 80) continue;
                        // 近似圆形
                        if (Math.abs(rect.width - rect.height) > 10) continue;
                        // 在 input 附近区域（上方50px 到 下方300px）
                        if (rect.top < inputRect.top - 50) continue;
                        if (rect.top > inputRect.bottom + 300) continue;
                        // 排除距 input 太远的固定定位元素（如帮助中心）
                        if (rect.left > inputRect.right + 400) continue;
                        // 排除在 input 左侧太远的
                        if (rect.right < inputRect.left) continue;
                        
                        const style = window.getComputedStyle(el);
                        if (style.display === 'none' || style.visibility === 'hidden') continue;
                        if (parseFloat(style.opacity) < 0.1) continue;
                        
                        const isClickable = style.cursor === 'pointer' || el.tagName === 'BUTTON' || el.onclick;
                        if (!isClickable) continue;
                        
                        // 排除已知非生成按钮
                        const cls = (el.className?.toString() || '').toLowerCase();
                        if (cls.includes('help') || cls.includes('trigger') || cls.includes('customer')) continue;
                        if (cls.includes('play') || cls.includes('arrow-button') || cls.includes('unread')) continue;
                        
                        diagnostics.push({
                            tag: el.tagName, cls: (el.className?.toString() || '').substring(0, 60),
                            x: Math.round(rect.x), y: Math.round(rect.y),
                            w: Math.round(rect.width), h: Math.round(rect.height),
                            cursor: style.cursor, bg: style.backgroundColor.substring(0, 40),
                        });
                        
                        // 选最右侧的候选按钮
                        if (rect.right > bestRight) {
                            bestRight = rect.right;
                            best = {cx: rect.x + rect.width/2, cy: rect.y + rect.height/2,
                                    tag: el.tagName, cls: (el.className?.toString() || '').substring(0, 60)};
                        }
                    }
                    return {
                        inputPos: {x: Math.round(inputRect.x), y: Math.round(inputRect.y),
                                   w: Math.round(inputRect.width), h: Math.round(inputRect.height)},
                        candidates: diagnostics, best: best,
                    };
                }''')
                
                if result and not result.get('error'):
                    ip = result['inputPos']
                    print(f"   📋 输入框: pos=({ip['x']},{ip['y']}) size={ip['w']}x{ip['h']}")
                    cands = result.get('candidates', [])
                    print(f"   📋 圆形按钮候选 ({len(cands)}个):")
                    for item in cands:
                        print(f"      {item['tag']} class={item['cls'][:50]} pos=({item['x']},{item['y']}) size={item['w']}x{item['h']} cursor={item['cursor']} bg={item['bg']}")
                    
                    if result.get('best'):
                        c = result['best']
                        print(f"   ✅ 选中生成按钮: {c['tag']} class={c['cls'][:50]} at ({int(c['cx'])},{int(c['cy'])})")
                        self.page.mouse.click(c['cx'], c['cy'])
                        gen_btn_clicked = True
                    else:
                        print("   ⚠️ 策略1: 未找到圆形可点击按钮")
                elif result:
                    print(f"   ⚠️ 策略1: {result.get('error')}")
            except Exception as e:
                print(f"   ⚠️ 策略1: {e}")
            
            # 策略2：class 名带 send/submit/primary
            if not gen_btn_clicked:
                for selector in [
                    'button[class*="primary"]', '[class*="send-btn"]', '[class*="submit-btn"]',
                    '[class*="sendBtn"]', '[class*="submitBtn"]',
                    'button[class*="send"]', 'button[class*="submit"]',
                ]:
                    el = self.page.query_selector(selector)
                    if el and el.is_visible():
                        box = el.bounding_box()
                        if box and box['x'] > 300:
                            print(f"   ✅ 策略2找到: {selector}")
                            self.page.mouse.click(box['x'] + box['width']/2, box['y'] + box['height']/2)
                            gen_btn_clicked = True
                            break
            
            # 策略3：键盘快捷键 Ctrl+Enter
            if not gen_btn_clicked:
                print("   📋 策略3: 使用 Ctrl+Enter 提交")
                input_el = self.page.query_selector('[contenteditable="true"]')
                if input_el:
                    input_el.click()
                    time.sleep(0.3)
                self.page.keyboard.press('Control+Enter')
                gen_btn_clicked = True
            
            if not gen_btn_clicked:
                print("   ❌ 未找到生成按钮")
                return {'clicked': False, 'error': '未找到生成按钮'}
            
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
        reference_images: list = None,
        character_names: list = None,
    ) -> dict:
        """
        仅执行 UI 操作提交生成任务，不等待结果。
        
        这个方法需要浏览器锁保护（同一时间只能一个任务操作 UI）。
        返回 history_id 后立即释放锁，后续轮询不需要锁。
        
        Args:
            reference_images: 多张参考图文件路径列表（全能参考模式）
            character_names: 角色名列表，与 reference_images 一一对应
        
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
        if reference_images:
            print(f"   参考图列表: {len(reference_images)} 张")
        if character_names:
            print(f"   角色名: {character_names}")
        
        try:
            # 整个 submit 过程需要页面锁（UI 操作不可并发）
            with self._page_lock:
                # 0. 导航到生成页面（清除上一轮残留，确保在 generate 而非 home）
                print("   🔄 导航到生成页面（清除上轮状态）...")
                self.page.goto(JIMENG_GENERATE_URL, wait_until='domcontentloaded', timeout=30000)
                self.page.wait_for_load_state('networkidle', timeout=15000)
                time.sleep(1)
                
                # 记录刷新后已存在的视频 URL（避免 DOM 轮询误取旧视频）
                self._pre_existing_video_urls = set()
                try:
                    for v in self.page.query_selector_all('video'):
                        src = v.get_attribute('src') or ''
                        if src and src.startswith('http'):
                            self._pre_existing_video_urls.add(src)
                        current_src = v.evaluate('el => el.currentSrc || ""')
                        if current_src and current_src.startswith('http'):
                            self._pre_existing_video_urls.add(current_src)
                    if self._pre_existing_video_urls:
                        print(f"   📋 记录 {len(self._pre_existing_video_urls)} 个已有视频 URL")
                except:
                    pass
                
                # 1. 导航到对应工具类型的页面
                self._ensure_tool_page(tool_type)
                
                # 2. 选择模型
                if tool_type != 'agent':
                    self.select_model(model)
                
                # 3. 设置方式
                if mode and tool_type == 'video_gen':
                    self.set_mode(mode)
                    time.sleep(2)  # 切换模式后 UI 需要重新渲染
                
                # 4. 设置时长
                self.set_duration(duration)
                
                # 5. 上传参考图片 + 输入提示词（比例放到最后设，因为上传图片会触发即梦自动改比例）
                has_ref_images = reference_images and len(reference_images) > 0
                has_char_names = character_names and len(character_names) > 0
                is_all_ref = mode in ('all_ref', 'subject_ref')
                
                # 清理提示词中的占位符标记 [📷 角色名] → 空
                if has_char_names:
                    import re
                    clean_prompt = prompt
                    for name in character_names:
                        clean_prompt = re.sub(r'\[[^\]]*' + re.escape(name) + r'\]', '', clean_prompt)
                    if clean_prompt != prompt:
                        print(f"   🧹 清理占位符: {prompt[:60]} → {clean_prompt[:60]}")
                        prompt = clean_prompt
                
                if has_ref_images and is_all_ref:
                    # 全能参考模式：先上传多图，然后 @ 引用
                    uploaded = self.upload_multiple_references(reference_images)
                    if uploaded == 0:
                        return {'success': False, 'error': '参考图片全部上传失败'}
                    
                    if has_char_names:
                        if not self.input_prompt_with_at_references(prompt, character_names, mode=mode):
                            return {'success': False, 'error': '输入提示词失败'}
                    else:
                        if not self.input_prompt(prompt):
                            return {'success': False, 'error': '输入提示词失败'}
                elif has_ref_images:
                    # 非全能参考模式（首尾帧/智能多帧/主体参考等）
                    uploaded = 0
                    is_first_last = mode == 'first_last_frame'
                    
                    if is_first_last:
                        # 首尾帧模式：页面左侧有「首帧」和「尾帧」两个带「+」的上传区域
                        frame_labels = ['首帧', '尾帧'] if len(reference_images) > 1 else ['首帧']
                        for i, fp in enumerate(reference_images[:2]):
                            if not os.path.exists(fp):
                                print(f"   ⚠️ 文件不存在，跳过: {fp}")
                                continue
                            label = frame_labels[i] if i < len(frame_labels) else f'图片{i+1}'
                            print(f"   📤 上传{label}: {os.path.basename(fp)}")
                            success = False
                            
                            # 策略1：找到「首帧」/「尾帧」文字标签，点击其所在区域触发上传
                            try:
                                label_el = self.page.query_selector(f'text="{label}"')
                                if label_el and label_el.is_visible():
                                    # 点击标签所在的上传区域（标签本身或父容器）
                                    parent = label_el.evaluate_handle('el => el.closest("[class*=upload], [class*=frame], [class*=add], [class*=trigger]") || el.parentElement')
                                    click_target = parent.as_element() if parent else label_el
                                    try:
                                        with self.page.expect_file_chooser(timeout=5000) as fc_info:
                                            if click_target:
                                                click_target.click()
                                            else:
                                                label_el.click()
                                        file_chooser = fc_info.value
                                        file_chooser.set_files(fp)
                                        time.sleep(3)
                                        uploaded += 1
                                        success = True
                                        print(f"   ✅ {label}已上传（点击标签区域）")
                                    except Exception as e:
                                        print(f"   ⚠️ 点击标签区域方式失败: {e}")
                            except Exception as e:
                                print(f"   ⚠️ 查找标签失败: {e}")
                            
                            # 策略2：直接用 input[type="file"] 按顺序分配
                            if not success:
                                file_inputs = self.page.query_selector_all('input[type="file"]')
                                if i < len(file_inputs):
                                    try:
                                        file_inputs[i].set_input_files(fp)
                                        time.sleep(3)
                                        uploaded += 1
                                        success = True
                                        print(f"   ✅ {label}已上传（input 方式）")
                                    except Exception as e:
                                        print(f"   ⚠️ input 方式失败: {e}")
                            
                            # 策略3：找页面上第 i 个可见的「+」按钮
                            if not success:
                                plus_btns = self.page.query_selector_all('text="+"')
                                visible_plus = []
                                for btn in plus_btns:
                                    try:
                                        if btn.is_visible():
                                            visible_plus.append(btn)
                                    except:
                                        continue
                                if i < len(visible_plus):
                                    try:
                                        with self.page.expect_file_chooser(timeout=5000) as fc_info:
                                            visible_plus[i].click()
                                        file_chooser = fc_info.value
                                        file_chooser.set_files(fp)
                                        time.sleep(3)
                                        uploaded += 1
                                        success = True
                                        print(f"   ✅ {label}已上传（+ 按钮方式）")
                                    except Exception as e:
                                        print(f"   ⚠️ + 按钮方式失败: {e}")
                            
                            if not success:
                                print(f"   ❌ {label}上传失败：所有策略均未成功")
                    else:
                        # 其他非全能参考模式：用通用 file input 上传
                        file_inputs = self.page.query_selector_all('input[type="file"]')
                        for i, fp in enumerate(reference_images):
                            if i >= len(file_inputs):
                                break
                            if os.path.exists(fp):
                                try:
                                    file_inputs[i].set_input_files(fp)
                                    time.sleep(2)
                                    uploaded += 1
                                    print(f"   ✅ 上传图片 {i+1}: {os.path.basename(fp)}")
                                except Exception as e:
                                    print(f"   ⚠️ 上传图片 {i+1} 失败: {e}")
                    
                    if uploaded == 0:
                        print("   ⚠️ 未能上传任何图片，继续生成")
                    
                    if not self.input_prompt(prompt):
                        return {'success': False, 'error': '输入提示词失败'}
                else:
                    # 原有逻辑：单图上传 + 普通提示词
                    if reference_file and os.path.exists(reference_file):
                        if not self.upload_reference_image(reference_file):
                            return {'success': False, 'error': '上传参考图片失败'}
                    
                    if not self.input_prompt(prompt):
                        return {'success': False, 'error': '输入提示词失败'}
                
                # 7. 设置宽高比（必须在上传和提示词之后，因为即梦会根据图片自动改比例）
                self.set_aspect_ratio(aspect_ratio)
                time.sleep(0.5)
                
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
        
        # 记录轮询开始时页面已有的错误文本（防止误检上一次任务的旧错误）
        _initial_errors = set()
        try:
            with self._page_lock:
                for err_text in ['不符合平台规则', '不符合', '生成失败', '未通过审核', '视频未通过审核', '重新编辑']:
                    el = self.page.query_selector(f'text={err_text}')
                    if el and el.is_visible():
                        _initial_errors.add(err_text)
                if _initial_errors:
                    print(f"   ⚠️ 页面已有旧错误文本（将忽略）: {_initial_errors}")
        except:
            pass
        
        while time.time() - start_time < max_wait:
            elapsed = int(time.time() - start_time)
            
            # 动态获取 history_id（生成响应可能晚于 click_generate_and_get_id 的等待窗口）
            if not history_id and self._last_generate_response:
                history_id = self._extract_history_id(self._last_generate_response)
                if history_id:
                    print(f"   📡 延迟获取到 history_id: {history_id}")
            
            # 方法1：通过 history_id 精准匹配（优先，只读字典不需要页面锁）
            if history_id and history_id in self._pending_tasks:
                task = self._pending_tasks[history_id]
                if elapsed % 15 == 0 and str(elapsed) + '_pt' != last_check:
                    print(f"   📡 pending_task[{history_id}]: status={task['status']}, has_url={bool(task.get('video_url'))}")
                    last_check = str(elapsed) + '_pt'
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
            elif history_id and elapsed % 15 == 0 and str(elapsed) + '_npt' != last_check:
                print(f"   ⚠️ history_id={history_id} 不在 pending_tasks 中 (共 {len(self._pending_tasks)} 个任务)")
                last_check = str(elapsed) + '_npt'
            
            # 方法2：检查生成响应是否有错误（只读字典，不需要页面锁）
            if self._generate_response:
                ret = str(self._generate_response.get('ret', ''))
                if ret != '0':
                    errmsg = self._generate_response.get('errmsg', '未知错误')
                    return {'success': False, 'error': f'生成请求失败: ret={ret}, msg={errmsg}'}
            
            # 方法3：页面 DOM 检测（需要短锁，作为 history_id 模式的后备）
            # 如果有 history_id 正在追踪，DOM 检测延迟到 60s 后再启用（优先信任网络监听）
            dom_check_threshold = 60 if (history_id and history_id in self._pending_tasks) else 10
            if elapsed >= dom_check_threshold:
                pre_existing = getattr(self, '_pre_existing_video_urls', set())
                with self._page_lock:
                    try:
                        # 辅助函数：过滤掉加载动画/占位符/静态资源等非真实视频 URL
                        def _is_real_video_url(url):
                            if not url or not url.startswith('http'):
                                return False
                            # 过滤即梦的加载动画和静态资源
                            skip_patterns = ['record-load', 'static/media', 'loading', 'placeholder', 'skeleton', 'preview-', 'lottie']
                            for p in skip_patterns:
                                if p in url:
                                    return False
                            # 真实视频 URL 通常包含特定模式
                            return True
                        
                        video_el = self.page.query_selector('video[src]')
                        if video_el:
                            video_src = video_el.get_attribute('src')
                            if elapsed % 15 == 0:
                                print(f"   🔍 DOM video src: {video_src[:80] if video_src else 'None'}... pre_existing={len(pre_existing)}")
                            if _is_real_video_url(video_src) and video_src not in pre_existing:
                                print(f"   ✅ 检测到新视频元素 ({elapsed}s)")
                                if save_path:
                                    if download_video(video_src, save_path):
                                        return {'success': True, 'video_path': save_path, 'video_url': video_src}
                                return {'success': True, 'video_url': video_src}
                        
                        # 也检查 currentSrc（有些视频通过 JS 动态设置）
                        video_blob = self.page.query_selector('video')
                        if video_blob:
                            current_src = video_blob.evaluate('el => el.currentSrc || ""')
                            if _is_real_video_url(current_src) and current_src not in pre_existing:
                                print(f"   ✅ 通过 currentSrc 检测到视频 ({elapsed}s)")
                                if save_path:
                                    if download_video(current_src, save_path):
                                        return {'success': True, 'video_path': save_path, 'video_url': current_src}
                                return {'success': True, 'video_url': current_src}
                        
                        download_btn = self.page.query_selector('text=下载')
                        if download_btn and download_btn.is_visible():
                            video_url = self._extract_video_url_from_page()
                            if video_url and video_url not in pre_existing:
                                print(f"   ✅ 视频生成完成 ({elapsed}s)")
                                if save_path:
                                    if download_video(video_url, save_path):
                                        return {'success': True, 'video_path': save_path, 'video_url': video_url}
                                return {'success': True, 'video_url': video_url}
                    except:
                        pass
                
            # 检查网络监听的历史记录响应（只读列表，不需要页面锁）
            if self._video_responses and elapsed % 15 == 0:
                print(f"   📡 video_responses 数量: {len(self._video_responses)}")
            for resp in self._video_responses:
                video_url = self._extract_video_url_from_response(resp)
                if video_url:
                    print(f"   ✅ 从网络响应获取到视频 URL ({elapsed}s)")
                    if save_path:
                        if download_video(video_url, save_path):
                            return {'success': True, 'video_path': save_path, 'video_url': video_url}
                    return {'success': True, 'video_url': video_url}
            
            # 检查页面状态提示（需要短锁，至少 15s 后再检测错误，避免误检旧错误）
            if elapsed >= 15:
                with self._page_lock:
                    try:
                        # 错误检测：只检测新出现的错误
                        error_el = self.page.query_selector('text=生成失败')
                        if error_el and error_el.is_visible() and '生成失败' not in _initial_errors:
                            return {'success': False, 'error': '页面显示生成失败'}
                        
                        review_el = self.page.query_selector('text=未通过审核')
                        if not review_el:
                            review_el = self.page.query_selector('text=视频未通过审核')
                        if review_el and review_el.is_visible():
                            if '未通过审核' not in _initial_errors and '视频未通过审核' not in _initial_errors:
                                return {'success': False, 'error': '内容未通过审核'}
                        
                        # 检测平台规则违规
                        rule_el = self.page.query_selector('text=不符合平台规则')
                        if rule_el and rule_el.is_visible() and '不符合平台规则' not in _initial_errors:
                            return {'success': False, 'error': '内容不符合平台规则'}
                        
                        # 检测重新编辑按钮（只检测新出现的）
                        reedit_el = self.page.query_selector('text=重新编辑')
                        if reedit_el and reedit_el.is_visible() and '重新编辑' not in _initial_errors:
                            return {'success': False, 'error': '生成失败（页面显示重新编辑按钮）'}
                        
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
