# ✅ 安装和使用清单

## 📋 安装步骤（按顺序执行）

### ☐ 步骤 1: 安装 Python 依赖

```bash
pip install -r python_backend/web_automation/requirements_api.txt
```

**验证**:
```bash
python -c "import fastapi, uvicorn, pygetwindow, playwright; print('✅ 依赖安装成功')"
```

---

### ☐ 步骤 2: 安装 Playwright 浏览器

```bash
playwright install chromium
```

**验证**:
```bash
playwright --version
```

---

### ☐ 步骤 3: 初始化 Vidu 登录状态

```bash
python python_backend/web_automation/init_login.py vidu
```

**操作**:
1. 浏览器会自动打开 Vidu 官网
2. 手动扫码登录
3. 登录成功后关闭浏览器
4. 看到 `✅ Vidu 登录状态已保存！` 说明成功

---

### ☐ 步骤 4: 启动 API 服务器

**方法 A: 使用批处理脚本（推荐）**

```bash
# Windows 双击运行
python_backend/web_automation/start_api_server.bat
```

**方法 B: 直接运行**

```bash
python python_backend/web_automation/api_server.py
```

**验证**: 看到以下横幅说明启动成功

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

### ☐ 步骤 5: 测试 API 接口

**方法 A: 使用测试脚本**

```bash
python python_backend/web_automation/test_api.py
```

**方法 B: 使用浏览器**

打开 `http://127.0.0.1:8000/docs`，在 Swagger UI 中测试接口

**方法 C: 使用 cURL**

```bash
curl -X POST "http://127.0.0.1:8000/api/vidu/generate" \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": \"一个赛博朋克风格的女孩\"}"
```

---

## 🎯 核心接口速查

### 1. 提交生成任务

```bash
POST http://127.0.0.1:8000/api/vidu/generate

Body:
{
  "prompt": "一个赛博朋克风格的女孩"
}

Response:
{
  "task_id": "task_20260227_143025_123456",
  "status": "pending",
  "message": "任务已受理，正在后台执行"
}
```

### 2. 查询任务状态

```bash
GET http://127.0.0.1:8000/api/task/{task_id}

Response:
{
  "task_id": "task_20260227_143025_123456",
  "status": "success",  # pending / running / success / failed
  "result": { ... }
}
```

### 3. 显示浏览器

```bash
POST http://127.0.0.1:8000/api/browser/show

Response:
{
  "success": true,
  "message": "浏览器窗口已显示"
}
```

### 4. 隐藏浏览器

```bash
POST http://127.0.0.1:8000/api/browser/hide

Response:
{
  "success": true,
  "message": "浏览器窗口已最小化"
}
```

---

## 📁 关键文件位置

| 文件 | 路径 | 说明 |
|------|------|------|
| API 服务器 | `python_backend/web_automation/api_server.py` | 主程序 |
| 核心自动化 | `python_backend/web_automation/auto_vidu.py` | Vidu 自动化 |
| 登录脚手架 | `python_backend/web_automation/init_login.py` | 初始化登录 |
| 测试脚本 | `python_backend/web_automation/test_api.py` | API 测试 |
| 快速启动 | `python_backend/web_automation/start_api_server.bat` | 启动脚本 |
| 依赖清单 | `python_backend/web_automation/requirements_api.txt` | 依赖列表 |
| 详细文档 | `python_backend/web_automation/API_SERVER_GUIDE.md` | 使用指南 |
| 快速开始 | `python_backend/web_automation/QUICK_START.md` | 快速指南 |

---

## 🔧 Flutter 集成清单

### ☐ 1. 添加 HTTP 依赖

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  http: ^1.1.0
```

### ☐ 2. 创建 API 服务类

创建 `lib/services/vidu_api_service.dart`：

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
      throw Exception('任务提交失败');
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
      throw Exception('查询失败');
    }
  }
  
  // 显示浏览器
  Future<void> showBrowser() async {
    await http.post(Uri.parse('$baseUrl/api/browser/show'));
  }
  
  // 隐藏浏览器
  Future<void> hideBrowser() async {
    await http.post(Uri.parse('$baseUrl/api/browser/hide'));
  }
}
```

### ☐ 3. 在 UI 中使用

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
    print('任务失败');
    timer.cancel();
  }
});

// 显示浏览器
await apiService.showBrowser();
```

---

## 🐛 故障排除清单

### ☐ 问题 1: 依赖安装失败

**症状**: `pip install` 报错

**解决**:
```bash
# 升级 pip
python -m pip install --upgrade pip

# 使用国内镜像
pip install -r requirements_api.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
```

---

### ☐ 问题 2: 端口被占用

**症状**: `Address already in use`

**解决**:
```bash
# Windows: 查找占用端口的进程
netstat -ano | findstr :8000

# 终止进程（替换 <PID>）
taskkill /PID <PID> /F
```

---

### ☐ 问题 3: 窗口控制不可用

**症状**: 启动时显示 `窗口控制: ❌ 不可用`

**解决**:
```bash
pip install pygetwindow
```

---

### ☐ 问题 4: 找不到浏览器窗口

**症状**: `window_found: false`

**解决**:
1. 确保已提交任务（浏览器会自动打开）
2. 检查浏览器窗口标题是否包含 "Vidu" 或 "Chrome"
3. 手动调整 `api_server.py` 中的窗口匹配逻辑

---

### ☐ 问题 5: 任务一直 pending

**症状**: 任务状态一直是 `pending`

**解决**:
1. 检查服务器日志，查看是否有错误
2. 确认 `auto_vidu.py` 路径正确
3. 确认已完成登录初始化（步骤 3）

---

### ☐ 问题 6: 中文乱码

**症状**: 日志或响应中文显示乱码

**解决**:
```bash
# Windows CMD
chcp 65001

# 或使用 PowerShell（默认 UTF-8）
```

---

## 📊 验证清单

完成以下所有项目说明安装成功：

- [ ] Python 依赖已安装（`pip list` 可以看到 fastapi, uvicorn, pygetwindow）
- [ ] Playwright 浏览器已安装（`playwright --version` 有输出）
- [ ] Vidu 登录状态已保存（`python_backend/user_data/vidu_profile/` 目录存在）
- [ ] API 服务器可以启动（看到启动横幅）
- [ ] 健康检查通过（访问 `http://127.0.0.1:8000/health` 返回 200）
- [ ] 可以提交任务（`POST /api/vidu/generate` 返回 task_id）
- [ ] 可以查询状态（`GET /api/task/{task_id}` 返回任务信息）
- [ ] 浏览器窗口控制可用（`POST /api/browser/show` 成功）
- [ ] Swagger UI 可访问（`http://127.0.0.1:8000/docs` 可以打开）

---

## 🎉 完成！

如果所有清单项都已完成，恭喜你！现在可以：

1. ✅ 在 Flutter 中集成 HTTP 客户端
2. ✅ 创建 UI 界面调用 API
3. ✅ 实现任务状态轮询
4. ✅ 添加浏览器窗口控制按钮
5. ✅ 扩展支持更多平台

参考文档：
- 详细指南：`API_SERVER_GUIDE.md`
- 快速开始：`QUICK_START.md`
- 实现总结：`API_IMPLEMENTATION_SUMMARY.md`

开始构建你的 Flutter 应用吧！🚀
