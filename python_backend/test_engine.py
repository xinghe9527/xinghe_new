"""
测试打包后的引擎是否正常工作
"""
import requests
import time
import sys

def test_engine():
    """测试引擎健康状态"""
    url = "http://127.0.0.1:8000/"
    
    print("🔍 正在测试引擎...")
    print(f"📍 URL: {url}")
    print("")
    
    # 尝试连接
    max_attempts = 10
    for i in range(max_attempts):
        try:
            response = requests.get(url, timeout=2)
            
            if response.status_code == 200:
                data = response.json()
                print("✅ 引擎运行正常！")
                print("")
                print("📊 引擎状态:")
                print(f"  - 状态: {data.get('status')}")
                print(f"  - 模型已加载: {data.get('model_loaded')}")
                print(f"  - 设备: {data.get('device')}")
                print("")
                return True
            else:
                print(f"❌ 引擎返回错误状态码: {response.status_code}")
                return False
                
        except requests.exceptions.ConnectionError:
            if i < max_attempts - 1:
                print(f"⏳ 等待引擎启动... ({i+1}/{max_attempts})")
                time.sleep(1)
            else:
                print("")
                print("❌ 无法连接到引擎！")
                print("")
                print("💡 请确保:")
                print("  1. 引擎已启动 (运行 watermark_engine.exe)")
                print("  2. 端口 8000 未被占用")
                print("  3. lama_model.onnx 文件存在")
                print("")
                return False
        except Exception as e:
            print(f"❌ 测试失败: {e}")
            return False
    
    return False

if __name__ == "__main__":
    success = test_engine()
    sys.exit(0 if success else 1)
