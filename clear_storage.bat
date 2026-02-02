@echo off
echo ======================================
echo 清除本地 SecureStorage 配置
echo ======================================
echo.
echo 正在清除 Windows 凭据管理器中的数据...
echo.

REM 清除 Windows 凭据管理器中的相关凭据
cmdkey /list | findstr "xinghe" > nul
if %errorlevel% equ 0 (
    for /f "tokens=*" %%a in ('cmdkey /list ^| findstr "xinghe"') do (
        echo 发现凭据: %%a
        REM cmdkey /delete:%%a
    )
) else (
    echo 未找到 xinghe 相关凭据
)

echo.
echo 说明：SecureStorage 的数据存储在 Windows 凭据管理器中
echo 如果需要手动清除，请：
echo 1. Win + R → control keymgr.dll
echo 2. 找到包含 "xinghe" 的凭据
echo 3. 删除它们
echo.
pause
