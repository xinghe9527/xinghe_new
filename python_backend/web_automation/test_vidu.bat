@echo off
chcp 65001 >nul
echo ========================================
echo   Vidu 文生视频自动化测试
echo ========================================
echo.
echo 目标网址: https://www.vidu.com/zh/create/text2video
echo.
python python_backend\web_automation\auto_vidu.py "一个赛博朋克风格的女孩，霓虹灯闪烁，未来都市背景"
echo.
echo ========================================
pause
