#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
API 服务器测试脚本
用于测试所有 API 接口是否正常工作

用法：
    python python_backend/web_automation/test_api.py
"""

import sys
import io
import json
import time
import requests

# 确保标准输出使用 UTF-8 编码
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# API 基础地址
BASE_URL = "http://127.0.0.1:8123"


def print_section(title):
    """打印分隔线"""
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}\n")


def test_health_check():
    """测试健康检查"""
    print_section("1️⃣  测试健康检查")
    
    try:
        response = requests.get(f"{BASE_URL}/health")
        print(f"状态码: {response.status_code}")
        print(f"响应: {json.dumps(response.json(), ensure_ascii=False, indent=2)}")
        
        if response.status_code == 200:
            print("✅ 健康检查通过")
            return True
        else:
            print("❌ 健康检查失败")
            return False
    except Exception as e:
        print(f"❌ 连接失败: {e}")
        print("\n💡 提示: 请先启动 API 服务器")
        print("   python python_backend/web_automation/api_server.py")
        return False


def test_generate_video():
    """测试视频生成接口"""
    print_section("2️⃣  测试视频生成接口")
    
    try:
        # 提交任务
        payload = {
            "prompt": "一个赛博朋克风格的女孩（API 测试）",
            "platform": "vidu"
        }
        
        print(f"📤 提交任务...")
        print(f"提示词: {payload['prompt']}")
        
        response = requests.post(
            f"{BASE_URL}/api/vidu/generate",
            json=payload,
        )
        
        print(f"\n状态码: {response.status_code}")
        result = response.json()
        print(f"响应: {json.dumps(result, ensure_ascii=False, indent=2)}")
        
        if response.status_code == 200:
            task_id = result.get("task_id")
            print(f"\n✅ 任务已提交")
            print(f"📋 任务 ID: {task_id}")
            return task_id
        else:
            print("❌ 任务提交失败")
            return None
            
    except Exception as e:
        print(f"❌ 请求失败: {e}")
        return None


def test_task_status(task_id):
    """测试任务状态查询"""
    print_section("3️⃣  测试任务状态查询")
    
    if not task_id:
        print("⚠️  跳过测试（无任务 ID）")
        return
    
    try:
        print(f"📋 查询任务: {task_id}")
        
        # 轮询查询任务状态（最多 10 次）
        for i in range(10):
            response = requests.get(f"{BASE_URL}/api/task/{task_id}")
            
            if response.status_code == 200:
                result = response.json()
                status = result.get("status")
                
                print(f"\n[{i+1}/10] 任务状态: {status}")
                
                if status == "success":
                    print(f"✅ 任务成功！")
                    print(f"结果: {json.dumps(result.get('result'), ensure_ascii=False, indent=2)}")
                    break
                elif status == "failed":
                    print(f"❌ 任务失败")
                    print(f"错误: {result.get('error')}")
                    break
                elif status == "running":
                    print(f"⏳ 任务执行中...")
                    time.sleep(3)
                elif status == "pending":
                    print(f"⏳ 任务等待中...")
                    time.sleep(2)
                else:
                    print(f"⚠️  未知状态: {status}")
                    break
            else:
                print(f"❌ 查询失败: {response.status_code}")
                break
        
    except Exception as e:
        print(f"❌ 请求失败: {e}")


def test_get_all_tasks():
    """测试获取所有任务"""
    print_section("4️⃣  测试获取所有任务")
    
    try:
        response = requests.get(f"{BASE_URL}/api/tasks")
        
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            total = result.get("total", 0)
            tasks = result.get("tasks", [])
            
            print(f"✅ 共有 {total} 个任务")
            
            if tasks:
                print("\n任务列表:")
                for task in tasks:
                    print(f"  • {task['task_id']}: {task['status']}")
            else:
                print("  （暂无任务）")
        else:
            print("❌ 获取失败")
            
    except Exception as e:
        print(f"❌ 请求失败: {e}")


def test_browser_control():
    """测试浏览器窗口控制"""
    print_section("5️⃣  测试浏览器窗口控制")
    
    try:
        # 测试显示浏览器
        print("📤 测试显示浏览器...")
        response = requests.post(f"{BASE_URL}/api/browser/show")
        
        print(f"状态码: {response.status_code}")
        result = response.json()
        print(f"响应: {json.dumps(result, ensure_ascii=False, indent=2)}")
        
        if result.get("success"):
            print("✅ 显示浏览器成功")
        else:
            print(f"⚠️  {result.get('message')}")
        
        time.sleep(2)
        
        # 测试隐藏浏览器
        print("\n📤 测试隐藏浏览器...")
        response = requests.post(f"{BASE_URL}/api/browser/hide")
        
        print(f"状态码: {response.status_code}")
        result = response.json()
        print(f"响应: {json.dumps(result, ensure_ascii=False, indent=2)}")
        
        if result.get("success"):
            print("✅ 隐藏浏览器成功")
        else:
            print(f"⚠️  {result.get('message')}")
            
    except Exception as e:
        print(f"❌ 请求失败: {e}")


def main():
    """主函数"""
    print("\n" + "="*60)
    print("  🧪 Vidu 自动化 API 测试")
    print("="*60)
    
    # 1. 健康检查
    if not test_health_check():
        print("\n❌ 服务器未启动，测试终止")
        return
    
    # 2. 测试视频生成
    task_id = test_generate_video()
    
    # 3. 测试任务状态查询
    if task_id:
        test_task_status(task_id)
    
    # 4. 测试获取所有任务
    test_get_all_tasks()
    
    # 5. 测试浏览器控制
    test_browser_control()
    
    # 总结
    print_section("🎉 测试完成")
    print("所有接口测试已完成！")
    print("\n💡 提示:")
    print("  • 访问 http://127.0.0.1:8123/docs 查看交互式 API 文档")
    print("  • 使用 Postman 或 cURL 进行更多测试")
    print()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  测试被用户中断\n")
    except Exception as e:
        print(f"\n\n❌ 测试异常: {e}\n")
