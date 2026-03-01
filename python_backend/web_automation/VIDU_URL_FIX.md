# 🔧 Vidu URL 修复说明

## 问题原因

之前的脚本访问的是 Vidu 的宣传首页：
```
❌ https://www.vidu.studio/
```

这个页面没有创作功能，只是展示页面。

## 解决方案

现在脚本直接访问创作页面：
```
✅ https://www.vidu.studio/zh/create
```

这是真正的视频创作后台，包含：
- 提示词输入框（"请输入描述词"）
- 生成按钮
- 模型选择
- 参数配置

## 优化内容

### 1. URL 修改
```python
# 旧版本
VIDU_URL = 'https://www.vidu.studio/'

# 新版本
VIDU_URL = 'https://www.vidu.studio/zh/create'  # 直接访问创作页面
```

### 2. 页面加载优化
```python
# 等待网络空闲
page.wait_for_load_state('networkidle', timeout=30000)

# 额外等待动态组件渲染
time.sleep(5)
```

### 3. 输入框选择器优化

优先匹配中文占位符：
```python
'textarea[placeholder*="请输入描述词"]',  # 最优先
'textarea[placeholder*="描述词"]',
'textarea[placeholder*="请输入"]',
```

### 4. 按钮选择器扩展

增加更多可能的按钮选择器：
```python
'button:has-text("生成")',
'button:has-text("生成视频")',
'button:has-text("开始生成")',
'button:has-text("创建视频")',
# ... 共 20+ 种选择器
```

## 测试命令

```cmd
python python_backend\web_automation\auto_vidu.py "一个赛博朋克风格的女孩"
```

## 预期效果

1. ✅ 浏览器打开创作页面（已登录）
2. ✅ 等待页面完全加载（networkidle）
3. ✅ 找到"请输入描述词"输入框
4. ✅ 自动填充提示词
5. ✅ 找到生成按钮
6. ✅ 自动点击生成
7. ✅ 截图保存
8. ✅ 输出 JSON 结果

## 其他创作页面 URL

如果需要访问其他页面：

```python
# 图生视频
'https://www.vidu.studio/zh/create?mode=img2video'

# 文生视频
'https://www.vidu.studio/zh/create?mode=text2video'

# 首页（需要手动点击创作按钮）
'https://www.vidu.studio/'

# 个人中心
'https://www.vidu.studio/zh/home'
```

## 注意事项

1. **登录状态**：确保已运行 `init_login.py vidu` 初始化登录
2. **网络稳定**：创作页面加载较慢，需要稳定的网络
3. **页面变化**：如果 Vidu 更新页面结构，可能需要更新选择器

---

**现在脚本会直接进入创作页面，大显身手！** 🚀
