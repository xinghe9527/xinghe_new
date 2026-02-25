#!/bin/bash

echo "========================================"
echo "LaMa 水印去除服务启动脚本"
echo "========================================"
echo ""

# 检查模型是否存在
if [ ! -f "lama_model.onnx" ]; then
    echo "[警告] 未找到模型文件: lama_model.onnx"
    echo ""
    echo "请选择操作:"
    echo "1. 自动下载模型"
    echo "2. 手动下载后再启动"
    echo ""
    read -p "请输入选择 (1/2): " choice
    
    if [ "$choice" = "1" ]; then
        echo ""
        echo "[下载] 开始下载模型..."
        python3 download_model.py
        if [ $? -ne 0 ]; then
            echo "[错误] 下载失败"
            exit 1
        fi
    else
        echo ""
        echo "[提示] 请手动下载模型:"
        echo "1. 访问: https://huggingface.co/smartywu/big-lama/resolve/main/big-lama.onnx"
        echo "2. 下载后重命名为: lama_model.onnx"
        echo "3. 放在 python_backend 目录下"
        echo "4. 重新运行此脚本"
        exit 1
    fi
fi

echo ""
echo "[启动] 正在启动服务..."
echo "[地址] http://127.0.0.1:8000"
echo "[提示] 按 Ctrl+C 停止服务"
echo ""

python3 main.py
