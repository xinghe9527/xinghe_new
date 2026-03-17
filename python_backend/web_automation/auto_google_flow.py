#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Google Flow 网页自动化脚本

Google Flow（labs.google/fx/flow）AI 图片生成自动化
使用 Playwright + BrowserManager（系统浏览器 CDP 连接）

架构：与 Vidu/即梦一致的两阶段分离
  - submit_generate()  → UI 操作提交生成（需要锁）
  - poll_result()      → 等待并获取结果（无需锁）
"""

import sys
import os
import io
import re
import time
import json
import threading
import urllib.request
import urllib.error
from typing import Optional, Dict, Any

# 确保 UTF-8 输出
if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')
    except:
        pass

_original_print = print
def _safe_print(*args, **kwargs):
    try:
        _original_print(*args, **kwargs)
    except (OSError, IOError, ValueError):
        pass
print = _safe_print

# 脚本目录
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Google Flow 工作区 URL
FLOW_WORKSPACE_URL = 'https://labs.google/fx/flow'
FLOW_TOOL_URLS = {
    'text2image': 'https://labs.google/fx/flow',
}


class GoogleFlowAutomation:
    """
    Google Flow 图片生成自动化
    
    使用 BrowserManager 连接系统浏览器（Edge/Chrome），
    在 Google Flow 工作区中自动输入提示词、点击生成、抓取结果图片。
    """
    
    def __init__(self, cdp_port: int = 9226):
        """
        初始化
        
        Args:
            cdp_port: CDP 调试端口（默认 9224，与 Vidu 的 9222 和即梦的 9223 错开）
        """
        self.cdp_port = cdp_port
        self._browser_mgr = None
        self.page = None
        self._cdp_session = None  # CDP session，用于底层 Input 事件
        self._started = False
        self._page_lock = threading.Lock()
        self._last_submit_time = 0
        self._min_submit_interval = 3.0  # Google 可能有反爬,间隔稍长
        self._captured_responses = []
        self._network_listener_active = False
        self._cdp_request_map = {}
    
    def start(self) -> bool:
        """启动浏览器连接"""
        try:
            from browser_manager import BrowserManager
            
            print(f"\n{'='*60}")
            print(f"  🌐 Google Flow 自动化启动")
            print(f"  📡 CDP 端口: {self.cdp_port}")
            print(f"{'='*60}\n")
            
            self._browser_mgr = BrowserManager(
                cdp_port=self.cdp_port,
                profile_name='google_flow',
            )
            
            self.page = self._browser_mgr.connect_or_launch(
                target_url=FLOW_WORKSPACE_URL
            )
            
            if self.page:
                self._started = True
                # 先创建 CDP session，再设置网络监听（CDP 监听需要 session）
                try:
                    self._cdp_session = self.page.context.new_cdp_session(self.page)
                except Exception as e:
                    print(f"   ⚠️  CDP session 创建失败: {e}")
                self._setup_network_listener()
                print(f"   ✅ Google Flow 浏览器已连接")
                print(f"   📄 当前页面: {self.page.url[:80]}")
                return True
            else:
                print(f"   ❌ 无法获取页面")
                return False
                
        except Exception as e:
            print(f"   ❌ 启动失败: {e}")
            return False
    
    def stop(self):
        """断开浏览器连接"""
        try:
            if self._cdp_session:
                self._cdp_session.detach()
        except:
            pass
        self._cdp_session = None
        try:
            if self._browser_mgr:
                self._browser_mgr.disconnect()
        except:
            pass
        self._started = False
        self.page = None
        self._browser_mgr = None
        print("   ✅ Google Flow 已断开连接")
    
    def check_login(self) -> bool:
        """检查 Google 登录状态"""
        try:
            if not self.page:
                return False
            
            url = self.page.url
            
            # 如果在登录页或 about 页，说明未登录
            if 'accounts.google.com' in url:
                print("   ⚠️  当前在 Google 登录页，需要先登录")
                return False
            
            # 如果在 Flow 工作区内，说明已登录
            if 'labs.google' in url and ('flow' in url or 'fx' in url):
                # 进一步确认：检查页面上有没有用户头像或创建按钮
                try:
                    # 检查是否有常见的已登录标识
                    has_avatar = self.page.locator('img[alt*="avatar"], img[alt*="profile"], button[aria-label*="Account"], button[aria-label*="Google 账号"]').count() > 0
                    has_workspace = self.page.locator('textarea, [contenteditable="true"], [role="textbox"]').count() > 0
                    
                    if has_avatar or has_workspace:
                        print("   ✅ Google Flow 已登录")
                        return True
                except:
                    pass
                
                # 即使没检测到头像，如果 URL 对就认为登录了
                print("   ✅ Google Flow 页面已加载（URL 正确）")
                return True
            
            print(f"   ⚠️  当前页面不在 Flow 工作区: {url[:80]}")
            return False
            
        except Exception as e:
            print(f"   ❌ 检查登录失败: {e}")
            return False
    
    def _setup_network_listener(self):
        """设置网络监听器，通过 CDP Network 域捕获 API 响应"""
        if self._network_listener_active:
            return
        
        try:
            # 方式 1: Playwright page.on('response')
            def on_response(response):
                try:
                    url = response.url
                    if response.request.method == 'POST' and any(kw in url for kw in [
                        'batchGenerateImages',
                    ]):
                        if 'batchLog' in url or 'reportClientSideError' in url or 'recaptcha' in url:
                            return
                        try:
                            body = response.json()
                            self._captured_responses.append({
                                'url': url,
                                'body': body,
                                'time': time.time(),
                            })
                            if len(self._captured_responses) > 20:
                                self._captured_responses = self._captured_responses[-20:]
                            print(f"   📡 捕获 API 响应: {url[:60]}...")
                        except:
                            pass
                except:
                    pass
            
            self.page.on('response', on_response)
            
            # 方式 2: CDP Network 域监听（更可靠，对 CDP 连接的已有页面也有效）
            if self._cdp_session:
                self._setup_cdp_network_listener()
            
            self._network_listener_active = True
            print("   ✅ 网络监听器已启动")
        except Exception as e:
            print(f"   ⚠️  网络监听器启动失败: {e}")
    
    def _setup_cdp_network_listener(self):
        """通过 CDP Network 域监听 batchGenerateImages 响应"""
        try:
            # 记录请求 ID → URL 映射
            self._cdp_request_map = {}
            
            def on_request(params):
                req_id = params.get('requestId', '')
                url = params.get('request', {}).get('url', '')
                method = params.get('request', {}).get('method', '')
                if method == 'POST' and 'batchGenerateImages' in url:
                    self._cdp_request_map[req_id] = url
            
            def on_response_received(params):
                req_id = params.get('requestId', '')
                if req_id in self._cdp_request_map:
                    # 异步获取响应体
                    try:
                        result = self._cdp_session.send('Network.getResponseBody', {
                            'requestId': req_id
                        })
                        body_str = result.get('body', '')
                        if result.get('base64Encoded'):
                            import base64
                            body_str = base64.b64decode(body_str).decode('utf-8')
                        body = json.loads(body_str)
                        url = self._cdp_request_map.pop(req_id, '')
                        self._captured_responses.append({
                            'url': url,
                            'body': body,
                            'time': time.time(),
                        })
                        if len(self._captured_responses) > 20:
                            self._captured_responses = self._captured_responses[-20:]
                        print(f"   📡 [CDP] 捕获 API 响应: {url[:60]}...")
                    except Exception as e:
                        # responseReceived 时 body 可能还没完全到达，
                        # 改在 loadingFinished 中获取
                        pass
            
            def on_loading_finished(params):
                req_id = params.get('requestId', '')
                if req_id in self._cdp_request_map:
                    try:
                        result = self._cdp_session.send('Network.getResponseBody', {
                            'requestId': req_id
                        })
                        body_str = result.get('body', '')
                        if result.get('base64Encoded'):
                            import base64
                            body_str = base64.b64decode(body_str).decode('utf-8')
                        body = json.loads(body_str)
                        url = self._cdp_request_map.pop(req_id, '')
                        self._captured_responses.append({
                            'url': url,
                            'body': body,
                            'time': time.time(),
                        })
                        if len(self._captured_responses) > 20:
                            self._captured_responses = self._captured_responses[-20:]
                        print(f"   📡 [CDP] 捕获 API 响应: {url[:60]}...")
                    except Exception as e:
                        self._cdp_request_map.pop(req_id, None)
            
            self._cdp_session.on('Network.requestWillBeSent', on_request)
            self._cdp_session.on('Network.responseReceived', on_response_received)
            self._cdp_session.on('Network.loadingFinished', on_loading_finished)
            self._cdp_session.send('Network.enable')
            print("   ✅ CDP 网络监听已启用")
        except Exception as e:
            print(f"   ⚠️  CDP 网络监听启用失败: {e}")
    
    def _ensure_flow_page(self, force_reload: bool = False) -> bool:
        """确保在 Flow 工作区页面"""
        try:
            url = self.page.url
            
            # URL 含 labs.google 且含 flow 或 fx 就认为已在工作区
            if 'labs.google' in url and ('flow' in url or 'fx' in url):
                if force_reload:
                    print("   🔄 强制刷新页面...")
                    self.page.reload(wait_until='domcontentloaded', timeout=30000)
                    time.sleep(5)
                return True
            
            # 导航到 Flow 工作区
            print(f"   🌐 导航到 Google Flow 工作区...")
            self.page.goto(FLOW_WORKSPACE_URL, wait_until='domcontentloaded', timeout=30000)
            time.sleep(6)
            
            # 检查是否成功（URL 可能被重定向到 /fx/zh/tools/flow/...）
            final_url = self.page.url
            return 'labs.google' in final_url
            
        except Exception as e:
            print(f"   ❌ 页面导航失败: {e}")
            return False
    
    def _find_prompt_input(self):
        """查找提示词输入框（Slate.js 编辑器）"""
        try:
            el = self.page.locator('[data-slate-editor="true"]').first
            if el.is_visible(timeout=5000):
                print(f"   📝 找到 Slate 编辑器输入框")
                return el
        except:
            pass
        
        # 降级选择器
        selectors = [
            'div[role="textbox"][contenteditable="true"]',
            '[contenteditable="true"][role="textbox"]',
        ]
        for selector in selectors:
            try:
                el = self.page.locator(selector).first
                if el.is_visible(timeout=3000):
                    print(f"   📝 找到输入框: {selector}")
                    return el
            except:
                continue
        
        return None
    
    def _clear_and_input_prompt(self, prompt: str) -> bool:
        """清空并输入提示词（使用 CDP 底层事件驱动 Slate.js 编辑器）"""
        try:
            input_el = self._find_prompt_input()
            if not input_el:
                print("   ❌ 未找到提示词输入框")
                return False
            
            # 获取编辑器中心坐标
            box = input_el.bounding_box()
            if not box:
                print("   ❌ 无法获取输入框位置")
                return False
            
            cx = box['x'] + box['width'] / 2
            cy = box['y'] + box['height'] / 2
            
            cdp = self._cdp_session
            if not cdp:
                print("   ❌ CDP session 未就绪")
                return False
            
            # 1. CDP 点击聚焦编辑器
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mousePressed',
                'x': cx, 'y': cy,
                'button': 'left', 'clickCount': 1,
            })
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mouseReleased',
                'x': cx, 'y': cy,
                'button': 'left', 'clickCount': 1,
            })
            time.sleep(0.3)
            
            # 2. Ctrl+A 全选
            cdp.send('Input.dispatchKeyEvent', {
                'type': 'keyDown', 'modifiers': 2,
                'key': 'a', 'code': 'KeyA', 'windowsVirtualKeyCode': 65,
            })
            cdp.send('Input.dispatchKeyEvent', {
                'type': 'keyUp', 'modifiers': 2,
                'key': 'a', 'code': 'KeyA', 'windowsVirtualKeyCode': 65,
            })
            time.sleep(0.1)
            
            # 3. Backspace 删除
            cdp.send('Input.dispatchKeyEvent', {
                'type': 'keyDown',
                'key': 'Backspace', 'code': 'Backspace', 'windowsVirtualKeyCode': 8,
            })
            cdp.send('Input.dispatchKeyEvent', {
                'type': 'keyUp',
                'key': 'Backspace', 'code': 'Backspace', 'windowsVirtualKeyCode': 8,
            })
            time.sleep(0.3)
            
            # 4. 用 CDP Input.insertText 输入（正确触发 Slate.js 的 onBeforeInput）
            cdp.send('Input.insertText', {'text': prompt})
            time.sleep(0.5)
            
            print(f"   ✅ 已输入提示词: {prompt[:50]}...")
            return True
            
        except Exception as e:
            print(f"   ❌ 输入提示词失败: {e}")
            return False
    
    def _click_generate(self) -> bool:
        """点击生成按钮（使用 CDP 底层鼠标事件，确保 isTrusted=true）"""
        try:
            # 获取 arrow_forward 按钮坐标
            btn_coords = self.page.evaluate("""() => {
                const btn = Array.from(document.querySelectorAll('button'))
                    .find(b => b.textContent.includes('arrow_forward'));
                if (!btn) return null;
                const r = btn.getBoundingClientRect();
                return { cx: r.x + r.width/2, cy: r.y + r.height/2, disabled: btn.disabled };
            }""")
            
            if not btn_coords:
                print("   ❌ 未找到生成按钮")
                return False
            
            if btn_coords.get('disabled'):
                print("   ⏳ 按钮被禁用，等待...")
                for _ in range(30):
                    time.sleep(1)
                    check = self.page.evaluate("""() => {
                        const btn = Array.from(document.querySelectorAll('button'))
                            .find(b => b.textContent.includes('arrow_forward'));
                        return btn ? !btn.disabled : false;
                    }""")
                    if check:
                        # 重新获取坐标
                        btn_coords = self.page.evaluate("""() => {
                            const btn = Array.from(document.querySelectorAll('button'))
                                .find(b => b.textContent.includes('arrow_forward'));
                            const r = btn.getBoundingClientRect();
                            return { cx: r.x + r.width/2, cy: r.y + r.height/2 };
                        }""")
                        break
                else:
                    print("   ⚠️  按钮始终禁用")
                    return False
            
            bx, by = btn_coords['cx'], btn_coords['cy']
            
            cdp = self._cdp_session
            if not cdp:
                print("   ❌ CDP session 未就绪")
                return False
            
            # CDP 底层鼠标点击
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mousePressed',
                'x': bx, 'y': by,
                'button': 'left', 'clickCount': 1,
            })
            time.sleep(0.05)
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mouseReleased',
                'x': bx, 'y': by,
                'button': 'left', 'clickCount': 1,
            })
            
            print(f"   ✅ 点击了生成按钮 (CDP)")
            time.sleep(2)
            return True
            
        except Exception as e:
            print(f"   ❌ 点击生成按钮失败: {e}")
            return False
    
    def _close_settings_panel(self):
        """关闭底部设置面板"""
        try:
            cdp = self._cdp_session
            # 先用 Escape
            cdp.send('Input.dispatchKeyEvent', {
                'type': 'keyDown', 'key': 'Escape', 'code': 'Escape',
                'windowsVirtualKeyCode': 27,
            })
            cdp.send('Input.dispatchKeyEvent', {
                'type': 'keyUp', 'key': 'Escape', 'code': 'Escape',
                'windowsVirtualKeyCode': 27,
            })
            time.sleep(0.3)
            
            # 检查面板是否关闭
            still_open = self.page.evaluate("""() => {
                const menu = document.querySelector('[role="menu"]');
                if (!menu) return false;
                const r = menu.getBoundingClientRect();
                return r.width > 0 && r.height > 0;
            }""")
            
            if still_open:
                # 点击画布空白区域（面板上方）来关闭
                cdp.send('Input.dispatchMouseEvent', {
                    'type': 'mousePressed',
                    'x': 400, 'y': 400,
                    'button': 'left', 'clickCount': 1,
                })
                cdp.send('Input.dispatchMouseEvent', {
                    'type': 'mouseReleased',
                    'x': 400, 'y': 400,
                    'button': 'left', 'clickCount': 1,
                })
                time.sleep(0.3)
        except:
            pass
    
    def _dismiss_popups(self):
        """关闭页面上可能出现的确认弹窗/对话框（选择取消/保留而非删除）"""
        try:
            dismissed = self.page.evaluate("""() => {
                // 查找 dialog 或 modal
                const dialogs = document.querySelectorAll('[role="dialog"], [role="alertdialog"]');
                for (const dlg of dialogs) {
                    const rect = dlg.getBoundingClientRect();
                    if (rect.width === 0) continue;
                    
                    const buttons = Array.from(dlg.querySelectorAll('button'));
                    
                    // 优先找取消/关闭/否定按钮（避免误删数据）
                    const safeBtn = buttons.find(b => {
                        const t = (b.textContent || '').trim().toLowerCase();
                        return t.includes('取消') || t.includes('cancel') || t === '否' 
                            || t.includes('关闭') || t.includes('close')
                            || t.includes('保留') || t.includes('keep');
                    });
                    if (safeBtn) {
                        safeBtn.click();
                        return 'dismissed:' + safeBtn.textContent.trim();
                    }
                    
                    // 找关闭按钮（X 图标）
                    const closeBtn = dlg.querySelector('[aria-label="close"], [aria-label="关闭"]')
                        || dlg.querySelector('button svg') && dlg.querySelector('button svg').closest('button');
                    if (closeBtn) {
                        closeBtn.click();
                        return 'closed:x';
                    }
                }
                return null;
            }""")
            if dismissed:
                print(f"   🔄 已关闭弹窗: {dismissed}")
                time.sleep(0.5)
        except:
            pass
    
    def _open_settings_panel(self) -> bool:
        """打开底部设置面板（比例/数量/模型选择器）"""
        try:
            # 检查设置面板是否已经打开（通过查找 role="menu" 面板）
            is_open = self.page.evaluate("""() => {
                const menu = document.querySelector('[role="menu"]');
                if (!menu) return false;
                const tabs = menu.querySelectorAll('[role="tablist"]');
                return tabs.length >= 2;  // 至少有比例和数量两个 tablist
            }""")
            
            if is_open:
                return True
            
            # 点击底部的模型/设置按钮来打开面板
            coords = self.page.evaluate("""() => {
                // 查找包含模型名和设置信息的按钮（如 "🍌 Nano Banana 2crop_16_9x1"）
                const btns = Array.from(document.querySelectorAll('button'));
                const btn = btns.find(b => {
                    const t = b.textContent || '';
                    return (t.includes('Banana') || t.includes('crop_') || t.includes('x1') || t.includes('x2'))
                        && b.getBoundingClientRect().y > 900;
                });
                if (!btn) return null;
                const r = btn.getBoundingClientRect();
                return {x: r.x + r.width/2, y: r.y + r.height/2};
            }""")
            
            if not coords:
                print("   ⚠️  未找到设置面板按钮")
                return False
            
            cdp = self._cdp_session
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mousePressed',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mouseReleased',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            time.sleep(0.5)
            return True
        except Exception as e:
            print(f"   ⚠️  打开设置面板失败: {e}")
            return False
    
    def _set_aspect_ratio(self, aspect_ratio: str) -> bool:
        """
        设置生成图片的比例
        
        Args:
            aspect_ratio: '16:9' (横向) 或 '9:16' (纵向)，其他值忽略
        """
        if aspect_ratio not in ('16:9', '9:16'):
            return True  # 不支持的比例直接跳过
        
        try:
            if not self._open_settings_panel():
                print("   ⚠️  无法打开设置面板，跳过比例设置")
                return True
            
            # 确定目标按钮文本
            target = '横向' if aspect_ratio == '16:9' else '纵向'
            
            # 检查当前是否已经是目标比例
            already_selected = self.page.evaluate("""(target) => {
                const tabs = document.querySelectorAll('[role="tab"]');
                for (const tab of tabs) {
                    if (tab.textContent.includes(target) && tab.getAttribute('aria-selected') === 'true') {
                        return true;
                    }
                }
                return false;
            }""", target)
            
            if already_selected:
                print(f"   ✅ 比例已是 {aspect_ratio}（{target}）")
                return True
            
            # 点击目标比例按钮
            coords = self.page.evaluate("""(target) => {
                const tabs = document.querySelectorAll('[role="tab"]');
                for (const tab of tabs) {
                    if (tab.textContent.includes(target)) {
                        const r = tab.getBoundingClientRect();
                        return {x: r.x + r.width/2, y: r.y + r.height/2};
                    }
                }
                return null;
            }""", target)
            
            if not coords:
                print(f"   ⚠️  未找到 {target} 按钮")
                return True
            
            cdp = self._cdp_session
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mousePressed',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mouseReleased',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            time.sleep(0.3)
            print(f"   ✅ 比例已设为 {aspect_ratio}（{target}）")
            return True
        except Exception as e:
            print(f"   ⚠️  设置比例失败: {e}")
            return True  # 非致命错误
    
    def _set_batch_count(self, count: int) -> bool:
        """
        设置生成数量
        
        Args:
            count: 1-4，其他值忽略
        """
        if count not in (1, 2, 3, 4):
            return True  # 不支持的数量直接跳过
        
        try:
            if not self._open_settings_panel():
                print("   ⚠️  无法打开设置面板，跳过数量设置")
                return True
            
            target = f'x{count}'
            
            # 检查当前是否已经是目标数量
            already_selected = self.page.evaluate("""(target) => {
                const tabs = document.querySelectorAll('[role="tab"]');
                for (const tab of tabs) {
                    if (tab.textContent.trim() === target && tab.getAttribute('aria-selected') === 'true') {
                        return true;
                    }
                }
                return false;
            }""", target)
            
            if already_selected:
                print(f"   ✅ 数量已是 {target}")
                return True
            
            # 点击目标数量按钮
            coords = self.page.evaluate("""(target) => {
                const tabs = document.querySelectorAll('[role="tab"]');
                for (const tab of tabs) {
                    if (tab.textContent.trim() === target) {
                        const r = tab.getBoundingClientRect();
                        return {x: r.x + r.width/2, y: r.y + r.height/2};
                    }
                }
                return null;
            }""", target)
            
            if not coords:
                print(f"   ⚠️  未找到 {target} 按钮")
                return True
            
            cdp = self._cdp_session
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mousePressed',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mouseReleased',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            time.sleep(0.3)
            print(f"   ✅ 数量已设为 {target}")
            return True
        except Exception as e:
            print(f"   ⚠️  设置数量失败: {e}")
            return True  # 非致命错误

    # 模型 ID → Flow 页面显示名映射
    _MODEL_DISPLAY_NAMES = {
        'nano-banana-pro': 'Nano Banana Pro',
        'nano-banana-2': 'Nano Banana 2',
    }

    def _set_model(self, model: str) -> bool:
        """
        在 Flow 设置面板中切换模型

        Args:
            model: 模型 ID，如 'nano-banana-pro' 或 'nano-banana-2'
        """
        display_name = self._MODEL_DISPLAY_NAMES.get(model)
        if not display_name:
            print(f"   ⚠️  未知模型 ID: {model}，跳过模型切换")
            return True

        try:
            if not self._open_settings_panel():
                print("   ⚠️  无法打开设置面板，跳过模型切换")
                return True

            # 检查当前模型是否已经是目标模型
            current = self.page.evaluate("""(target) => {
                // 在设置面板中找模型下拉按钮（含 arrow_drop_down 的按钮）
                const menu = document.querySelector('[role="menu"]');
                if (!menu) return null;
                const btns = Array.from(menu.querySelectorAll('button'));
                const btn = btns.find(b => b.textContent && b.textContent.includes('arrow_drop_down') && b.textContent.includes('Banana'));
                if (!btn) return null;
                const text = btn.textContent || '';
                return text.includes(target) ? 'match' : 'mismatch';
            }""", display_name)

            if current == 'match':
                print(f"   ✅ 模型已是 {display_name}")
                return True

            if current is None:
                print("   ⚠️  未找到模型下拉按钮")
                return True

            # 点击模型下拉按钮
            coords = self.page.evaluate("""() => {
                const menu = document.querySelector('[role="menu"]');
                if (!menu) return null;
                const btns = Array.from(menu.querySelectorAll('button'));
                const btn = btns.find(b => b.textContent && b.textContent.includes('arrow_drop_down') && b.textContent.includes('Banana'));
                if (!btn) return null;
                const r = btn.getBoundingClientRect();
                return {x: r.x + r.width/2, y: r.y + r.height/2};
            }""")

            if not coords:
                print("   ⚠️  无法定位模型下拉按钮")
                return True

            cdp = self._cdp_session
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mousePressed',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mouseReleased',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            time.sleep(0.5)

            # 在展开的下拉列表中找目标模型并点击
            option_coords = self.page.evaluate("""(target) => {
                // 下拉选项可能是 menuitem / option / listbox 内的元素
                // 也可能是普通 div/span，遍历所有可见元素
                const candidates = document.querySelectorAll('[role="menuitem"], [role="option"], [role="listbox"] *, [role="menu"] *');
                for (const el of candidates) {
                    const t = (el.textContent || '').trim();
                    // 准确匹配目标模型名称
                    if (t.includes(target) && el.getBoundingClientRect().height > 0) {
                        const r = el.getBoundingClientRect();
                        return {x: r.x + r.width/2, y: r.y + r.height/2};
                    }
                }
                return null;
            }""", display_name)

            if not option_coords:
                print(f"   ⚠️  下拉列表中未找到 {display_name}")
                # 按 Escape 关闭下拉
                cdp.send('Input.dispatchKeyEvent', {'type': 'keyDown', 'key': 'Escape', 'code': 'Escape'})
                cdp.send('Input.dispatchKeyEvent', {'type': 'keyUp', 'key': 'Escape', 'code': 'Escape'})
                return True

            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mousePressed',
                'x': option_coords['x'], 'y': option_coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mouseReleased',
                'x': option_coords['x'], 'y': option_coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            time.sleep(0.5)
            print(f"   ✅ 模型已切换为 {display_name}")
            return True
        except Exception as e:
            print(f"   ⚠️  切换模型失败: {e}")
            return True  # 非致命错误

    def _upload_reference_image(self, file_paths) -> list:
        """
        上传参考图片到 Flow 画布（支持单个路径或路径列表）
        
        流程：
        1. 点击 "add_2创建" 按钮 → 弹出对话框
        2. 点击 "upload上传图片" → 触发 file input（支持 multiple）
        3. 通过 file chooser 选择文件
        
        Returns:
            list: 上传后页面所有图片 URL 列表（用于后续排除），失败返回 None
        """
        try:
            # 统一为列表
            if isinstance(file_paths, str):
                file_paths = [file_paths]
            
            # 验证文件存在
            valid_paths = []
            for fp in file_paths:
                if os.path.exists(fp):
                    valid_paths.append(fp)
                else:
                    print(f"   ⚠️  参考图片不存在，跳过: {fp}")
            
            if not valid_paths:
                print(f"   ❌ 没有有效的参考图片")
                return None
            
            print(f"   📸 上传 {len(valid_paths)} 张参考图片")
            for fp in valid_paths:
                print(f"      - {fp}")
            
            # STEP 1: 点击 "add_2创建" 按钮（带重试，等页面加载完毕）
            coords = None
            for attempt in range(6):  # 最多重试 6 次（共 ~3s）
                coords = self.page.evaluate("""() => {
                    const btn = Array.from(document.querySelectorAll('button'))
                        .find(b => {
                            const t = (b.textContent || '').trim();
                            return (t.includes('add_2') && t.includes('创建'))
                                || t.includes('add_2创建')
                                || (t.includes('创建') && t.includes('add'));
                        });
                    if (!btn) return null;
                    const r = btn.getBoundingClientRect();
                    return {x: r.x + r.width/2, y: r.y + r.height/2};
                }""")
                if coords:
                    break
                self.page.wait_for_timeout(500)
            
            if not coords:
                print("   ❌ 未找到 'add_2创建' 按钮（已重试 3s）")
                return None
            
            cdp = self._cdp_session
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mousePressed',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            cdp.send('Input.dispatchMouseEvent', {
                'type': 'mouseReleased',
                'x': coords['x'], 'y': coords['y'],
                'button': 'left', 'clickCount': 1,
            })
            time.sleep(1)
            
            # 验证对话框弹出
            dialog = self.page.evaluate("""() => {
                const dlg = document.querySelector('[role="dialog"][data-state="open"]');
                if (!dlg) return null;
                const btn = Array.from(dlg.querySelectorAll('button'))
                    .find(b => b.textContent.includes('上传图片') || b.textContent.includes('upload'));
                if (!btn) return null;
                const r = btn.getBoundingClientRect();
                return {x: r.x + r.width/2, y: r.y + r.height/2};
            }""")
            
            if not dialog:
                print("   ❌ 上传对话框未弹出或未找到上传按钮")
                return None
            
            # STEP 2: 点击 "upload上传图片" 并拦截 file chooser（支持多文件）
            try:
                with self.page.expect_file_chooser(timeout=5000) as fc_info:
                    cdp.send('Input.dispatchMouseEvent', {
                        'type': 'mousePressed',
                        'x': dialog['x'], 'y': dialog['y'],
                        'button': 'left', 'clickCount': 1,
                    })
                    cdp.send('Input.dispatchMouseEvent', {
                        'type': 'mouseReleased',
                        'x': dialog['x'], 'y': dialog['y'],
                        'button': 'left', 'clickCount': 1,
                    })
                
                file_chooser = fc_info.value
                file_chooser.set_files(valid_paths)
                print(f"   ✅ {len(valid_paths)} 张参考图片已上传")
            except Exception as e:
                print(f"   ⚠️  file_chooser 拦截失败: {e}，尝试直接设置 file input...")
                try:
                    file_input = self.page.locator('input[type="file"][accept="image/*"]')
                    file_input.set_input_files(valid_paths)
                    print(f"   ✅ {len(valid_paths)} 张参考图片已通过 input 直接上传")
                except Exception as e2:
                    print(f"   ❌ 上传失败: {e2}")
                    return None
            
            # 等待上传处理完成（Flow 需要时间渲染上传图片的主体缩略图）
            time.sleep(5)
            
            # 收集上传后新出现的图片 URL，用于后续排除
            uploaded_srcs = self.page.evaluate("""() => {
                const srcs = [];
                document.querySelectorAll('img[src]').forEach(el => {
                    if (el.src) srcs.push(el.src);
                });
                return srcs;
            }""")
            return uploaded_srcs  # 返回上传后的全部图片 URL 列表
            
        except Exception as e:
            print(f"   ❌ 上传参考图片失败: {e}")
            return None
    
    def _record_initial_images(self) -> list:
        """记录当前页面上已有的所有图片 src（用于对比新生成的）"""
        try:
            images = set()
            
            # 收集页面上所有 img 标签的 src（包括小图标，确保不漏判）
            img_srcs = self.page.evaluate("""() => {
                const srcs = [];
                document.querySelectorAll('img[src]').forEach(el => {
                    if (el.src) srcs.push(el.src);
                });
                // 也添加已知的静态资源
                srcs.push('perlin.png');
                return srcs;
            }""")
            for src in img_srcs:
                images.add(src)
            
            return list(images)
        except:
            return []
    
    def submit_generate(
        self,
        prompt: str,
        tool_type: str = 'text2image',
        model: str = None,
        reference_file = None,
        aspect_ratio: str = None,
        batch_count: int = None,
        **kwargs,
    ) -> dict:
        """
        提交图片生成任务（UI 操作阶段，需要锁保护）
        
        Args:
            prompt: 提示词
            tool_type: 工具类型（目前仅 text2image）
            model: 模型名称（可选）
            reference_file: 参考图片路径或路径列表（可选，上传到 Flow 画布）
            aspect_ratio: 比例，'16:9'(横向) 或 '9:16'(纵向)，其他值忽略
            batch_count: 生成数量 1-4，其他值忽略
            
        Returns:
            dict: {'success': bool, 'task_key': str, 'initial_images': list, ...}
        """
        with self._page_lock:
            return self._submit_generate_impl(prompt, tool_type, model, reference_file, aspect_ratio, batch_count, **kwargs)
    
    def _submit_generate_impl(
        self,
        prompt: str,
        tool_type: str = 'text2image',
        model: str = None,
        reference_file = None,
        aspect_ratio: str = None,
        batch_count: int = None,
        **kwargs,
    ) -> dict:
        """submit_generate 内部实现"""
        try:
            # 防反爬间隔
            elapsed = time.time() - self._last_submit_time
            if elapsed < self._min_submit_interval:
                wait = self._min_submit_interval - elapsed
                print(f"   ⏳ 等待 {wait:.1f}s（防反爬间隔）...")
                time.sleep(wait)
            
            task_key = f"flow_{int(time.time())}_{id(self) % 10000}"
            
            # STEP 1: 确保在 Flow 页面
            print(f"\n   📋 STEP 1: 确保在 Flow 页面")
            if not self._ensure_flow_page():
                return {'success': False, 'error': '无法导航到 Flow 页面'}
            
            # STEP 2: 等待页面加载
            print(f"   📋 STEP 2: 等待页面加载完成")
            time.sleep(2)
            
            # 处理可能出现的弹窗
            self._dismiss_popups()
            
            # STEP 2.5: 上传参考图片（如果提供）
            has_reference = False
            if reference_file:
                print(f"   📋 STEP 2.5: 上传参考图片")
                upload_result = self._upload_reference_image(reference_file)
                if upload_result is None:
                    return {'success': False, 'error': '上传参考图片失败'}
                has_reference = True
                # 再多等一会儿，确保 Flow 渲染完上传图片的主体缩略图
                time.sleep(3)
            
            # STEP 3: 记录初始图片
            print(f"   📋 STEP 3: 记录当前图片")
            initial_images = self._record_initial_images()
            print(f"   📝 当前页面有 {len(initial_images)} 张图片（含上传的参考图）")
            
            # 清空之前的网络响应
            self._captured_responses.clear()
            
            # STEP 3.5: 设置模型、比例和数量（如果指定）
            if model:
                print(f"   📋 STEP 3.5a: 设置模型 → {model}")
                self._set_model(model)
            if aspect_ratio:
                print(f"   📋 STEP 3.5b: 设置比例 → {aspect_ratio}")
                self._set_aspect_ratio(aspect_ratio)
            if batch_count:
                print(f"   📋 STEP 3.5c: 设置数量 → x{batch_count}")
                self._set_batch_count(batch_count)
            
            # 关闭设置面板（避免遮挡提示词输入框）
            if model or aspect_ratio or batch_count:
                self._close_settings_panel()
            
            # 处理可能出现的弹窗（如"删除xx张图片"确认框）
            self._dismiss_popups()
            
            # STEP 4: 输入提示词
            print(f"   📋 STEP 4: 输入提示词")
            if not self._clear_and_input_prompt(prompt):
                return {'success': False, 'error': '无法输入提示词，请确认页面已加载'}
            
            # STEP 5: 点击生成
            print(f"   📋 STEP 5: 点击生成按钮")
            if not self._click_generate():
                return {'success': False, 'error': '无法点击生成按钮'}
            
            self._last_submit_time = time.time()
            
            # STEP 6: 等待一下，看看有没有捕获到 API 响应
            print(f"   📋 STEP 6: 等待生成触发...")
            time.sleep(3)
            
            # 检查是否有新的 API 响应（可能包含任务 ID）
            generation_id = self._extract_generation_id()
            
            print(f"   ✅ 生成已触发")
            if generation_id:
                print(f"   🔑 generation_id: {generation_id}")
            
            return {
                'success': True,
                'task_key': task_key,
                'generation_id': generation_id,
                'initial_images': initial_images,
                'initial_image_count': len(initial_images),
                'has_reference': has_reference,
            }
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return {'success': False, 'error': str(e)}
    
    def _extract_generation_id(self) -> str:
        """从捕获的网络响应中提取生成 ID"""
        for resp in reversed(self._captured_responses):
            body = resp.get('body', {})
            # 优先从 batchGenerateImages 响应中提取 media name
            if isinstance(body, dict):
                media = body.get('media', [])
                if isinstance(media, list) and media:
                    name = media[0].get('name', '')
                    if name:
                        return name
            # 通用搜索
            found_id = self._deep_find_id(body)
            if found_id:
                return found_id
        return ''
    
    def _deep_find_id(self, obj, depth: int = 0) -> str:
        """递归搜索 JSON 中的 ID 字段"""
        if depth > 5:
            return ''
        
        if isinstance(obj, dict):
            # 优先查找常见 ID 字段
            for key in ['generation_id', 'generationId', 'id', 'task_id', 'taskId',
                        'request_id', 'requestId', 'creation_id', 'creationId']:
                val = obj.get(key)
                if val and isinstance(val, str) and len(val) > 3:
                    return val
            
            # 递归查找
            for key in ['data', 'result', 'response', 'task', 'generation']:
                if key in obj:
                    found = self._deep_find_id(obj[key], depth + 1)
                    if found:
                        return found
        
        elif isinstance(obj, list) and len(obj) > 0:
            found = self._deep_find_id(obj[0], depth + 1)
            if found:
                return found
        
        return ''
    
    def poll_result(
        self,
        task_key: str = '',
        initial_images: list = None,
        initial_image_count: int = 0,
        max_wait: int = 300,
        save_path: str = None,
        generation_id: str = '',
        has_reference: bool = False,
    ) -> dict:
        """
        轮询等待图片生成结果
        
        Args:
            task_key: 任务标识
            initial_images: 初始图片列表（用于对比）
            initial_image_count: 初始图片数量
            max_wait: 最长等待秒数（默认 5 分钟）
            save_path: 本地保存路径
            generation_id: 生成 ID（如果有）
            has_reference: 是否有上传参考图片（影响检测策略）
        
        Returns:
            dict: {'success': bool, 'image_url': str, 'image_path': str, ...}
        """
        if initial_images is None:
            initial_images = []
        initial_set = set(initial_images)
        
        print(f"\n   ⏳ 开始轮询图片结果 (最长等待 {max_wait}s)...")
        
        start_time = time.time()
        poll_interval = 5  # 图片生成通常较快，5 秒轮询一次
        attempt = 0
        
        while time.time() - start_time < max_wait:
            attempt += 1
            elapsed = time.time() - start_time
            
            if attempt % 6 == 0:  # 每 30 秒打印一次进度
                print(f"   ⏳ 已等待 {elapsed:.0f}s / {max_wait}s ...")
            
            try:
                # 优先从 API 响应中获取 fifeUrl（签名 URL，可直接下载，无需认证）
                with self._page_lock:
                    api_result = self._check_api_response_for_image(initial_set)
                if api_result.get('found'):
                    image_url = api_result.get('image_url', '')
                    print(f"   ✅ 从 API 响应获取到图片: {image_url[:80]}...")
                    local_path = ''
                    if save_path:
                        local_path = self._download_image(image_url, save_path)
                    return {
                        'success': True,
                        'image_url': image_url,
                        'image_path': local_path or save_path,
                        'task_key': task_key,
                        'message': 'Google Flow 图片生成成功',
                    }
                
                # 降级：从 DOM 中检测新图片
                # 当有参考图片时，前 30 秒只信任 API fifeUrl，避免把上传缩略图误当生成结果
                skip_dom = has_reference and elapsed < 30
                result = {'found': False}
                
                if not skip_dom:
                    with self._page_lock:
                        result = self._check_for_new_images(initial_set)
                
                if result.get('found'):
                    image_url = result.get('image_url', '')
                    
                    # 有参考图片时，DOM 检测到的新图片需要二次确认：等 API fifeUrl
                    if has_reference:
                        print(f"   🔍 DOM 检测到候选图片，等待 API fifeUrl 确认...")
                        for _ in range(20):  # 最多 10 秒
                            with self._page_lock:
                                self.page.wait_for_timeout(500)
                            api_result = self._check_api_response_for_image(initial_set)
                            if api_result.get('found'):
                                image_url = api_result['image_url']
                                print(f"   ✅ API 确认生成图片: {image_url[:80]}...")
                                break
                        else:
                            # 10 秒内 API 没返回，使用 DOM 结果（但跳过明显的上传缩略图）
                            print(f"   ⚠️  API 未响应，使用 DOM 检测结果: {image_url[:80]}...")
                    else:
                        print(f"   ✅ 检测到新图片: {image_url[:80]}...")
                    
                    # 如果 DOM 拿到的是 redirect URL，等一下 API 响应来提供 fifeUrl
                    if 'getMediaUrlRedirect' in image_url or 'trpc' in image_url:
                        print(f"   🔄 DOM URL 需要认证，等待 API 响应中的 fifeUrl...")
                        for _ in range(10):  # 最多 5 秒
                            # 用 page.wait_for_timeout 让 Playwright 事件循环处理回调
                            with self._page_lock:
                                self.page.wait_for_timeout(500)
                            api_result = self._check_api_response_for_image(initial_set)
                            if api_result.get('found'):
                                image_url = api_result['image_url']
                                print(f"   ✅ 从 API 响应获取到 fifeUrl: {image_url[:80]}...")
                                break
                    
                    # 下载图片
                    local_path = ''
                    if save_path:
                        local_path = self._download_image(image_url, save_path)
                        # 如果直接下载失败，从 DOM 通过 canvas 提取图片
                        if not local_path and result.get('image_url'):
                            print(f"   🔄 尝试通过 canvas 提取图片...")
                            with self._page_lock:
                                local_path = self._extract_image_via_canvas(result['image_url'], save_path)
                    
                    return {
                        'success': True,
                        'image_url': image_url,
                        'image_path': local_path or save_path,
                        'task_key': task_key,
                        'message': 'Google Flow 图片生成成功',
                    }
                
                # 检查是否有错误提示
                with self._page_lock:
                    error = self._check_for_errors()
                if error:
                    return {
                        'success': False,
                        'error': error,
                        'task_key': task_key,
                    }
                
                # 检查 API 响应中是否有错误（如 reCAPTCHA 失败）
                api_error = self._check_api_response_for_error()
                if api_error:
                    return {
                        'success': False,
                        'error': api_error,
                        'task_key': task_key,
                    }
                    
            except Exception as e:
                print(f"   ⚠️  轮询异常: {e}")
            
            # 用 page.wait_for_timeout 代替 time.sleep，让 Playwright 事件循环处理 CDP 回调
            try:
                with self._page_lock:
                    self.page.wait_for_timeout(poll_interval * 1000)
            except:
                time.sleep(poll_interval)
        
        return {
            'success': False,
            'error': f'等待超时（{max_wait}s）',
            'task_key': task_key,
        }
    
    def _check_api_response_for_image(self, initial_set: set) -> dict:
        """从捕获的 API 响应中提取 fifeUrl（签名 URL，可直接下载）"""
        for resp in reversed(self._captured_responses):
            body = resp.get('body', {})
            image_url = self._find_image_url_in_response(body)
            if image_url and image_url not in initial_set:
                return {'found': True, 'image_url': image_url}
        return {'found': False}
    
    def _check_api_response_for_error(self) -> str:
        """检查 API 响应中是否有错误（如 reCAPTCHA 失败、限频等）"""
        for resp in reversed(self._captured_responses):
            body = resp.get('body', {})
            if isinstance(body, dict) and 'error' in body:
                err = body['error']
                if isinstance(err, dict):
                    msg = err.get('message', '')
                    code = err.get('code', '')
                    if 'reCAPTCHA' in msg:
                        return f'reCAPTCHA 验证失败（Google 认为操作频率过高），请稍后再试'
                    if code in (403, 429):
                        return f'请求被拒绝({code}): {msg}'
                    if msg:
                        return f'API 错误({code}): {msg}'
        return ''

    def _check_for_new_images(self, initial_set: set) -> dict:
        """检查页面上是否出现了新的生成图片"""
        try:
            # 策略 1: 检查新出现的大尺寸 img 元素
            new_images = self.page.evaluate("""(initialSrcs) => {
                const results = [];
                // 排除的静态资源
                const excludes = ['perlin.png', 'favicon', 'avatar', 'flower-placeholder', 'logo'];
                document.querySelectorAll('img[src]').forEach(el => {
                    const src = el.src;
                    if (!src || initialSrcs.includes(src)) return;
                    // 跳过 SVG data URI
                    if (src.startsWith('data:image/svg')) return;
                    // 跳过静态资源
                    if (excludes.some(ex => src.includes(ex))) return;
                    const rect = el.getBoundingClientRect();
                    if (rect.width > 80 && rect.height > 80 && el.offsetParent !== null) {
                        results.push({src: src, w: rect.width, h: rect.height});
                    }
                });
                return results;
            }""", list(initial_set))
            
            if new_images:
                best = max(new_images, key=lambda x: x['w'] * x['h'])
                return {'found': True, 'image_url': best['src']}
            
            # 策略 2: 检查 Performance API 中的图片资源
            try:
                excludes_str = 'perlin.png|favicon|avatar|flower-placeholder|logo|recaptcha'
                resources = self.page.evaluate("""(args) => {
                    const initialSrcs = args.initial;
                    const excludePattern = new RegExp(args.excludes, 'i');
                    return performance.getEntriesByType('resource')
                        .filter(r => r.initiatorType === 'img' || r.name.match(/\\.(png|jpg|jpeg|webp)/i))
                        .map(r => r.name)
                        .filter(url => !initialSrcs.includes(url) && !excludePattern.test(url) && (
                            url.includes('storage.googleapis.com') || 
                            url.includes('lh3.googleusercontent.com') ||
                            url.includes('generated') ||
                            (url.match(/\\.(png|jpg|jpeg|webp)/i) && !url.includes('labs.google/fx/images/'))
                        ));
                }""", {'initial': list(initial_set), 'excludes': excludes_str})
                for url in resources:
                    if url not in initial_set:
                        return {'found': True, 'image_url': url}
            except:
                pass
            
            return {'found': False}
            
        except Exception as e:
            print(f"   ⚠️  检查图片失败: {e}")
            return {'found': False}
    
    def _find_image_url_in_response(self, obj, depth: int = 0) -> str:
        """从 API 响应中递归查找图片 URL"""
        if depth > 5:
            return ''
        
        if isinstance(obj, str):
            # 优先匹配 Google Storage 签名 URL
            if 'storage.googleapis.com' in obj and 'ai-sandbox-videofx/image/' in obj:
                return obj
            if re.match(r'https?://.*\.(png|jpg|jpeg|webp)', obj, re.IGNORECASE):
                return obj
        
        elif isinstance(obj, dict):
            # 优先查 fifeUrl（Google Flow 生成图片的专用字段）
            fife = obj.get('fifeUrl', '')
            if fife and fife.startswith('http'):
                return fife
            
            # 查图片相关字段
            for key in ['image_url', 'imageUrl', 'url', 'src', 'output_url', 'result_url',
                        'generated_image', 'image', 'output']:
                val = obj.get(key)
                if isinstance(val, str) and val.startswith('http'):
                    return val
            
            # 递归查找（优先 media/image/generatedImage 等关键路径）
            for key in ['media', 'generatedImage', 'image', 'data', 'result', 'response']:
                if key in obj:
                    found = self._find_image_url_in_response(obj[key], depth + 1)
                    if found:
                        return found
            
            # 其他值
            for val in obj.values():
                found = self._find_image_url_in_response(val, depth + 1)
                if found:
                    return found
        
        elif isinstance(obj, list):
            for item in obj:
                found = self._find_image_url_in_response(item, depth + 1)
                if found:
                    return found
        
        return ''
    
    def _check_for_errors(self) -> str:
        """检查页面上是否有错误提示（过滤误报）"""
        try:
            # 只使用高置信度的选择器，避免 [class*="error"] 这类泛匹配误报
            error_selectors = [
                '[role="alert"]',
                '.error-message',
            ]
            
            # 错误文本必须包含这些关键词之一才算真正的错误
            error_keywords = [
                'error', 'Error', 'failed', 'fail', '失败', '错误',
                'reCAPTCHA', 'denied', 'rejected', '拒绝', 'blocked',
                'quota', 'limit', '超限', '频率', 'too many', 'unavailable',
            ]
            
            # 这些文本即使匹配到也要忽略（页面 UI 元素的误报）
            ignore_texts = [
                'Flow', 'Google Flow', 'flow', 'google', 'Google',
                'Labs', 'labs.google', 'Banana', 'Nano',
            ]
            
            for selector in error_selectors:
                try:
                    el = self.page.locator(selector).first
                    if el.is_visible():
                        text = (el.inner_text() or '').strip()
                        # 跳过太短或在忽略列表中的文本
                        if not text or len(text) < 5:
                            continue
                        if text in ignore_texts:
                            continue
                        # 必须包含错误关键词
                        if any(kw in text for kw in error_keywords):
                            return text
                except:
                    continue
            
            return ''
        except:
            return ''
    
    def _download_image(self, image_url: str, save_path: str) -> str:
        """下载图片到本地"""
        try:
            # 确保目录存在
            save_dir = os.path.dirname(save_path)
            if save_dir:
                os.makedirs(save_dir, exist_ok=True)
            
            # 如果是 blob: URL，通过浏览器下载
            if image_url.startswith('blob:') or image_url.startswith('data:'):
                return self._download_blob_image(image_url, save_path)
            
            # HTTP 下载
            try:
                headers = {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                }
                req = urllib.request.Request(image_url, headers=headers)
                with urllib.request.urlopen(req, timeout=60) as resp:
                    data = resp.read()
                
                with open(save_path, 'wb') as f:
                    f.write(data)
                
                print(f"   💾 图片已保存: {save_path}")
                return save_path
            except urllib.error.HTTPError as http_err:
                print(f"   ⚠️  HTTP 下载失败({http_err.code})，尝试通过浏览器下载...")
                return self._download_via_browser(image_url, save_path)
            
        except Exception as e:
            print(f"   ⚠️  下载图片失败: {e}")
            return ''
    
    def _extract_image_via_canvas(self, img_src: str, save_path: str) -> str:
        """通过 canvas 从页面 img 元素提取图片数据（绕过 URL 认证问题）"""
        try:
            base64_data = self.page.evaluate('''(targetSrc) => {
                const img = Array.from(document.querySelectorAll('img[src]'))
                    .find(el => el.src === targetSrc);
                if (!img || !img.naturalWidth) return null;
                const canvas = document.createElement('canvas');
                canvas.width = img.naturalWidth;
                canvas.height = img.naturalHeight;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0);
                return canvas.toDataURL('image/png');
            }''', img_src)
            
            if base64_data:
                match = re.match(r'data:[^;]+;base64,(.+)', base64_data)
                if match:
                    import base64
                    data = base64.b64decode(match.group(1))
                    save_dir = os.path.dirname(save_path)
                    if save_dir:
                        os.makedirs(save_dir, exist_ok=True)
                    with open(save_path, 'wb') as f:
                        f.write(data)
                    print(f"   💾 图片已保存（canvas 提取）: {save_path}")
                    return save_path
            
            return ''
        except Exception as e:
            print(f"   ⚠️  canvas 提取失败: {e}")
            return ''
    
    def _download_via_browser(self, image_url: str, save_path: str) -> str:
        """通过浏览器 JS fetch 下载需要认证的图片"""
        try:
            with self._page_lock:
                base64_data = self.page.evaluate('''async (url) => {
                    try {
                        const resp = await fetch(url, {credentials: 'include'});
                        if (!resp.ok) return null;
                        const blob = await resp.blob();
                        return new Promise((resolve) => {
                            const reader = new FileReader();
                            reader.onload = () => resolve(reader.result);
                            reader.readAsDataURL(blob);
                        });
                    } catch(e) {
                        return null;
                    }
                }''', image_url)
            
            if base64_data:
                match = re.match(r'data:[^;]+;base64,(.+)', base64_data)
                if match:
                    import base64
                    data = base64.b64decode(match.group(1))
                    with open(save_path, 'wb') as f:
                        f.write(data)
                    print(f"   💾 图片已保存（浏览器下载）: {save_path}")
                    return save_path
            
            print("   ⚠️  浏览器下载也失败了")
            return ''
        except Exception as e:
            print(f"   ⚠️  浏览器下载失败: {e}")
            return ''
    
    def _download_blob_image(self, blob_url: str, save_path: str) -> str:
        """通过浏览器从 blob/data URL 下载图片"""
        try:
            # 在浏览器中将 blob 转为 base64
            if blob_url.startswith('data:'):
                # 直接从 data URL 提取
                match = re.match(r'data:image/\w+;base64,(.+)', blob_url)
                if match:
                    import base64
                    data = base64.b64decode(match.group(1))
                    with open(save_path, 'wb') as f:
                        f.write(data)
                    print(f"   💾 图片已保存（data URL）: {save_path}")
                    return save_path
            
            # blob URL：通过 fetch + FileReader 在浏览器中转换
            base64_data = self.page.evaluate(f'''async () => {{
                try {{
                    const resp = await fetch("{blob_url}");
                    const blob = await resp.blob();
                    return new Promise((resolve) => {{
                        const reader = new FileReader();
                        reader.onload = () => resolve(reader.result);
                        reader.readAsDataURL(blob);
                    }});
                }} catch(e) {{
                    return null;
                }}
            }}''')
            
            if base64_data:
                match = re.match(r'data:image/\w+;base64,(.+)', base64_data)
                if match:
                    import base64
                    data = base64.b64decode(match.group(1))
                    with open(save_path, 'wb') as f:
                        f.write(data)
                    print(f"   💾 图片已保存（blob）: {save_path}")
                    return save_path
            
            return ''
            
        except Exception as e:
            print(f"   ⚠️  blob 图片下载失败: {e}")
            return ''
    
    def generate(
        self,
        prompt: str,
        tool_type: str = 'text2image',
        model: str = None,
        save_path: str = None,
        max_wait: int = 300,
        reference_file = None,
        aspect_ratio: str = None,
        batch_count: int = None,
    ) -> dict:
        """
        一步完成：提交 + 轮询（串行便捷方法）
        """
        submit_result = self.submit_generate(
            prompt=prompt,
            tool_type=tool_type,
            model=model,
            reference_file=reference_file,
            aspect_ratio=aspect_ratio,
            batch_count=batch_count,
        )
        
        if not submit_result.get('success'):
            return submit_result
        
        return self.poll_result(
            task_key=submit_result.get('task_key', ''),
            initial_images=submit_result.get('initial_images', []),
            initial_image_count=submit_result.get('initial_image_count', 0),
            max_wait=max_wait,
            save_path=save_path,
            generation_id=submit_result.get('generation_id', ''),
            has_reference=submit_result.get('has_reference', False),
        )


# ============================================================
# 命令行测试
# ============================================================
if __name__ == '__main__':
    print("\n🧪 Google Flow 自动化测试\n")
    
    auto = GoogleFlowAutomation()
    
    if not auto.start():
        print("❌ 启动失败")
        sys.exit(1)
    
    if not auto.check_login():
        print("❌ 未登录，请先登录 Google 账号")
        print("   运行: python init_login.py google_flow")
        auto.stop()
        sys.exit(1)
    
    # 测试生成
    prompt = sys.argv[1] if len(sys.argv) > 1 else "a cute cat sitting on a cloud"
    print(f"\n📝 测试提示词: {prompt}\n")
    
    result = auto.generate(prompt=prompt, save_path='test_flow_output.png')
    print(f"\n📋 结果: {json.dumps(result, ensure_ascii=False, indent=2)}")
    
    auto.stop()
