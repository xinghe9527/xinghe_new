# 🚀 自动更新功能 - 快速开始

## 第一步：配置 Supabase（5分钟）

### 1. 创建数据库表

```bash
# 1. 打开 Supabase Dashboard
# 2. SQL Editor → New Query
# 3. 复制并执行 SUPABASE_UPDATE_SETUP.sql
```

### 2. 创建 Storage Bucket

```bash
# 1. Storage → Create bucket
# 2. 名称: app-updates
# 3. 类型: Public
```

---

## 第二步：发布第一个版本（10分钟）

### 1. 打包应用

```powershell
flutter build windows --release
```

### 2. 创建更新包

```powershell
# 进入 Release 目录
cd build\windows\x64\runner\Release

# 压缩需要更新的文件
# - xinghe_new.exe
# - flutter_windows.dll
# - data\app.so
# 压缩成: update-1.0.1.zip
```

### 3. 上传到 Supabase

```bash
# 1. Supabase Storage → app-updates
# 2. Upload file → update-1.0.1.zip
# 3. 复制文件 URL
```

### 4. 插入版本信息

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
  '1.0.1',
  '1.0.0',
  true,
  'https://你的Supabase项目.supabase.co/storage/v1/object/public/app-updates/update-1.0.1.zip',
  '测试更新功能',
  5242880,
  true
);
```

---

## 第三步：测试（2分钟）

### 1. 运行应用

```powershell
flutter run
```

### 2. 观察日志

```
✅ 应启动
✅ 2秒后开始检查更新
✅ 发现新版本
✅ 弹出更新对话框
```

### 3. 点击"立即更新"

```
✅ 下载更新包
✅ 显示进度
✅ 解压文件
✅ 替换文件
✅ 重启应用
```

---

## 完成！ 🎉

现在你的应用已经支持自动更新了！

**详细文档：**
- `AUTO_UPDATE_GUIDE.md` - 完整使用指南
- `SUPABASE_UPDATE_SETUP.sql` - 数据库脚本

**需要帮助？**
- 查看应用日志
- 检查 Supabase Dashboard
- 确认文件 URL 正确
