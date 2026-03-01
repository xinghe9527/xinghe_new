# 🔧 端口配置说明

## 当前配置

**API 服务器端口**: `8123`

**访问地址**:
- 服务地址: `http://127.0.0.1:8123`
- API 文档: `http://127.0.0.1:8123/docs`
- ReDoc 文档: `http://127.0.0.1:8123/redoc`

---

## 为什么使用 8123 端口？

原计划使用 `8000` 端口，但该端口已被其他程序占用，导致启动失败：

```
[Errno 13] error while attempting to bind on address ('127.0.0.1', 8000)
```

为避免端口冲突，已将服务器端口修改为 `8123`。

---

## 已修改的文件

### 1. api_server.py

```python
# 修改前
uvicorn.run(app, host="127.0.0.1", port=8000)

# 修改后
uvicorn.run(app, host="127.0.0.1", port=8123)
```

### 2. test_api.py

```python
# 修改前
BASE_URL = "http://127.0.0.1:8000"

# 修改后
BASE_URL = "http://127.0.0.1:8123"
```

### 3. 启动横幅

```
修改前: http://127.0.0.1:8000
修改后: http://127.0.0.1:8123
```

---

## Flutter 集成时的端口配置

在 Flutter 代码中使用新端口：

```dart
class ViduApiService {
  // 修改前
  // static const String baseUrl = 'http://127.0.0.1:8000';
  
  // 修改后
  static const String baseUrl = 'http://127.0.0.1:8123';
  
  // ... 其他代码
}
```

---

## 如何修改端口

如果 `8123` 端口也被占用，可以按以下步骤修改：

### 步骤 1: 修改 api_server.py

找到文件末尾的 `uvicorn.run()` 调用：

```python
if __name__ == "__main__":
    print_startup_banner()
    
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=8123,  # 修改这里的端口号
        log_level="info",
    )
```

### 步骤 2: 修改 test_api.py

找到文件开头的 `BASE_URL` 定义：

```python
# API 基础地址
BASE_URL = "http://127.0.0.1:8123"  # 修改这里的端口号
```

### 步骤 3: 修改启动横幅

在 `api_server.py` 中找到 `print_startup_banner()` 函数：

```python
def print_startup_banner():
    banner = f"""
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║          🚀 Vidu 自动化 API 服务器                        ║
║                                                          ║
║  本地地址: http://127.0.0.1:8123                         ║  # 修改这里
║  API 文档: http://127.0.0.1:8123/docs                    ║  # 修改这里
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"""
    print(banner)
```

### 步骤 4: 修改 Flutter 代码

在 Flutter 的 API 服务类中修改 `baseUrl`：

```dart
static const String baseUrl = 'http://127.0.0.1:8123';  // 修改这里
```

---

## 检查端口占用

### Windows

```bash
# 查看端口占用
netstat -ano | findstr :8123

# 如果被占用，终止进程（替换 <PID>）
taskkill /PID <PID> /F
```

### 查找可用端口

常用的备选端口：
- `8123` ✅ 当前使用
- `8888`
- `9000`
- `5000`
- `3000`

---

## 测试新端口

### 方法 1: 使用测试脚本

```bash
python python_backend/web_automation/test_api.py
```

### 方法 2: 使用 cURL

```bash
# 健康检查
curl http://127.0.0.1:8123/health

# 提交任务
curl -X POST "http://127.0.0.1:8123/api/vidu/generate" \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": \"测试\"}"
```

### 方法 3: 浏览器访问

打开浏览器访问：
```
http://127.0.0.1:8123/docs
```

---

## 常见问题

### Q: 为什么不使用 8000 端口？

A: 8000 端口已被其他程序占用（可能是其他开发服务器、数据库管理工具等）。

### Q: 8123 端口有什么特殊含义吗？

A: 没有特殊含义，只是一个不常用的端口号，避免冲突。

### Q: 可以使用其他端口吗？

A: 可以！按照上面的步骤修改即可。建议使用 1024-65535 之间的端口。

### Q: 修改端口后需要重启服务器吗？

A: 是的，修改端口后需要重启 `api_server.py`。

---

## 快速参考

| 项目 | 旧值 | 新值 |
|------|------|------|
| 服务器端口 | 8000 | 8123 |
| 服务地址 | http://127.0.0.1:8000 | http://127.0.0.1:8123 |
| API 文档 | http://127.0.0.1:8000/docs | http://127.0.0.1:8123/docs |
| Flutter baseUrl | http://127.0.0.1:8000 | http://127.0.0.1:8123 |

---

**更新时间**: 2026-02-27  
**当前端口**: 8123  
**状态**: ✅ 已修改并测试通过
