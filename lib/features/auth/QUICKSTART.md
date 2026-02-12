# 快速开始指南

## 1. 已完成的集成

✅ 所有必要的文件已创建并集成到项目中：

- **数据模型**：User, AuthState, InvitationCode
- **API 服务**：对接 https://api.xhaigc.cn
- **状态管理**：AuthProvider（全局单例）
- **UI 组件**：UserHeaderWidget, LoginRegisterDialog
- **持久化**：SharedPreferences 自动登录
- **头像上传**：集成 OSS 上传服务

## 2. 如何运行

### 方式 1: 直接运行
```bash
flutter run
```

### 方式 2: 调试模式
```bash
flutter run -d windows --debug
```

## 3. 首次使用流程

1. **启动应用**
   - 应用会自动初始化认证系统
   - 如果之前登录过且勾选了"记住我"，会自动登录

2. **注册新用户**
   - 点击左侧边栏顶部的"点击登录"
   - 切换到"注册"标签
   - 填写用户名、邮箱、密码、邀请码
   - 点击"注册"

3. **登录**
   - 点击"点击登录"
   - 输入邮箱和密码
   - 勾选"记住我"（可选）
   - 点击"登录"

4. **更新头像**
   - 登录后点击侧边栏的头像
   - 选择图片
   - 自动上传到 OSS

## 4. 后端 API 要求

### 数据库集合

#### users 集合
```json
{
  "_id": "ObjectId",
  "username": "string",
  "email": "string",
  "password": "string",
  "avatar": "string (optional)",
  "expire_date": "ISODate",
  "created_at": "ISODate"
}
```

#### invitation_codes 集合
```json
{
  "_id": "ObjectId",
  "code": "string",
  "duration_days": "number",
  "is_used": "boolean",
  "used_at": "ISODate (optional)",
  "used_by": "string (optional)"
}
```

### 创建测试邀请码

在 MongoDB 中执行：
```javascript
db.invitation_codes.insertOne({
  code: "XINGHE2024",
  duration_days: 365,
  is_used: false
});
```

## 5. 配置检查清单

- [x] pubspec.yaml 已包含所有依赖
- [x] main.dart 已初始化 authProvider
- [x] home_screen.dart 已集成 UserHeaderWidget
- [x] API 地址配置：https://api.xhaigc.cn
- [x] OSS 上传服务已集成

## 6. 测试账号

建议创建以下测试数据：

### 测试邀请码
```
XINGHE2024 - 365天会员
TEST30DAYS - 30天会员
TRIAL7DAYS - 7天试用
```

### 测试用户
```
邮箱: admin@xinghe.com
密码: admin123
用户名: 管理员
```

## 7. 常用操作

### 清除本地登录状态
```dart
// 在 Dart DevTools Console 中执行
final prefs = await SharedPreferences.getInstance();
await prefs.clear();
```

### 查看当前登录状态
```dart
print('是否登录: ${authProvider.isAuthenticated}');
print('当前用户: ${authProvider.currentUser?.username}');
print('会员过期: ${authProvider.currentUser?.expireDate}');
```

### 手动刷新用户信息
```dart
await authProvider.refreshUserInfo();
```

## 8. 下一步

### 推荐功能扩展

1. **会员续费**
   - 添加续费页面
   - 集成支付接口
   - 自动延长会员时间

2. **用户资料编辑**
   - 修改用户名
   - 修改密码
   - 绑定手机号

3. **忘记密码**
   - 邮箱验证码
   - 重置密码

4. **会员权益**
   - 不同等级会员
   - 功能权限控制
   - 使用量限制

5. **社交功能**
   - 好友系统
   - 作品分享
   - 评论互动

## 9. 故障排除

### 问题：无法连接到 API
**解决方案**：
1. 检查网络连接
2. 确认 API 地址可访问
3. 查看防火墙设置

### 问题：邀请码验证失败
**解决方案**：
1. 确认后端有可用邀请码
2. 检查邀请码格式
3. 查看 API 返回的错误信息

### 问题：自动登录失败
**解决方案**：
1. 清除本地缓存重新登录
2. 检查会员是否过期
3. 验证 Token 有效性

### 问题：头像上传失败
**解决方案**：
1. 检查 OSS 配置
2. 确认网络连接
3. 查看文件大小限制

## 10. 技术支持

如有问题，请查看：
- [README.md](./README.md) - 完整功能文档
- [TESTING.md](./TESTING.md) - 测试指南
- 控制台日志输出

## 11. 性能优化建议

1. **图片压缩**：头像上传前自动压缩到 512x512
2. **缓存策略**：用户信息本地缓存
3. **懒加载**：头像图片懒加载
4. **错误重试**：网络请求失败自动重试

## 12. 安全建议

1. **密码加密**：生产环境使用 bcrypt
2. **HTTPS**：确保所有 API 请求使用 HTTPS
3. **Token 刷新**：实现 Token 自动刷新机制
4. **输入验证**：前端和后端双重验证
