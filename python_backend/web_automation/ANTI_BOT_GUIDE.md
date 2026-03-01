# 反机器人检测指南

## 🤖 为什么会被识别为机器人？

网站使用多种技术检测自动化工具：

1. **Webdriver 特征检测**
   - 检查 `navigator.webdriver` 属性
   - 检查 Chrome DevTools Protocol
   - 检查自动化控制特征

2. **行为模式检测**
   - 鼠标移动轨迹（机器人移动太精确）
   - 操作速度（机器人操作太快）
   - 操作间隔（机器人间隔太规律）

3. **浏览器指纹检测**
   - User-Agent
   - 插件列表
   - 语言设置
   - 屏幕分辨率

## ✅ 我们的反检测策略

### 1. 隐藏自动化特征

```python
# 启动参数
args=[
    '--disable-blink-features=AutomationControlled',  # 隐藏自动化特征
    '--disable-dev-shm-usage',
    '--no-sandbox',
]

# 注入脚本
context.add_init_script("""
    Object.defineProperty(navigator, 'webdriver', {
        get: () => undefined  // 隐藏 webdriver 属性
    });
""")
```

### 2. 模拟人类行为

```python
# 随机延迟
def human_like_delay(min_seconds=0.5, max_seconds=2.0):
    delay = random.uniform(min_seconds, max_seconds)
    time.sleep(delay)

# 随机鼠标移动
def human_like_mouse_move(page, element):
    # 随机偏移，模拟人类不精确的点击
    x = box['x'] + box['width'] / 2 + random.uniform(-5, 5)
    y = box['y'] + box['height'] / 2 + random.uniform(-5, 5)
    page.mouse.move(x, y)

# 模拟打字速度
input_element.type(prompt, delay=random.randint(50, 100))  # 50-100ms 每个字符
```

### 3. 使用持久化登录

```python
# 使用已登录的浏览器配置文件
context = p.chromium.launch_persistent_context(
    user_data_dir=USER_DATA_DIR,  # 保存 Cookie 和登录状态
    headless=False,
)
```

### 4. 错误时不关闭浏览器

```python
except Exception as e:
    print("⚠️  发生错误，浏览器将保持打开状态")
    print("  请手动检查页面，查看具体问题")
    
    # 永久等待，不关闭浏览器
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("用户中断，现在关闭浏览器")
```

## 🛡️ 如何应对机器人验证弹窗

### 方法 1：手动完成验证（推荐）

1. **脚本遇到验证时会暂停**
   - 浏览器保持打开
   - 你可以手动完成验证（点击图片、滑块等）

2. **完成验证后**
   - 验证通过后，页面会继续
   - 脚本会自动继续执行

3. **如果脚本已经退出**
   - 重新运行脚本
   - 由于使用持久化登录，验证状态会保留

### 方法 2：使用 Stealth 插件（高级）

安装 playwright-stealth：

```bash
pip install playwright-stealth
```

修改脚本：

```python
from playwright_stealth import stealth_sync

# 在创建页面后
page = context.new_page()
stealth_sync(page)  # 应用反检测补丁
```

### 方法 3：降低操作频率

如果经常遇到验证：

1. **增加操作间隔**
   ```python
   # 在 human_like_delay 中使用更长的延迟
   human_like_delay(2.0, 5.0)  # 2-5 秒
   ```

2. **减少批量操作**
   - 不要一次生成太多视频
   - 每次生成后等待更长时间

3. **使用不同的账号**
   - 轮流使用多个账号
   - 避免单个账号频繁操作

### 方法 4：使用代理 IP（高级）

```python
context = p.chromium.launch_persistent_context(
    user_data_dir=USER_DATA_DIR,
    headless=False,
    proxy={
        "server": "http://proxy-server:port",
        "username": "username",
        "password": "password"
    }
)
```

## 🔧 调试技巧

### 1. 查看浏览器控制台

当浏览器保持打开时：
1. 按 F12 打开开发者工具
2. 查看 Console 标签页
3. 查看是否有错误信息

### 2. 检查网络请求

1. 打开开发者工具
2. 切换到 Network 标签页
3. 查看是否有失败的请求
4. 查看是否有验证相关的请求

### 3. 手动测试流程

1. 在浏览器中手动执行操作
2. 观察页面反应
3. 记录成功的操作步骤
4. 根据观察结果调整脚本

## 📊 常见问题

### Q1: 为什么别人的软件不会被检测？

**A**: 专业的自动化软件通常使用：

1. **更复杂的反检测技术**
   - 修改浏览器内核
   - 使用真实的浏览器指纹
   - 模拟真实用户的行为模式

2. **付费的反检测服务**
   - 专业的代理 IP 池
   - 浏览器指纹伪装服务
   - 验证码识别服务

3. **与网站的合作**
   - 有些软件可能与网站有合作关系
   - 使用官方 API 而不是网页自动化

### Q2: 如何减少被检测的概率？

**A**: 最佳实践：

1. **使用真实的浏览器配置**
   - 使用持久化登录（已实现）
   - 保留 Cookie 和缓存

2. **模拟真实用户行为**
   - 随机延迟（已实现）
   - 随机鼠标移动（已实现）
   - 随机滚动页面（已实现）

3. **降低操作频率**
   - 不要连续快速操作
   - 每次操作后等待足够长的时间

4. **分散操作时间**
   - 不要在固定时间操作
   - 模拟人类的作息时间

### Q3: 遇到验证码怎么办？

**A**: 三种方案：

1. **手动完成**（推荐）
   - 脚本会暂停
   - 你手动完成验证
   - 脚本继续执行

2. **使用验证码识别服务**
   - 2Captcha
   - Anti-Captcha
   - 需要付费

3. **避免触发验证码**
   - 降低操作频率
   - 使用已验证的账号

## 🎯 当前脚本的反检测特性

### ✅ 已实现

- [x] 隐藏 webdriver 特征
- [x] 伪装浏览器指纹
- [x] 随机操作延迟
- [x] 随机鼠标移动
- [x] 模拟人类打字速度
- [x] 随机页面滚动
- [x] 使用持久化登录
- [x] 错误时保持浏览器打开

### 🔄 可以改进

- [ ] 更复杂的鼠标轨迹
- [ ] 模拟真实的浏览行为（访问其他页面）
- [ ] 使用代理 IP
- [ ] 集成验证码识别服务

## 💡 使用建议

1. **首次使用**
   - 先手动登录一次
   - 完成任何初始验证
   - 让账号"热身"

2. **日常使用**
   - 不要连续生成太多视频
   - 每次生成后等待几分钟
   - 模拟正常用户的使用模式

3. **遇到验证**
   - 不要慌张
   - 手动完成验证
   - 验证状态会保留

4. **长期使用**
   - 定期手动登录
   - 保持账号活跃
   - 避免异常行为模式

---

**记住**: 自动化工具的目的是提高效率，而不是滥用服务。请合理使用，遵守网站的使用条款。
