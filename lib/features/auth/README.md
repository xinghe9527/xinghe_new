# 星河 R·O·S 会员系统

## 功能概述

完整的用户认证和会员管理系统，对接 `https://api.xhaigc.cn` API。

## 核心功能

### 1. 侧边栏用户头像 (UserHeaderWidget)

- **未登录状态**：
  - 显示默认头像和"点击登录"文字
  - 点击后弹出登录/注册对话框
  
- **已登录状态**：
  - 显示用户名和会员过期时间
  - 点击头像可选择并上传新头像（使用 image_picker）
  - 会员过期时显示红色警告

### 2. 登录/注册对话框 (LoginRegisterDialog)

#### 登录功能
- 输入邮箱和密码
- "记住我"选项（保存凭据到本地）
- 自动验证会员是否过期

#### 注册功能
- 输入用户名、邮箱、密码、邀请码
- 邀请码验证逻辑：
  1. 查询 `invitation_codes` 集合
  2. 验证 `code` 是否存在且 `is_used == false`
  3. 根据 `duration_days` 计算会员过期时间
  4. 注册成功后将邀请码标记为已使用
- 邮箱唯一性检查

### 3. 持久化与自动登录

- 使用 `shared_preferences` 保存认证状态
- 应用启动时自动检测：
  - Token 有效性
  - 会员是否过期
  - 自动恢复登录状态
- "记住我"功能保存账号密码

## 文件结构

```
lib/features/auth/
├── domain/
│   └── models/
│       ├── user.dart              # 用户模型
│       ├── auth_state.dart        # 认证状态模型
│       └── invitation_code.dart   # 邀请码模型
├── data/
│   ├── auth_api_service.dart      # API 服务（对接后端）
│   └── auth_storage_service.dart  # 本地存储服务
└── presentation/
    ├── auth_provider.dart         # 状态管理
    └── widgets/
        ├── user_header_widget.dart        # 侧边栏用户头像
        └── login_register_dialog.dart     # 登录/注册对话框
```

## API 接口

### 基础 URL
```
https://api.xhaigc.cn
```

### 接口列表

1. **验证邀请码**
   - GET `/invitation_codes?code={code}&is_used=false`

2. **检查邮箱**
   - GET `/users?email={email}`

3. **注册用户**
   - POST `/users`
   - Body: `{ username, email, password, expire_date, created_at }`

4. **核销邀请码**
   - PUT `/invitation_codes/{id}`
   - Body: `{ is_used: true, used_at, used_by }`

5. **登录**
   - GET `/users?email={email}&password={password}`

6. **更新头像**
   - PUT `/users/{id}`
   - Body: `{ avatar: url }`

7. **获取用户信息**
   - GET `/users/{id}`

## 使用方法

### 1. 在 main.dart 中初始化

```dart
import 'features/auth/presentation/auth_provider.dart';

// 全局认证状态管理器
final AuthProvider authProvider = AuthProvider();

void main() async {
  // ... 其他初始化代码
  
  // 初始化认证状态（自动登录）
  await authProvider.initialize();
  
  runApp(const XingheApp());
}
```

### 2. 在侧边栏使用 UserHeaderWidget

```dart
import 'package:xinghe_new/features/auth/presentation/widgets/user_header_widget.dart';
import 'package:xinghe_new/main.dart';

// 在侧边栏中
UserHeaderWidget(authProvider: authProvider)
```

### 3. 监听认证状态

```dart
ListenableBuilder(
  listenable: authProvider,
  builder: (context, _) {
    if (authProvider.isAuthenticated) {
      final user = authProvider.currentUser;
      // 已登录逻辑
    } else {
      // 未登录逻辑
    }
  },
)
```

## 数据模型

### User
```dart
{
  id: String,
  username: String,
  email: String,
  avatar: String?,
  expireDate: DateTime,
  createdAt: DateTime,
}
```

### InvitationCode
```dart
{
  id: String,
  code: String,
  durationDays: int,
  isUsed: bool,
  usedAt: DateTime?,
  usedBy: String?,
}
```

### AuthState
```dart
{
  user: User?,
  token: String?,
  isAuthenticated: bool,
}
```

## 注意事项

1. **会员过期检查**：登录时自动检查，过期则拦截并提示续费
2. **邀请码唯一性**：一个邀请码只能使用一次
3. **邮箱唯一性**：一个邮箱只能注册一个账号
4. **头像上传**：需要集成 OSS 上传服务（当前为占位实现）
5. **Token 管理**：当前使用简化的 token 生成，生产环境需要使用真实的 JWT

## TODO

- [ ] 集成 OSS 头像上传服务
- [ ] 实现真实的 JWT Token 认证
- [ ] 添加密码加密（bcrypt）
- [ ] 添加忘记密码功能
- [ ] 添加会员续费功能
- [ ] 添加用户资料编辑功能
