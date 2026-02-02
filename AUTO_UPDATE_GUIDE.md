# 星橙AI动漫制作 - 自动更新功能使用指南

## 📋 目录

1. [功能介绍](#功能介绍)
2. [Supabase 配置](#supabase-配置)
3. [打包发布流程](#打包发布流程)
4. [测试更新功能](#测试更新功能)
5. [常见问题](#常见问题)

---

## 功能介绍

✅ **已实现的功能：**

- ✅ 应用启动时自动检测更新
- ✅ 强制更新 / 可选更新
- ✅ 版本过低阻止使用
- ✅ 增量更新（只下载变化的文件）
- ✅ 下载进度显示
- ✅ 自动替换文件并重启
- ✅ 使用 Supabase 存储版本信息和更新包

---

## Supabase 配置

### 1. 创建数据库表

1. 登录 [Supabase Dashboard](https://app.supabase.com/)
2. 选择你的项目
3. 点击左侧菜单 **SQL Editor**
4. 点击 **New Query**
5. 复制 `SUPABASE_UPDATE_SETUP.sql` 文件的内容
6. 粘贴并点击 **Run** 执行

**✅ 执行成功后，会创建 `app_versions` 表**

### 2. 创建 Storage Bucket

1. 在 Supabase Dashboard 左侧菜单点击 **Storage**
2. 点击 **Create a new bucket**
3. 输入名称：`app-updates`
4. 选择 **Public bucket**（允许公开访问）
5. 点击 **Create bucket**

### 3. 上传更新包

1. 进入 `app-updates` bucket
2. 点击 **Upload file**
3. 上传你的更新包 ZIP 文件（如 `update-1.0.1.zip`）

**获取文件 URL：**
- 点击文件名
- 点击 **Copy URL**
- 得到类似这样的链接：
  ```
  https://你的项目ID.supabase.co/storage/v1/object/public/app-updates/update-1.0.1.zip
  ```

---

## 打包发布流程

### 步骤1：准备更新包

#### 方法A：打包整个应用（首次发布）

```powershell
# 1. 清理旧构建
flutter clean

# 2. 构建 Release 版本
flutter build windows --release

# 3. 生成的文件在：
# build\windows\x64\runner\Release\
```

#### 方法B：打包增量更新（后续更新）

**只打包变化的文件，减小更新包大小：**

```powershell
# 1. 构建新版本
flutter build windows --release

# 2. 进入 Release 目录
cd build\windows\x64\runner\Release

# 3. 创建更新包（只包含必要文件）
# 手动选择需要更新的文件，压缩成 ZIP
```

**通常需要更新的文件：**
- `xinghe_new.exe` - 主程序
- `flutter_windows.dll` - Flutter 引擎
- `data\app.so` - Dart 代码（如果有改动）
- 其他修改过的 DLL 或资源文件

**压缩成 ZIP：**
1. 选中需要更新的文件
2. 右键 → **发送到** → **压缩(zipped)文件夹**
3. 重命名为 `update-1.0.1.zip`

### 步骤2：上传到 Supabase Storage

1. 登录 Supabase Dashboard
2. Storage → `app-updates`
3. 上传 `update-1.0.1.zip`
4. 复制文件 URL

### 步骤3：更新数据库版本信息

在 Supabase SQL Editor 中执行：

```sql
INSERT INTO app_versions (
  version, 
  min_version, 
  force_update, 
  update_package_url,
  update_log,
  file_size,
  is_active
) VALUES (
  '1.0.1',                    -- 新版本号
  '1.0.0',                    -- 最低支持版本
  true,                       -- 是否强制更新
  'https://你的项目ID.supabase.co/storage/v1/object/public/app-updates/update-1.0.1.zip',
  '新增功能：
  - 会员系统
  - 自动更新功能
  
  修复问题：
  - 修复了XXX问题',
  5242880,                    -- 文件大小（字节）
  true                        -- 启用
);
```

**✅ 完成！用户下次启动应用时会自动检测到更新**

---

## 测试更新功能

### 测试场景1：可选更新

```sql
-- 设置为可选更新
UPDATE app_versions 
SET force_update = false 
WHERE version = '1.0.1';
```

**预期效果：**
- 启动应用 → 弹出更新提示
- 用户可以选择"稍后提醒"或"立即更新"

### 测试场景2：强制更新

```sql
-- 设置为强制更新
UPDATE app_versions 
SET force_update = true 
WHERE version = '1.0.1';
```

**预期效果：**
- 启动应用 → 弹出更新提示
- 用户必须点击"立即更新"，无法关闭对话框

### 测试场景3：版本过低（阻止使用）

```sql
-- 设置最低版本为 1.0.1
UPDATE app_versions 
SET min_version = '1.0.1' 
WHERE version = '1.0.2';
```

**预期效果（当前版本 1.0.0）：**
- 启动应用 → 弹出警告
- "版本过低，必须更新"
- 用户必须更新，无法使用旧版本

---

## 版本号管理

### 修改应用版本号

在 `pubspec.yaml` 中修改：

```yaml
version: 1.0.1+2
#         ^^^^^ build number
#        ^^^^^ version name
```

**版本格式：**
- `1.0.0` - 主版本.次版本.修订号
- `+1` - 构建号（可选）

### 版本对比规则

```
1.0.0 < 1.0.1    ✅ 需要更新
1.0.1 = 1.0.1    ✅ 已是最新
1.0.2 > 1.0.1    ✅ 无需更新
```

---

## 更新流程图

```
用户启动应用
    ↓
等待 2 秒（让应用完全加载）
    ↓
查询 Supabase app_versions 表
    ↓
获取最新版本信息
    ↓
对比版本号
    ↓
┌─────────────────────────────┐
│ 情况1：无需更新              │ → 正常使用
│ 情况2：可选更新              │ → 弹出对话框（可关闭）
│ 情况3：强制更新              │ → 弹出对话框（不可关闭）
│ 情况4：版本过低（被阻止）    │ → 必须更新才能使用
└─────────────────────────────┘
    ↓ 用户点击"立即更新"
下载更新包（显示进度）
    ↓
解压到临时目录
    ↓
创建更新脚本（.bat）
    ↓
运行更新脚本
    ↓
关闭当前应用
    ↓
替换文件（xinghe_new.exe 等）
    ↓
重新启动应用
    ↓
✅ 更新完成！
```

---

## 文件说明

**核心文件：**
- `lib/core/update/update_info.dart` - 数据模型
- `lib/core/update/update_checker.dart` - 版本检测
- `lib/core/update/update_downloader.dart` - 下载器
- `lib/core/update/update_dialog.dart` - 更新对话框

**配置文件：**
- `SUPABASE_UPDATE_SETUP.sql` - 数据库表结构
- `AUTO_UPDATE_GUIDE.md` - 本文档

---

## 常见问题

### Q: 如何禁用自动更新检查？

A: 在 `home_screen.dart` 中注释掉这段代码：

```dart
@override
void initState() {
  super.initState();
  // 注释掉下面这段代码即可禁用
  // WidgetsBinding.instance.addPostFrameCallback((_) {
  //   UpdateChecker.checkOnStartup(context);
  // });
}
```

### Q: 如何修改检查更新的时机？

A: 默认在应用启动 2 秒后检查，可以修改 `update_checker.dart`：

```dart
static Future<void> checkOnStartup(BuildContext context) async {
  // 修改这里的延迟时间
  await Future.delayed(const Duration(seconds: 5));  // 改为 5 秒
  // ...
}
```

### Q: 更新失败怎么办？

A: 检查以下几点：
1. ✅ 网络连接正常
2. ✅ Supabase Storage 文件可访问
3. ✅ 更新包 ZIP 格式正确
4. ✅ 应用有写入权限

### Q: 如何回滚版本？

A: 在 Supabase 中禁用新版本：

```sql
UPDATE app_versions 
SET is_active = false 
WHERE version = '1.0.1';
```

### Q: 可以跳过某个版本吗？

A: 用户可以点击"稍后提醒"（仅可选更新时），但无法永久跳过。如需实现，需修改代码添加"跳过此版本"功能。

---

## 🎉 完成！

现在你的应用已经具备完整的自动更新功能了！

**下一步：**
1. ✅ 在 Supabase 中创建表和 Storage
2. ✅ 测试更新流程
3. ✅ 发布第一个更新版本

**有问题？**
- 查看应用日志（F12 打开 DevTools）
- 检查 Supabase Dashboard 中的数据
- 确认 Storage 文件 URL 正确
