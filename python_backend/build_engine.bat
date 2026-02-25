@echo off
echo ========================================
echo LaMa 水印去除引擎打包工具
echo ========================================
echo.

REM 检查 PyInstaller 是否安装
python -c "import PyInstaller" 2>nul
if errorlevel 1 (
    echo [安装] 正在安装 PyInstaller...
    pip install pyinstaller
    if errorlevel 1 (
        echo [错误] PyInstaller 安装失败
        pause
        exit /b 1
    )
)

echo [清理] 删除旧的构建文件...
if exist "build" rmdir /s /q build
if exist "dist" rmdir /s /q dist
if exist "watermark_engine.exe" del /f /q watermark_engine.exe

echo.
echo [打包] 开始打包引擎...
echo [提示] 这可能需要几分钟时间...
echo.

pyinstaller --clean watermark_engine.spec

if errorlevel 1 (
    echo.
    echo [错误] 打包失败
    pause
    exit /b 1
)

echo.
echo [复制] 移动 EXE 到当前目录...
if exist "dist\watermark_engine.exe" (
    move /y "dist\watermark_engine.exe" "watermark_engine.exe"
    echo [成功] watermark_engine.exe 已生成
) else (
    echo [错误] 找不到生成的 EXE 文件
    pause
    exit /b 1
)

echo.
echo [清理] 删除临时文件...
rmdir /s /q build
rmdir /s /q dist

echo.
echo ========================================
echo ✅ 打包完成！
echo ========================================
echo.
echo 📦 生成文件: watermark_engine.exe
echo 📐 文件大小: 
for %%A in (watermark_engine.exe) do echo    %%~zA 字节

REM ========================================
REM 🚀 自动复制到 Flutter 构建目录
REM ========================================
echo.
echo ========================================
echo 🚀 自动部署到 Flutter 项目
echo ========================================
echo.

REM 检查模型文件是否存在
if not exist "lama_model.onnx" (
    echo [警告] 找不到 lama_model.onnx 模型文件
    echo [提示] 请先运行: python download_model.py
    echo.
)

REM 定义 Flutter 构建目录
set "FLUTTER_DEBUG=..\build\windows\x64\runner\Debug"
set "FLUTTER_RELEASE=..\build\windows\x64\runner\Release"

REM 复制到 Debug 目录
if exist "%FLUTTER_DEBUG%" (
    echo [复制] 部署到 Debug 目录...
    copy /y "watermark_engine.exe" "%FLUTTER_DEBUG%\watermark_engine.exe" >nul
    if exist "lama_model.onnx" (
        copy /y "lama_model.onnx" "%FLUTTER_DEBUG%\lama_model.onnx" >nul
        echo [成功] ✅ Debug 目录部署完成
    ) else (
        echo [警告] ⚠️ Debug 目录已复制 EXE，但缺少模型文件
    )
) else (
    echo [跳过] Debug 目录不存在（需要先运行 flutter run）
)

echo.

REM 复制到 Release 目录
if exist "%FLUTTER_RELEASE%" (
    echo [复制] 部署到 Release 目录...
    copy /y "watermark_engine.exe" "%FLUTTER_RELEASE%\watermark_engine.exe" >nul
    if exist "lama_model.onnx" (
        copy /y "lama_model.onnx" "%FLUTTER_RELEASE%\lama_model.onnx" >nul
        echo [成功] ✅ Release 目录部署完成
    ) else (
        echo [警告] ⚠️ Release 目录已复制 EXE，但缺少模型文件
    )
) else (
    echo [跳过] Release 目录不存在（需要先运行 flutter build windows）
)

echo.
echo ========================================
echo 📋 使用说明
echo ========================================
echo.
echo 开发调试:
echo   1. 运行 flutter run
echo   2. 引擎会自动从 Debug 目录启动
echo.
echo 生产发布:
echo   1. 运行 flutter build windows --release
echo   2. 引擎和模型已自动复制到 Release 目录
echo.
echo 手动测试引擎:
echo   双击 watermark_engine.exe 启动
echo   访问 http://127.0.0.1:8000 查看状态
echo.
echo 💡 提示: 如果 Debug/Release 目录不存在，请先运行一次 Flutter
echo.

pause
