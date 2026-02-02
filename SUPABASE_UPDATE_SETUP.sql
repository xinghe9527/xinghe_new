-- ========================================
-- 星橙AI动漫制作 - 自动更新功能
-- Supabase 数据库表结构
-- ========================================

-- 创建应用版本表
CREATE TABLE IF NOT EXISTS app_versions (
  id SERIAL PRIMARY KEY,
  version VARCHAR(20) NOT NULL UNIQUE,       -- 版本号，如: 1.0.1
  min_version VARCHAR(20),                    -- 最低支持版本，如: 1.0.0
  force_update BOOLEAN DEFAULT false,         -- 是否强制更新
  update_package_url TEXT NOT NULL,          -- 更新包下载链接（ZIP）
  full_package_url TEXT,                      -- 完整安装包链接（EXE，可选）
  update_log TEXT,                            -- 更新日志
  file_size BIGINT,                           -- 更新包文件大小（字节）
  file_list TEXT[],                           -- 需要更新的文件列表
  created_at TIMESTAMP DEFAULT NOW(),
  is_active BOOLEAN DEFAULT true,             -- 是否启用此版本
  CONSTRAINT version_format CHECK (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

-- 创建索引
CREATE INDEX idx_app_versions_active ON app_versions(is_active, created_at DESC);

-- 添加注释
COMMENT ON TABLE app_versions IS '应用版本管理表';
COMMENT ON COLUMN app_versions.version IS '版本号，格式: x.y.z';
COMMENT ON COLUMN app_versions.min_version IS '最低支持版本，低于此版本的用户必须更新';
COMMENT ON COLUMN app_versions.force_update IS '是否强制更新';
COMMENT ON COLUMN app_versions.update_package_url IS 'Supabase Storage 中的更新包 URL';
COMMENT ON COLUMN app_versions.update_log IS '更新日志，支持多行文本';
COMMENT ON COLUMN app_versions.file_size IS '更新包大小（字节）';
COMMENT ON COLUMN app_versions.is_active IS '是否启用，只有启用的版本才会被检测到';

-- ========================================
-- 插入示例数据
-- ========================================

-- 示例：插入版本 1.0.0（当前版本）
INSERT INTO app_versions (
  version, 
  min_version, 
  force_update, 
  update_package_url,
  update_log,
  file_size,
  is_active
) VALUES (
  '1.0.0',
  '1.0.0',
  false,
  'https://你的项目ID.supabase.co/storage/v1/object/public/app-updates/update-1.0.0.zip',
  '初始版本',
  0,
  false  -- 设为 false，不触发更新
);

-- 示例：插入版本 1.0.1（新版本）
-- 注意：实际使用时需要替换 URL 为真实的 Supabase Storage 链接
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
  true,  -- 强制更新
  'https://你的项目ID.supabase.co/storage/v1/object/public/app-updates/update-1.0.1.zip',
  '新增功能：
  - 会员系统
  - 自动更新功能
  
  修复问题：
  - 修复了键盘输入问题
  - 优化了性能',
  5242880,  -- 5MB
  true  -- 启用此版本，应用会检测到此更新
);

-- ========================================
-- 设置 RLS（Row Level Security）策略
-- ========================================

-- 启用 RLS
ALTER TABLE app_versions ENABLE ROW LEVEL SECURITY;

-- 允许所有人读取（应用需要查询最新版本）
CREATE POLICY "允许所有人读取版本信息"
ON app_versions FOR SELECT
TO public
USING (is_active = true);

-- 只允许管理员插入/更新/删除（需要认证）
CREATE POLICY "只允许认证用户修改版本信息"
ON app_versions FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);
