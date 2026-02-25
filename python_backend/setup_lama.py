"""
一键安装 LaMa 模型（使用 lama-cleaner）
"""
import os
import sys
import subprocess

def run_command(cmd):
    """运行命令并显示输出"""
    print(f"🔧 执行: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"❌ 错误: {result.stderr}")
        return False
    print(result.stdout)
    return True

def main():
    """主函数"""
    print("=" * 60)
    print("LaMa 模型一键安装工具")
    print("=" * 60)
    
    print("\n📦 安装方式:")
    print("1. 使用 lama-cleaner（推荐，自动下载模型）")
    print("2. 手动下载 ONNX 模型")
    print("3. 从 PyTorch 转换")
    
    choice = input("\n请选择 (1/2/3): ").strip()
    
    if choice == "1":
        print("\n📥 安装 lama-cleaner...")
        if not run_command(f"{sys.executable} -m pip install lama-cleaner"):
            print("❌ 安装失败")
            return
        
        print("\n✅ lama-cleaner 安装成功！")
        print("\n💡 使用方法:")
        print("1. 启动 lama-cleaner: lama-cleaner --model=lama --device=cpu")
        print("2. 或者使用我们的 FastAPI 服务: python main.py")
        print("\n⚠️  首次运行会自动下载模型（约 200MB）")
    
    elif choice == "2":
        print("\n📥 开始下载 ONNX 模型...")
        if not run_command(f"{sys.executable} download_model.py"):
            print("❌ 下载失败")
            return
    
    elif choice == "3":
        print("\n🔄 开始转换模型...")
        # 先下载 PyTorch 模型
        print("📥 下载 PyTorch 模型...")
        if not run_command(f"{sys.executable} download_model.py"):
            print("❌ 下载失败")
            return
        
        # 转换为 ONNX
        print("\n🔧 转换为 ONNX...")
        if not run_command(f"{sys.executable} convert_to_onnx.py"):
            print("❌ 转换失败")
            return
    
    else:
        print("❌ 无效选择")
        return
    
    print("\n" + "=" * 60)
    print("✅ 安装完成！")
    print("=" * 60)
    print("\n🚀 启动服务: python main.py")
    print("🌐 访问: http://127.0.0.1:8000")

if __name__ == "__main__":
    main()
