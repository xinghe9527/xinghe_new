"""
测试 LaMa 服务是否正常运行
"""
import requests
import numpy as np
import cv2
import time

def test_health_check():
    """测试健康检查接口"""
    print("=" * 60)
    print("测试 1: 健康检查")
    print("=" * 60)
    
    try:
        response = requests.get("http://127.0.0.1:8000/", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print("✅ 服务运行正常")
            print(f"📊 状态: {data.get('status')}")
            print(f"🔧 模型加载: {data.get('model_loaded')}")
            print(f"💻 设备: {data.get('device')}")
            return True
        else:
            print(f"❌ 服务返回错误: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("❌ 无法连接到服务")
        print("💡 请先启动服务: python main.py")
        return False
    except Exception as e:
        print(f"❌ 测试失败: {e}")
        return False

def test_remove_watermark():
    """测试去水印接口"""
    print("\n" + "=" * 60)
    print("测试 2: 去水印功能")
    print("=" * 60)
    
    try:
        # 创建测试图片（512x512 白色图片）
        print("📝 创建测试图片...")
        test_image = np.ones((512, 512, 3), dtype=np.uint8) * 255
        
        # 添加一个黑色方块作为"水印"
        test_image[200:300, 200:300] = 0
        
        # 创建遮罩（标记黑色方块区域）
        test_mask = np.zeros((512, 512), dtype=np.uint8)
        test_mask[200:300, 200:300] = 255
        
        # 编码为 PNG
        _, img_encoded = cv2.imencode('.png', test_image)
        _, mask_encoded = cv2.imencode('.png', test_mask)
        
        print("📤 发送请求到服务...")
        start_time = time.time()
        
        # 发送请求
        files = {
            'image': ('test.png', img_encoded.tobytes(), 'image/png'),
            'mask': ('mask.png', mask_encoded.tobytes(), 'image/png')
        }
        
        response = requests.post(
            "http://127.0.0.1:8000/remove_watermark",
            files=files,
            timeout=60
        )
        
        elapsed_time = time.time() - start_time
        
        if response.status_code == 200:
            print(f"✅ 去水印成功")
            print(f"⏱️  处理时间: {elapsed_time:.2f} 秒")
            print(f"📦 返回大小: {len(response.content) / 1024:.2f} KB")
            
            # 保存结果
            result_image = cv2.imdecode(
                np.frombuffer(response.content, np.uint8),
                cv2.IMREAD_COLOR
            )
            cv2.imwrite("test_result.png", result_image)
            print("💾 结果已保存: test_result.png")
            
            return True
        else:
            print(f"❌ 请求失败: {response.status_code}")
            print(f"📄 错误信息: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """主函数"""
    print("\n🧪 LaMa 服务测试工具\n")
    
    # 测试 1: 健康检查
    if not test_health_check():
        print("\n❌ 健康检查失败，停止测试")
        return
    
    # 测试 2: 去水印功能
    if not test_remove_watermark():
        print("\n❌ 去水印测试失败")
        return
    
    print("\n" + "=" * 60)
    print("✅ 所有测试通过！")
    print("=" * 60)
    print("\n🚀 服务已就绪，可以在 Flutter 中使用")

if __name__ == "__main__":
    main()
