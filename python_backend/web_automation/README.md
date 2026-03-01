# Web Automation - Python 脚本目录

## 📁 目录说明

这个目录包含所有用于网页自动化的 Python 脚本，通过 Playwright 实现对各大 AI 平台的自动化操作。

## 🎯 当前状态

### ✅ 已完成
- `hello_flutter.py` - Flutter 与 Python 通信测试脚本
- `vidu_demo.py` - Vidu 浏览器自动化测试
- `jimeng_demo.py` - 即梦浏览器自动化测试
- `init_login.py` - 登录脚手架（Cookie 持久化）✨

### 🚧 待开发
- `vidu_automation.py` - Vidu 完整自动化脚本
- `jimeng_automation.py` - 即梦完整自动化脚本
- `keling_automation.py` - 可灵完整自动化脚本
- `hailuo_automation.py` - 海螺完整自动化脚本

## 🔐 登录状态管理

### 初始化登录（首次使用必须执行）

```cmd
# Vidu 登录
python python_backend\web_automation\init_login.py vidu

# 即梦登录
python python_backend\web_automation\init_login.py jimeng

# 可灵登录
python python_backend\web_automation\init_login.py keling
```

详细说明请查看：[LOGIN_GUIDE.md](LOGIN_GUIDE.md)

## 🧪 测试步骤

### 1. 测试 Python 通信（命令行）

```cmd
# 不带参数
python python_backend\web_automation\hello_flutter.py

# 带参数
python python_backend\web_automation\hello_flutter.py "测试消息"
```

### 2. 测试 Playwright 浏览器自动化

```cmd
# 测试 Vidu
python python_backend\web_automation\vidu_demo.py

# 测试即梦
python python_backend\web_automation\jimeng_demo.py
```

### 3. 初始化登录状态

```cmd
# 运行登录脚手架
python python_backend\web_automation\init_login.py vidu

# 在弹出的浏览器中手动登录
# 登录成功后关闭浏览器
# 登录状态会自动保存
```

### 4. 测试 Flutter 调用（应用内）

1. 启动 Flutter 应用
2. 进入「设置」页面
3. 切换到「保存设置」标签
4. 滚动到底部，找到「🧪 开发测试区域」
5. 点击「打开 Python 通信测试页面」按钮
6. 在测试页面输入消息，点击「测试 Python 通信」
7. 查看弹窗显示的 Python 返回结果

## 📦 依赖安装

```cmd
# 安装 Playwright
pip install playwright

# 安装浏览器内核
playwright install chromium
```

或使用 requirements.txt：

```cmd
pip install -r python_backend/web_automation/requirements.txt
playwright install chromium
```

## 🔧 开发规范

### 脚本输出格式

所有 Python 脚本必须以 JSON 格式输出结果：

```python
import json
import sys

result = {
    "success": True,  # 或 False
    "message": "操作描述",
    "data": {},  # 可选：返回数据
    "error": ""  # 可选：错误信息
}

print(json.dumps(result, ensure_ascii=False, indent=2))
```

### 参数传递

通过命令行参数传递：

```python
import sys

# 获取参数
param1 = sys.argv[1] if len(sys.argv) > 1 else "默认值"
param2 = sys.argv[2] if len(sys.argv) > 2 else "默认值"
```

### 错误处理

所有异常必须捕获并以 JSON 格式返回：

```python
try:
    # 主逻辑
    result = {"success": True, "message": "成功"}
except Exception as e:
    result = {"success": False, "error": str(e)}
finally:
    print(json.dumps(result, ensure_ascii=False))
```

## 🚀 下一步计划

1. ✅ 完成 Flutter-Python 通信测试
2. 📝 编写 Playwright 自动化脚本模板
3. 🎨 实现即梦平台自动化
4. 🎬 实现可灵平台自动化
5. 📹 实现 Vidu 平台自动化
6. 🌊 实现海螺 AI 自动化

## 📝 注意事项

- 所有脚本必须处理 UTF-8 编码（Windows 兼容）
- 输出必须是有效的 JSON 格式
- 必须包含 `success` 字段用于判断执行状态
- 错误信息必须清晰易懂
