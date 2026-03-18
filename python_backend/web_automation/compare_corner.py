"""放大检查右下角水印区域"""
from PIL import Image, ImageDraw, ImageFont
import numpy as np

task = Image.open(r"D:\new\xinghe\python_backend\web_automation\downloads\frame_task_watermark.png")
pub = Image.open(r"D:\new\xinghe\python_backend\web_automation\downloads\frame_published.png")

t = np.array(task).astype(float)
p = np.array(pub).astype(float)
h, w = t.shape[:2]

# 提取右下角区域 (底部20%, 右侧30%)
y1, x1 = int(h * 0.8), int(w * 0.7)
corner_task = t[y1:, x1:]
corner_pub = p[y1:, x1:]
corner_diff = np.abs(corner_task - corner_pub)

print(f"右下角区域: ({y1},{x1}) to ({h},{w}), size={h-y1}x{w-x1}")
print(f"角落区域平均差异: {np.mean(corner_diff):.2f}")
print(f"角落区域最大差异: {np.max(corner_diff):.2f}")

# 找到差异最大的像素块
# 按8x8块分析
block_size = 16
for by in range(0, corner_diff.shape[0] - block_size, block_size):
    for bx in range(0, corner_diff.shape[1] - block_size, block_size):
        block = corner_diff[by:by+block_size, bx:bx+block_size]
        block_mean = np.mean(block)
        if block_mean > 20:  # 高差异块
            print(f"  高差异块 at ({y1+by},{x1+bx}): mean={block_mean:.1f} max={np.max(block):.1f}")

# 保存角落对比图
corner_task_img = Image.fromarray(corner_task.astype(np.uint8))
corner_pub_img = Image.fromarray(corner_pub.astype(np.uint8))
corner_diff_img = Image.fromarray((corner_diff.mean(axis=2) * 5).clip(0, 255).astype(np.uint8), 'L')

# 创建并排对比图
comparison = Image.new('RGB', (corner_task_img.width * 3, corner_task_img.height + 30))
comparison.paste(corner_task_img, (0, 30))
comparison.paste(corner_pub_img, (corner_task_img.width, 30))
# 差异图转RGB
corner_diff_rgb = Image.merge('RGB', [corner_diff_img, corner_diff_img, corner_diff_img])
comparison.paste(corner_diff_rgb, (corner_task_img.width * 2, 30))

# 添加标签
draw = ImageDraw.Draw(comparison)
draw.text((10, 5), "TASK (watermarked)", fill=(255, 0, 0))
draw.text((corner_task_img.width + 10, 5), "PUBLISHED", fill=(0, 255, 0))
draw.text((corner_task_img.width * 2 + 10, 5), "DIFFERENCE x5", fill=(255, 255, 0))

comparison.save(r"D:\new\xinghe\python_backend\web_automation\downloads\corner_comparison.png")
print("\n角落对比图已保存: corner_comparison.png")

# 也检查左上角（另一个常见水印位置）
print("\n\n--- 左上角区域 ---")
y2, x2 = int(h * 0.15), int(w * 0.25)
lt_task = t[:y2, :x2]
lt_pub = p[:y2, :x2]
lt_diff = np.abs(lt_task - lt_pub)
print(f"左上角区域平均差异: {np.mean(lt_diff):.2f}")

for by in range(0, lt_diff.shape[0] - block_size, block_size):
    for bx in range(0, lt_diff.shape[1] - block_size, block_size):
        block = lt_diff[by:by+block_size, bx:bx+block_size]
        block_mean = np.mean(block)
        if block_mean > 20:
            print(f"  高差异块 at ({by},{bx}): mean={block_mean:.1f} max={np.max(block):.1f}")

# 看看两个视频在右下角的实际颜色分布
print("\n\n--- 右下角颜色分析 ---")
# 检查是否有半透明logo（通常是白色或带透明度的）
# 在水印区域，如果有Vidu logo，会看到亮度偏高的像素
rdc_task = corner_task[:, :, :].mean(axis=2)  # 灰度
rdc_pub = corner_pub[:, :, :].mean(axis=2)

# 找到task比pub明显更亮的区域（水印通常是半透明白色叠加）
brighter_in_task = (rdc_task - rdc_pub) > 15
brighter_in_pub = (rdc_pub - rdc_task) > 15

print(f"Task更亮的像素: {np.sum(brighter_in_task)} ({np.sum(brighter_in_task)/brighter_in_task.size*100:.1f}%)")
print(f"Pub更亮的像素: {np.sum(brighter_in_pub)} ({np.sum(brighter_in_pub)/brighter_in_pub.size*100:.1f}%)")

# 如果task有水印logo，task中水印区域会比pub更亮
# 如果pub有水印logo，pub中水印区域会比task更亮

# 全帧也检查
full_task_gray = t.mean(axis=2)
full_pub_gray = p.mean(axis=2)
full_brighter_task = (full_task_gray - full_pub_gray) > 15
full_brighter_pub = (full_pub_gray - full_task_gray) > 15

print(f"\n全帧比较:")
print(f"Task更亮的像素: {np.sum(full_brighter_task)} ({np.sum(full_brighter_task)/full_brighter_task.size*100:.1f}%)")
print(f"Pub更亮的像素: {np.sum(full_brighter_pub)} ({np.sum(full_brighter_pub)/full_brighter_pub.size*100:.1f}%)")

# 保存两帧的右下角放大图（让用户自己看）
task_rb = task.crop((int(w*0.65), int(h*0.75), w, h))
pub_rb = pub.crop((int(w*0.65), int(h*0.75), w, h))
task_rb = task_rb.resize((task_rb.width * 2, task_rb.height * 2), Image.NEAREST)
pub_rb = pub_rb.resize((pub_rb.width * 2, pub_rb.height * 2), Image.NEAREST)

task_rb.save(r"D:\new\xinghe\python_backend\web_automation\downloads\task_bottom_right_2x.png")
pub_rb.save(r"D:\new\xinghe\python_backend\web_automation\downloads\pub_bottom_right_2x.png")
print("\n右下角2x放大图已保存")
