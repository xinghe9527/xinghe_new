#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
测试通用 API 接口 /api/generate
"""

import requests
import json
import time

BASE_URL = "http://127.0.0.1:8123"

def test_health():
    """测试健康检查"""
    print("\n" + "="*60)
    print("测试 1: 健康检查")
    print("="*60)
    
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
        print(f"✅ 状态码: {response.status_code}")
        print(f"✅ 响应: {response.json()}")
        return True
    except Exception as e:
        print(f"❌ 失败: {e}")
        return False


def test_universal_generate():
    """测试通用生成接口"""
    print("\n" + "="*60)
    print("测试 2: 通用生成接口 /api/generate")
    print("="*60)
    
    # 构建请求
    request_data = {
        "platform": "vidu",
        "tool_type": "text2video",
        "payload": {
            "prompt": "一个赛博朋克风格的女孩在霓虹灯下行走",
            "model": "vidu-q3"
        }
    }
    
    print(f"\n📤 发送请求:")
    print(json.dumps(request_data, indent=2, ensure_ascii=False))
    
    try:
        response = requests.post(
            f"{BASE_URL}/api/generate",
            json=request_data,
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        
        print(f"\n✅ 状态码: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ 响应:")
            print(json.dumps(result, indent=2, ensure_ascii=False))
            
            task_id = result.get("task_id")
            print(f"\n✅ 任务 ID: {task_id}")
            
            # 查询任务状态
            print(f"\n等待 3 秒后查询任务状态...")
            time.sleep(3)
            
            status_response = requests.get(f"{BASE_URL}/api/task/{task_id}")
            print(f"\n✅ 任务状态:")
            print(json.dumps(status_response.json(), indent=2, ensure_ascii=False))
            
            return True
        else:
            print(f"❌ 失败: {response.status_code}")
            print(f"❌ 错误: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 失败: {e}")
        return False


def test_old_api():
    """测试旧的 Vidu 专用接口（兼容性测试）"""
    print("\n" + "="*60)
    print("测试 3: 旧接口 /api/vidu/generate（兼容性）")
    print("="*60)
    
    request_data = {
        "prompt": "测试旧接口",
        "platform": "vidu"
    }
    
    print(f"\n📤 发送请求:")
    print(json.dumps(request_data, indent=2, ensure_ascii=False))
    
    try:
        response = requests.post(
            f"{BASE_URL}/api/vidu/generate",
            json=request_data,
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        
        print(f"\n✅ 状态码: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ 响应:")
            print(json.dumps(result, indent=2, ensure_ascii=False))
            return True
        else:
            print(f"❌ 失败: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ 失败: {e}")
        return False


def main():
    """主函数"""
    print("\n" + "="*60)
    print("🧪 API 接口测试")
    print("="*60)
    print(f"📍 服务地址: {BASE_URL}")
    print(f"⚠️  请确保 API 服务已启动: python api_server.py")
    
    # 测试 1: 健康检查
    if not test_health():
        print("\n❌ 健康检查失败，请确保 API 服务已启动")
        return
    
    # 测试 2: 通用接口
    test_universal_generate()
    
    # 测试 3: 旧接口（兼容性）
    test_old_api()
    
    print("\n" + "="*60)
    print("✅ 测试完成")
    print("="*60)


if __name__ == "__main__":
    main()
