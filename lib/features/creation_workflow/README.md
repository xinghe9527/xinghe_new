# 项目创作流模块 (Project Workflow Module)

## 📁 目录结构

```
creation_workflow/
├── data/
│   └── mock_ai_service.dart          # Mock AI服务（模拟数据）
├── domain/
│   └── models/
│       ├── script_line.dart          # 剧本行模型
│       ├── entity.dart                # 实体模型（角色/场景）
│       ├── storyboard.dart            # 分镜模型
│       ├── video_clip.dart            # 视频片段模型
│       └── project.dart               # 项目模型（总数据容器）
└── presentation/
    ├── creation_workflow_page.dart    # 主工作流页面
    ├── workflow_controller.dart       # 状态控制器
    └── views/
        ├── script_editor_view.dart    # 第1步：剧本编辑器
        ├── entity_manager_view.dart   # 第2步：实体管理
        ├── storyboard_view.dart       # 第3步：分镜生成
        └── video_gen_view.dart        # 第4步：视频生成
```

## 🚀 功能特性

### ✅ 零侵入设计
- 完全独立的模块，不影响现有主界面
- 全屏弹窗方式呈现
- 通过 Navigator 路由进出

### ✅ 全中文环境
- 所有UI文字、提示、标签均为中文
- 数据模型字段注释清晰
- 用户体验完全本地化

### ✅ 四步工作流

#### 第1步：智能剧本编辑器
- **Excel风格表格界面**
- AI自动生成剧本
- 支持手动编辑、插入行
- AI扩写功能（在任意两行间插入内容）
- 上下文记忆标识

#### 第2步：实体与资产管理
- 从剧本自动提取角色和场景
- 卡片式展示
- **锁定形象功能**：固定角色外貌描述
- 手动添加/编辑实体

#### 第3步：分镜生成
- 时间轴式界面
- **智能提示词拼接**：
  - 场景描述 + 角色固定描述 + 剧本内容
- 为每个剧本行生成分镜图
- 支持重新生成和确认

#### 第4步：视频生成
- **三种生成模式**：
  1. 模式A：文生视频
  2. 模式B：图生视频（使用分镜图）
  3. 模式C：首尾帧控制（⭐ 核心功能）
- 首尾帧模式支持：
  - 自动填入起始帧（分镜图）
  - 用户上传结束帧
  - 或留空让AI自动生成

## 🎨 UI设计规范

### 配色方案
- 主背景：`#161618` (深邃黑)
- 卡片背景：`#1E1E20` (次级黑)
- 强调色：`#2AF598` (青绿渐变)
- 次要强调：`#009EFD` (科技蓝)
- 文字主色：`#FFFFFF`
- 文字次色：`#888888`
- 边框分割：`#2A2A2C`

### 组件风格
- 圆角半径：8-12px
- 按钮高度：40-48px
- 卡片间距：16-24px
- 机甲科技风设计语言

## 💡 使用方法

### 从创作空间进入

```dart
// 在 creation_space.dart 中
import '../../../creation_workflow/presentation/creation_workflow_page.dart';

// 点击"创建作品"按钮后：
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (context) => CreationWorkflowPage(projectName: '我的作品'),
    fullscreenDialog: true,
  ),
);
```

### 工作流程

1. **输入作品名称** → 打开工作流页面
2. **第1步：编写剧本** → AI生成或手动输入
3. **第2步：管理实体** → 提取角色和场景，设置固定描述
4. **第3步：生成分镜** → 为每行剧本生成图片
5. **第4步：生成视频** → 选择模式生成视频片段
6. **点击"完成"** → 保存项目并返回

## 🔧 技术实现

### 状态管理
使用 `ValueNotifier` 进行轻量级状态管理：
- `projectNotifier`：项目数据
- `currentStepNotifier`：当前步骤
- `isLoadingNotifier`：加载状态
- `errorMessageNotifier`：错误信息

### Mock数据服务
`MockAIService` 提供模拟AI响应：
- 2秒延迟模拟网络请求
- 返回中文示例数据
- 使用占位符图片服务

### 数据持久化
项目数据支持 JSON 序列化：
```dart
// 保存
final json = project.toJson();

// 加载
final project = Project.fromJson(json);
```

## 🔄 后续接入真实API

### 替换 MockAIService

1. 创建 `RealAIService` 实现相同接口
2. 修改 `WorkflowController` 初始化：

```dart
// 从
final MockAIService _aiService = MockAIService();

// 改为
final RealAIService _aiService = RealAIService(
  apiKey: 'your_api_key',
  baseUrl: 'https://api.example.com',
);
```

### API接口对应

| 功能 | Mock方法 | 真实API端点 |
|------|----------|-------------|
| 生成剧本 | `generateScript()` | `POST /api/script/generate` |
| 扩写剧本 | `expandScript()` | `POST /api/script/expand` |
| 提取实体 | `extractEntities()` | `POST /api/entities/extract` |
| 生成分镜 | `generateStoryboardImage()` | `POST /api/image/generate` |
| 生成视频 | `generateVideoClip()` | `POST /api/video/generate` |

## 📝 核心数据模型

### ScriptLine（剧本行）
```dart
{
  "id": "1234567890",
  "content": "主角站在高楼阳台，眺望城市",
  "type": "action",  // action/dialogue
  "aiPrompt": "年轻主角，阳台，城市背景",
  "contextTags": ["主角", "城市", "阳台"],
  "hasContextMemory": true
}
```

### Entity（实体）
```dart
{
  "id": "1234567890",
  "type": "character",  // character/scene
  "name": "主角",
  "fixedPrompt": "银白短发，蓝色眼睛，黑色机能风外套",
  "isLocked": true
}
```

### Storyboard（分镜）
```dart
{
  "id": "1234567890",
  "scriptLineId": "xxx",
  "imageUrl": "https://...",
  "finalPrompt": "场景：未来都市，主角：银白短发...",
  "isConfirmed": true
}
```

### VideoClip（视频片段）
```dart
{
  "id": "1234567890",
  "storyboardId": "xxx",
  "videoUrl": "https://...",
  "generationMode": "keyframes",  // textToVideo/imageToVideo/keyframes
  "startFrameUrl": "https://...",
  "endFrameUrl": "https://...",
  "status": "completed"  // pending/generating/completed/failed
}
```

## 🎯 关键特性说明

### 1. 上下文记忆
每个剧本行都有 `hasContextMemory` 标识，显示为绿色标签。这表示AI在生成时会考虑前后文。

### 2. 实体锁定
当实体被锁定（`isLocked: true`）时：
- 其 `fixedPrompt` 会被添加到所有相关分镜的提示词中
- 确保角色外貌在整个项目中保持一致

### 3. 提示词拼接
在生成分镜时，最终提示词由三部分组成：
```
场景描述 + 锁定实体的固定描述 + 当前剧本内容
```

### 4. 首尾帧控制
模式C允许用户：
- 使用分镜图作为起始帧
- 上传自定义结束帧
- 让AI在两帧之间生成平滑过渡

## 🚧 注意事项

### 性能优化
- 图片使用缓存加载
- 大量数据时使用分页
- 视频生成使用后台任务

### 错误处理
- 所有异步操作都有 try-catch
- 错误信息显示在页面底部
- 网络失败时提供重试选项

### 测试流程
1. 点击"创建作品"
2. 输入作品名称
3. 在第1步点击"AI生成"（输入任意主题）
4. 等待2秒，查看生成的剧本
5. 点击"下一步"
6. 在第2步点击"从剧本提取"
7. 查看提取的角色和场景
8. 继续测试后续步骤...

## 🎨 界面截图说明

### 步骤导航条
- 显示4个步骤，当前步骤高亮
- 已完成步骤显示✓标记
- 点击可直接跳转

### 剧本编辑器
- Excel风格表格
- 序号 | 类型 | 内容 | AI提示词 | 操作
- 插入按钮在两行之间

### 实体管理
- 卡片网格布局
- 每张卡片显示类型图标、名称、锁定开关
- 固定描述文本框

### 分镜生成
- 左侧：分镜图预览（300x200）
- 右侧：提示词显示和操作按钮
- 确认后显示绿色✓标记

### 视频生成
- 三个模式卡片横向排列
- 点击模式C弹出首尾帧选择对话框
- 左右两个图片槽位 + 中间箭头

## 📦 依赖说明

项目已使用的包（无需额外安装）：
- `flutter/material.dart` - UI框架
- `shared_preferences` - 数据持久化（如需）
- `file_picker` - 文件选择（首尾帧上传）

## 🔗 集成检查清单

✅ 数据模型已创建（4个核心模型 + 1个项目模型）
✅ Mock服务已实现
✅ 工作流控制器已实现
✅ 主页面已创建
✅ 4个步骤视图已创建
✅ 已连接到创作空间
✅ 全中文界面
✅ 零侵入设计
✅ 无Lint错误

## 🎉 使用演示

启动应用后：
1. 进入"创作空间"标签
2. 点击"创建作品"按钮
3. 输入作品名称（如："赛博朋克冒险"）
4. 点击"开始创作"
5. 在第1步输入主题："未来都市的冒险故事"
6. 点击"AI生成"，等待Mock数据返回
7. 查看生成的中文剧本（5行示例）
8. 体验插入行、编辑等功能
9. 点击"下一步"继续...

---

**模块版本**: v1.0.0  
**创建日期**: 2026年1月  
**维护者**: AI团队  
**状态**: ✅ 已完成 | 🧪 使用Mock数据 | 🚀 准备接入真实API
