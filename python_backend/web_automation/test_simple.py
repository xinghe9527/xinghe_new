#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
简单测试脚本 - 验证 API 是否正常工作

使用方法：
    python python_backend/web_automation/test_simple.py
"""

import requests
import json
import time

API_BASE_URL = "http://127.0.0.1:8123"

def test_health():
    """测试健康检查接口"""
    print("\n" + "="*60)
    print("  测试 1: 健康检查")
    print("="*60)
    
    try:
        response = requests.get(f"{API_BASE_URL}/health", timeout=5)
        print(f"✅ 状态码: {response.status_code}")
        print(f"✅ 响应: {json.dumps(response.json(), indent=2, ensure_ascii=False)}")
        return True
    except Exception as e:
        print(f"❌ 失败: {e}")
        return False


def test_submit_task():
    """测试提交任务接口"""
    print("\n" + "="*60)
    print("  测试 2: 提交任务")
    print("="*60)
    
    payload = {
        "platform": "vidu",
        "tool_type": "text2video",
        "payload": {
            "prompt": "测试提示词",
            "model": "vidu-1.5"
        }
    }
    
    print(f"📤 发送请求:")
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    
    try:
        response = requests.post(
            f"{API_BASE_URL}/api/generate",
            json=payload,
            timeout=10
        )
        
        print(f"\n✅ 状态码: {response.status_code}")
        result = response.json()
        print(f"✅ 响应: {json.dumps(result, indent=2, ensure_ascii=False)}")
        
        task_id = result.get('task_id')
        if task_id:
            print(f"\n✅ 任务 ID: {task_id}")
            return task_id
        else:
            print(f"\n❌ 响应中没有 task_id")
            return None
            
    except Exception as e:
        print(f"❌ 失败: {e}")
        return None


def test_query_task(task_id):
    """测试查询任务接口"""
    print("\n" + "="*60)
    print("  测试 3: 查询任务状态")
    print("="*60)
    
    print(f"📤 查询任务: {task_id}")
    
    try:
        response = requests.get(
            f"{API_BASE_URL}/api/task/{task_id}",
            timeout=10
        )
        
        print(f"\n✅ 状态码: {response.status_code}")
        result = response.json()
        print(f"✅ 响应: {json.dumps(result, indent=2, ensure_ascii=False)}")
        return True
        
    except Exception as e:
        print(f"❌ 失败: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"   响应内容: {e.response.text}")
        return False


def test_list_tasks():
    """测试列出所有任务接口"""
    print("\n" + "="*60)
    print("  测试 4: 列出所有任务")
    print("="*60)
    
    try:
        response = requests.get(f"{API_BASE_URL}/api/tasks", timeout=10)
        
        print(f"✅ 状态码: {response.status_code}")
        result = response.json()
        print(f"✅ 响应: {json.dumps(result, indent=2, ensure_ascii=False)}")
        return True
        
    except Exception as e:
        print(f"❌ 失败: {e}")
        return False


def main():
    """主函数"""
    print("\n" + "="*60)
    print("  🧪 API 简单测试")
    print("="*60)
    
    # 测试 1: 健康检查
    if not test_health():
        print("\n❌ 健康检查失败，请确保 API 服务器正在运行")
        print("   启动命令: python api_server.py")
        return 1
    
    # 测试 2: 提交任务
    task_id = test_submit_task()
    if not task_id:
        print("\n❌ 提交任务失败")
        return 1
    
    # 等待一下，让任务被处理
    print("\n⏳ 等待 2 秒...")
    time.sleep(2)
    
    # 测试 3: 查询任务
    if not test_query_task(task_id):
        print("\n❌ 查询任务失败")
        return 1
    
    # 测试 4: 列出所有任务
    if not test_list_tasks():
        print("\n❌ 列出任务失败")
        return 1
    
    print("\n" + "="*60)
    print("  ✅ 所有测试通过！")
    print("="*60)
    return 0


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
