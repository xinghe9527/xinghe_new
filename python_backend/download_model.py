"""
下载预转换的 LaMa ONNX 模型
"""
import os
import requests
from tqdm import tqdm

# 模型下载地址
MODEL_URLS = {
    # GitHub Release (推荐)
    "lama_github": "https://github.com/Sanster/models/releases/download/add_big_lama/big-lama.pt",
    
    # 备用地址 1: lama-cleaner 的 ONNX 模型
    "lama_cleaner_onnx": "https://github.com/Sanster/models/releases/download/add_big_lama/big-lama.onnx",
    
    # 备用地址 2: 使用 Google Drive 镜像
    "lama_gdrive": "https://drive.google.com/uc?export=download&id=1XXX",  # 需要替换实际 ID
    
    # 备用地址 3: 使用轻量级模型（更小，速度更快）
    "lama_small": "https://github.com/Sanster/models/releases/download/add_big_lama/big-lama.pt",
}

def download_file(url, filename):
    """下载文件并显示进度条"""
    print(f"📥 开始下载: {filename}")
    print(f"🔗 URL: {url}")
    
    response = requests.get(url, stream=True)
    total_size = int(response.headers.get('content-length', 0))
    
    with open(filename, 'wb') as file, tqdm(
        desc=filename,
        total=total_size,
        unit='B',
        unit_scale=True,
        unit_divisor=1024,
    ) as bar:
        for data in response.iter_content(chunk_size=1024):
            size = file.write(data)
            bar.update(size)
    
    print(f"✅ 下载完成: {filename}")

def main():
    """主函数"""
    print("=" * 60)
    print("LaMa ONNX 模型下载工具")
    print("=" * 60)
    
    # 检查是否已存在
    if os.path.exists("lama_model.onnx"):
        print("⚠️  模型文件已存在: lama_model.onnx")
        choice = input("是否重新下载？(y/n): ")
        if choice.lower() != 'y':
            print("❌ 取消下载")
            return
    
    print("\n选择下载方式:")
    print("1. 下载 ONNX 模型（推荐，约 200MB）")
    print("2. 下载 PyTorch 模型（需要手动转换，约 200MB）")
    
    choice = input("\n请选择 (1/2): ").strip()
    
    if choice == "1":
        # 下载 ONNX 模型
        try:
            download_file(MODEL_URLS["lama_onnx"], "lama_model.onnx")
            print("\n✅ 模型下载成功！")
            print("📍 模型位置: lama_model.onnx")
            print("🚀 现在可以运行: python main.py")
        except Exception as e:
            print(f"\n❌ 下载失败: {e}")
            print("\n💡 备用方案:")
            print("1. 手动下载: https://huggingface.co/smartywu/big-lama/resolve/main/big-lama.onnx")
            print("2. 重命名为: lama_model.onnx")
            print("3. 放在 python_backend 目录下")
    
    elif choice == "2":
        # 下载 PyTorch 模型
        try:
            download_file(MODEL_URLS["lama"], "big-lama.pt")
            print("\n✅ PyTorch 模型下载成功！")
            print("📍 模型位置: big-lama.pt")
            print("\n⚠️  需要转换为 ONNX 格式")
            print("🔧 运行转换脚本: python convert_to_onnx.py")
        except Exception as e:
            print(f"\n❌ 下载失败: {e}")
    
    else:
        print("❌ 无效选择")

if __name__ == "__main__":
    main()
