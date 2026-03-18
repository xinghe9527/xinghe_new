"""
测试 auto_vidu_v2.py 新增的无水印下载功能
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from auto_vidu_v2 import ViduAutomation, VIDU_PROFILE_DIR

def main():
    auto = ViduAutomation(profile_dir=VIDU_PROFILE_DIR)
    
    print("启动浏览器连接...")
    if not auto.start():
        print("❌ 无法连接浏览器")
        return
    
    # 用一个未投稿的creation测试
    # 从之前的调查知道 3210177418133087 是未投稿的
    creation_id = "3210177418133087"
    task_id = "3210177405977070"
    save_path = os.path.join(os.path.dirname(__file__), "downloads", "test_watermark_free.mp4")
    
    print(f"\n测试 download_watermark_free:")
    print(f"  creation_id: {creation_id}")
    print(f"  save_path: {save_path}")
    
    result = auto.download_watermark_free(
        creation_id=creation_id,
        save_path=save_path,
        task_id=task_id,
        max_wait=120,
    )
    
    print(f"\n结果: {result}")
    
    if result.get('success') and result.get('video_path'):
        size = os.path.getsize(result['video_path'])
        print(f"\n✅ 下载成功! 文件大小: {size / 1024 / 1024:.2f} MB")
    elif result.get('success'):
        print(f"\n✅ 获取URL成功但未下载: {result.get('video_url', '')[:100]}")
    else:
        print(f"\n❌ 失败: {result.get('error')}")

if __name__ == '__main__':
    main()
