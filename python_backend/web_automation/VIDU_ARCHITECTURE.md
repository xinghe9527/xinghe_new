# 🏗️ Vidu 自动化架构说明

## 📐 架构设计

### URL 配置字典

```python
VIDU_URLS = {
    'text2video': 'https://www.vidu.com/zh/create/text2video',  # 文生视频（当前使用）
    'img2video': 'https://www.vidu.com/zh/create/img2video',    # 图生视频（预留）
    'text2image': 'https://www.vidu.com/zh/create/text2image',  # 文生图片（预留）
}
```

### 当前使用

```python
VIDU_URL = VIDU_URLS['text2video']  # 精确锁定文生视频工作台
```

---

## 🎯 功能模式

### 1. 文生视频（Text to Video）✅ 当前实现

**地址**: `https://www.vidu.com/zh/create/text2video`

**功能**:
- 输入文本提示词
- 自动生成视频
- 支持多种风格和参数

**使用**:
```cmd
python auto_vidu.py "一个赛博朋克风格的女孩"
```

---

### 2. 图生视频（Image to Video）🚧 预留

**地址**: `https://www.vidu.com/zh/create/img2video`

**功能**:
- 上传参考图片
- 输入运镜提示词
- 生成基于图片的视频

**未来实现**:
```python
# 修改 VIDU_URL
VIDU_URL = VIDU_URLS['img2video']

# 添加图片上传逻辑
page.set_input_files('input[type="file"]', image_path)
```

---

### 3. 文生图片（Text to Image）🚧 预留

**地址**: `https://www.vidu.com/zh/create/text2image`

**功能**:
- 输入文本提示词
- 生成静态图片
- 支持多种尺寸和风格

**未来实现**:
```python
# 修改 VIDU_URL
VIDU_URL = VIDU_URLS['text2image']

# 图片生成逻辑与视频类似
```

---

## 🔧 核心优化

### 1. 强制等待机制

```python
# 等待输入框出现（最多 20 秒）
page.wait_for_selector('textarea', timeout=20000)

# 等待网络空闲
page.wait_for_load_state('networkidle', timeout=30000)

# 额外等待动态组件
time.sleep(3)
```

### 2. 智能填充逻辑

```python
# 1. 点击获取焦点
input_element.click()

# 2. 清空现有内容
input_element.fill('')

# 3. 模拟人工输入（每个字符延迟 50ms）
input_element.type(prompt, delay=50)

# 4. 验证填充结果
filled_value = input_element.input_value()
if filled_value == prompt:
    print("✅ 提示词填充成功")
```

### 3. 选择器优先级

```python
# 第一优先级：直接定位 textarea
'textarea'

# 第二优先级：中文占位符
'textarea[placeholder*="请输入描述词"]'

# 第三优先级：英文占位符
'textarea[placeholder*="prompt"]'

# 第四优先级：通用输入框
'input[type="text"]'

# 第五优先级：CSS 类名和 ID
'.prompt-input', '#prompt'

# 第六优先级：属性选择器
'[data-testid="prompt-input"]'
```

---

## 🚀 扩展指南

### 如何切换到图生视频模式

1. **修改 URL 配置**
   ```python
   VIDU_URL = VIDU_URLS['img2video']
   ```

2. **添加图片上传逻辑**
   ```python
   # 在填充提示词之前
   if image_path:
       print("📸 上传参考图片...")
       page.set_input_files('input[type="file"]', image_path)
       time.sleep(2)
   ```

3. **修改命令行参数**
   ```python
   # 接收图片路径参数
   if len(sys.argv) < 3:
       print("用法: python auto_vidu.py <prompt> <image_path>")
       return 1
   
   prompt = sys.argv[1]
   image_path = sys.argv[2]
   ```

### 如何添加模型选择

```python
# 在填充提示词之前
print("🎨 选择模型...")
model_selector = 'button:has-text("模型选择")'
page.locator(model_selector).click()
time.sleep(1)

# 选择具体模型
model_option = 'div:has-text("Vidu 1.5")'
page.locator(model_option).click()
time.sleep(1)
```

### 如何添加参数配置

```python
# 设置视频时长
duration_selector = 'select[name="duration"]'
page.locator(duration_selector).select_option('8')  # 8秒

# 设置分辨率
resolution_selector = 'select[name="resolution"]'
page.locator(resolution_selector).select_option('1080p')

# 设置风格
style_selector = 'button:has-text("赛博朋克")'
page.locator(style_selector).click()
```

---

## 📊 架构优势

### 1. 可扩展性

通过 `VIDU_URLS` 字典，轻松切换不同功能模式：
```python
# 切换到图生视频
VIDU_URL = VIDU_URLS['img2video']

# 切换到文生图片
VIDU_URL = VIDU_URLS['text2image']
```

### 2. 可维护性

- 所有 URL 集中管理
- 修改一处，全局生效
- 便于版本控制

### 3. 可测试性

```python
# 测试所有模式
for mode, url in VIDU_URLS.items():
    print(f"测试模式: {mode}")
    test_automation(url)
```

---

## 🎯 未来规划

### 短期目标

- [x] 文生视频自动化
- [ ] 图生视频自动化
- [ ] 模型选择功能
- [ ] 参数配置功能

### 中期目标

- [ ] 生成进度监控
- [ ] 自动下载结果
- [ ] 批量生成队列
- [ ] 错误重试机制

### 长期目标

- [ ] 多平台统一接口
- [ ] 智能参数推荐
- [ ] 生成结果分析
- [ ] 成本优化建议

---

## 📝 使用示例

### 当前：文生视频

```cmd
python auto_vidu.py "一个赛博朋克风格的女孩"
```

### 未来：图生视频

```cmd
python auto_vidu.py "镜头缓缓推进" "reference.jpg"
```

### 未来：文生图片

```cmd
python auto_vidu.py "一幅水墨画" --mode text2image
```

---

**架构已就绪，随时可扩展！** 🚀
