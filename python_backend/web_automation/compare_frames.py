"""对比水印版和发布版的视频帧
检查是否有visible watermark差异
"""
from PIL import Image
import numpy as np

# 加载两张截图
task_frame = Image.open(r"D:\new\xinghe\python_backend\web_automation\downloads\frame_task_watermark.png")
pub_frame = Image.open(r"D:\new\xinghe\python_backend\web_automation\downloads\frame_published.png")

print(f"任务水印版: {task_frame.size} {task_frame.mode}")
print(f"发布版: {pub_frame.size} {pub_frame.mode}")

# 转为numpy数组
t = np.array(task_frame).astype(float)
p = np.array(pub_frame).astype(float)

print(f"\n任务帧shape: {t.shape}")
print(f"发布帧shape: {p.shape}")

if t.shape != p.shape:
    print("⚠️ 尺寸不同！")
    # 调整为相同大小
    min_h = min(t.shape[0], p.shape[0])
    min_w = min(t.shape[1], p.shape[1])
    t = t[:min_h, :min_w]
    p = p[:min_h, :min_w]

# 计算差异
diff = np.abs(t - p)
mean_diff = np.mean(diff)
max_diff = np.max(diff)
nonzero_pixels = np.sum(diff.mean(axis=2) > 5)  # 像素差异>5的算不同
total_pixels = diff.shape[0] * diff.shape[1]

print(f"\n--- 全局差异统计 ---")
print(f"平均像素差异: {mean_diff:.2f}")
print(f"最大像素差异: {max_diff:.2f}")
print(f"不同像素数: {nonzero_pixels}/{total_pixels} ({nonzero_pixels/total_pixels*100:.2f}%)")

# 检查典型水印位置（通常在角落）
h, w = t.shape[:2]
regions = {
    "左上角": (0, 0, h//6, w//6),
    "右上角": (0, w*5//6, h//6, w),
    "左下角": (h*5//6, 0, h, w//6),
    "右下角": (h*5//6, w*5//6, h, w),
    "中心": (h//3, w//3, h*2//3, w*2//3),
    "顶部中央": (0, w//3, h//8, w*2//3),
    "底部中央": (h*7//8, w//3, h, w*2//3),
}

print(f"\n--- 区域差异分析（水印通常在角落） ---")
for name, (y1, x1, y2, x2) in regions.items():
    region_diff = diff[y1:y2, x1:x2]
    region_mean = np.mean(region_diff)
    region_max = np.max(region_diff)
    nonzero_in_region = np.sum(region_diff.mean(axis=2) > 5)
    total_in_region = (y2-y1) * (x2-x1)
    marker = "⚠️" if region_mean > mean_diff * 1.5 else "  "
    print(f"{marker} {name}: mean={region_mean:.2f} max={region_max:.2f} diff_pixels={nonzero_in_region}/{total_in_region} ({nonzero_in_region/total_in_region*100:.1f}%)")

# 生成差异图
diff_img = (diff.mean(axis=2) * 5).clip(0, 255).astype(np.uint8)
diff_image = Image.fromarray(diff_img, 'L')
diff_image.save(r"D:\new\xinghe\python_backend\web_automation\downloads\diff_map.png")
print(f"\n差异热图已保存: diff_map.png")

# 检查是否有明显的水印区域（连续的非零差异区域）
print(f"\n--- 差异区域检测 ---")
# 二值化差异图
binary_diff = (diff.mean(axis=2) > 10).astype(np.uint8)
# 找到差异区域的行/列分布
row_sums = binary_diff.sum(axis=1)
col_sums = binary_diff.sum(axis=0)

# 找差异集中的行范围
diff_rows = np.where(row_sums > w * 0.01)[0]  # 差异超过宽度1%的行
if len(diff_rows) > 0:
    print(f"差异集中的行范围: {diff_rows[0]}-{diff_rows[-1]} (总高度: {h})")
    print(f"  占比: 行{diff_rows[0]/h*100:.1f}%-{diff_rows[-1]/h*100:.1f}%")
else:
    print("没有发现差异集中的行")

diff_cols = np.where(col_sums > h * 0.01)[0]
if len(diff_cols) > 0:
    print(f"差异集中的列范围: {diff_cols[0]}-{diff_cols[-1]} (总宽度: {w})")
    print(f"  占比: 列{diff_cols[0]/w*100:.1f}%-{diff_cols[-1]/w*100:.1f}%")
else:
    print("没有发现差异集中的列")

# 最终判断
print(f"\n--- 结论 ---")
if mean_diff < 1:
    print("🔴 两帧几乎完全相同 — 发布版和任务版watermark完全一致")
elif mean_diff < 5:
    print("🟡 差异很小 — 可能是编码差异，水印可能相同")
else:
    print("🟢 存在明显差异 — 可能表示水印被移除或修改")
    
print(f"\n总结: 平均差异={mean_diff:.2f}, 不同像素占比={nonzero_pixels/total_pixels*100:.2f}%")
