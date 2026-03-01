@echo off
chcp 65001 >nul
echo ========================================
echo   Playwright 自动化测试
echo ========================================
echo.

echo [1/2] 测试 Vidu 官网...
python python_backend\web_automation\vidu_demo.py
echo.

echo ========================================
echo.
echo [2/2] 测试即梦官网...
python python_backend\web_automation\jimeng_demo.py
echo.

echo ========================================
echo 测试完成！
echo 请查看生成的截图：
echo - python_backend\web_automation\browser_test.png
echo - python_backend\web_automation\jimeng_test.png
echo ========================================
pause
