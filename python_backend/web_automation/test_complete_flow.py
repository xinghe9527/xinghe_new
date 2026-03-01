#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
测试完整的 Vidu 视频生成流程（包含下载）

测试步骤：
1. 启动 API 服务器（需要手动启动）
2. 提交视频生成任务（带保存路径）
3. 轮询任务状态
4. 验证视频是否下载到指定路径

使用方法：
    python python_backend/web_automation/test_complete_flow.py
"""

import requests
import time
import json
import os
from pathlib import Path

# API 配置
API_BASE_URL = "http://127.0.0.1:8123"

# 测试配置
TEST_PROMPT = "一个赛博朋克风格的女孩在霓虹灯下行走"
TEST_SAVE_DIR = os.path.join(os.path.dirname(__file__), 'test_downloads')

def print_step(step_num, message):
    """打印步骤信息"""
    print(f"\n{'='*60}")
    print(f"  步骤 {step_num}: {message}")
    print(f"{'='*60}\n")


def check_api_health():
    """检查 API 服务是否运行"""
    try:
        response = requests.get(f"{API_BASE_URL}/health", timeout=5)
        if response.status_code == 200:
            print("✅ API 服务运行正常")
            print(f"   响应: {response.json()}")
            return True
        else:
            print(f"❌ API 服务响应异常: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ 无法连接到 API 服务: {e}")
        print(f"\n请先启动 API 服务器：")
        print(f"   python python_backend/web_automation/api_server.py")
        return False


def submit_task(prompt, save_path):
    """提交视频生成任务"""
    url = f"{API_BASE_URL}/api/generate"
    
    payload = {
        "platform": "vidu",
        "tool_type": "text2video",
        "payload": {
            "prompt": prompt,
            "model": "vidu-1.5",
            "savePath": save_path
        }
    }
    
    print(f"📤 提交任务...")
    print(f"   提示词: {prompt}")
    print(f"   保存路径: {save_path}")
    
    try:
        response = requests.post(url, json=payload, timeout=10)
        response.raise_for_status()
        
        result = response.json()
        task_id = result.get('task_id')
        
        print(f"✅ 任务已提交")
        print(f"   任务 ID: {task_id}")
        print(f"   状态: {result.get('status')}")
        
        return task_id
    except requests.exceptions.RequestException as e:
        print(f"❌ 提交任务失败: {e}")
        return None


def poll_task_status(task_id, max_wait_minutes=15):
    """轮询任务状态"""
    url = f"{API_BASE_URL}/api/task/{task_id}"
    
    max_attempts = max_wait_minutes * 60 // 5  # 每 5 秒检查一次
    
    print(f"\n⏳ 开始轮询任务状态（最多等待 {max_wait_minutes} 分钟）...")
    
    for attempt in range(max_attempts):
        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            
            result = response.json()
            status = result.get('status')
            
            elapsed = (attempt + 1) * 5
            print(f"   [{elapsed:3d}s] 状态: {status}", end='')
            
            if status == 'success':
                print(" ✅")
                print(f"\n✅ 任务完成！")
                
                # 显示结果
                task_result = result.get('result', {})
                print(f"\n📊 任务结果:")
                print(f"   成功: {task_result.get('success')}")
                print(f"   消息: {task_result.get('message')}")
                print(f"   视频 URL: {task_result.get('video_url', 'N/A')}")
                print(f"   本地路径: {task_result.get('local_video_path', 'N/A')}")
                
                return result
            elif status == 'failed':
                print(" ❌")
                error = result.get('error', '未知错误')
                print(f"\n❌ 任务失败: {error}")
                return result
            elif status == 'cancelled':
                print(" ⚠️")
                print(f"\n⚠️  任务已取消")
                return result
            else:
                print()  # 换行
            
            # 等待 5 秒后继续
            time.sleep(5)
            
        except requests.exceptions.RequestException as e:
            print(f"\n❌ 查询任务状态失败: {e}")
            time.sleep(5)
            continue
    
    print(f"\n⏰ 轮询超时（{max_wait_minutes} 分钟）")
    return None


def verify_video_file(file_path):
    """验证视频文件是否存在"""
    if os.path.exists(file_path):
        file_size = os.path.getsize(file_path)
        print(f"✅ 视频文件已下载")
        print(f"   路径: {file_path}")
        print(f"   大小: {file_size / 1024 / 1024:.2f} MB")
        return True
    else:
        print(f"❌ 视频文件不存在: {file_path}")
        return False


def main():
    """主函数"""
    print("\n" + "="*60)
    print("  🧪 Vidu 完整流程测试")
    print("="*60)
    
    # 步骤 1：检查 API 服务
    print_step(1, "检查 API 服务")
    if not check_api_health():
        return 1
    
    # 步骤 2：准备保存目录
    print_step(2, "准备保存目录")
    os.makedirs(TEST_SAVE_DIR, exist_ok=True)
    
    timestamp = int(time.time())
    save_path = os.path.join(TEST_SAVE_DIR, f'test_video_{timestamp}.mp4')
    print(f"📁 保存路径: {save_path}")
    
    # 步骤 3：提交任务
    print_step(3, "提交视频生成任务")
    task_id = submit_task(TEST_PROMPT, save_path)
    
    if not task_id:
        print("\n❌ 测试失败：无法提交任务")
        return 1
    
    # 步骤 4：轮询任务状态
    print_step(4, "轮询任务状态")
    result = poll_task_status(task_id, max_wait_minutes=15)
    
    if not result:
        print("\n❌ 测试失败：任务超时")
        return 1
    
    # 步骤 5：验证视频文件
    print_step(5, "验证视频文件")
    
    task_result = result.get('result', {})
    local_path = task_result.get('local_video_path')
    
    if local_path:
        if verify_video_file(local_path):
            print("\n" + "="*60)
            print("  ✅ 测试成功！完整流程正常工作")
            print("="*60)
            return 0
        else:
            print("\n❌ 测试失败：视频文件未找到")
            return 1
    else:
        print("\n❌ 测试失败：任务结果中没有本地路径")
        return 1


if __name__ == "__main__":
    try:
        exit_code = main()
        exit(exit_code)
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断测试")
        exit(1)
    except Exception as e:
        print(f"\n❌ 测试异常: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
