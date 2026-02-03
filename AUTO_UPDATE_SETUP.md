# 自动更新功能 - 完整配置指南（模式3：强制更新）

## ✅ 已完成的实现

### 核心文件
- ✅ `lib/core/update/update_service.dart` - 版本检测和更新服务
- ✅ `lib/features/home/presentation/home_screen.dart` - 集成启动检查

### 功能特性
- ✅ 应用启动 2 秒后自动检查更新
- ✅ 强制更新模式：版本低于 min_version 时阻止使用
- ✅ 不可关闭的更新对话框（强制更新时）
- ✅ 打开浏览器下载新安装包
- ✅ 完全基于 Supabase

---

## 🚀 快速开始（5分钟配置）

### 步骤1：创建 Supabase 表

1. 登录 [Supabase Dashboard](https://app.supabase.com/)
2. 选择项目：`tnmbprizergdjrirehyi`
3. 左侧菜单 → **SQL Editor**
4. 点击 **New Query**
5. 复制下面的 SQL 并执行：

```sql
-- 创建版本表
CREATE TABLE IF NOT EXISTS app_versions (
  id SERIAL PRIMARY KEY,
  version VARCHAR(20) NOT NULL UNIQUE,
  min_version VARCHAR(20),
  force_update BOOLEAN DEFAULT false,
  update_package_url TEXT NOT NULL,
  update_log TEXT,
  file_size BIGINT,
  created_at TIMESTAMP DEFAULT NOW(),
  is_active BOOLEAN DEFAULT true
);

-- 创建索引
CREATE INDEX idx_app_versions_active ON app_versions(is_active, created_at DESC);

-- 启用 RLS
ALTER TABLE app_versions ENABLE ROW LEVEL SECURITY;

-- 允许所有人读取
CREATE POLICY "允许读取激活的版本"
ON app_versions FOR SELECT
TO public
USING (is_active = true);

-- 插入初始版本（不激活，避免触发更新）
INSERT INTO app_versions (
  version, 
  min_version, 
  force_update, 
  update_package_url,
  update_log,
  is_active
) VALUES (
  '1.0.0',
  '1.0.0',
  false,
  'https://你的网站.com/星橙AI动漫制作_Setup_1.0.0.exe',
  '初始版本',
  false  -- 不激活，因为是当前版本
);
```

### 步骤2：创建 Storage Bucket

1. 左侧菜单 → **Storage**
2. 点击 **Create a new bucket**
3. 名称：`app-updates`
4. 选择：**Public bucket**
5. 点击 **Create bucket**

---

## 📦 发布更新版本

### 完整流程

#### 1. 修改版本号

编辑 `pubspec.yaml`：
```yaml
version: 1.0.1+1  # 从 1.0.0 改为 1.0.1
```

#### 2. 构建新版本

```powershell
flutter clean
flutter build windows --release
```

#### 3. 创建新安装包

```powershell
# 编译安装程序
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer-script.iss

# 生成：installer_output\星橙AI动漫制作_Setup_1.0.1.exe
```

#### 4. 上传到 Supabase Storage

```
1. Supabase Dashboard → Storage → app-updates
2. Upload file: 星橙AI动漫制作_Setup_1.0.1.exe
3. 点击文件 → Copy URL
4. 得到：https://tnmbprizergdjrirehyi.supabase.co/storage/v1/object/public/app-updates/星橙AI动漫制作_Setup_1.0.1.exe
```

#### 5. 插入版本信息（强制更新）

在 Supabase SQL Editor 执行：

```sql
INSERT INTO app_versions (
  version, 
  min_version,        -- 🔑 关键：设为当前版本，让旧版本失效
  force_update,       -- 🔑 关键：强制更新
  update_package_url,
  update_log,
  file_size,
  is_active
) VALUES (
  '1.0.1',
  '1.0.1',           -- 🔑 和 version 相同，1.0.0 立即失效
  true,              -- 🔑 强制更新
  'https://tnmbprizergdjrirehyi.supabase.co/storage/v1/object/public/app-updates/星橙AI动漫制作_Setup_1.0.1.exe',
  '新增功能：
- 自动更新系统
- 会员功能准备

修复问题：
- 优化了性能
- 修复了若干 bug',
  58000000,          -- 文件大小（字节），约 58MB
  true               -- 🔑 激活此版本
);
```

**✅ 完成！版本 1.0.0 的用户下次启动时会被强制更新**

---

## 🎬 用户体验流程

### 场景：用户使用版本 1.0.0

```
打开应用
    ↓
等待 2 秒
    ↓
检测版本：1.0.0 < 1.0.1 (min_version)
    ↓
🚫 版本过低！
    ↓
弹出对话框（不可关闭）：
┌─────────────────────────────────┐
│  ⚠️ 版本过低，必须更新            │
│                                 │
│  当前版本：1.0.0                 │
│  最新版本：1.0.1                 │
│                                 │
│  更新内容：                      │
│  - 自动更新系统                  │
│  - 会员功能准备                  │
│                                 │
│  ⚠️ 当前版本过低，必须更新后才能  │
│     使用软件                     │
│                                 │
│          [立即更新] ←           │
└─────────────────────────────────┘
    ↓
用户点击"立即更新"
    ↓
浏览器打开下载链接
    ↓
用户下载新安装包
    ↓
用户运行安装包
    ↓
覆盖安装
    ↓
✅ 更新完成，现在是 1.0.1
```

---

## 🔑 模式3 配置原则

### 每次发布新版本时

**黄金法则：`version` 和 `min_version` 设为相同值**

```sql
-- 版本 1.0.1
version = '1.0.1'
min_version = '1.0.1'  -- ← 让所有 < 1.0.1 的版本失效

-- 版本 1.0.2
version = '1.0.2'
min_version = '1.0.2'  -- ← 让所有 < 1.0.2 的版本失效

-- 版本 2.0.0
version = '2.0.0'
min_version = '2.0.0'  -- ← 让所有 < 2.0.0 的版本失效
```

**效果：**
- ✅ 老版本立即失效
- ✅ 用户必须更新
- ✅ 所有用户保持在最新版本

---

## 🧪 测试自动更新

### 准备工作

1. **安装版本 1.0.0**
   ```
   installer_output\星橙AI动漫制作_Setup_1.0.0.exe
   ```

2. **配置 Supabase（执行上面的 SQL）**

3. **构建版本 1.0.1**
   ```powershell
   # 修改 pubspec.yaml: version: 1.0.1+1
   flutter build windows --release
   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer-script.iss
   ```

4. **上传 1.0.1 安装包到 Supabase Storage**

5. **插入版本信息到 Supabase Database**

### 测试

1. **运行已安装的 1.0.0 版本**
   ```
   C:\Program Files\XingheAI\xinghe_new.exe
   ```

2. **观察：**
   - ✅ 启动 2 秒后弹出更新对话框
   - ✅ 显示"版本过低，必须更新"
   - ✅ 对话框无法关闭（按 ESC 无效）
   - ✅ 只有"立即更新"按钮

3. **点击"立即更新"：**
   - ✅ 浏览器自动打开下载链接
   - ✅ 用户下载新安装包
   - ✅ 运行安装包覆盖安装
   - ✅ 完成！

---

## 📝 SQL 快速参考

### 发布新版本模板

```sql
-- 复制这个模板，每次发布时修改版本号和 URL
INSERT INTO app_versions (
  version, 
  min_version,       -- ⚠️ 改成新版本号
  force_update, 
  update_package_url, -- ⚠️ 改成新文件 URL
  update_log,        -- ⚠️ 改成实际更新内容
  file_size,         -- ⚠️ 改成实际文件大小
  is_active
) VALUES (
  '1.0.X',           -- 新版本号
  '1.0.X',           -- 和上面相同
  true,
  'https://tnmbprizergdjrirehyi.supabase.co/storage/v1/object/public/app-updates/星橙AI动漫制作_Setup_1.0.X.exe',
  '更新内容：\n- 新增XXX\n- 修复YYY',
  58000000,
  true
);
```

### 紧急回滚（如果新版本有 bug）

```sql
-- 禁用有问题的版本
UPDATE app_versions 
SET is_active = false 
WHERE version = '1.0.1';

-- 或者降低最低版本要求
UPDATE app_versions 
SET min_version = '1.0.0'  -- 允许 1.0.0 继续使用
WHERE version = '1.0.1';
```

---

## 🎉 完成！

### ✅ 你现在有了：

1. ✅ 完整的自动更新系统
2. ✅ 强制更新（模式3）
3. ✅ 老版本失效机制
4. ✅ 基于 Supabase（无需额外服务器）

### 📝 核心配置记住：

```sql
version = '最新版本'
min_version = '最新版本'  -- 🔑 相同值 = 老版本失效
force_update = true       -- 🔑 强制更新
is_active = true          -- 🔑 激活
```

---

## 🔧 调试技巧

### 查看更新检测日志

应用启动后，查看控制台：

```
📱 当前版本: 1.0.0
🆕 最新版本: 1.0.1
🔒 最低版本: 1.0.1
🔔 发现新版本
🚫 版本过低，强制更新
```

### 测试不同场景

```sql
-- 场景1：可选更新
UPDATE app_versions SET min_version = '1.0.0', force_update = false WHERE version = '1.0.1';

-- 场景2：强制更新（但允许继续使用）
UPDATE app_versions SET min_version = '1.0.0', force_update = true WHERE version = '1.0.1';

-- 场景3：阻止旧版本（你的需求）
UPDATE app_versions SET min_version = '1.0.1', force_update = true WHERE version = '1.0.1';
```

---

**需要帮你配置 Supabase 吗？还是你自己操作？** 🚀
