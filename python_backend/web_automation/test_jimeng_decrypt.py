#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""测试解密即梦 Chromium 加密 cookie"""
import sqlite3
import os
import sys
import shutil
import json
import base64
import io
import ctypes
import ctypes.wintypes

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

class DATA_BLOB(ctypes.Structure):
    _fields_ = [
        ('cbData', ctypes.wintypes.DWORD),
        ('pbData', ctypes.POINTER(ctypes.c_char)),
    ]

def dpapi_decrypt(encrypted):
    """用 Windows DPAPI 解密"""
    blob_in = DATA_BLOB(
        len(encrypted),
        ctypes.create_string_buffer(encrypted, len(encrypted))
    )
    blob_out = DATA_BLOB()
    
    if ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(blob_in), None, None, None, None, 0,
        ctypes.byref(blob_out)
    ):
        result = ctypes.string_at(blob_out.pbData, blob_out.cbData)
        ctypes.windll.kernel32.LocalFree(blob_out.pbData)
        return result
    return None

def get_encryption_key(profile_dir):
    """从 Local State 获取 Chromium 加密密钥"""
    local_state_path = os.path.join(profile_dir, 'Local State')
    if not os.path.exists(local_state_path):
        print(f"Local State 不存在: {local_state_path}")
        return None
    
    with open(local_state_path, 'r', encoding='utf-8') as f:
        local_state = json.load(f)
    
    encrypted_key = base64.b64decode(
        local_state['os_crypt']['encrypted_key']
    )
    # 去掉 "DPAPI" 前缀（5 bytes）
    encrypted_key = encrypted_key[5:]
    
    # 用 DPAPI 解密密钥
    decrypted_key = dpapi_decrypt(encrypted_key)
    if decrypted_key:
        print(f"✅ 获取到加密密钥 ({len(decrypted_key)} bytes)")
    return decrypted_key

def decrypt_cookie_value(encrypted_value, key):
    """解密 Chromium v10/v20 加密的 cookie"""
    try:
        # v10 或 v20 前缀
        prefix = encrypted_value[:3]
        if prefix in (b'v10', b'v20'):
            # AES-256-GCM
            nonce = encrypted_value[3:15]  # 12 bytes
            ciphertext = encrypted_value[15:]
            
            try:
                from cryptography.hazmat.primitives.ciphers.aead import AESGCM
                aesgcm = AESGCM(key)
                decrypted = aesgcm.decrypt(nonce, ciphertext, None)
                return decrypted.decode('utf-8')
            except ImportError:
                print("需要安装 cryptography: pip install cryptography")
                return None
        else:
            # 旧版 DPAPI 直接加密
            result = dpapi_decrypt(encrypted_value)
            if result:
                return result.decode('utf-8')
    except Exception as e:
        print(f"解密失败: {e}")
    return None

# 主逻辑
profile = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                       'jimeng_web_video_plugin_seedance_2_0', '.jimeng_cdp_profile')

print(f"Profile: {profile}\n")

# 获取加密密钥
key = get_encryption_key(profile)
if not key:
    print("❌ 无法获取加密密钥")
    sys.exit(1)

# 读取 sessionid
cookie_path = os.path.join(profile, 'Default', 'Network', 'Cookies')
tmp = cookie_path + '.tmp_decrypt'
shutil.copy2(cookie_path, tmp)

conn = sqlite3.connect(tmp)
cur = conn.cursor()
cur.execute(
    "SELECT name, value, encrypted_value, host_key FROM cookies "
    "WHERE name = 'sessionid' AND host_key LIKE '%jianying%'"
)
rows = cur.fetchall()
conn.close()
os.remove(tmp)

for r in rows:
    name, value, encrypted, host = r
    if value:
        print(f"\n✅ sessionid (明文): {value[:20]}...{value[-8:]}")
    elif encrypted:
        decrypted = decrypt_cookie_value(encrypted, key)
        if decrypted:
            print(f"\n✅ sessionid (解密): {decrypted[:20]}...{decrypted[-8:]}")
            print(f"   长度: {len(decrypted)}")
            print(f"   host: {host}")
        else:
            print(f"\n❌ sessionid 解密失败")
