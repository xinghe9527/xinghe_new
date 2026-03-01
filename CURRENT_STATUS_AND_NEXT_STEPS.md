# 📊 当前状态和下一步工作

## ✅ 已完成的功能

### 1. 设置界面
- ✅ 可以选择网页服务商（Vidu、即梦、可灵、海螺）
- ✅ 可以选择工具类型（文生视频、图生视频等）
- ✅ 可以选择模型（Vidu Q3、Q2、Q1）
- ✅ 配置自动保存

### 2. API 通信
- ✅ Flutter 可以调用 Python API
- ✅ Python API 可以接收任务
- ✅ 任务可以提交到后台执行

### 3. 浏览器自动化
- ✅ 浏览器可以自动打开 Vidu 网站
- ✅ 可以自动填写提示词
- ✅ 可以自动点击生成按钮
- ✅ **视频可以在网页上成功生成** 🎉

## ❌ 当前问题

### 问题 1：视频没有下载
**现象**：
- 视频在 Vidu 网页上生成成功
- 但没有下载到本地
- 不知道保存在哪里

**原因**：
`auto_vidu.py` 脚本只做了以下事情：
1. 打开浏览器
2. 填写提示词
3. 点击生成按钮
4. 等待 30 秒
5. 退出

**缺少的功能**：
- ❌ 没有等待视频生成完成
- ❌ 没有获取视频 URL
- ❌ 没有下载视频
- ❌ 没有保存到指定路径

### 问题 2：Flutter 一直显示"等待中"
**现象**：
- Flutter 显示 0% 进度
- 一直显示"等待中..."
- 永远不会完成

**原因**：
1. Python 脚本 30 秒后就退出了
2. 但视频还在生成中（可能需要 1-2 分钟）
3. 脚本退出时返回成功状态
4. 但实际上没有视频 URL
5. Flutter 轮询任务状态，发现没有视频 URL，所以一直等待

### 问题 3：保存路径不一致
**现象**：
- 设置中配置了保存路径
- 但视频不知道保存在哪里

**原因**：
- Python 脚本还没有实现下载功能
- 没有读取 Flutter 设置的保存路径

## 🔧 需要做的改进

### 改进 1：实现完整的视频生成流程

需要修改 `auto_vidu.py`，添加以下功能：

```python
def wait_for_video_generation(page):
    """等待视频生成完成"""
    print("⏳ 等待视频生成完成...")
    
    max_wait_time = 300  # 最多等待 5 分钟
    start_time = time.time()
    
    while time.time() - start_time < max_wait_time:
        # 检查是否有下载按钮或视频链接
        try:
            # 查找下载按钮
            download_button = page.locator('button:has-text("下载")').first
            if download_button.is_visible(timeout=1000):
                print("✅ 视频生成完成！")
                return True
        except:
            pass
        
        # 等待 5 秒后再检查
        time.sleep(5)
        print(f"⏳ 已等待 {int(time.time() - start_time)} 秒...")
    
    print("❌ 等待超时")
    return False


def get_video_url(page):
    """获取生成的视频 URL"""
    print("🔍 获取视频 URL...")
    
    # 方法 1：从下载按钮获取
    try:
        download_link = page.locator('a[download]').first
        video_url = download_link.get_attribute('href')
        if video_url:
            print(f"✅ 找到视频 URL: {video_url}")
            return video_url
    except:
        pass
    
    # 方法 2：从 video 标签获取
    try:
        video_element = page.locator('video').first
        video_url = video_element.get_attribute('src')
        if video_url:
            print(f"✅ 找到视频 URL: {video_url}")
            return video_url
    except:
        pass
    
    print("❌ 未找到视频 URL")
    return None


def download_video(video_url, save_path):
    """下载视频到指定路径"""
    import requests
    
    print(f"📥 开始下载视频...")
    print(f"📍 保存路径: {save_path}")
    
    try:
        response = requests.get(video_url, stream=True, timeout=60)
        response.raise_for_status()
        
        # 确保目录存在
        os.makedirs(os.path.dirname(save_path), exist_ok=True)
        
        # 下载视频
        with open(save_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        print(f"✅ 视频下载完成: {save_path}")
        return save_path
    except Exception as e:
        print(f"❌ 下载失败: {e}")
        return None
```

### 改进 2：支持自定义保存路径

需要修改 API 接口，接收保存路径参数：

```python
class UniversalGenerateRequest(BaseModel):
    platform: str
    tool_type: str
    payload: Dict[str, Any]
    save_path: Optional[str] = None  # ✅ 新增：保存路径
```

然后在执行时使用这个路径：

```python
async def execute_vidu_automation(task_id: str, prompt: str, save_path: str = None):
    # 如果没有指定保存路径，使用默认路径
    if save_path is None:
        save_path = os.path.join(SCRIPT_DIR, 'downloads', f'{task_id}.mp4')
    
    # 传递给 auto_vidu.py
    command = [PYTHON_EXECUTABLE, AUTO_VIDU_SCRIPT, prompt, '--save-path', save_path]
    # ...
```

### 改进 3：返回完整的结果

修改 `auto_vidu.py` 的输出格式：

```python
# 在脚本最后输出 JSON 结果
result = {
    "success": True,
    "video_url": video_url,  # 云端 URL
    "local_video_path": local_path,  # 本地路径
    "message": "视频生成成功"
}

print(json.dumps(result, ensure_ascii=False))
```

## 🎯 临时解决方案

在完整实现之前，你可以：

### 方案 1：手动下载视频
1. 等待网页上视频生成完成
2. 在 Vidu 网站上点击下载按钮
3. 手动保存到你设置的路径

### 方案 2：使用浏览器的默认下载
1. 视频会下载到浏览器的默认下载文件夹
2. 通常是 `C:\Users\你的用户名\Downloads\`
3. 手动移动到你想要的位置

### 方案 3：等待完整实现
我可以帮你实现完整的下载功能，但需要：
1. 修改 `auto_vidu.py`（约 100-200 行代码）
2. 修改 `api_server.py`（约 50 行代码）
3. 修改 Flutter 客户端（传递保存路径）
4. 测试整个流程

## 📝 实现优先级

### 高优先级（必须实现）
1. ✅ 等待视频生成完成
2. ✅ 获取视频 URL
3. ✅ 下载视频到本地
4. ✅ 返回本地路径给 Flutter

### 中优先级（重要但不紧急）
1. ⏳ 支持自定义保存路径
2. ⏳ 显示下载进度
3. ⏳ 支持断点续传

### 低优先级（锦上添花）
1. ⏸️ 支持批量下载
2. ⏸️ 支持视频预览
3. ⏸️ 支持视频格式转换

## 🚀 下一步行动

### 选项 A：快速修复（推荐）
我可以快速实现核心功能：
1. 等待视频生成完成
2. 获取视频 URL
3. 下载到默认路径
4. 返回结果给 Flutter

**预计时间**：30-60 分钟
**效果**：可以完整走通流程

### 选项 B：完整实现
实现所有功能，包括自定义路径、进度显示等

**预计时间**：2-3 小时
**效果**：功能完善，用户体验好

### 选项 C：暂时手动
继续使用当前版本，手动下载视频

**预计时间**：0 分钟
**效果**：可以用，但不方便

## 💡 建议

我建议选择 **选项 A：快速修复**，原因：
1. 可以快速验证整个流程
2. 解决最核心的问题
3. 后续可以逐步完善

你觉得呢？要不要我现在就实现快速修复？
