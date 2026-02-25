#!/bin/bash
# LaMa 水印去除引擎打包工具 (Linux/Mac)

echo "========================================"
echo "LaMa 水印去除引擎打包工具"
echo "========================================"
echo ""

# 检查 PyInstaller 是否安装
if ! python3 -c "import PyInstaller" 2>/dev/null; then
    echo "[安装] 正在安装 PyInstaller..."
    pip3 install pyinstaller
    if [ $? -ne 0 ]; then
        echo "[错误] PyInstaller 安装失败"
        exit 1
    fi
fi

echo "[清理] 删除旧的构建文件..."
rm -rf build dist watermark_engine

echo ""
echo "[打包] 开始打包引擎..."
echo "[提示] 这可能需要几分钟时间..."
echo ""

pyinstaller --clean watermark_engine.spec

if [ $? -ne 0 ]; then
    echo ""
    echo "[错误] 打包失败"
    exit 1
fi

echo ""
echo "[复制] 移动可执行文件到当前目录..."
if [ -f "dist/watermark_engine" ]; then
    mv "dist/watermark_engine" "watermark_engine"
    chmod +x watermark_engine
    echo "[成功] watermark_engine 已生成"
else
    echo "[错误] 找不到生成的可执行文件"
    exit 1
fi

echo ""
echo "[清理] 删除临时文件..."
rm -rf build dist

echo ""
echo "========================================"
echo "✅ 打包完成！"
echo "========================================"
echo ""
echo "📦 生成文件: watermark_engine"
echo "📐 文件大小: $(du -h watermark_engine | cut -f1)"

# ========================================
# 🚀 自动复制到 Flutter 构建目录
# ========================================
echo ""
echo "========================================"
echo "🚀 自动部署到 Flutter 项目"
echo "========================================"
echo ""

# 检查模型文件是否存在
if [ ! -f "lama_model.onnx" ]; then
    echo "[警告] 找不到 lama_model.onnx 模型文件"
    echo "[提示] 请先运行: python download_model.py"
    echo ""
fi

# 定义 Flutter 构建目录（根据平台调整）
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    FLUTTER_DEBUG="../build/macos/Build/Products/Debug"
    FLUTTER_RELEASE="../build/macos/Build/Products/Release"
else
    # Linux
    FLUTTER_DEBUG="../build/linux/x64/debug/bundle"
    FLUTTER_RELEASE="../build/linux/x64/release/bundle"
fi

# 复制到 Debug 目录
if [ -d "$FLUTTER_DEBUG" ]; then
    echo "[复制] 部署到 Debug 目录..."
    cp -f "watermark_engine" "$FLUTTER_DEBUG/watermark_engine"
    if [ -f "lama_model.onnx" ]; then
        cp -f "lama_model.onnx" "$FLUTTER_DEBUG/lama_model.onnx"
        echo "[成功] ✅ Debug 目录部署完成"
    else
        echo "[警告] ⚠️ Debug 目录已复制引擎，但缺少模型文件"
    fi
else
    echo "[跳过] Debug 目录不存在（需要先运行 flutter run）"
fi

echo ""

# 复制到 Release 目录
if [ -d "$FLUTTER_RELEASE" ]; then
    echo "[复制] 部署到 Release 目录..."
    cp -f "watermark_engine" "$FLUTTER_RELEASE/watermark_engine"
    if [ -f "lama_model.onnx" ]; then
        cp -f "lama_model.onnx" "$FLUTTER_RELEASE/lama_model.onnx"
        echo "[成功] ✅ Release 目录部署完成"
    else
        echo "[警告] ⚠️ Release 目录已复制引擎，但缺少模型文件"
    fi
else
    echo "[跳过] Release 目录不存在（需要先运行 flutter build）"
fi

echo ""
echo "========================================"
echo "📋 使用说明"
echo "========================================"
echo ""
echo "开发调试:"
echo "  1. 运行 flutter run"
echo "  2. 引擎会自动从 Debug 目录启动"
echo ""
echo "生产发布:"
echo "  1. 运行 flutter build (linux/macos)"
echo "  2. 引擎和模型已自动复制到 Release 目录"
echo ""
echo "手动测试引擎:"
echo "  ./watermark_engine"
echo "  访问 http://127.0.0.1:8000 查看状态"
echo ""
echo "💡 提示: 如果 Debug/Release 目录不存在，请先运行一次 Flutter"
echo ""

