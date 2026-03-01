#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""测试即梦视频生成完整流程"""
import sys, os, io, json, time

if hasattr(sys.stdout, 'buffer') and not isinstance(sys.stdout, io.TextIOWrapper):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    except: pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from auto_jimeng import JimengBrowserAPI, build_api_url, JIMENG_BASE_URL

profile = sys.argv[1] if len(sys.argv) > 1 else 'jimeng_web_video_plugin_seedance_2_0/.jimeng_cdp_profile'

api = JimengBrowserAPI(profile_dir=profile)
if not api.start():
    print("启动失败")
    sys.exit(1)

try:
    # 1. 检查登录
    if not api.check_login():
        print("未登录")
        sys.exit(1)
    
    # 2. 获取模型配置，看看有哪些模型
    print("\n📋 获取模型列表...")
    url = build_api_url('/mweb/v1/video_generate/get_common_config')
    data = api._fetch_api(url, 'POST', {})
    if str(data.get('ret')) == '0':
        models = data.get('data', {}).get('model_list', [])
        print(f"   共 {len(models)} 个模型:")
        for m in models:
            name = m.get('name', '')
            model_key = m.get('key', m.get('model', ''))
            desc = m.get('desc', '')[:50]
            print(f"   - {name} (key={model_key}) {desc}")
    
    # 3. 尝试提交一个简单的文生视频任务
    print("\n🎬 提交测试视频生成任务...")
    try:
        result = api.generate_video(
            prompt='一只可爱的小猫在草地上奔跑',
            model='seedance-2.0-fast',
            tool_type='text2video',
            aspect_ratio='16:9',
            resolution='720p',
            duration=5,
        )
        print(f"\n✅ 任务提交成功!")
        print(f"   history_id: {result.get('history_id')}")
        print(f"   完整返回: {json.dumps(result.get('data', {}), ensure_ascii=False)[:500]}")
        
        # 4. 轮询等待（最多等 60 秒，只是测试）
        history_id = result.get('history_id')
        if history_id:
            print(f"\n⏳ 轮询任务状态（最多 60 秒）...")
            poll_result = api.poll_task(history_id, max_wait=60, poll_interval=5)
            print(f"   结果: {json.dumps(poll_result, ensure_ascii=False)[:500]}")
        
    except Exception as e:
        print(f"\n❌ 生成失败: {e}")
        # 打印完整错误信息用于调试
        import traceback
        traceback.print_exc()

finally:
    api.stop()
