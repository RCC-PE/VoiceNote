import sys
from PIL import Image, ImageDraw

S = 4  # 超取樣倍率，畫大再縮小讓邊緣平滑
N = 1024 * S
out = sys.argv[1]

# 對角漸層背景：靛藍 -> 紫
top, bottom = (79, 70, 229), (147, 51, 234)
grad = Image.new("RGB", (256, 256))
px = grad.load()
for y in range(256):
    for x in range(256):
        t = (x + y) / 510
        px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
img = grad.resize((N, N), Image.BICUBIC).convert("RGBA")

layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
s = lambda v: int(v * S)

def pill(x0, y0, x1, y1, fill):
    r = min(x1 - x0, y1 - y0) / 2
    d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s(r), fill=fill)

white = (255, 255, 255, 255)

# 左半：聲波
heights = [150, 310, 460, 330, 400, 190]
bar_w, gap, x = 40, 22, 170
for h in heights:
    pill(x, 512 - h / 2, x + bar_w, 512 + h / 2, white)
    x += bar_w + gap

# 右半：逐字稿文字行
lines = [(560, 300), (560, 250), (560, 290), (560, 210), (560, 260)]
y = 372
for x0, w in lines:
    pill(x0, y, x0 + w, y + 40, (255, 255, 255, 235))
    y += 68

# 右上角：AI 星星
def sparkle(cx, cy, r, fill):
    k = 0.22
    pts = [(cx, cy - r), (cx + r * k, cy - r * k), (cx + r, cy), (cx + r * k, cy + r * k),
           (cx, cy + r), (cx - r * k, cy + r * k), (cx - r, cy), (cx - r * k, cy - r * k)]
    d.polygon([(s(a), s(b)) for a, b in pts], fill=fill)

sparkle(830, 210, 92, (253, 230, 138, 255))
sparkle(905, 330, 40, (253, 230, 138, 255))

img = Image.alpha_composite(img, layer).convert("RGB")  # App 圖示不能有透明
img.resize((1024, 1024), Image.LANCZOS).save(out)
