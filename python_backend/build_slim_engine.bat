@echo off
REM ========================================
REM 极限瘦身版 Python 引擎打包脚本
REM ========================================

echo [1/5] 清理旧的打包文件（仅清理 PyInstaller 临时目录）...
REM 安全检查：确保在 python_backend 目录下
if not exist "main.py" (
    echo ❌ 错误：请在 python_backend 目录下运行此脚本！
    pause
    exit /b 1
)

REM 只删除 PyInstaller 生成的目录
if exist "dist" rmdir /s /q "dist"
if exist "build" rmdir /s /q "build"
if exist "*.spec~" del /f /q "*.spec~"

echo.
echo [2/5] 安装精简依赖（如果需要）...
pip install opencv-python-headless==4.10.0.84 --upgrade

echo.
echo [3/5] 使用 PyInstaller 打包引擎（极限瘦身模式）...
pyinstaller --clean watermark_engine.spec

if not exist dist\watermark_engine.exe (
    echo ❌ 打包失败！
    pause
    exit /b 1
)

echo.
echo [4/5] 检查打包结果...
dir dist\watermark_engine.exe

echo.
echo [5/5] 复制到 Flutter Debug 目录...
set "DEBUG_DIR=..\build\windows\x64\runner\Debug"
if not exist "%DEBUG_DIR%" (
    echo ⚠️ Debug 目录不存在，跳过复制
    echo 💡 请先运行: flutter run
) else (
    copy /Y "dist\watermark_engine.exe" "%DEBUG_DIR%\"
    copy /Y "lama_model.onnx" "%DEBUG_DIR%\"
    echo ✅ 已复制到 Debug 目录
)

echo.
echo ========================================
echo ✅ 打包完成！
echo ========================================
echo.
echo 📦 引擎位置: python_backend\dist\watermark_engine.exe
echo 📐 文件大小:
for %%A in ("dist\watermark_engine.exe") do echo    %%~zA 字节 (约 %%~zA / 1048576 MB)
echo.
echo ========================================
echo 📋 部署到 Release 版本的步骤
echo ========================================
echo.
echo 1️⃣ 先构建 Flutter Release 版本:
echo    cd ..
echo    flutter build windows --release
echo.
echo 2️⃣ 然后复制引擎和模型:
echo    cd python_backend
echo    copy /Y dist\watermark_engine.exe ..\build\windows\x64\runner\Release\
echo    copy /Y lama_model.onnx ..\build\windows\x64\runner\Release\
echo.
echo 💡 提示：这样可以避免 Flutter 构建目录被污染
echo.
pause
