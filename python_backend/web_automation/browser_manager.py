#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
通用浏览器管理模块

使用系统浏览器（Edge/Chrome）+ 独立 profile + CDP 连接。
独立 profile 会保存登录态、Cookie，下次打开自动恢复。
不会影响用户正在使用的浏览器。

用法：
    from browser_manager import BrowserManager
    
    mgr = BrowserManager(cdp_port=9222, profile_name='jimeng')
    page = mgr.connect_or_launch(target_url='https://jimeng.jianying.com')
    # ... 操作 page ...
    mgr.disconnect()  # 断开连接，但不关闭浏览器
"""

import sys
import os
import io
import time
import subprocess
import platform
from pathlib import Path
from typing import Optional

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

# 浏览器 profile 统一存储在 %APPDATA%/com.example/xinghe_new/user_data/
# 这样 Debug、Release、Inno Setup 安装后都共享同一份登录态
_APPDATA = os.environ.get('APPDATA', os.path.expanduser('~'))
USER_DATA_ROOT = os.path.join(_APPDATA, 'com.example', 'xinghe_new', 'user_data')
os.makedirs(USER_DATA_ROOT, exist_ok=True)

# SCRIPT_DIR 仅在非打包模式下有意义
if getattr(sys, 'frozen', False):
    SCRIPT_DIR = os.path.dirname(os.path.abspath(sys.executable))
else:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

DEFAULT_CDP_PORT = 9222


# ============================================================
# 浏览器检测
# ============================================================

def find_system_browser() -> Optional[str]:
    """自动检测系统浏览器，优先 Edge > Chrome"""
    import winreg
    
    candidates = []
    
    # Edge
    for path in [
        r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
        r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    ]:
        candidates.append(path)
    try:
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
            r'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe')
        val, _ = winreg.QueryValueEx(key, '')
        winreg.CloseKey(key)
        if val and os.path.isfile(val):
            candidates.insert(0, val)
    except:
        pass
    
    # Chrome
    for path in [
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    ]:
        candidates.append(path)
    try:
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
            r'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe')
        val, _ = winreg.QueryValueEx(key, '')
        winreg.CloseKey(key)
        if val and os.path.isfile(val):
            candidates.append(val)
    except:
        pass
    
    local = os.environ.get('LOCALAPPDATA', '')
    if local:
        candidates.append(os.path.join(local, r'Google\Chrome\Application\chrome.exe'))
    
    seen = set()
    for p in candidates:
        if p and p not in seen:
            seen.add(p)
            if os.path.isfile(p):
                return p
    return None


def get_browser_name(exe_path: str) -> str:
    """根据路径判断浏览器名称"""
    lower = exe_path.lower()
    if 'msedge' in lower or 'edge' in lower:
        return 'Edge'
    elif 'chrome' in lower:
        return 'Chrome'
    return 'Browser'


def is_cdp_port_active(port: int) -> bool:
    """检查 CDP 端口是否有浏览器在监听"""
    import urllib.request
    try:
        url = f'http://127.0.0.1:{port}/json/version'
        with urllib.request.urlopen(url, timeout=3) as resp:
            return len(resp.read()) > 0
    except:
        return False


def get_cdp_ws_url(port: int) -> Optional[str]:
    """
    通过 Python urllib 获取 CDP WebSocket URL。
    
    Playwright 1.58+ 的 Node.js 后端在发送 /json/version 请求时，
    可能被 Edge 145+ 返回 400（HTTP header 兼容性问题）。
    但 Python 的 urllib 可以正常获取。
    获取到 ws:// URL 后直接传给 connect_over_cdp 即可绕过此问题。
    """
    import urllib.request
    import json as _json
    try:
        url = f'http://127.0.0.1:{port}/json/version'
        with urllib.request.urlopen(url, timeout=5) as resp:
            data = _json.loads(resp.read().decode('utf-8'))
            ws_url = data.get('webSocketDebuggerUrl')
            if ws_url:
                print(f"   🔗 获取到 CDP WebSocket URL: {ws_url[:60]}...")
                return ws_url
    except Exception as e:
        print(f"   ⚠️  获取 CDP WebSocket URL 失败: {e}")
    return None


# ============================================================
# 浏览器管理器
# ============================================================

class BrowserManager:
    """
    通用浏览器管理器
    
    使用系统 Edge/Chrome + 独立 profile + CDP。
    独立 profile 保存登录态，不影响用户正在使用的浏览器。
    """
    
    def __init__(self, cdp_port=DEFAULT_CDP_PORT, profile_name='default',
                 profile_dir=None, browser_exe=None):
        self.cdp_port = cdp_port
        self.profile_name = profile_name
        self.browser_exe = browser_exe
        self.profile_dir = profile_dir or os.path.join(
            USER_DATA_ROOT, f'{profile_name}_cdp_profile')
        
        self.pw = None
        self.browser = None
        self.context = None
        self.page = None
        self._browser_process = None
        self._connected = False
    
    def connect_or_launch(self, target_url=None):
        """连接已有浏览器或启动新浏览器，返回 page"""
        from playwright.sync_api import sync_playwright
        
        self.pw = sync_playwright().start()
        
        if is_cdp_port_active(self.cdp_port):
            print(f"   🔗 CDP 端口 {self.cdp_port} 已有浏览器运行")
        else:
            self._launch_browser()
        
        # 先用 Python urllib 获取 WebSocket URL，绕过 Playwright Node.js
        # 与 Edge 145+ 的 HTTP 兼容性问题（Node.js 请求 /json/version 返回 400）
        ws_url = get_cdp_ws_url(self.cdp_port)
        cdp_endpoint = ws_url or f'http://127.0.0.1:{self.cdp_port}'
        
        print(f"   🔗 通过 CDP 连接（端口 {self.cdp_port}）...")
        self.browser = self.pw.chromium.connect_over_cdp(cdp_endpoint)
        
        self.page = self._find_or_create_page(target_url)
        self._connected = True
        
        name = get_browser_name(self.browser_exe) if self.browser_exe else '浏览器'
        print(f"   ✅ 已连接 {name}，页面: {self.page.url[:80]}")
        return self.page
    
    def _launch_browser(self):
        """启动系统浏览器（独立 profile + CDP 端口）"""
        if not self.browser_exe:
            self.browser_exe = find_system_browser()
        
        if not self.browser_exe:
            raise RuntimeError(
                "未找到可用的浏览器（Edge/Chrome）。\n"
                "Windows 系统通常自带 Edge，请确认是否已安装。")
        
        name = get_browser_name(self.browser_exe)
        print(f"   🌐 检测到 {name}: {self.browser_exe}")
        
        os.makedirs(self.profile_dir, exist_ok=True)
        
        # 启动参数：只保留必要的，不禁用网络相关功能
        # 这样页面加载速度和正常浏览器一样
        args = [
            self.browser_exe,
            f'--remote-debugging-port={self.cdp_port}',
            f'--user-data-dir={self.profile_dir}',
            '--no-first-run',
            '--no-default-browser-check',
            '--remote-allow-origins=*',  # Edge 145+ 需要此参数允许 CDP 连接
        ]
        
        print(f"   🚀 启动 {name}（CDP 端口 {self.cdp_port}）...")
        
        # Windows 下确保浏览器窗口正常显示
        popen_kwargs = {
            'stdout': subprocess.DEVNULL,
            'stderr': subprocess.DEVNULL,
        }
        if platform.system() == 'Windows':
            popen_kwargs['creationflags'] = (
                subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
            )
        
        self._browser_process = subprocess.Popen(args, **popen_kwargs)
        
        # 等待 CDP 就绪
        for i in range(30):
            if is_cdp_port_active(self.cdp_port):
                print(f"   ✅ {name} 已启动（{i+1}s）")
                return
            time.sleep(1)
        
        raise RuntimeError(f"{name} 启动超时，CDP 端口 {self.cdp_port} 未就绪")
    
    def _find_or_create_page(self, target_url=None):
        """查找或创建目标页面"""
        contexts = self.browser.contexts
        
        if target_url:
            from urllib.parse import urlparse
            target_domain = urlparse(target_url).netloc
            
            for ctx in contexts:
                for p in ctx.pages:
                    try:
                        if target_domain in urlparse(p.url).netloc:
                            self.context = ctx
                            print(f"   📄 找到已有页面: {p.url[:80]}")
                            return p
                    except:
                        continue
        
        if contexts:
            self.context = contexts[0]
            page = self.context.new_page()
            if target_url:
                print(f"   🌐 导航到: {target_url}")
                page.goto(target_url, wait_until='domcontentloaded', timeout=30000)
                time.sleep(3)
            return page
        
        raise RuntimeError("浏览器没有可用的 context")
    
    def disconnect(self):
        """断开 CDP 连接，浏览器保持运行"""
        try:
            if self.browser:
                self.browser.close()
        except:
            pass
        try:
            if self.pw:
                self.pw.stop()
        except:
            pass
        self.browser = None
        self.pw = None
        self.page = None
        self.context = None
        self._connected = False
    
    def close_browser(self):
        """关闭浏览器（完全退出）"""
        self.disconnect()
        if self._browser_process:
            try:
                self._browser_process.terminate()
                self._browser_process.wait(timeout=5)
            except:
                try:
                    self._browser_process.kill()
                except:
                    pass
            self._browser_process = None
    
    @property
    def is_connected(self):
        return self._connected and self.page is not None


# ============================================================
# 便捷函数
# ============================================================

def launch_browser_for_login(platform_name: str, cdp_port: int = DEFAULT_CDP_PORT):
    """启动浏览器供用户登录"""
    platform_urls = {
        'vidu': 'https://www.vidu.cn',
        'jimeng': 'https://jimeng.jianying.com',
        'keling': 'https://klingai.kuaishou.com',
        'hailuo': 'https://hailuoai.com',
        'google_flow': 'https://labs.google/fx/flow',
    }
    
    if platform_name not in platform_urls:
        print(f"❌ 不支持的平台: {platform_name}")
        return
    
    url = platform_urls[platform_name]
    mgr = BrowserManager(cdp_port=cdp_port, profile_name=platform_name)
    
    exe = find_system_browser()
    name = get_browser_name(exe) if exe else '浏览器'
    
    print(f"\n{'='*60}")
    print(f"  🌐 使用 {name} 打开 {platform_name.upper()}")
    print(f"{'='*60}")
    print(f"📍 网址: {url}")
    print(f"📁 配置: {mgr.profile_dir}")
    print(f"💡 登录态会自动保存到独立 profile，下次打开自动恢复")
    print(f"{'='*60}\n")
    
    try:
        page = mgr.connect_or_launch(target_url=url)
        print(f"\n✅ 浏览器已就绪，请登录")
        print(f"⏳ 按 Ctrl+C 退出...\n")
        
        while True:
            try:
                time.sleep(1)
            except KeyboardInterrupt:
                print("\n⚠️  用户中断")
                break
    except Exception as e:
        print(f"\n❌ 错误: {e}")
    finally:
        mgr.disconnect()
        print("✅ 已断开连接（浏览器保持运行）\n")


# ============================================================
# 命令行入口
# ============================================================

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='浏览器管理工具')
    sub = parser.add_subparsers(dest='command')
    
    login_p = sub.add_parser('login', help='打开浏览器登录')
    login_p.add_argument('platform', help='平台（vidu, jimeng, keling, hailuo）')
    login_p.add_argument('--port', type=int, default=DEFAULT_CDP_PORT)
    
    sub.add_parser('detect', help='检测系统浏览器')
    
    args = parser.parse_args()
    
    if args.command == 'login':
        launch_browser_for_login(args.platform, cdp_port=args.port)
    elif args.command == 'detect':
        exe = find_system_browser()
        if exe:
            print(f"✅ 检测到 {get_browser_name(exe)}: {exe}")
        else:
            print("❌ 未找到可用的浏览器")
    else:
        parser.print_help()
