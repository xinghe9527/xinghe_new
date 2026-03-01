#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
网页服务商登录脚手架
使用 Playwright Persistent Context 实现 Cookie 持久化

用法：
    python python_backend/web_automation/init_login.py vidu
    python python_backend/web_automation/init_login.py jimeng
    python python_backend/web_automation/init_login.py keling
"""

import sys
import json
import io
import os
from playwright.sync_api import sync_playwright
import time

# 确保标准输出使用 UTF-8 编码（Windows 兼容）
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# ✅ 获取项目根目录的绝对路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))  # python_backend/web_automation/
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))  # 项目根目录
USER_DATA_ROOT = os.path.join(PROJECT_ROOT, 'python_backend', 'user_data')

# 平台配置（使用绝对路径）
PLATFORMS = {
    'vidu': {
        'name': 'Vidu',
        'url': 'https://www.vidu.cn/',
        'user_data_dir': os.path.join(USER_DATA_ROOT, 'vidu_profile')
    },
    'jimeng': {
        'name': '即梦',
        'url': 'https://jimeng.jianying.com/',
        'user_data_dir': os.path.join(USER_DATA_ROOT, 'jimeng_profile')
    },
    'keling': {
        'name': '可灵',
        'url': 'https://klingai.com/',
        'user_data_dir': os.path.join(USER_DATA_ROOT, 'keling_profile')
    },
    'hailuo': {
        'name': '海螺',
        'url': 'https://hailuoai.com/',
        'user_data_dir': os.path.join(USER_DATA_ROOT, 'hailuo_profile')
    }
}


def print_banner(platform_name):
    """打印欢迎横幅"""
    banner = f"""
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║          🔐 {platform_name} 登录脚手架                      ║
║                                                          ║
║  功能：使用持久化浏览器上下文保存登录状态                  ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"""
    print(banner)


def print_instructions(platform_name, url):
    """打印操作说明"""
    instructions = f"""
📋 操作说明：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1️⃣  浏览器窗口即将打开，显示 {platform_name} 官网
2️⃣  请在浏览器中手动完成登录操作（扫码/账号密码）
3️⃣  登录成功后，请确认能看到你的账号信息
4️⃣  完成后，直接关闭浏览器窗口即可
5️⃣  脚本会自动保存你的登录状态（Cookie）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌐 目标网址：{url}

⏳ 正在启动浏览器，请稍候...
"""
    print(instructions)


def main():
    """主函数：启动持久化浏览器并等待用户登录"""
    
    # 检查命令行参数
    if len(sys.argv) < 2:
        error_result = {
            "success": False,
            "error": "缺少平台参数",
            "usage": "python init_login.py <platform>",
            "available_platforms": list(PLATFORMS.keys()),
            "example": "python init_login.py vidu"
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        return 1
    
    platform_key = sys.argv[1].lower()
    
    # 验证平台
    if platform_key not in PLATFORMS:
        error_result = {
            "success": False,
            "error": f"不支持的平台: {platform_key}",
            "available_platforms": list(PLATFORMS.keys()),
            "example": "python init_login.py vidu"
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        return 1
    
    platform = PLATFORMS[platform_key]
    platform_name = platform['name']
    url = platform['url']
    user_data_dir = platform['user_data_dir']
    
    # 打印横幅和说明
    print_banner(platform_name)
    print_instructions(platform_name, url)
    
    try:
        # 确保用户数据目录存在
        os.makedirs(user_data_dir, exist_ok=True)
        
        print(f"\n🔐 用户数据目录（绝对路径）：\n   {user_data_dir}\n")
        
        # 启动 Playwright
        with sync_playwright() as p:
            # 使用持久化上下文（自动保存 Cookie）
            context = p.chromium.launch_persistent_context(
                user_data_dir=user_data_dir,
                headless=False,  # 显示浏览器
                viewport={'width': 1920, 'height': 1080},
                locale='zh-CN',
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                args=[
                    '--start-maximized',
                    '--disable-blink-features=AutomationControlled'  # 隐藏自动化特征
                ]
            )
            
            # 获取第一个页面（持久化上下文会自动创建）
            if len(context.pages) > 0:
                page = context.pages[0]
            else:
                page = context.new_page()
            
            # 访问目标网站
            print(f"\n🌐 正在打开 {platform_name} 官网...\n")
            page.goto(url, wait_until='domcontentloaded', timeout=30000)
            
            # 等待页面加载
            time.sleep(3)
            
            # 打印等待提示
            wait_message = f"""
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║  ✅ 浏览器已打开！                                        ║
║                                                          ║
║  👉 请在浏览器中完成登录操作                              ║
║  👉 登录成功后，关闭浏览器窗口即可                        ║
║                                                          ║
║  ⏳ 脚本正在等待中...                                     ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"""
            print(wait_message)
            
            # 监听浏览器关闭事件
            # 使用轮询方式检测上下文是否关闭
            try:
                while True:
                    # 检查页面是否还存在
                    if page.is_closed():
                        break
                    time.sleep(1)
            except Exception:
                # 上下文已关闭
                pass
            
            print("\n🔄 检测到浏览器已关闭，正在保存登录状态...\n")
            
            # 持久化上下文会自动保存 Cookie，无需手动操作
            time.sleep(1)
            
        # 返回成功结果
        result = {
            "success": True,
            "message": f"✅ {platform_name} 登录状态已保存！",
            "platform": platform_name,
            "platform_key": platform_key,
            "user_data_dir": user_data_dir,
            "details": {
                "说明": "登录状态已保存到本地",
                "下次使用": "自动化脚本将自动使用此登录状态",
                "重新登录": f"再次运行此脚本即可更新登录状态",
                "数据位置": user_data_dir
            },
            "next_step": "现在可以运行自动化脚本了！🚀"
        }
        
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
        
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断操作\n")
        result = {
            "success": False,
            "message": "用户手动中断",
            "platform": platform_name
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1
        
    except Exception as e:
        error_result = {
            "success": False,
            "error": str(e),
            "message": f"❌ {platform_name} 登录脚手架执行失败",
            "platform": platform_name,
            "troubleshooting": [
                "1. 确保网络连接正常",
                "2. 确保 Playwright 已正确安装",
                "3. 检查目标网站是否可访问",
                "4. 查看详细错误信息"
            ]
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        return 1


if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except Exception as e:
        print(json.dumps({
            "success": False,
            "error": str(e),
            "message": "脚本执行异常"
        }, ensure_ascii=False, indent=2))
        sys.exit(1)
