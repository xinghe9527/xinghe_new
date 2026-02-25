@echo off
REM ========================================
REM 安全部署脚本 - 复制引擎到 Release 目录
REM ========================================

echo ========================================
echo 🚀 部署 Python 引擎到 Flutter Release
echo ========================================
echo.

REM 安全检查：确保在 python_backend 目录下
if not exist "main.py" (
    echo ❌ 错误：请在 python_backend 目录下运行此脚本！
    pause
    exit /b 1
)

REM 检查引擎是否存在
if not exist "dist\watermark_engine.exe" (
    echo ❌ 错误：找不到 watermark_engine.exe
    echo 💡 请先运行: build_slim_engine.bat
    pause
    exit /b 1
)

REM 检查模型是否存在
if not exist "lama_model.onnx" (
    echo ❌ 错误：找不到 lama_model.onnx
    echo 💡 请先运行: python setup_lama.py
    pause
    exit /b 1
)

REM 定义 Release 目录
set "RELEASE_DIR=..\build\windows\x64\runner\Release"

REM 检查 Release 目录是否存在
if not exist "%RELEASE_DIR%" (
    echo ❌ 错误：Release 目录不存在
    echo.
    echo 💡 请先构建 Flutter Release 版本:
    echo    cd ..
    echo    flutter build windows --release
    echo    cd python_backend
    pause
    exit /b 1
)

echo [1/2] 复制引擎到 Release 目录...
copy /Y "dist\watermark_engine.exe" "%RELEASE_DIR%\"
if errorlevel 1 (
    echo ❌ 复制引擎失败
    pause
    exit /b 1
)

echo [2/2] 复制模型到 Release 目录...
copy /Y "lama_model.onnx" "%RELEASE_DIR%\"
if errorlevel 1 (
    echo ❌ 复制模型失败
    pause
    exit /b 1
)

echo.
echo ========================================
echo ✅ 部署成功！
echo ========================================
echo.
echo 📂 Release 目录内容:
dir "%RELEASE_DIR%\watermark_engine.exe" "%RELEASE_DIR%\lama_model.onnx"
echo.
echo 💡 现在可以运行 Release 版本:
echo    cd ..
echo    .\build\windows\x64\runner\Release\xinghe_new.exe
echo.
pause
