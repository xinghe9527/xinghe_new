@echo off
echo ======================================
echo 测试 Release 版本
echo ======================================
echo.
echo 正在启动应用...
echo.

cd build\windows\x64\runner\Release
start xinghe_new.exe

echo.
echo 应用已启动！
echo 请检查应用是否正常运行。
echo.
pause
