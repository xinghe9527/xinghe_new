#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Vidu 自动视频生成脚本
使用持久化登录状态，自动填充提示词并生成视频

用法：
    python python_backend/web_automation/auto_vidu.py "一个赛博朋克风格的女孩"
"""

import sys
import json
import io
import os
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError
import time

# 确保标准输出使用 UTF-8 编码（Windows 兼容）
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# ✅ 获取项目根目录的绝对路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))  # python_backend/web_automation/
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))  # 项目根目录
USER_DATA_ROOT = os.path.join(PROJECT_ROOT, 'python_backend', 'user_data')

# ✅ Vidu 功能地址配置（.com 已重定向到 .cn）
VIDU_URLS = {
    'text2video': 'https://www.vidu.cn/create/text2video',  # 文生视频（当前使用）
    'img2video': 'https://www.vidu.cn/create/img2video',    # 图生视频（预留）
    'text2image': 'https://www.vidu.cn/create/text2image',  # 文生图片（预留）
}

# 配置（使用绝对路径）
VIDU_URL = VIDU_URLS['text2video']  # ✅ 精确锁定文生视频工作台
USER_DATA_DIR = os.path.join(USER_DATA_ROOT, 'vidu_profile')


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
    """自动清障：关闭所有弹窗和遮挡物（极速版）"""
    print("\n🧹 开始清障：检测并关闭弹窗...")
    
    # 弹窗关闭按钮的选择器（按优先级排序）
    close_selectors = [
        # 常见的关闭按钮文本
        'button:has-text("关闭")',
        'button:has-text("Close")',
        'button:has-text("×")',
        'button:has-text("✕")',
        'button:has-text("X")',
        
        # 包含特定关键词的弹窗
        'button:has-text("知道了")',
        'button:has-text("我知道了")',
        'button:has-text("稍后")',
        'button:has-text("取消")',
        'button:has-text("跳过")',
        'button:has-text("不再提示")',
        
        # 任务/积分相关弹窗
        'div:has-text("免费获得积分") button',
        'div:has-text("任务") button:has-text("关闭")',
        'div:has-text("每日任务") button',
        
        # CSS 类名
        '.close-button',
        '.close-btn',
        '.modal-close',
        '.popup-close',
        '.dialog-close',
        'button.close',
        '.icon-close',
        
        # 属性选择器
        '[aria-label="关闭"]',
        '[aria-label="Close"]',
        '[data-testid="close-button"]',
        '[data-testid="modal-close"]',
        'button[title="关闭"]',
        'button[title="Close"]',
        
        # 遮罩层
        '.mask',
        '.overlay',
        '.backdrop',
    ]
    
    closed_count = 0
    max_attempts = 3  # ✅ 减少到 3 轮（原来是 5 轮）
    
    for attempt in range(max_attempts):
        found_blocker = False
        
        for selector in close_selectors:
            try:
                # 查找所有匹配的元素
                elements = page.locator(selector).all()
                
                for element in elements:
                    try:
                        # ✅ 缩短超时到 500ms（原来是 1000ms）
                        if element.is_visible(timeout=500):
                            print(f"  🎯 发现遮挡物: {selector}")
                            element.click(timeout=1000)  # ✅ 点击超时 1 秒
                            closed_count += 1
                            found_blocker = True
                            print(f"  ✅ 已关闭遮挡物 #{closed_count}")
                            time.sleep(0.3)  # ✅ 减少等待时间（原来是 0.5 秒）
                    except:
                        continue
            except:
                continue
        
        # 如果这一轮没有发现遮挡物，说明清理完成
        if not found_blocker:
            break
        
        # ✅ 减少轮次间隔（原来是 1 秒）
        time.sleep(0.5)
    
    if closed_count > 0:
        print(f"✅ 清障完成：共关闭 {closed_count} 个遮挡物")
    else:
        print("✅ 未发现遮挡物，页面清洁")
    
    return closed_count


def wait_for_manual_check(page):
    """永久等待，让用户手动检查"""
    warning = """
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║  ⚠️  未检测到登录状态！                                   ║
║                                                          ║
║  请手动检查浏览器：                                       ║
║  1. 如果未登录，请手动登录                                ║
║  2. 登录成功后，按 Ctrl+C 中断脚本                        ║
║  3. 重新运行 init_login.py 保存登录状态                   ║
║                                                          ║
║  🔧 或者：                                                ║
║  如果确认已登录，按 Ctrl+C 中断，然后直接重新运行此脚本    ║
║                                                          ║
║  ⏳ 脚本将永久等待，不会自动关闭浏览器...                 ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"""
    print(warning)
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断，脚本退出\n")
        raise


def main():
    """主函数：自动生成 Vidu 视频"""
    
    # 检查命令行参数
    if len(sys.argv) < 2:
        error_result = {
            "success": False,
            "error": "缺少提示词参数",
            "usage": "python auto_vidu.py <prompt>",
            "example": "python auto_vidu.py '一个赛博朋克风格的女孩'"
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        return 1
    
    # 获取提示词
    prompt = sys.argv[1]
    
    # 检查登录状态目录
    if not os.path.exists(USER_DATA_DIR):
        error_result = {
            "success": False,
            "error": "未找到登录状态目录",
            "message": "请先运行登录脚手架初始化登录状态",
            "user_data_dir": USER_DATA_DIR,
            "solution": "python python_backend/web_automation/init_login.py vidu"
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        return 1
    
    print_step(1, "启动浏览器（携带登录状态）")
    print(f"📝 提示词: {prompt}")
    print(f"🔐 登录数据目录（绝对路径）:\n   {USER_DATA_DIR}")
    print(f"📂 目录是否存在: {os.path.exists(USER_DATA_DIR)}")
    
    try:
        # 启动 Playwright
        with sync_playwright() as p:
            # ✅ 使用持久化上下文（参数与 init_login.py 完全一致）
            context = p.chromium.launch_persistent_context(
                user_data_dir=USER_DATA_DIR,
                headless=False,  # 显示浏览器
                viewport={'width': 1920, 'height': 1080},
                locale='zh-CN',
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                args=[
                    '--start-maximized',
                    '--disable-blink-features=AutomationControlled'
                ]
            )
            
            # 获取页面
            if len(context.pages) > 0:
                page = context.pages[0]
            else:
                page = context.new_page()
            
            print_step(2, "访问 Vidu 文生视频工作台")
            print(f"🌐 目标地址: {VIDU_URL}")
            page.goto(VIDU_URL, wait_until='domcontentloaded', timeout=30000)
            
            # ✅ 只等待 DOM 加载完成，不等待网络空闲（大厂网页永远不会完全空闲）
            print("⏳ 等待 DOM 加载完成...")
            
            # ✅ 强制等待输入框出现（最多 10 秒）- 缩短超时
            print("⏳ 等待输入框加载...")
            try:
                page.wait_for_selector('textarea:visible', timeout=10000)
                print("✅ 检测到输入框元素")
            except PlaywrightTimeoutError:
                print("⚠️  输入框加载超时，但继续尝试...")
            
            # ✅ 最小等待时间（只等 2 秒）
            time.sleep(2)
            
            # ✅ 强制聚焦补丁：激活页面焦点
            print("\n🎯 强制激活页面焦点...")
            try:
                page.click('body')
                time.sleep(0.5)
                print("✅ 页面焦点已激活")
            except:
                print("⚠️  焦点激活失败，但继续执行")
            
            # ✅ 自动清障：关闭所有弹窗和遮挡物
            close_popups_and_blockers(page)
            
            print_step(3, "检测登录状态")
            login_status = check_login_status(page)
            
            if login_status == False:
                # 明确检测到未登录
                wait_for_manual_check(page)
                return 1
            elif login_status == None:
                # 不确定登录状态，给用户 10 秒检查
                print("\n⚠️  无法自动判断登录状态")
                print("⏳ 给你 10 秒时间手动检查浏览器...")
                print("   如果未登录，请按 Ctrl+C 中断\n")
                time.sleep(10)
            else:
                # 检测到已登录
                print("✅ 确认已登录，继续执行\n")
            
            print_step(4, "智能填充提示词")
            
            # ✅ 严格使用 :visible 过滤，避免隐藏的 textarea
            print("🔍 查找可见的输入框（使用 :visible 过滤）...")
            
            # 第一优先级：直接定位可见的 textarea
            input_selectors = [
                'textarea:visible',  # ✅ 最优先：可见的 textarea
                'textarea[placeholder*="请输入描述词"]:visible',
                'textarea[placeholder*="描述"]:visible',
                'textarea[placeholder*="提示词"]:visible',
                'input[type="text"]:visible',
            ]
            
            input_found = False
            found_input_element = None  # 保存找到的输入框元素
            
            for i, selector in enumerate(input_selectors, 1):
                try:
                    print(f"🔍 [{i}/{len(input_selectors)}] 尝试: {selector}")
                    input_element = page.locator(selector).first
                    
                    # ✅ 延长超时时间到 10 秒（原来是 15 秒）
                    if input_element.is_visible(timeout=10000):
                        print(f"✅ 找到可见输入框: {selector}")
                        
                        # ✅ 操作高亮：给元素画红框（Debug 模式）
                        print("🎨 高亮显示找到的输入框...")
                        try:
                            input_element.evaluate("el => el.style.border = '3px solid red'")
                            input_element.evaluate("el => el.style.backgroundColor = 'rgba(255, 0, 0, 0.1)'")
                            time.sleep(1)  # 停留 1 秒让你看清楚
                        except:
                            print("⚠️  高亮失败，但继续执行")
                        
                        # ✅ 智能填充逻辑
                        print("📝 开始填充提示词...")
                        
                        # 1. ✅ 暴力聚焦：直接使用 evaluate 强制夺取焦点
                        print("🎯 暴力聚焦：强制夺取输入框焦点...")
                        try:
                            input_element.evaluate("el => el.focus()")
                            time.sleep(0.3)
                            print("✅ 焦点已强制夺取")
                        except:
                            print("⚠️  evaluate 聚焦失败，使用 click 备用")
                            input_element.click(force=True)  # ✅ 强制点击
                            time.sleep(0.3)
                        
                        # 2. 清空现有内容（强制模式）
                        print("🧹 清空现有内容...")
                        try:
                            input_element.fill('', force=True)  # ✅ 强制填充
                        except:
                            input_element.fill('')
                        time.sleep(0.2)
                        
                        # 3. 填充新提示词（强制模式 + 模拟人工输入）
                        print(f"⌨️  输入提示词: {prompt}")
                        try:
                            # 先尝试 type（模拟人工）
                            input_element.type(prompt, delay=30)  # ✅ 加快输入速度（30ms）
                        except:
                            # 失败则使用 fill（强制模式）
                            print("⚠️  type 失败，使用 fill 强制填充")
                            input_element.fill(prompt, force=True)  # ✅ 强制填充
                        time.sleep(0.3)
                        
                        # 4. 验证填充结果
                        filled_value = input_element.input_value()
                        if filled_value == prompt:
                            print(f"✅ 提示词填充成功: {prompt}")
                        else:
                            print(f"⚠️  填充验证: 期望='{prompt}', 实际='{filled_value}'")
                            # 如果不匹配，使用 fill 再次尝试
                            input_element.fill(prompt)
                            time.sleep(0.5)
                        
                        # ✅ 填充后缓冲时间
                        print("⏳ 缓冲 1 秒...")
                        page.wait_for_timeout(1000)
                        
                        input_found = True
                        found_input_element = input_element  # 保存元素用于相对定位
                        break
                except Exception as e:
                    print(f"   ❌ 失败: {str(e)[:80]}")
                    continue
            
            if not input_found:
                # 如果没找到，截图并永久等待
                screenshot_path = os.path.join(SCRIPT_DIR, 'debug_page.png')
                page.screenshot(path=screenshot_path)
                print(f"\n❌ 未找到提示词输入框")
                print(f"📸 调试截图已保存: {screenshot_path}\n")
                
                wait_message = """
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║  ⚠️  未找到输入框！                                       ║
║                                                          ║
║  请手动检查：                                             ║
║  1. 查看浏览器中的页面是否正常                            ║
║  2. 查看 debug_page.png 截图                             ║
║  3. 手动找到输入框并记录其选择器                          ║
║                                                          ║
║  ⏳ 脚本将永久等待，不会关闭浏览器...                     ║
║  按 Ctrl+C 中断                                          ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"""
                print(wait_message)
                wait_for_manual_check(page)
                return 1
            
            print_step(5, "查找并点击生成按钮（相对定位）")
            
            # ✅ 再次清障：确保没有新弹窗遮挡按钮
            close_popups_and_blockers(page)
            
            # ✅ 使用相对定位：在输入框附近查找生成按钮
            print("🎯 使用相对定位：在输入框区域查找生成按钮...")
            
            button_found = False
            
            if found_input_element:
                # 方法1：在输入框的父容器中查找按钮
                print("\n📍 方法1：在输入框的父容器中查找...")
                try:
                    # 获取输入框的父容器
                    parent_container = found_input_element.locator('xpath=ancestor::div[contains(@class, "container") or contains(@class, "form") or contains(@class, "content")][1]')
                    
                    # 在父容器中查找生成按钮
                    relative_button_selectors = [
                        # ✅ 第一优先级：创作按钮（Vidu 实际使用的文本）
                        'button:has-text("创作"):visible',
                        'button:has-text("创作 0"):visible',
                        'button:has-text("创作 "):visible',
                        
                        # 第二优先级：生成按钮（兼容）
                        'button:has-text("生成"):visible',
                        'button:has-text("生成视频"):visible',
                        'button:has-text("开始生成"):visible',
                        
                        # 第三优先级：其他可能的文本
                        'button:has-text("创建"):visible',
                        'button[type="submit"]:visible',
                    ]
                    
                    for selector in relative_button_selectors:
                        try:
                            button = parent_container.locator(selector).first
                            if button.is_visible(timeout=3000):
                                print(f"✅ 在父容器中找到按钮: {selector}")
                                
                                # ✅ 高亮显示按钮
                                print("🎨 高亮显示找到的按钮...")
                                try:
                                    button.evaluate("el => el.style.border = '3px solid red'")
                                    button.evaluate("el => el.style.backgroundColor = 'rgba(255, 0, 0, 0.1)'")
                                    time.sleep(1)
                                except:
                                    pass
                                
                                # 点击按钮（强制模式）
                                print("🖱️  点击创作按钮...")
                                try:
                                    button.click(timeout=5000, force=True)  # ✅ 强制点击
                                    print("✅ 创作按钮已点击（相对定位）")
                                    button_found = True
                                    break
                                except Exception as click_error:
                                    print(f"❌ 点击失败: {str(click_error)[:80]}")
                                    continue
                        except:
                            continue
                except Exception as e:
                    print(f"⚠️  父容器定位失败: {str(e)[:80]}")
            
            # 方法2：排除导航栏区域，在主内容区查找
            if not button_found:
                print("\n📍 方法2：排除导航栏，在主内容区查找...")
                try:
                    # 排除 header/nav 区域
                    main_content_selectors = [
                        'main:visible',
                        '[role="main"]:visible',
                        '.main-content:visible',
                        '.content:visible',
                        '#content:visible',
                    ]
                    
                    for content_selector in main_content_selectors:
                        try:
                            main_content = page.locator(content_selector).first
                            if main_content.is_visible(timeout=2000):
                                print(f"✅ 找到主内容区: {content_selector}")
                                
                                # 在主内容区中查找生成按钮
                                button_selectors_in_main = [
                                    # ✅ 第一优先级：创作按钮
                                    'button:has-text("创作"):visible',
                                    'button:has-text("创作 0"):visible',
                                    'button:has-text("创作 "):visible',
                                    
                                    # 第二优先级：生成按钮（兼容）
                                    'button:has-text("生成"):visible',
                                    'button:has-text("生成视频"):visible',
                                    'button:has-text("开始生成"):visible',
                                    
                                    # 第三优先级：其他
                                    'button:has-text("创建"):visible',
                                    'button[type="submit"]:visible',
                                ]
                                
                                for selector in button_selectors_in_main:
                                    try:
                                        button = main_content.locator(selector).first
                                        if button.is_visible(timeout=3000):
                                            print(f"✅ 在主内容区找到按钮: {selector}")
                                            
                                            # ✅ 高亮显示按钮
                                            print("🎨 高亮显示找到的按钮...")
                                            try:
                                                button.evaluate("el => el.style.border = '3px solid red'")
                                                button.evaluate("el => el.style.backgroundColor = 'rgba(255, 0, 0, 0.1)'")
                                                time.sleep(1)
                                            except:
                                                pass
                                            
                                            # 点击按钮（强制模式）
                                            button.click(timeout=5000, force=True)  # ✅ 强制点击
                                            print("✅ 生成按钮已点击（主内容区定位）")
                                            button_found = True
                                            break
                                    except:
                                        continue
                                
                                if button_found:
                                    break
                        except:
                            continue
                except Exception as e:
                    print(f"⚠️  主内容区定位失败: {str(e)[:80]}")
            
            # 方法3：使用 XPath 排除导航栏
            if not button_found:
                print("\n📍 方法3：使用 XPath 排除导航栏...")
                try:
                    # ✅ 优先查找"创作"按钮，排除 header/nav
                    xpath_selectors = [
                        '//button[contains(text(), "创作") and not(ancestor::header) and not(ancestor::nav)]',
                        '//button[contains(text(), "生成") and not(ancestor::header) and not(ancestor::nav)]',
                    ]
                    
                    for xpath in xpath_selectors:
                        try:
                            xpath_button = page.locator(f'xpath={xpath}').first
                            if xpath_button.is_visible(timeout=3000):
                                print(f"✅ 使用 XPath 找到按钮（已排除导航栏）")
                                
                                # ✅ 高亮显示按钮
                                print("🎨 高亮显示找到的按钮...")
                                try:
                                    xpath_button.evaluate("el => el.style.border = '3px solid red'")
                                    xpath_button.evaluate("el => el.style.backgroundColor = 'rgba(255, 0, 0, 0.1)'")
                                    time.sleep(1)
                                except:
                                    pass
                                
                                # 点击按钮（强制模式）
                                xpath_button.click(timeout=5000, force=True)  # ✅ 强制点击
                                print("✅ 生成按钮已点击（XPath 定位）")
                                button_found = True
                                break
                        except:
                            continue
                except Exception as e:
                    print(f"⚠️  XPath 定位失败: {str(e)[:80]}")
            
            # 如果所有相对定位方法都失败，显示错误信息
            if not button_found:
                # 如果没找到，截图并永久等待
                screenshot_path = os.path.join(SCRIPT_DIR, 'debug_page.png')
                page.screenshot(path=screenshot_path)
                print(f"\n❌ 未找到生成按钮")
                print(f"📸 调试截图已保存: {screenshot_path}\n")
                
                wait_message = """
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║  ⚠️  未找到生成按钮！                                     ║
║                                                          ║
║  请手动检查：                                             ║
║  1. 查看浏览器中的页面                                    ║
║  2. 查看 debug_page.png 截图                             ║
║  3. 手动找到生成按钮并记录其选择器                        ║
║  4. 或者手动点击生成按钮                                  ║
║                                                          ║
║  ⏳ 脚本将永久等待，不会关闭浏览器...                     ║
║  按 Ctrl+C 中断                                          ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"""
                print(wait_message)
                wait_for_manual_check(page)
                return 1
            
            print_step(6, "观影模式：等待确认生成状态")
            
            # ✅ 观影模式：停留 30 秒让用户确认
            print("\n" + "="*60)
            print("  🎬 任务已提交云端！")
            print("  ⏳ 等待 30 秒以供人工确认生成状态...")
            print("  💡 你可以在浏览器中查看生成进度")
            print("="*60 + "\n")
            
            # 倒计时显示
            for remaining in range(30, 0, -5):
                print(f"⏰ 剩余 {remaining} 秒...")
                time.sleep(5)
            
            print("\n✅ 观影时间结束，准备关闭浏览器\n")
            
            # 最后截图保存
            screenshot_path = os.path.join(SCRIPT_DIR, 'generating.png')
            page.screenshot(path=screenshot_path)
            print(f"📸 最终截图已保存: {screenshot_path}")
            
            print_step(7, "关闭浏览器")
            context.close()
            
            # 返回成功结果
            result = {
                "success": True,
                "message": "✅ Vidu 视频生成任务已提交！",
                "prompt": prompt,
                "details": {
                    "平台": "Vidu",
                    "提示词": prompt,
                    "状态": "已点击生成按钮",
                    "截图": screenshot_path,
                    "用户数据目录": USER_DATA_DIR,
                    "说明": "视频正在生成中，请在 Vidu 官网查看进度"
                },
                "next_step": "可以在 Vidu 官网查看生成进度和结果"
            }
            
            print("\n" + "="*60)
            print("  🎉 自动化执行成功！")
            print("="*60 + "\n")
            
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
            
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断执行\n")
        result = {
            "success": False,
            "message": "用户手动中断",
            "prompt": prompt
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1
        
    except PlaywrightTimeoutError as e:
        error_result = {
            "success": False,
            "error": "页面加载超时",
            "message": "❌ Vidu 页面加载超时",
            "details": str(e),
            "troubleshooting": [
                "1. 检查网络连接",
                "2. 确认 Vidu 官网可访问",
                "3. 尝试增加等待时间"
            ]
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        return 1
        
    except Exception as e:
        error_result = {
            "success": False,
            "error": str(e),
            "message": "❌ Vidu 自动化执行失败",
            "prompt": prompt,
            "user_data_dir": USER_DATA_DIR,
            "troubleshooting": [
                "1. 确保已完成登录（运行 init_login.py vidu）",
                "2. 检查 Vidu 页面结构是否变化",
                "3. 查看 debug_page.png 截图分析问题",
                "4. 检查详细错误信息"
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
        }, ensure_ascii=False, indent=2))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({
            "success": False,
            "error": str(e),
            "message": "脚本执行异常"
        }, ensure_ascii=False, indent=2))
        sys.exit(1)
