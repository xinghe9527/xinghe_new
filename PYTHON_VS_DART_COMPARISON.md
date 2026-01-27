# Python vs Dart 视频生成 API 实现对比

## 📅 日期
2026-01-26

## 🎯 目的
对比 Python 和 Dart 在调用视频生成 API 时的关键差异和最佳实践。

## 📋 核心差异总览

| 特性 | Python (requests) | Dart (http package) |
|------|------------------|---------------------|
| Content-Type 处理 | 手动传递空 files 对象 | 自动（MultipartRequest） |
| 异步处理 | 手动编写轮询代码 | 内置轮询方法 |
| 类型安全 | 运行时检查 | 编译时检查 |
| 错误处理 | 手动检查 status_code | ApiResponse 封装 |
| 代码简洁度 | 需要更多模板代码 | 高度封装，一行调用 |

## 🔧 关键技术点对比

### 1. multipart/form-data 强制使用

#### Python 实现

```python
import requests

# 关键技巧：即使不上传文件，也要传递空的 files 对象
# 这会强制 requests 库使用 multipart/form-data 格式
files = {
    'placeholder': (None, '')  # 假的文件参数
}

payload = {
    "model": "kling-video-o1",
    "prompt": "猫咪带着耳机听着歌走路",
    "size": "720x1280",
    "seconds": 10
}

headers = {
    "Authorization": f"Bearer {API_KEY}"
    # ⚠️ 不要手动设置 Content-Type
}

response = requests.post(
    BASE_URL,
    headers=headers,
    data=payload,    # 参数通过 data 传递
    files=files      # ⚠️ 必须传递 files，即使是空的
)
```

**关键点**：
- ✅ 必须传递 `files` 参数（即使是假的）
- ✅ 不要手动设置 `Content-Type`
- ✅ 参数通过 `data` 传递，不是 `json`

#### Dart 实现

```dart
import 'package:http/http.dart' as http;

// ⚠️ 关键：必须使用 MultipartRequest
var request = http.MultipartRequest(
  'POST',
  Uri.parse('$baseUrl/v1/videos'),
);

// 添加请求头（不要手动设置 Content-Type）
request.headers['Authorization'] = 'Bearer $apiKey';

// 添加文本参数（自动变成 multipart/form-data）
request.fields['model'] = 'kling-video-o1';
request.fields['prompt'] = '猫咪带着耳机听着歌走路';
request.fields['size'] = '720x1280';
request.fields['seconds'] = '10';

// 发送请求
final streamedResponse = await request.send();
final response = await http.Response.fromStream(streamedResponse);
```

**关键点**：
- ✅ 使用 `http.MultipartRequest`（不是普通的 POST）
- ✅ 通过 `request.fields` 添加参数
- ✅ 不需要假的文件参数
- ✅ Content-Type 自动设置为 multipart/form-data

### 2. 异步任务查询和轮询

#### Python 实现（需要手动编写，约 80 行）

```python
import time

def check_and_download(task_id):
    """查询任务状态并下载视频"""
    headers = {"Authorization": f"Bearer {API_KEY}"}
    query_url = f"{BASE_URL}/{task_id}"
    
    print(f"🕵️‍♂️ 开始追踪任务: {task_id}")
    print("☕️ Sora 生成较慢 (预计 2-10 分钟)，请耐心等待...")
    
    while True:
        try:
            response = requests.get(query_url, headers=headers)
            
            # 处理 404 - 数据同步延迟
            if response.status_code == 404:
                print("...暂时未查到任务信息，继续等待...")
                time.sleep(5)
                continue
            
            if response.status_code != 200:
                print(f"⚠️ 查询接口返回异常: {response.status_code}")
                time.sleep(10)
                continue
            
            data = response.json()
            status = data.get("status")
            progress = data.get("progress", 0)
            
            # 1. 成功完成
            if status == "completed":
                print("\n🎉 任务完成！")
                
                # 兼容多种字段名
                video_url = (data.get("url") or 
                           data.get("output") or 
                           data.get("video_url"))
                
                # 检查嵌套字段
                if not video_url and "data" in data:
                    video_url = data["data"].get("url")
                
                if video_url:
                    download_video(video_url)
                else:
                    print(f"❌ 虽显示完成，但没找到视频链接")
                break
            
            # 2. 失败
            elif status == "failed":
                print(f"\n❌ 生成失败: {data.get('fail_reason')}")
                break
            
            # 3. 处理中
            else:
                dots = "." * (int(time.time()) % 4)
                print(f"\r🔄 状态: [{status}] 进度: {progress}% {dots}", end="")
                time.sleep(5)
        
        except Exception as e:
            print(f"\n💥 查询过程出错: {e}")
            time.sleep(5)

def download_video(url):
    """下载视频"""
    filename = f"video_{TASK_ID[:8]}.mp4"
    try:
        with requests.get(url, stream=True) as r:
            r.raise_for_status()
            with open(filename, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
        print(f"✅ 视频已保存: {filename}")
    except Exception as e:
        print(f"❌ 下载失败: {e}")

# 使用
check_and_download(task_id)
```

**代码行数**：约 80 行

#### Dart 实现（内置支持，约 20 行）

```dart
// 查询任务并下载（对应上面的 Python 代码）
final helper = VeoVideoHelper(service);

print('🕵️‍♂️ 开始追踪任务: $taskId');
print('☕️ Sora 生成较慢 (预计 2-10 分钟)，请耐心等待...\n');

// 自动轮询直到完成
final result = await helper.pollTaskUntilComplete(
  taskId: taskId,
  maxWaitMinutes: 15,
  onProgress: (progress, status) {
    // 进度动画（对应 Python 的 \r 效果）
    final dots = '.' * (DateTime.now().second % 4);
    stdout.write('\r🔄 状态: [$status] 进度: $progress% $dots    ');
  },
);

print('\n');  // 换行

// 处理结果
if (result.isSuccess && result.data!.hasVideo) {
  print('🎉 任务完成！');
  print('视频URL: ${result.data!.videoUrl}');
  
  // 下载视频
  await downloadVideo(
    result.data!.videoUrl!,
    'video_${taskId.substring(0, 8)}.mp4',
  );
} else if (result.data?.isFailed ?? false) {
  print('❌ 生成失败: ${result.data!.errorMessage}');
} else {
  print('❌ 查询失败: ${result.errorMessage}');
}

// downloadVideo 函数（流式下载）
Future<void> downloadVideo(String url, String filename) async {
  final request = await HttpClient().getUrl(Uri.parse(url));
  final response = await request.close();
  final file = File(filename).openWrite();
  await response.pipe(file);
  print('✅ 视频已保存: $filename');
}
```

**代码行数**：约 20 行（**减少 75%**）

**关键优势**：
- ✅ 内置轮询方法（无需手动 while 循环）
- ✅ 自动 404 重试（数据同步延迟）
- ✅ 多字段名兼容（已在 VeoTaskStatus.fromJson 中处理）
- ✅ 进度回调支持
- ✅ 类型安全的状态判断

### 3. 完整的视频生成流程对比

#### Python 完整代码

```python
import requests
import time

API_KEY = "your-api-key"
BASE_URL = "https://xxxxx/v1/videos"

def generate_video():
    # 1. 提交任务
    headers = {"Authorization": f"Bearer {API_KEY}"}
    payload = {
        "model": "kling-video-o1",
        "prompt": "猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下",
        "size": "720x1280",
        "seconds": 10
    }
    files = {'placeholder': (None, '')}  # 强制 multipart/form-data
    
    response = requests.post(BASE_URL, headers=headers, data=payload, files=files)
    
    if response.status_code != 200:
        print(f"提交失败: {response.text}")
        return
    
    task_id = response.json()['id']
    print(f"任务提交成功: {task_id}")
    
    # 2. 轮询任务状态
    max_attempts = 120  # 10 分钟
    for i in range(max_attempts):
        status_response = requests.get(
            f"{BASE_URL}/{task_id}",
            headers=headers
        )
        
        if status_response.status_code == 200:
            data = status_response.json()
            status = data.get('status')
            progress = data.get('progress', 0)
            
            print(f"进度: {progress}%, 状态: {status}")
            
            if status == 'completed':
                video_url = data.get('video_url')
                print(f"视频完成: {video_url}")
                return video_url
            elif status in ['failed', 'cancelled']:
                print(f"任务失败: {data.get('error')}")
                return None
        
        time.sleep(5)
    
    print("任务超时")
    return None

# 运行
generate_video()
```

**代码行数**：约 50 行

#### Dart 完整代码

```dart
import '../lib/services/api/providers/veo_video_service.dart';
import '../lib/services/api/base/api_config.dart';

Future<void> generateVideo() async {
  // 1. 配置
  final config = ApiConfig(
    baseUrl: 'https://xxxxx',
    apiKey: 'your-api-key',
  );

  final service = VeoVideoService(config);
  final helper = VeoVideoHelper(service);

  // 2. 提交任务并自动轮询直到完成
  final result = await service.generateVideos(
    prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
    model: VeoModel.klingO1,
    ratio: '720x1280',
    parameters: {'seconds': 10},
  );

  if (!result.isSuccess) {
    print('提交失败: ${result.errorMessage}');
    return;
  }

  final taskId = result.data!.first.videoId!;
  print('任务提交成功: $taskId');

  // 3. 轮询状态
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId,
    maxWaitMinutes: 10,
    onProgress: (progress, status) {
      print('进度: $progress%, 状态: $status');
    },
  );

  if (status.isSuccess && status.data!.hasVideo) {
    print('视频完成: ${status.data!.videoUrl}');
  } else {
    print('任务失败: ${status.errorMessage}');
  }
}
```

**代码行数**：约 30 行（减少 40%）

**关键优势**：
- ✅ 更简洁（少 40% 代码）
- ✅ 无需手动轮询逻辑
- ✅ 自动错误处理
- ✅ 类型安全

## 🎯 使用建议

### Python 适合场景
- 快速脚本和原型
- 数据处理和分析
- 服务器端批处理
- 已有 Python 基础设施

### Dart/Flutter 适合场景
- 移动应用开发
- 跨平台应用
- 需要类型安全
- UI 集成需求

## 📊 性能对比

### 网络请求

| 特性 | Python | Dart |
|------|--------|------|
| HTTP 库 | requests | http package |
| 异步支持 | asyncio/aiohttp | 原生支持 |
| 连接池 | Session 对象 | IOClient |
| 超时控制 | timeout 参数 | Duration 对象 |

### 错误处理

| 特性 | Python | Dart |
|------|--------|------|
| 异常处理 | try/except | try/catch |
| 状态码检查 | response.status_code | response.statusCode |
| 错误封装 | 手动处理 | ApiResponse 封装 |
| 类型安全 | 否 | 是 |

## 💡 最佳实践

### Python 最佳实践

1. **使用 Session 对象**：
   ```python
   session = requests.Session()
   session.headers.update({"Authorization": f"Bearer {API_KEY}"})
   ```

2. **设置超时**：
   ```python
   response = requests.post(url, timeout=30)
   ```

3. **错误处理**：
   ```python
   try:
       response = requests.post(url)
       response.raise_for_status()
   except requests.exceptions.RequestException as e:
       print(f"请求错误: {e}")
   ```

4. **重试机制**：
   ```python
   from requests.adapters import HTTPAdapter
   from requests.packages.urllib3.util.retry import Retry
   
   retry_strategy = Retry(total=3, backoff_factor=1)
   adapter = HTTPAdapter(max_retries=retry_strategy)
   session.mount("https://", adapter)
   ```

### Dart 最佳实践

1. **使用服务封装**：
   ```dart
   final service = VeoVideoService(config);
   final helper = VeoVideoHelper(service);
   ```

2. **使用 Helper 方法**：
   ```dart
   // 推荐：使用 Helper
   await helper.textToVideo(prompt: '...');
   
   // 而不是：直接调用 service
   await service.generateVideos(prompt: '...', model: '...', ...);
   ```

3. **检查响应状态**：
   ```dart
   if (result.isSuccess) {
     // 处理成功
   } else {
     print('错误: ${result.errorMessage}');
     print('状态码: ${result.statusCode}');
   }
   ```

4. **使用进度回调**：
   ```dart
   await helper.pollTaskUntilComplete(
     taskId: taskId,
     onProgress: (progress, status) {
       // 更新 UI 或日志
     },
   );
   ```

## 🚀 迁移指南

### 从 Python 迁移到 Dart

#### Python 代码
```python
# 提交任务
payload = {
    "model": "kling-video-o1",
    "prompt": "猫咪走路",
    "size": "720x1280",
    "seconds": 10
}
files = {'placeholder': (None, '')}
response = requests.post(BASE_URL, headers=headers, data=payload, files=files)
task_id = response.json()['id']

# 轮询状态
while True:
    status_response = requests.get(f"{BASE_URL}/{task_id}", headers=headers)
    data = status_response.json()
    if data['status'] == 'completed':
        video_url = data['video_url']
        break
    time.sleep(5)
```

#### 对应的 Dart 代码
```dart
// 提交任务并自动轮询
final result = await service.generateVideos(
  prompt: '猫咪走路',
  model: VeoModel.klingO1,
  ratio: '720x1280',
  parameters: {'seconds': 10},
);

final taskId = result.data!.first.videoId!;

final status = await helper.pollTaskUntilComplete(
  taskId: taskId,
  onProgress: (progress, status) {
    print('进度: $progress%');
  },
);

final videoUrl = status.data!.videoUrl;
```

**迁移要点**：
1. ✅ 移除手动 files 参数处理
2. ✅ 使用 MultipartRequest（已封装）
3. ✅ 使用 pollTaskUntilComplete 替代手动轮询
4. ✅ 使用类型安全的数据模型

## 📖 常见问题

### Q1: 为什么 Python 需要传递空的 files 参数？

**A:** Python requests 库的行为：
- 如果只传递 `data` 参数：使用 `application/x-www-form-urlencoded`
- 如果传递 `json` 参数：使用 `application/json`
- 如果传递 `files` 参数：使用 `multipart/form-data`

而视频生成 API **要求** `multipart/form-data` 格式，所以必须传递 files 参数。

### Q2: Dart 为什么不需要假的文件参数？

**A:** Dart 的设计更清晰：
- `http.Request` → `application/json`
- `http.MultipartRequest` → `multipart/form-data`

直接使用 `MultipartRequest` 就会自动设置正确的 Content-Type。

### Q3: 如何在 Dart 中添加文件上传？

**A:** 
```dart
// 添加文件（如果需要）
request.files.add(
  await http.MultipartFile.fromPath(
    'input_reference',  // 字段名
    '/path/to/image.jpg',  // 文件路径
  ),
);

// 如果不需要文件，就不添加，MultipartRequest 仍然有效
```

### Q4: Python 和 Dart 哪个更快？

**A:** 性能对比：
- **网络请求速度**：基本相同（都是 HTTP 请求）
- **代码执行**：Dart 稍快（编译型语言 vs 解释型）
- **并发处理**：Dart 更优（原生异步支持）
- **开发效率**：各有优势

## 🔍 实际代码对比

### 场景：生成 Kling 视频并下载

#### Python 版本（约 80 行）

```python
import requests
import time

API_KEY = "your-api-key"
BASE_URL = "https://xxxxx/v1/videos"

def generate_and_download():
    # 1. 提交任务
    headers = {"Authorization": f"Bearer {API_KEY}"}
    payload = {
        "model": "kling-video-o1",
        "prompt": "猫咪走路",
        "size": "720x1280",
        "seconds": 10
    }
    files = {'placeholder': (None, '')}
    
    response = requests.post(BASE_URL, headers=headers, data=payload, files=files)
    if response.status_code != 200:
        print("提交失败")
        return
    
    task_id = response.json()['id']
    print(f"任务ID: {task_id}")
    
    # 2. 轮询状态
    max_attempts = 120
    for i in range(max_attempts):
        status_response = requests.get(f"{BASE_URL}/{task_id}", headers=headers)
        
        if status_response.status_code == 200:
            data = status_response.json()
            status = data['status']
            progress = data.get('progress', 0)
            
            print(f"进度: {progress}%")
            
            if status == 'completed':
                video_url = data['video_url']
                
                # 3. 下载视频
                video_response = requests.get(video_url)
                with open('video.mp4', 'wb') as f:
                    f.write(video_response.content)
                
                print(f"视频已下载: video.mp4")
                return
            elif status in ['failed', 'cancelled']:
                print("任务失败")
                return
        
        time.sleep(5)
    
    print("超时")

generate_and_download()
```

#### Dart 版本（约 40 行）

```dart
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> generateAndDownload() async {
  // 1. 配置
  final config = ApiConfig(
    baseUrl: 'https://xxxxx',
    apiKey: 'your-api-key',
  );

  final service = VeoVideoService(config);
  final helper = VeoVideoHelper(service);

  // 2. 提交任务
  final result = await service.generateVideos(
    prompt: '猫咪走路',
    model: VeoModel.klingO1,
    ratio: '720x1280',
    parameters: {'seconds': 10},
  );

  if (!result.isSuccess) {
    print('提交失败');
    return;
  }

  final taskId = result.data!.first.videoId!;
  print('任务ID: $taskId');

  // 3. 轮询状态（自动）
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId,
    onProgress: (progress, status) {
      print('进度: $progress%');
    },
  );

  if (status.isSuccess && status.data!.hasVideo) {
    // 4. 下载视频
    final videoUrl = status.data!.videoUrl!;
    final response = await http.get(Uri.parse(videoUrl));
    await File('video.mp4').writeAsBytes(response.bodyBytes);
    print('视频已下载: video.mp4');
  }
}
```

**代码行数减少 50%**

## 🎨 高级功能对比

### 批量生成

#### Python
```python
# 需要手动实现并发
from concurrent.futures import ThreadPoolExecutor

def generate_multiple():
    prompts = ["场景1", "场景2", "场景3"]
    
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = [executor.submit(generate_video, p) for p in prompts]
        results = [f.result() for f in futures]
    
    return results
```

#### Dart
```dart
// 原生异步支持
Future<List<String?>> generateMultiple() async {
  final prompts = ["场景1", "场景2", "场景3"];
  
  final futures = prompts.map((prompt) async {
    final result = await service.generateVideos(
      prompt: prompt,
      model: VeoModel.klingO1,
      ratio: '720x1280',
      parameters: {'seconds': 10},
    );
    
    if (result.isSuccess) {
      final taskId = result.data!.first.videoId!;
      final status = await helper.pollTaskUntilComplete(taskId: taskId);
      return status.data?.videoUrl;
    }
    return null;
  });
  
  return await Future.wait(futures);
}
```

## 📚 总结

### Python 优势
- ✅ 简单直接的语法
- ✅ 丰富的第三方库
- ✅ 快速脚本开发
- ✅ 数据处理强大

### Dart 优势
- ✅ 类型安全（编译时检查）
- ✅ 原生异步支持
- ✅ 更好的代码封装
- ✅ 跨平台 UI 支持（Flutter）
- ✅ 更少的模板代码（本项目）

### 选择建议

**使用 Python**：
- 服务器端批处理
- 数据分析脚本
- 快速原型验证
- 已有 Python 技术栈

**使用 Dart/Flutter**：
- 移动应用
- 桌面应用
- Web 应用
- 需要 UI 的应用
- 跨平台需求

## 🔗 相关资源

- **Dart 示例代码**: `examples/video_generation_example.dart`
- **VEO 使用文档**: `lib/services/api/providers/VEO_VIDEO_USAGE.md`
- **Python 参考代码**: 用户提供的示例

---

**文档版本**: v1.0.0
**创建日期**: 2026-01-26
