"""
LaMa 水印去除服务 - FastAPI + ONNX Runtime
"""
from fastapi import FastAPI, File, UploadFile, Form
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
import numpy as np
import cv2
import onnxruntime as ort
from PIL import Image
import io
import base64
import logging

import os
import sys

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="LaMa Watermark Remover")

# 允许跨域（Flutter 桌面应用需要）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 全局变量：ONNX 模型会话
ort_session = None

# 获取可执行文件所在目录（支持 PyInstaller 打包）
if getattr(sys, 'frozen', False):
    # 如果是打包后的 EXE
    BASE_DIR = os.path.dirname(sys.executable)
else:
    # 如果是开发环境
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

MODEL_PATH = os.path.join(BASE_DIR, "lama_model.onnx")  # 模型在 EXE 同级目录


def load_model():
    """加载 LaMa ONNX 模型"""
    global ort_session
    try:
        # 优先使用 GPU
        providers = ['CUDAExecutionProvider', 'CPUExecutionProvider']
        ort_session = ort.InferenceSession(MODEL_PATH, providers=providers)
        logger.info(f"✅ LaMa 模型加载成功: {MODEL_PATH}")
        logger.info(f"🔧 使用设备: {ort_session.get_providers()}")
    except Exception as e:
        logger.error(f"❌ 模型加载失败: {e}")
        logger.info("💡 请确保 lama_model.onnx 文件存在")


@app.on_event("startup")
async def startup_event():
    """应用启动时加载模型"""
    load_model()


@app.get("/")
async def root():
    """健康检查"""
    return {
        "status": "running",
        "model_loaded": ort_session is not None,
        "device": ort_session.get_providers() if ort_session else None
    }


@app.post("/remove_watermark")
async def remove_watermark(
    image: UploadFile = File(...),
    mask: UploadFile = File(...)
):
    """
    去除水印接口
    
    参数:
        image: 原始图片文件
        mask: 遮罩图片文件（白色=需要修复的区域，黑色=保留区域）
    
    返回:
        处理后的图片（PNG 格式）
    """
    if ort_session is None:
        return {"error": "模型未加载"}
    
    try:
        logger.info("📥 接收到去水印请求")
        
        # 1. 读取图片
        image_bytes = await image.read()
        mask_bytes = await mask.read()
        
        # 2. 解码图片
        image_np = np.frombuffer(image_bytes, np.uint8)
        mask_np = np.frombuffer(mask_bytes, np.uint8)
        
        img = cv2.imdecode(image_np, cv2.IMREAD_COLOR)
        mask_img = cv2.imdecode(mask_np, cv2.IMREAD_GRAYSCALE)
        
        logger.info(f"📐 图片尺寸: {img.shape}, 遮罩尺寸: {mask_img.shape}")
        
        # 3. 预处理
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img_normalized = img_rgb.astype(np.float32) / 255.0
        mask_normalized = mask_img.astype(np.float32) / 255.0
        
        # 调整维度: (H, W, C) -> (1, C, H, W)
        img_input = np.transpose(img_normalized, (2, 0, 1))
        img_input = np.expand_dims(img_input, axis=0)
        
        mask_input = np.expand_dims(mask_normalized, axis=0)
        mask_input = np.expand_dims(mask_input, axis=0)
        
        logger.info(f"🔄 输入形状: image={img_input.shape}, mask={mask_input.shape}")
        
        # 4. ONNX 推理
        logger.info("🚀 开始 LaMa 推理...")
        input_name_img = ort_session.get_inputs()[0].name
        input_name_mask = ort_session.get_inputs()[1].name
        output_name = ort_session.get_outputs()[0].name
        
        result = ort_session.run(
            [output_name],
            {input_name_img: img_input, input_name_mask: mask_input}
        )[0]
        
        logger.info("✅ 推理完成")
        
        # 5. 后处理
        result = np.squeeze(result, axis=0)  # (1, C, H, W) -> (C, H, W)
        result = np.transpose(result, (1, 2, 0))  # (C, H, W) -> (H, W, C)
        result = (result * 255).clip(0, 255).astype(np.uint8)
        result_bgr = cv2.cvtColor(result, cv2.COLOR_RGB2BGR)
        
        # 6. 编码为 PNG
        _, encoded = cv2.imencode('.png', result_bgr)
        
        logger.info("📤 返回处理结果")
        
        return Response(
            content=encoded.tobytes(),
            media_type="image/png"
        )
        
    except Exception as e:
        logger.error(f"❌ 处理失败: {e}")
        import traceback
        traceback.print_exc()
        return {"error": str(e)}


@app.post("/remove_watermark_base64")
async def remove_watermark_base64(
    image_base64: str = Form(...),
    mask_base64: str = Form(...)
):
    """
    去除水印接口（Base64 版本）
    
    参数:
        image_base64: 原始图片的 base64 字符串
        mask_base64: 遮罩图片的 base64 字符串
    
    返回:
        处理后的图片 base64 字符串
    """
    if ort_session is None:
        return {"error": "模型未加载"}
    
    try:
        logger.info("📥 接收到去水印请求 (Base64)")
        
        # 1. 解码 Base64
        image_bytes = base64.b64decode(image_base64)
        mask_bytes = base64.b64decode(mask_base64)
        
        # 2. 解码图片
        image_np = np.frombuffer(image_bytes, np.uint8)
        mask_np = np.frombuffer(mask_bytes, np.uint8)
        
        img = cv2.imdecode(image_np, cv2.IMREAD_COLOR)
        mask_img = cv2.imdecode(mask_np, cv2.IMREAD_GRAYSCALE)
        
        logger.info(f"📐 图片尺寸: {img.shape}, 遮罩尺寸: {mask_img.shape}")
        
        # 3. 预处理
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img_normalized = img_rgb.astype(np.float32) / 255.0
        mask_normalized = mask_img.astype(np.float32) / 255.0
        
        img_input = np.transpose(img_normalized, (2, 0, 1))
        img_input = np.expand_dims(img_input, axis=0)
        
        mask_input = np.expand_dims(mask_normalized, axis=0)
        mask_input = np.expand_dims(mask_input, axis=0)
        
        # 4. ONNX 推理
        logger.info("🚀 开始 LaMa 推理...")
        input_name_img = ort_session.get_inputs()[0].name
        input_name_mask = ort_session.get_inputs()[1].name
        output_name = ort_session.get_outputs()[0].name
        
        result = ort_session.run(
            [output_name],
            {input_name_img: img_input, input_name_mask: mask_input}
        )[0]
        
        logger.info("✅ 推理完成")
        
        # 5. 后处理
        result = np.squeeze(result, axis=0)
        result = np.transpose(result, (1, 2, 0))
        result = (result * 255).clip(0, 255).astype(np.uint8)
        result_bgr = cv2.cvtColor(result, cv2.COLOR_RGB2BGR)
        
        # 6. 编码为 Base64
        _, encoded = cv2.imencode('.png', result_bgr)
        result_base64 = base64.b64encode(encoded.tobytes()).decode('utf-8')
        
        logger.info("📤 返回处理结果 (Base64)")
        
        return {
            "success": True,
            "result": result_base64
        }
        
    except Exception as e:
        logger.error(f"❌ 处理失败: {e}")
        import traceback
        traceback.print_exc()
        return {"error": str(e)}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
