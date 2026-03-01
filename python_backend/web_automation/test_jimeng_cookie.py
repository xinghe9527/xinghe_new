#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""测试从即梦插件 profile 中读取 sessionid"""
import sqlite3
import os
import sys
import shutil
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 检查插件的 cookie 数据库
profile = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                       'jimeng_web_video_plugin_seedance_2_0', '.jimeng_cdp_profile')

print(f"Profile 目录: {profile}")
print(f"存在: {os.path.exists(profile)}")

paths = [
    os.path.join(profile, 'Default', 'Network', 'Cookies'),
    os.path.join(profile, 'Default', 'Cookies'),
]

for p in paths:
    if os.path.exists(p):
        print(f"\n找到 cookie 数据库: {p}")
        tmp = p + '.tmp_test'
        shutil.copy2(p, tmp)
        conn = sqlite3.connect(tmp)
        cur = conn.cursor()
        
        # 查看所有 jianying/jimeng 相关的 cookie
        cur.execute(
            "SELECT name, value, encrypted_value, host_key FROM cookies "
            "WHERE host_key LIKE '%jianying%' OR host_key LIKE '%jimeng%' "
            "ORDER BY name LIMIT 30"
        )
        rows = cur.fetchall()
        print(f"即梦相关 cookie 数量: {len(rows)}")
        
        for r in rows:
            name = r[0]
            value = r[1]
            encrypted = r[2]
            host = r[3]
            
            if value:
                display_val = value[:30] + '...' if len(value) > 30 else value
            elif encrypted:
                display_val = f'[加密, {len(encrypted)} bytes]'
            else:
                display_val = '[空]'
            
            marker = ' ★' if name == 'sessionid' else ''
            print(f"  {name} = {display_val} (host: {host}){marker}")
        
        conn.close()
        os.remove(tmp)
    else:
        print(f"不存在: {p}")
