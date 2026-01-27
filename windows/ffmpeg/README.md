# FFmpeg 目录

## 📁 用途

此目录存放 FFmpeg 可执行文件，用于：
- 图片转视频（3秒静态视频）
- 视频合并
- 提取视频首帧

## 📥 获取 FFmpeg

### 自动下载（推荐）

在项目根目录运行：
```powershell
.\download_ffmpeg.ps1
```

### 手动下载

1. 访问：https://github.com/BtbN/FFmpeg-Builds/releases
2. 下载：`ffmpeg-master-latest-win64-gpl.zip`
3. 解压后将 `ffmpeg.exe` 复制到此目录

## ✅ 验证

运行以下命令测试：
```powershell
.\windows\ffmpeg\ffmpeg.exe -version
```

## 📦 打包说明

- FFmpeg 会自动打包到 Windows EXE 中
- 文件大小约 100MB
- 运行时会自动找到打包的 FFmpeg

---

**注意**: ffmpeg.exe 文件较大（~100MB），不要提交到 Git
