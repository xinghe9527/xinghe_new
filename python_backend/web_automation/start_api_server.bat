@echo off
chcp 65001 >nul
echo.
echo ╔══════════════════════════════════════════════════════════╗
echo ║                                                          ║
echo ║          🚀 启动 Vidu 自动化 API 服务器                   ║
echo ║                                                          ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

cd /d "%~dp0"

echo 📋 检查依赖...
python -c "import fastapi, uvicorn, pygetwindow" 2>nul
if errorlevel 1 (
    echo.
    echo ❌ 缺少依赖，正在安装...
    pip install -r requirements_api.txt
    echo.
)

echo.
echo ✅ 依赖检查完成
echo.
echo 🚀 启动服务器...
echo.

python api_server.py

pause
