#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
打开浏览器供用户登录（使用系统浏览器）

使用系统已安装的 Edge/Chrome 浏览器，登录态、Cookie、插件全部保留。

用法：
    python open_browser_for_login.py <platform>
    python open_browser_for_login.py <platform> --no-wait  # 启动后立即退出（供 Flutter 调用）
    
示例：
    python open_browser_for_login.py vidu
    python open_browser_for_login.py jimeng
"""

import sys
import os
import io
import argparse

# 确保标准输出使用 UTF-8 编码（Windows 兼容）
if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')
    except:
        pass

# 平台 → CDP 端口映射（不同平台用不同端口，避免冲突）
PLATFORM_PORTS = {
    'jimeng': 9222,
    'vidu': 9223,
    'keling': 9224,
    'hailuo': 9225,
}


def main():
    parser = argparse.ArgumentParser(description='打开浏览器供用户登录（使用系统浏览器）')
    parser.add_argument('platform', help='平台名称（vidu, jimeng, keling, hailuo）')
    parser.add_argument('--port', type=int, default=None, help='CDP 端口（默认按平台自动分配）')
    parser.add_argument('--no-wait', action='store_true', help='启动浏览器后立即退出（不等待用户操作）')
    
    args = parser.parse_args()
    
    port = args.port or PLATFORM_PORTS.get(args.platform, 9222)
    
    try:
        if args.no_wait:
            # 快速模式：只启动浏览器并导航到目标页面，然后立即退出
            from browser_manager import BrowserManager, find_system_browser, get_browser_name
            
            platform_urls = {
                'vidu': 'https://www.vidu.cn',
                'jimeng': 'https://jimeng.jianying.com',
                'keling': 'https://klingai.kuaishou.com',
                'hailuo': 'https://hailuoai.com',
            }
            
            if args.platform not in platform_urls:
                print(f"❌ 不支持的平台: {args.platform}")
                return 1
            
            url = platform_urls[args.platform]
            mgr = BrowserManager(cdp_port=port, profile_name=args.platform)
            
            page = mgr.connect_or_launch(target_url=url)
            print(f"✅ 浏览器已打开: {page.url[:80]}")
            
            # 断开 CDP 连接，但浏览器保持运行
            mgr.disconnect()
            print("✅ 已断开连接（浏览器保持运行）")
            return 0
        else:
            # 交互模式：启动浏览器并等待用户操作
            from browser_manager import launch_browser_for_login
            launch_browser_for_login(args.platform, cdp_port=port)
            return 0
    except ImportError:
        print("❌ 无法导入 browser_manager 模块")
        print("   请确保 browser_manager.py 在同一目录下")
        return 1
    except Exception as e:
        print(f"❌ 错误: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
