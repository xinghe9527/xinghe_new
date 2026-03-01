# 🚀 快速开始指南

## 📋 完整安装流程

### 步骤 1: 安装 Python 依赖

```bash
# 安装 API 服务器依赖
pip install -r python_backend/web_automation/requirements_api.txt

# 安装 Playwright 浏览器
playwright install chromium
```

### 步骤 2: 初始化登录状态

```bash
# 运行登录脚手架（首次使用必须）
python python_backend/web_automation/init_login.py vidu
```

在弹出的浏览器中手动登录 Vidu，登录成功后关闭浏览器。

### 步骤 3: 启动 API 服务器

**方法 A: 使用批处理脚本（推荐）**

```bash
# Windows 双击运行
python_backend/web_automation/start_api_server.bat
```

**方法 B: 直接运行 Python**

```bash
python python_backend/web_automation/api_server.py
```

### 步骤 4: 测试 API 接口

**方法 A: 使用测试脚本**

```bash
python python_backend/web_automation/test_api.py
```

**方法 B: 使用浏览器访问交互式文档**

打开浏览器访问：
```
http://127.0.0.1:8000/docs
```

**方法 C: 使用 cURL 命令**

```bash
# 提交任务
curl -X POST "http://127.0.0.1:8000/api/vidu/generate" \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": \"一个赛博朋克风格的女孩\"}"

# 查询任务状态（替换 task_id）
curl "http://127.0.0.1:8000/api/task/task_20260227_143025_123456"

# 显示浏览器
curl -X POST "http://127.0.0.1:8000/api/browser/show"

# 隐藏浏览器
curl -X POST "http://127.0.0.1:8000/api/browser/hide"
```

---

## 🎯 核心工作流程

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  1. Flutter 应用发送 HTTP 请求                          │
│     POST /api/vidu/generate                             │
│     { "prompt": "..." }                                 │
│                                                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  2. API 服务器立即返回任务 ID                            │
│     { "task_id": "task_xxx", "status": "pending" }      │
│                                                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  3. 后台异步执行 auto_vidu.py                            │
│     • 打开浏览器（携带登录状态）                         │
│     • 填充提示词                                         │
│     • 点击生成按钮                                       │
│     • 等待 30 秒观影                                     │
│                                                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  4. Flutter 轮询查询任务状态                             │
│     GET /api/task/{task_id}                             │
│     { "status": "running" / "success" / "failed" }      │
│                                                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  5. 用户可随时控制浏览器窗口                             │
│     POST /api/browser/show  - 显示浏览器                │
│     POST /api/browser/hide  - 隐藏浏览器                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 文件结构总览

```
python_backend/web_automation/
├── api_server.py              # ✅ FastAPI 服务器（新增）
├── auto_vidu.py               # ✅ Vidu 自动化核心
├── init_login.py              # ✅ 登录脚手架
├── hello_flutter.py           # Flutter 通信测试
├── test_api.py                # ✅ API 测试脚本（新增）
├── start_api_server.bat       # ✅ 快速启动脚本（新增）
├── requirements.txt           # 基础依赖
├── requirements_api.txt       # ✅ API 服务器依赖（新增）
├── API_SERVER_GUIDE.md        # ✅ API 服务器详细文档（新增）
├── QUICK_START.md             # ✅ 快速开始指南（本文件）
└── ...（其他文档）
```

---

## 🔧 依赖清单

### 核心依赖
- `playwright` - 浏览器自动化
- `fastapi` - Web 框架
- `uvicorn` - ASGI 服务器
- `pydantic` - 数据验证
- `pygetwindow` - Windows 窗口控制

### 安装命令

```bash
pip install playwright fastapi uvicorn[standard] pydantic pygetwindow
playwright install chromium
```

---

## 🧪 验证安装

运行以下命令验证所有依赖已正确安装：

```bash
python -c "import playwright, fastapi, uvicorn, pygetwindow; print('✅ 所有依赖已安装')"
```

---

## 🎬 完整演示流程

### 1. 启动服务器

```bash
python python_backend/web_automation/api_server.py
```

看到以下输出说明启动成功：

```
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║          🚀 Vidu 自动化 API 服务器                        ║
║                                                          ║
║  本地地址: http://127.0.0.1:8000                         ║
║  API 文档: http://127.0.0.1:8000/docs                    ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

### 2. 打开交互式文档

在浏览器中访问：
```
http://127.0.0.1:8000/docs
```

### 3. 测试提交任务

在 Swagger UI 中：
1. 找到 `POST /api/vidu/generate` 接口
2. 点击 "Try it out"
3. 输入提示词：
   ```json
   {
     "prompt": "一个赛博朋克风格的女孩"
   }
   ```
4. 点击 "Execute"
5. 记录返回的 `task_id`

### 4. 查询任务状态

1. 找到 `GET /api/task/{task_id}` 接口
2. 输入刚才的 `task_id`
3. 点击 "Execute"
4. 查看任务状态（pending → running → success）

### 5. 控制浏览器窗口

- 显示浏览器：`POST /api/browser/show`
- 隐藏浏览器：`POST /api/browser/hide`

---

## 🐛 常见问题

### Q1: 服务器启动失败

**A**: 检查端口是否被占用

```bash
# Windows
netstat -ano | findstr :8000

# 如果被占用，终止进程或修改端口
```

### Q2: 窗口控制不可用

**A**: 安装 pygetwindow

```bash
pip install pygetwindow
```

### Q3: 找不到浏览器窗口

**A**: 确保浏览器已启动（提交任务后浏览器会自动打开）

### Q4: 任务一直 pending

**A**: 检查 `auto_vidu.py` 路径是否正确，查看服务器日志

### Q5: 中文乱码

**A**: 确保终端编码为 UTF-8

```bash
# Windows CMD
chcp 65001
```

---

## 📊 性能指标

| 指标 | 数值 |
|------|------|
| 接口响应时间 | < 100ms |
| 任务提交延迟 | 立即返回 |
| 浏览器启动时间 | 3-5 秒 |
| 任务执行时间 | 30-60 秒 |
| 内存占用 | < 200MB |

---

## 🎉 下一步

现在你已经完成了 API 服务器的搭建，可以：

1. ✅ 在 Flutter 中集成 HTTP 客户端
2. ✅ 创建 UI 界面调用 API
3. ✅ 实现任务状态轮询
4. ✅ 添加浏览器窗口控制按钮
5. ✅ 扩展支持更多平台（即梦、可灵等）

参考 `API_SERVER_GUIDE.md` 获取更多详细信息！🚀
