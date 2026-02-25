"""
将 LaMa PyTorch 模型转换为 ONNX 格式
"""
import torch
import torch.onnx
import numpy as np
from pathlib import Path

def convert_lama_to_onnx():
    """转换 LaMa 模型为 ONNX"""
    print("=" * 60)
    print("LaMa PyTorch -> ONNX 转换工具")
    print("=" * 60)
    
    # 检查 PyTorch 模型是否存在
    pt_model_path = "big-lama.pt"
    if not Path(pt_model_path).exists():
        print(f"❌ 找不到 PyTorch 模型: {pt_model_path}")
        print("💡 请先运行: python download_model.py")
        return
    
    print(f"\n📂 加载 PyTorch 模型: {pt_model_path}")
    
    try:
        # 加载模型
        model = torch.jit.load(pt_model_path)
        model.eval()
        
        print("✅ 模型加载成功")
        
        # 创建示例输入
        print("\n🔧 准备转换...")
        dummy_image = torch.randn(1, 3, 512, 512)
        dummy_mask = torch.randn(1, 1, 512, 512)
        
        # 导出为 ONNX
        output_path = "lama_model.onnx"
        print(f"📤 导出 ONNX 模型: {output_path}")
        
        torch.onnx.export(
            model,
            (dummy_image, dummy_mask),
            output_path,
            export_params=True,
            opset_version=11,
            do_constant_folding=True,
            input_names=['image', 'mask'],
            output_names=['output'],
            dynamic_axes={
                'image': {0: 'batch_size', 2: 'height', 3: 'width'},
                'mask': {0: 'batch_size', 2: 'height', 3: 'width'},
                'output': {0: 'batch_size', 2: 'height', 3: 'width'}
            }
        )
        
        print(f"\n✅ 转换成功！")
        print(f"📍 ONNX 模型位置: {output_path}")
        print(f"📊 文件大小: {Path(output_path).stat().st_size / 1024 / 1024:.2f} MB")
        print("\n🚀 现在可以运行: python main.py")
        
    except Exception as e:
        print(f"\n❌ 转换失败: {e}")
        import traceback
        traceback.print_exc()
        print("\n💡 可能的原因:")
        print("1. PyTorch 版本不兼容")
        print("2. 模型文件损坏")
        print("3. 缺少依赖包")
        print("\n建议直接下载预转换的 ONNX 模型")

if __name__ == "__main__":
    convert_lama_to_onnx()
