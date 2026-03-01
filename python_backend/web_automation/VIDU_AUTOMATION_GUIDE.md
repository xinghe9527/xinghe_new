# 🎬 Vidu 自动化脚本使用指南

## 📋 功能说明

`auto_vidu.py` 是 Vidu 平台的自动化视频生成脚本，可以自动填充提示词并点击生成按钮。

### 核心特性

- ✅ **免登录**：使用持久化登录状态，无需重复登录
- ✅ **自动填充**：自动定位输入框并填充提示词
- ✅ **自动点击**：自动查找并点击生成按钮
- ✅ **智能定位**：支持多种选择器，适应页面变化
- ✅ **截图记录**：保存生成时的页面状态
- ✅ **完美输出**：JSON 格式输出，中文无乱码

## 🚀 使用方法

### 前置条件

1. **已完成登录初始化**
   ```cmd
   python python_backend\web_automation\init_login.py vidu
   ```

2. **确认登录状态存在**
   - 检查目录：`python_backend/user_data/vidu_profile/`
   - 应该包含浏览器数据文件

### 基础用法

```cmd
python python_backend\web_automation\auto_vidu.py "你的提示词"
```

### 示例

```cmd
# 示例1：简单提示词
python python_backend\web_automation\auto_vidu.py "一个赛博朋克风格的女孩"

# 示例2：详细提示词
python python_backend\web_automation\auto_vidu.py "一个赛博朋克风格的女孩，霓虹灯闪烁，未来都市背景，电影级画质"

# 示例3：中文提示词
python python_backend\web_automation\auto_vidu.py "古风美女，水墨画风格，飘逸长发"

# 示例4：英文提示词
python python_backend\web_automation\auto_vidu.py "A cyberpunk girl with neon lights"
```

### 快捷测试

双击运行 `test_vidu.bat` 进行快速测试。

## 📝 执行流程

### 1. 启动浏览器
```
✅ 使用持久化上下文
✅ 自动加载登录状态
✅ 显示浏览器窗口（headless=False）
```

### 2. 访问 Vidu 官网
```
✅ 打开 https://www.vidu.studio/
✅ 等待页面加载（5秒）
✅ 此时应该是已登录状态
```

### 3. 填充提示词
```
✅ 智能定位输入框（支持多种选择器）
✅ 清空现有内容
✅ 填充新的提示词
```

### 4. 点击生成
```
✅ 智能定位生成按钮
✅ 自动点击
✅ 等待响应
```

### 5. 保存状态
```
✅ 等待 3 秒
✅ 截图保存（generating.png）
✅ 关闭浏览器
```

### 6. 输出结果
```json
{
  "success": true,
  "message": "✅ Vidu 视频生成任务已提交！",
  "prompt": "一个赛博朋克风格的女孩",
  "details": {
    "平台": "Vidu",
    "提示词": "一个赛博朋克风格的女孩",
    "状态": "已点击生成按钮",
    "截图": "python_backend/web_automation/generating.png"
  }
}
```

## 🎯 智能定位机制

### 输入框定位

脚本会依次尝试以下选择器：

```python
textarea[placeholder*="prompt"]
textarea[placeholder*="Prompt"]
textarea[placeholder*="描述"]
textarea[placeholder*="输入"]
textarea
input[type="text"][placeholder*="prompt"]
input[type="text"]
.prompt-input
#prompt
[data-testid="prompt-input"]
```

### 按钮定位

脚本会依次尝试以下选择器：

```python
button:has-text("生成")
button:has-text("Generate")
button:has-text("创建")
button:has-text("Create")
button[type="submit"]
.generate-button
#generate
[data-testid="generate-button"]
```

## 📸 生成的文件

- `generating.png` - 点击生成后的页面截图
- `debug_page.png` - 出错时的调试截图（仅在失败时生成）

## 🐛 常见问题

### Q1: 提示"未找到登录状态"

**原因**：没有运行登录脚手架

**解决**：
```cmd
python python_backend\web_automation\init_login.py vidu
```

### Q2: 提示"未找到提示词输入框"

**原因**：Vidu 页面结构可能变化

**解决**：
1. 查看生成的 `debug_page.png` 截图
2. 手动访问 Vidu 官网，检查输入框的实际选择器
3. 在脚本中添加新的选择器

### Q3: 提示"未找到生成按钮"

**原因**：按钮选择器不匹配

**解决**：
1. 查看 `debug_page.png` 截图
2. 使用浏览器开发者工具检查按钮元素
3. 更新脚本中的按钮选择器

### Q4: 浏览器打开后显示未登录

**原因**：登录状态过期或 Cookie 失效

**解决**：
```cmd
# 重新登录
python python_backend\web_automation\init_login.py vidu
```

### Q5: 脚本执行成功但视频没有生成

**可能原因**：
- 账号余额不足
- 提示词违规
- Vidu 服务器繁忙

**解决**：
- 手动访问 Vidu 官网查看具体原因
- 检查账号状态

## 🔧 高级用法

### 自定义等待时间

修改脚本中的 `time.sleep()` 值：

```python
# 页面加载等待（默认 5 秒）
time.sleep(5)

# 生成后等待（默认 3 秒）
time.sleep(3)
```

### 后台运行（Headless）

修改脚本中的 `headless` 参数：

```python
context = p.chromium.launch_persistent_context(
    user_data_dir=USER_DATA_DIR,
    headless=True,  # 改为 True
    ...
)
```

### 添加自定义选择器

如果页面结构变化，可以添加新的选择器：

```python
input_selectors = [
    'textarea[placeholder*="prompt"]',
    'your-custom-selector',  # 添加你的选择器
    ...
]
```

## 🚀 与 Flutter 集成

### 在 Flutter 中调用

```dart
final service = WebAutomationService();
final result = await service._runPythonScript(
  scriptPath: 'python_backend/web_automation/auto_vidu.py',
  arguments: ['一个赛博朋克风格的女孩'],
);

if (result['success'] == true) {
  print('生成成功: ${result['message']}');
}
```

### 完整工作流

1. 用户在 Flutter 界面输入提示词
2. Flutter 调用 `auto_vidu.py` 并传递提示词
3. Python 脚本自动打开浏览器并生成
4. 返回 JSON 结果给 Flutter
5. Flutter 显示生成状态

## 📊 性能优化

### 减少等待时间

使用 Playwright 的智能等待：

```python
# 等待元素出现
page.wait_for_selector('textarea', timeout=10000)

# 等待网络空闲
page.wait_for_load_state('networkidle')
```

### 批量生成

循环调用脚本：

```cmd
for /L %%i in (1,1,5) do (
    python auto_vidu.py "提示词 %%i"
)
```

## 🎨 扩展功能

### 待实现功能

- [ ] 支持图片上传（图生视频）
- [ ] 支持模型选择
- [ ] 支持参数配置（时长、分辨率等）
- [ ] 监控生成进度
- [ ] 自动下载结果视频
- [ ] 批量生成队列

## 📝 注意事项

1. **登录状态有效期**
   - Cookie 通常 7-30 天有效
   - 过期后需要重新运行 `init_login.py`

2. **页面结构变化**
   - Vidu 可能更新页面结构
   - 需要相应更新选择器

3. **网络稳定性**
   - 确保网络连接稳定
   - 建议在网络良好时使用

4. **账号限制**
   - 注意 Vidu 的使用限制
   - 避免频繁调用导致账号异常

---

**祝你使用愉快！有问题随时查看此文档。** 🎉
