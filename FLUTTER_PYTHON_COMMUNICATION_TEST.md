# Flutter-Python 通信测试指南

## 🎯 测试目标

验证 Flutter 应用能够成功调用 Python 脚本并获取返回结果，为后续的网页自动化功能打下基础。

## 📦 新增文件清单

### Python 端
```
python_backend/web_automation/
├── hello_flutter.py          # 测试脚本
├── requirements.txt           # 依赖文件（当前为空）
└── README.md                  # 说明文档
```

### Flutter 端
```
lib/
├── services/
│   └── web_automation_service.dart    # Python 调用服务（新增）
└── pages/
    └── web_automation_test_page.dart  # 测试页面（新增）

lib/features/home/presentation/
└── settings_page.dart                 # 设置页面（仅添加测试按钮）
```

## 🧪 测试步骤

### 第一步：命令行测试 Python 脚本

打开终端（CMD），执行以下命令：

```cmd
python python_backend\web_automation\hello_flutter.py "星河前端发来的测试指令"
```

**预期输出：**
```json
{
  "success": true,
  "message": "Hello from Python! 你好，Flutter！",
  "received_param": "星河前端发来的测试指令",
  "test_chinese": "中文测试：星河AI创作工具",
  "emoji_test": "🎨✨🚀"
}
```

✅ **检查点：**
- JSON 格式正确
- 中文没有乱码
- Emoji 正常显示
- `received_param` 正确接收了参数

---

### 第二步：Flutter 应用内测试

1. **启动 Flutter 应用**
   ```cmd
   flutter run
   ```

2. **进入设置页面**
   - 点击主界面的「设置」按钮

3. **找到测试区域**
   - 切换到「保存设置」标签
   - 滚动到页面最底部
   - 找到橙色的「🧪 开发测试区域」

4. **打开测试页面**
   - 点击「打开 Python 通信测试页面」按钮

5. **执行测试**
   - 在输入框中输入测试消息（默认：「星河前端发来的测试指令」）
   - 点击「测试 Python 通信」按钮
   - 等待执行（通常 1-2 秒）

6. **查看结果**
   - 应该弹出一个对话框，显示 Python 返回的消息
   - 页面下方的「执行结果」区域会显示完整的 JSON 响应

✅ **检查点：**
- 按钮点击后有加载状态
- 成功弹出对话框
- 对话框中显示中文消息
- 执行结果区域显示完整 JSON
- 没有任何错误提示

---

## 🎉 测试成功标志

如果你看到以下内容，说明通信桥梁已经成功搭建：

1. ✅ 命令行能正确执行 Python 脚本
2. ✅ Flutter 能成功调用 Python 脚本
3. ✅ Flutter 能正确解析 JSON 返回值
4. ✅ 中文和 Emoji 显示正常
5. ✅ 参数传递正确

## 🚀 下一步

测试通过后，我们可以开始：

1. **安装 Playwright**
   ```cmd
   pip install playwright
   playwright install chromium
   ```

2. **编写真实的自动化脚本**
   - `jimeng.py` - 即梦平台自动化
   - `keling.py` - 可灵平台自动化
   - `vidu.py` - Vidu 平台自动化

3. **在 Flutter 中集成网页服务商功能**
   - 创建网页服务商配置界面
   - 实现平台选择和模型选择
   - 集成到现有的生成工作流

## ❌ 常见问题

### 问题1：找不到 Python 命令

**解决方案：**
- 确保已安装 Python 3.7+
- 将 Python 添加到系统 PATH
- 或在 Flutter 中设置完整的 Python 路径：
  ```dart
  final service = WebAutomationService();
  service.setPythonPath('C:\\Python39\\python.exe');
  ```

### 问题2：中文乱码

**解决方案：**
- 脚本已经处理了 UTF-8 编码
- 如果仍有问题，检查终端编码设置：
  ```cmd
  chcp 65001
  ```

### 问题3：Flutter 调用超时

**解决方案：**
- 检查 Python 脚本路径是否正确
- 检查脚本是否有执行权限
- 查看 Flutter 控制台的详细错误信息

### 问题4：找不到测试按钮

**解决方案：**
- 确保在「设置」→「保存设置」标签
- 滚动到页面最底部
- 测试按钮在橙色背景的区域

## 📝 代码说明

### WebAutomationService 核心功能

```dart
// 调用 Python 脚本
final service = WebAutomationService();
final result = await service.testHelloFlutter("测试消息");

// 检查结果
if (result['success'] == true) {
  print(result['message']);  // Python 返回的消息
}
```

### Python 脚本核心逻辑

```python
# 接收参数
user_input = sys.argv[1] if len(sys.argv) > 1 else "未提供参数"

# 构建结果
result = {
    "success": True,
    "message": "Hello from Python!",
    "received_param": user_input
}

# 输出 JSON
print(json.dumps(result, ensure_ascii=False, indent=2))
```

## 🔒 安全性说明

- Python 脚本在本地执行，不涉及网络传输
- 所有参数通过命令行传递，不存储敏感信息
- 脚本输出仅包含测试数据，无隐私风险

## 🎨 UI 说明

测试按钮采用橙色主题，与正式功能区分：
- 橙色背景：表示这是临时测试功能
- 独立区域：不影响现有设置功能
- 清晰标注：「🧪 开发测试区域」

测试通过后，这个区域可以：
- 保留作为开发工具
- 删除以简化界面
- 改造为正式的网页服务商入口

---

## ✅ 测试完成确认

请在测试完成后确认以下内容：

- [ ] 命令行测试通过
- [ ] Flutter 应用内测试通过
- [ ] 中文显示正常
- [ ] JSON 解析正确
- [ ] 参数传递成功
- [ ] 无任何错误提示

**测试通过后，我们的通信桥梁正式合龙！🎉**

可以开始编写真正的 Playwright 自动化脚本了！
