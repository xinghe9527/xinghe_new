@echo off
echo ========================================
echo 水印去除功能 - 快速测试
echo ========================================
echo.

REM 检查 Python 是否安装
python --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未检测到 Python
    echo [提示] 请先安装 Python 3.8+
    pause
    exit /b 1
)

echo [检查] Python 版本:
python --version
echo.

REM 检查依赖是否安装
echo [检查] 检查依赖...
python -c "import fastapi, uvicorn, onnxruntime, cv2, numpy" 2>nul
if errorlevel 1 (
    echo [警告] 缺少依赖包
    echo [安装] 正在安装依赖...
    pip install -r requirements.txt
    if errorlevel 1 (
        echo [错误] 依赖安装失败
        pause
        exit /b 1
    )
)
echo [成功] 依赖已安装
echo.

REM 检查模型文件
if not exist "lama_model.onnx" (
    echo [警告] 找不到模型文件
    echo [下载] 正在下载模型...
    python download_model.py
    if errorlevel 1 (
        echo [错误] 模型下载失败
        pause
        exit /b 1
    )
)
echo [成功] 模型文件存在
echo.

REM 启动服务
echo ========================================
echo 🚀 启动后端服务
echo ========================================
echo.
echo [提示] 服务将在 http://127.0.0.1:8000 启动
echo [提示] 按 Ctrl+C 停止服务
echo [提示] 保持此窗口打开，然后运行 Flutter
echo.

python main.py
