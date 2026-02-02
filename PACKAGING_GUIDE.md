# 星橙AI动漫制作 - 完整打包发布指南

## 📋 目录

1. [打包成 EXE](#第一步打包成-exe)
2. [制作安装程序](#第二步制作安装程序-inno-setup)
3. [测试安装](#第三步测试安装)
4. [发布更新版本](#第四步发布更新版本)
5. [测试自动更新](#第五步测试自动更新)

---

## 第一步：打包成 EXE

### 1. 修改版本号

在 `pubspec.yaml` 中：

```yaml
version: 1.0.0+1
#        ^^^^^ 版本名称（显示给用户）
#             ^ 构建号
```

### 2. 构建 Release 版本

```powershell
# 清理旧的构建文件
flutter clean

# 构建 Windows Release 版本
flutter build windows --release
```

**⏱️ 耗时：约 2-5 分钟**

### 3. 查看构建结果

构建完成后，文件位于：

```
build\windows\x64\runner\Release\
├── xinghe_new.exe          ← 主程序
├── flutter_windows.dll     ← Flutter 引擎
├── data\                   ← 应用数据
│   ├── app.so             ← Dart 代码
│   ├── flutter_assets\    ← 资源文件
│   └── icudtl.dat
└── [其他 DLL 文件]
```

**⚠️ 注意：** 需要整个 `Release` 文件夹的所有文件，不能只复制 exe！

---

## 第二步：制作安装程序 (Inno Setup)

### 1. 安装 Inno Setup

你说你已经安装了 Inno Setup，确认一下：

```powershell
# 查找 Inno Setup 安装路径
# 通常在：C:\Program Files (x86)\Inno Setup 6\
```

如果没安装：
- 下载：https://jrsoftware.org/isdl.php
- 安装最新版本

### 2. 创建安装脚本

创建文件：`installer-script.iss`

```iss
; 星橙AI动漫制作 - Inno Setup 安装脚本

#define MyAppName "星橙AI动漫制作"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "星橙AI"
#define MyAppExeName "xinghe_new.exe"

[Setup]
; 应用信息
AppId={{YOUR-UNIQUE-APP-ID}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\XingheAI
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; 输出设置
OutputDir=installer_output
OutputBaseFilename=星橙AI动漫制作_Setup_{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes

; 图标和界面
SetupIconFile=assets\logo.png
WizardStyle=modern

; 权限
PrivilegesRequired=admin

; 架构
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "chinese"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项:"; Flags: unchecked

[Files]
; 复制整个 Release 目录
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
```

**⚠️ 重要：** 修改这行：

```iss
AppId={{YOUR-UNIQUE-APP-ID}}
```

生成唯一 ID：
1. 打开 Inno Setup
2. Tools → Generate GUID
3. 复制生成的 GUID 替换 `YOUR-UNIQUE-APP-ID`

### 3. 编译安装程序

**方法1：使用 Inno Setup GUI**

1. 打开 Inno Setup Compiler
2. File → Open → 选择 `installer-script.iss`
3. Build → Compile
4. 等待编译完成（约 30 秒）

**方法2：使用命令行**

```powershell
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer-script.iss
```

### 4. 查看结果

编译完成后，安装程序位于：

```
installer_output\
└── 星橙AI动漫制作_Setup_1.0.0.exe   ← 这就是安装程序！
```

**文件大小：** 约 50-100 MB（包含了所有 Flutter 依赖）

---

## 第三步：测试安装

### 1. 运行安装程序

双击 `星橙AI动漫制作_Setup_1.0.0.exe`

### 2. 安装过程

```
1. 欢迎页面 → 下一步
2. 选择安装位置（默认：C:\Program Files\XingheAI）
3. 选择是否创建桌面快捷方式
4. 开始安装
5. 完成（可选勾选"启动应用"）
```

### 3. 验证安装

- ✅ 检查安装目录是否有所有文件
- ✅ 运行应用是否正常
- ✅ 桌面快捷方式是否可用
- ✅ 开始菜单项是否正常

---

## 第四步：发布更新版本

### 现在你有了 1.0.0 版本，可以发布 1.0.1 更新了！

### 1. 修改代码（添加新功能）

```dart
// 比如修改某个功能...
```

### 2. 修改版本号

```yaml
version: 1.0.1+1
```

### 3. 重新构建

```powershell
flutter clean
flutter build windows --release
```

### 4. 创建更新包

**只打包变化的文件：**

```powershell
cd build\windows\x64\runner\Release

# 创建一个新文件夹
mkdir update_files

# 复制需要更新的文件
copy xinghe_new.exe update_files\
copy flutter_windows.dll update_files\
xcopy /E data update_files\data\

# 压缩成 ZIP
# 右键 update_files → 发送到 → 压缩文件
# 重命名为: update-1.0.1.zip
```

### 5. 上传到 Supabase

1. 登录 Supabase Dashboard
2. Storage → app-updates
3. 上传 `update-1.0.1.zip`
4. 复制 URL

### 6. 插入版本信息

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
  'https://你的项目.supabase.co/storage/v1/object/public/app-updates/update-1.0.1.zip',
  '新增自动更新功能',
  5242880,
  true
);
```

---

## 第五步：测试自动更新

### 1. 运行已安装的 1.0.0 版本

```
C:\Program Files\XingheAI\xinghe_new.exe
```

### 2. 观察日志

应该看到：

```
✅ 应用启动
✅ 检查更新...
✅ 发现新版本 1.0.1
✅ 弹出更新对话框
```

### 3. 点击"立即更新"

```
✅ 下载更新包（显示进度）
✅ 解压文件
✅ 替换文件
✅ 重启应用
```

### 4. 验证更新

重启后，检查版本号：

```dart
// 在应用中显示版本号
PackageInfo.fromPlatform().then((info) {
  print('当前版本: ${info.version}');  // 应该是 1.0.1
});
```

---

## 隐藏 Flutter 痕迹

### 方法1：修改 EXE 图标和属性

1. **修改图标：**
   - 在 `windows/runner/resources/app_icon.ico` 替换图标
   - 重新构建

2. **修改文件属性：**
   ```cmake
   # 在 windows/runner/CMakeLists.txt 中添加
   set(APP_VERSION "1.0.0")
   set(APP_COMPANY "星橙AI")
   set(APP_COPYRIGHT "Copyright (C) 2026")
   ```

### 方法2：Inno Setup 隐藏安装细节

已经在脚本中实现：
- ✅ 不显示组件选择（用户看不到 DLL 列表）
- ✅ 使用 SolidCompression（压缩所有文件）
- ✅ 自定义安装目录名称

### 方法3：重命名文件（高级）

```powershell
# 重命名 flutter_windows.dll
rename flutter_windows.dll xinghe_core.dll

# 但需要修改 exe 导入表（较复杂，不推荐）
```

---

## 快速参考

### 打包命令

```powershell
# 1. 清理
flutter clean

# 2. 构建
flutter build windows --release

# 3. 编译安装程序
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer-script.iss
```

### 文件位置

```
构建结果：build\windows\x64\runner\Release\
安装程序：installer_output\星橙AI动漫制作_Setup_1.0.0.exe
```

---

## 常见问题

### Q: 安装后打开闪退？

A: 检查：
1. ✅ 是否复制了所有文件（包括 data 文件夹）
2. ✅ 是否缺少 VC++ 运行库
3. ✅ 是否有管理员权限

### Q: 如何减小安装包大小？

A: 
1. 使用 `--split-debug-info` 构建
2. 移除不需要的资源文件
3. Inno Setup 使用最大压缩

### Q: 如何添加自定义安装界面？

A: 在 Inno Setup 脚本中添加：
```iss
[Files]
Source: "banner.bmp"; Flags: dontcopy
[Code]
// 自定义页面代码
```

---

## 🎉 完成！

现在你知道如何：
1. ✅ 打包成 EXE
2. ✅ 制作安装程序
3. ✅ 发布更新
4. ✅ 测试自动更新

**下一步：** 完成第一个版本的打包！
