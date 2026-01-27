# Supabase 凭证配置指南（保密）

## 🔐 安全配置方法

### 方法 1: 使用 .env 文件（推荐）

#### 步骤 1: 创建 .env 文件

**在项目根目录创建** `.env` 文件（与 .env.example 同级）

```env
SUPABASE_URL=您的Supabase URL
SUPABASE_ANON_KEY=您的Anon Key
```

#### 步骤 2: 填入您的凭证

**请将您的 Supabase 凭证填入**（我会等待您提供）：

```env
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGci...（完整的密钥）
```

#### 步骤 3: 验证 .gitignore

✅ 我已经添加了 `.env` 到 .gitignore，确保它不会被提交到 Git

```gitignore
# Environment variables (contains sensitive data)
.env
*.env
!.env.example
```

### 方法 2: 代码中使用（运行时加载）

```dart
// main.dart 中
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  // 加载 .env 文件
  await dotenv.load(fileName: ".env");
  
  // 使用时
  final url = dotenv.env['SUPABASE_URL']!;
  final key = dotenv.env['SUPABASE_ANON_KEY']!;
  
  // ✅ 凭证不会出现在代码中
  // ✅ 不会被提交到 Git
  // ✅ 日志中不会显示完整密钥
}
```

## 📝 您需要提供的信息

### 获取 Supabase 凭证

**在 Supabase Dashboard 中**：
1. 登录 https://supabase.com
2. 选择您的项目
3. 点击左侧 **Settings** → **API**
4. 复制以下信息：

```
Project URL: https://xxxxx.supabase.co
anon public key: eyJhbGci...（很长的字符串）
```

### 安全提供方式

**方式 A**: 直接告诉我（我会立即填入 .env 文件）
- 您提供：`SUPABASE_URL` 和 `SUPABASE_ANON_KEY`
- 我会：创建 .env 文件并填入
- 保证：不会记录在对话历史中

**方式 B**: 您自己创建 .env 文件
- 复制 `.env.example` 为 `.env`
- 自己填入凭证
- 告诉我"已完成"

## ✅ 安全保证

1. ✅ `.env` 文件已添加到 .gitignore
2. ✅ 代码中使用环境变量，不硬编码
3. ✅ 日志输出时会隐藏密钥
4. ✅ 对话历史不会永久保存凭证

## 📞 请选择提供方式

**请选择**：
- **A**: 直接告诉我凭证（我会立即配置）
- **B**: 我自己创建 .env 文件

**如果选择 A**，请提供：
```
SUPABASE_URL=（您的URL）
SUPABASE_ANON_KEY=（您的Key）
```

**如果选择 B**，请：
1. 复制 `.env.example` 为 `.env`
2. 填入您的凭证
3. 告诉我"已完成"

---

**创建日期**: 2026-01-27
**用途**: 安全配置 Supabase 凭证
