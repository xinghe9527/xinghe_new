#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
即梦 网页自动化 Demo
测试 Playwright 浏览器自动化功能
"""

import sys
import json
import io
from playwright.sync_api import sync_playwright
import time

# 确保标准输出使用 UTF-8 编码（Windows 兼容）
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


def main():
    """主函数：打开即梦官网并截图"""
    
    try:
        # 启动 Playwright
        with sync_playwright() as p:
            # 启动浏览器（headless=False 显示浏览器窗口）
            browser = p.chromium.launch(
                headless=False,  # 显示浏览器
                args=['--start-maximized']  # 最大化窗口
            )
            
            # 创建浏览器上下文
            context = browser.new_context(
                viewport={'width': 1920, 'height': 1080},
                locale='zh-CN',  # 设置中文
            )
            
            # 创建新页面
            page = context.new_page()
            
            # 访问即梦官网
            jimeng_url = 'https://jimeng.jianying.com/'
            page.goto(jimeng_url, wait_until='domcontentloaded', timeout=30000)
            
            # 等待页面加载（5-10秒）
            time.sleep(8)
            
            # 截图保存
            screenshot_path = 'python_backend/web_automation/jimeng_test.png'
            page.screenshot(path=screenshot_path, full_page=False)
            
            # 获取页面标题
            page_title = page.title()
            
            # 关闭浏览器
            browser.close()
            
            # 返回成功结果
            result = {
                "success": True,
                "message": "✅ 即梦 Playwright 自动化测试成功！",
                "details": {
                    "访问网址": jimeng_url,
                    "页面标题": page_title,
                    "截图路径": screenshot_path,
                    "浏览器": "Chromium",
                    "测试状态": "浏览器已成功打开即梦官网并截图"
                },
                "next_step": "可以开始分析即梦页面结构，编写自动填充脚本！🎨"
            }
            
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
            
    except Exception as e:
        # 错误处理
        error_result = {
            "success": False,
            "error": str(e),
            "message": "❌ 即梦 Playwright 自动化测试失败",
            "troubleshooting": [
                "1. 确保已安装 Playwright: pip install playwright",
                "2. 确保已安装浏览器: playwright install chromium",
                "3. 检查网络连接是否正常",
                "4. 即梦官网可能需要登录才能访问完整功能"
            ]
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        return 1


if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print(json.dumps({
            "success": False,
            "message": "用户中断执行"
        }, ensure_ascii=False))
        sys.exit(1)
