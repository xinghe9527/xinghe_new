# 🚀 Vidu 自动化 API 服务器使用指南

## 📋 概述

`api_server.py` 是一个基于 FastAPI 的本地微服务，提供 HTTP 接口供 Flutter 调用 Vidu 自动化功能。

### 核心特性

- ✅ **异步任务处理**：接口立即返回，后台执行，不阻塞
- ✅ **浏览器窗口控制**：显示/隐藏浏览器窗口
- ✅ **任务状态查询**：实时查询任务执行状态
- ✅ **长时间运行**：作为后台服务持续监听请求
- ✅ **跨域支持**：允许 Flutter 跨域访问
- ✅ **完整日志**：详细的执行日志输出

---

## 🔧 安装依赖

### 方法 1：使用 requirements_api.txt（推荐）

```bash
pip install -r python_backend/web_automation/requirements_api.txt
```

### 方法 2：手动安装

```bash
pip install fastapi uvicorn[standard] pydantic pygetwindow playwright
```

### 验证安装

```bash
python -c "import fastapi, uvicorn, pygetwindow; print('✅ 所有依赖已安装')"
```

---

## 🚀 启动服务

### 方法 1：直接运行脚本

```bash
python python_backend/web_automation/api_server.py
```

### 方法 2：使用 Uvicorn 命令

```bash
cd python_backend/web_automation
uvicorn api_server:app --host 127.0.0.1 --port 8000 --reload
```

### 启动成功标志

看到以下横幅说明服务已启动：

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

---

## 📡 API 接口文档

### 1. 提交视频生成任务

**接口**: `POST /api/vidu/generate`

**功能**: 提交视频生成任务，立即返回任务 ID，后台异步执行

**请求体**:
```json
{
  "prompt": "一个赛博朋克风格的女孩",
  "platform": "vidu"
}
```

**响应**:
```json
{
  "task_id": "task_20260227_143025_123456",
  "status": "pending",
  "message": "任务已受理，正在后台执行",
  "created_at": "2026-02-27T14:30:25.123456",
  "prompt": "一个赛博朋克风格的女孩"
}
```

**cURL 测试**:
```bash
curl -X POST "http://127.0.0.1:8000/api/vidu/generate" \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": \"一个赛博朋克风格的女孩\"}"
```

---

### 2. 查询任务状态

**接口**: `GET /api/task/{task_id}`

**功能**: 查询指定任务的执行状态

**响应**:
```json
{
  "task_id": "task_20260227_143025_123456",
  "status": "success",
  "message": "任务执行成功",
  "created_at": "2026-02-27T14:30:25.123456",
  "updated_at": "2026-02-27T14:31:10.789012",
  "prompt": "一个赛博朋克风格的女孩",
  "result": {
    "success": true,
    "message": "✅ Vidu 视频生成任务已提交！",
    "details": { ... }
  },
  "error": null
}
```

**任务状态枚举**:
- `pending`: 等待执行
- `running`: 执行中
- `success`: 成功
- `failed`: 失败
- `cancelled`: 已取消

**cURL 测试**:
```bash
curl "http://127.0.0.1:8000/api/task/task_20260227_143025_123456"
```

---

### 3. 获取所有任务

**接口**: `GET /api/tasks`

**功能**: 获取所有任务列表

**响应**:
```json
{
  "total": 3,
  "tasks": [
    { "task_id": "...", "status": "success", ... },
    { "task_id": "...", "status": "running", ... },
    { "task_id": "...", "status": "pending", ... }
  ]
}
```

**cURL 测试**:
```bash
curl "http://127.0.0.1:8000/api/tasks"
```

---

### 4. 显示浏览器窗口

**接口**: `POST /api/browser/show`

**功能**: 激活并置顶浏览器窗口

**响应**:
```json
{
  "success": true,
  "message": "浏览器窗口已显示: Vidu - Chrome",
  "window_found": true
}
```

**cURL 测试**:
```bash
curl -X POST "http://127.0.0.1:8000/api/browser/show"
```

---

### 5. 隐藏浏览器窗口

**接口**: `POST /api/browser/hide`

**功能**: 最小化浏览器窗口

**响应**:
```json
{
  "success": true,
  "message": "浏览器窗口已最小化: Vidu - Chrome",
  "window_found": true
}
```

**cURL 测试**:
```bash
curl -X POST "http://127.0.0.1:8000/api/browser/hide"
```

---

### 6. 取消任务

**接口**: `DELETE /api/task/{task_id}`

**功能**: 取消正在运行的任务

**响应**:
```json
{
  "message": "任务已取消: task_20260227_143025_123456"
}
```

**cURL 测试**:
```bash
curl -X DELETE "http://127.0.0.1:8000/api/task/task_20260227_143025_123456"
```

---

### 7. 健康检查

**接口**: `GET /health`

**功能**: 检查服务健康状态

**响应**:
```json
{
  "status": "healthy",
  "timestamp": "2026-02-27T14:30:25.123456",
  "window_control": true
}
```

---

## 🧪 完整测试流程

### 1. 启动服务

```bash
python python_backend/web_automation/api_server.py
```

### 2. 提交任务

```bash
curl -X POST "http://127.0.0.1:8000/api/vidu/generate" \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": \"一个赛博朋克风格的女孩\"}"
```

**记录返回的 `task_id`**

### 3. 查询任务状态

```bash
curl "http://127.0.0.1:8000/api/task/task_20260227_143025_123456"
```

### 4. 显示浏览器

```bash
curl -X POST "http://127.0.0.1:8000/api/browser/show"
```

### 5. 隐藏浏览器

```bash
curl -X POST "http://127.0.0.1:8000/api/browser/hide"
```

---

## 🌐 交互式 API 文档

FastAPI 自动生成交互式 API 文档，可以在浏览器中直接测试接口：

### Swagger UI（推荐）
```
http://127.0.0.1:8000/docs
```

### ReDoc
```
http://127.0.0.1:8000/redoc
```

---

## 🔌 Flutter 集成示例

### 1. 添加 HTTP 依赖

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  http: ^1.1.0
```

### 2. 创建 API 服务类

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ViduApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';
  
  // 提交生成任务
  Future<Map<String, dynamic>> generateVideo(String prompt) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/vidu/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': prompt}),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('任务提交失败: ${response.statusCode}');
    }
  }
  
  // 查询任务状态
  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/task/$taskId'),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('查询失败: ${response.statusCode}');
    }
  }
  
  // 显示浏览器
  Future<Map<String, dynamic>> showBrowser() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/browser/show'),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('显示浏览器失败: ${response.statusCode}');
    }
  }
  
  // 隐藏浏览器
  Future<Map<String, dynamic>> hideBrowser() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/browser/hide'),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('隐藏浏览器失败: ${response.statusCode}');
    }
  }
}
```

### 3. 使用示例

```dart
final apiService = ViduApiService();

// 提交任务
final result = await apiService.generateVideo('一个赛博朋克风格的女孩');
final taskId = result['task_id'];

// 轮询查询状态
Timer.periodic(Duration(seconds: 2), (timer) async {
  final status = await apiService.getTaskStatus(taskId);
  
  if (status['status'] == 'success') {
    print('任务成功！');
    timer.cancel();
  } else if (status['status'] == 'failed') {
    print('任务失败: ${status['error']}');
    timer.cancel();
  }
});

// 显示浏览器
await apiService.showBrowser();
```

---

## ⚙️ 高级配置

### 修改端口

编辑 `api_server.py` 最后几行：

```python
uvicorn.run(
    app,
    host="127.0.0.1",
    port=8888,  # 修改为你想要的端口
    log_level="info",
)
```

### 允许外部访问

⚠️ **仅用于开发测试，生产环境不推荐**

```python
uvicorn.run(
    app,
    host="0.0.0.0",  # 允许外部访问
    port=8000,
    log_level="info",
)
```

### 启用热重载（开发模式）

```bash
uvicorn api_server:app --host 127.0.0.1 --port 8000 --reload
```

---

## 🐛 故障排除

### 问题 1: 窗口控制不可用

**症状**: 启动时显示 `窗口控制: ❌ 不可用`

**原因**: `pygetwindow` 未安装

**解决**:
```bash
pip install pygetwindow
```

### 问题 2: 端口被占用

**症状**: `Address already in use`

**解决**:
```bash
# Windows: 查找占用端口的进程
netstat -ano | findstr :8000

# 终止进程（替换 PID）
taskkill /PID <PID> /F

# 或者修改端口
```

### 问题 3: 找不到浏览器窗口

**症状**: `window_found: false`

**原因**: 浏览器窗口标题不匹配

**解决**: 修改 `find_browser_window()` 函数中的窗口标题匹配逻辑

### 问题 4: 任务一直 pending

**症状**: 任务状态一直是 `pending`

**原因**: 后台任务未启动

**解决**: 检查服务器日志，确认 `auto_vidu.py` 路径正确

---

## 📊 性能优化

### 1. 限制并发任务数

当前实现只支持单任务执行，如需并发，可以修改 `TaskManager` 类。

### 2. 任务队列

可以集成 Celery 或 RQ 实现更强大的任务队列。

### 3. 数据库持久化

当前任务存储在内存中，重启服务会丢失。可以集成 SQLite 或 PostgreSQL 持久化任务数据。

---

## 🔒 安全建议

1. **仅监听本地地址**: 默认 `127.0.0.1`，不对外暴露
2. **添加认证**: 生产环境建议添加 API Key 或 JWT 认证
3. **限流**: 使用 `slowapi` 限制请求频率
4. **HTTPS**: 如需外部访问，使用 HTTPS 加密

---

## 📝 日志说明

服务器会输出详细的执行日志：

```
✅ 任务已受理: task_20260227_143025_123456
📝 提示词: 一个赛博朋克风格的女孩

============================================================
  🚀 开始执行任务: task_20260227_143025_123456
  📝 提示词: 一个赛博朋克风格的女孩
============================================================

============================================================
  📊 任务执行完成: task_20260227_143025_123456
  退出码: 0
============================================================

✅ 任务成功: task_20260227_143025_123456
```

---

## 🎉 总结

`api_server.py` 提供了完整的本地微服务架构，实现了：

- ✅ 异步任务处理（不阻塞接口）
- ✅ 浏览器窗口控制（显示/隐藏）
- ✅ 任务状态管理（查询/取消）
- ✅ 跨域支持（Flutter 可直接调用）
- ✅ 交互式 API 文档（Swagger UI）
- ✅ 完整的错误处理和日志

现在你可以在 Flutter 中通过 HTTP 请求轻松调用 Vidu 自动化功能了！🚀
