# 🔐 登录脚手架使用指南

## 📋 功能说明

`init_login.py` 是一个专用的登录脚手架，用于初始化各个平台的登录状态。

### 核心特性

- ✅ **持久化 Cookie**：使用 Playwright Persistent Context 自动保存登录状态
- ✅ **人工登录**：支持扫码、账号密码等任何登录方式
- ✅ **多平台支持**：Vidu、即梦、可灵、海螺等
- ✅ **独立存储**：每个平台的登录状态独立保存
- ✅ **自动检测**：监听浏览器关闭，自动保存状态

## 🚀 使用方法

### 方式一：命令行运行

```cmd
# Vidu 登录
python python_backend\web_automation\init_login.py vidu

# 即梦登录
python python_backend\web_automation\init_login.py jimeng

# 可灵登录
python python_backend\web_automation\init_login.py keling

# 海螺登录
python python_backend\web_automation\init_login.py hailuo
```

### 方式二：快捷脚本（推荐）

直接双击运行：
- `login_vidu.bat` - Vidu 登录
- `login_jimeng.bat` - 即梦登录
- `login_keling.bat` - 可灵登录

## 📝 操作步骤

### 1. 运行脚本

```cmd
python python_backend\web_automation\init_login.py vidu
```

### 2. 等待浏览器打开

脚本会自动打开浏览器并访问目标网站。

### 3. 手动登录

在弹出的浏览器中：
- 扫码登录
- 或使用账号密码登录
- 确认登录成功（能看到你的账号信息）

### 4. 关闭浏览器

登录成功后，直接关闭浏览器窗口即可。

### 5. 查看结果

脚本会自动保存登录状态并输出 JSON 结果：

```json
{
  "success": true,
  "message": "✅ Vidu 登录状态已保存！",
  "platform": "Vidu",
  "user_data_dir": "python_backend/user_data/vidu_profile",
  "next_step": "现在可以运行自动化脚本了！🚀"
}
```

## 📂 数据存储位置

登录状态保存在以下目录：

```
python_backend/user_data/
├── vidu_profile/       # Vidu 登录数据
├── jimeng_profile/     # 即梦登录数据
├── keling_profile/     # 可灵登录数据
└── hailuo_profile/     # 海螺登录数据
```

每个目录包含：
- Cookies
- Local Storage
- Session Storage
- IndexedDB
- 其他浏览器数据

## 🔄 重新登录

如果需要更换账号或重新登录：

1. **方式一：删除数据目录**
   ```cmd
   rmdir /s /q python_backend\user_data\vidu_profile
   ```

2. **方式二：直接重新运行脚本**
   ```cmd
   python python_backend\web_automation\init_login.py vidu
   ```
   脚本会覆盖旧的登录状态。

## 🎯 后续使用

登录状态保存后，自动化脚本会自动使用这些登录状态：

```python
# 自动化脚本示例
context = p.chromium.launch_persistent_context(
    user_data_dir='python_backend/user_data/vidu_profile',
    headless=True  # 后台运行
)
# 此时已经是登录状态，无需重新登录
```

## ⚠️ 注意事项

### 1. 安全性

- 登录数据保存在本地，不会上传
- 每个用户的登录状态独立
- 打包 EXE 时不会包含登录数据

### 2. 有效期

- Cookie 有效期取决于平台设置
- 通常为 7-30 天
- 过期后需要重新运行登录脚本

### 3. 多账号

如果需要支持多个账号：

```cmd
# 为不同账号创建不同的配置文件
python init_login.py vidu --profile account1
python init_login.py vidu --profile account2
```

（此功能待实现）

## 🐛 常见问题

### Q1: 浏览器打开后立即关闭

**原因**：可能是网络问题或网站无法访问

**解决**：
- 检查网络连接
- 手动访问目标网站确认可访问
- 查看脚本输出的错误信息

### Q2: 登录后状态没有保存

**原因**：可能是浏览器没有正常关闭

**解决**：
- 确保通过点击窗口关闭按钮关闭浏览器
- 不要使用 Ctrl+C 强制中断脚本
- 等待脚本输出"登录状态已保存"提示

### Q3: 自动化脚本仍然需要登录

**原因**：可能使用了错误的 user_data_dir

**解决**：
- 确认自动化脚本使用的路径与登录脚本一致
- 检查 user_data 目录是否存在且有内容

### Q4: 多个平台可以同时登录吗？

**可以**！每个平台的登录状态独立存储，互不影响。

## 📊 支持的平台

| 平台 | 命令参数 | 官网地址 | 状态 |
|------|---------|---------|------|
| Vidu | `vidu` | https://www.vidu.studio/ | ✅ 支持 |
| 即梦 | `jimeng` | https://jimeng.jianying.com/ | ✅ 支持 |
| 可灵 | `keling` | https://klingai.com/ | ✅ 支持 |
| 海螺 | `hailuo` | https://hailuoai.com/ | ✅ 支持 |

## 🚀 下一步

登录状态保存后，可以开始编写真正的自动化脚本：

1. **自动填充提示词**
2. **自动上传图片**
3. **自动选择模型**
4. **自动点击生成**
5. **监控生成进度**
6. **自动下载结果**

---

## 💡 技术细节

### Persistent Context vs Regular Context

**Regular Context（普通上下文）**：
```python
browser = p.chromium.launch()
context = browser.new_context()
# 关闭后 Cookie 丢失
```

**Persistent Context（持久化上下文）**：
```python
context = p.chromium.launch_persistent_context(
    user_data_dir='path/to/profile'
)
# 关闭后 Cookie 自动保存
```

### 为什么不用 context.storage_state()？

`storage_state()` 只保存 Cookie 和 Local Storage，不包含：
- IndexedDB
- Service Workers
- Cache Storage
- 其他浏览器特性

而 Persistent Context 保存完整的浏览器配置文件，更可靠。

---

**祝你使用愉快！有问题随时查看此文档。** 🎉
