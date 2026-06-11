#!/usr/bin/env python3
"""Compose App-Store-grade marketing panels (3:4, 1080x1440) for 小红书
from the raw N1KO-STATE screenshots in build/shots/."""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "build", "shots")
OUT = os.path.join(ROOT, "build", "panels")
os.makedirs(OUT, exist_ok=True)

W, H = 1080, 1440
ACCENT = (94, 92, 230)        # #5E5CE6
ACCENT2 = (191, 90, 242)      # violet
INK = (236, 238, 245)
SUB = (150, 155, 175)

F_TITLE = "/System/Library/Fonts/Hiragino Sans GB.ttc"   # idx2 = W6
F_SUB = "/System/Library/Fonts/Hiragino Sans GB.ttc"     # idx0 = W3
F_MARK = "/System/Library/Fonts/SFNSRounded.ttf"

def font(path, size, index=0):
    return ImageFont.truetype(path, size, index=index)

def vgrad(w, h, top, bot):
    base = Image.new("RGB", (w, h))
    px = base.load()
    for y in range(h):
        t = y / (h - 1)
        # ease for a richer falloff
        t = t * t * (3 - 2 * t)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return base

def glow(canvas, cx, cy, radius, color, alpha):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
              fill=(color[0], color[1], color[2], alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    canvas.alpha_composite(layer)

def round_img(im, rad):
    im = im.convert("RGBA")
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0], im.size[1]], rad, fill=255)
    im.putalpha(mask)
    return im

def paste_with_shadow(canvas, im, cx, cy, rad=40, border=True):
    im = round_img(im, rad)
    w, h = im.size
    x = cx - w // 2
    y = cy - h // 2
    # soft shadow
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    pad = 0
    sd.rounded_rectangle([x - pad, y - pad + 26, x + w + pad, y + h + pad + 26],
                         rad + 6, fill=(0, 0, 0, 150))
    sh = sh.filter(ImageFilter.GaussianBlur(38))
    canvas.alpha_composite(sh)
    # subtle accent rim
    if border:
        rim = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(rim).rounded_rectangle(
            [x - 1, y - 1, x + w + 1, y + h + 1], rad + 1,
            outline=(255, 255, 255, 28), width=2)
        canvas.alpha_composite(rim)
    canvas.alpha_composite(im, (x, y))

def text_center(draw, cx, y, s, fnt, fill, stroke=0, stroke_fill=None, ls=0):
    if ls:  # letter spacing
        total = sum(draw.textlength(ch, font=fnt) + ls for ch in s) - ls
        x = cx - total / 2
        for ch in s:
            draw.text((x, y), ch, font=fnt, fill=fill,
                      stroke_width=stroke, stroke_fill=stroke_fill)
            x += draw.textlength(ch, font=fnt) + ls
        return
    w = draw.textlength(s, font=fnt)
    draw.text((cx - w / 2, y), s, font=fnt, fill=fill,
              stroke_width=stroke, stroke_fill=stroke_fill)

def base_canvas():
    c = vgrad(W, H, (26, 27, 46), (11, 11, 20)).convert("RGBA")
    glow(c, W // 2, 250, 430, ACCENT, 90)
    glow(c, W // 2, 1180, 360, ACCENT2, 55)
    return c

def fit(im, maxw, maxh):
    w, h = im.size
    s = min(maxw / w, maxh / h)
    return im.resize((int(w * s), int(h * s)), Image.LANCZOS)

def feature_panel(out, src, title, subtitle, maxw=640, maxh=980, cy=905):
    c = base_canvas()
    d = ImageDraw.Draw(c)
    # kicker dot + wordmark
    mark = font(F_MARK, 30)
    text_center(d, W // 2, 96, "N1KO  STATE", mark, (255, 255, 255, 230), ls=6)
    d.line([W // 2 - 70, 150, W // 2 + 70, 150], fill=(*ACCENT, 200), width=4)
    # title / subtitle
    ft = font(F_TITLE, 60, index=2)
    fs = font(F_SUB, 31, index=0)
    text_center(d, W // 2, 196, title, ft, INK, stroke=0)
    # subtitle may wrap on ·-separated logical groups; keep single line if fits
    text_center(d, W // 2, 286, subtitle, fs, SUB)
    im = fit(Image.open(os.path.join(SHOTS, src)), maxw, maxh)
    paste_with_shadow(c, im, W // 2, cy, rad=38)
    c.convert("RGB").save(os.path.join(OUT, out), quality=95)
    print("wrote", out, im.size)

def cover_panel(out, src):
    c = base_canvas()
    glow(c, W // 2, 1080, 520, ACCENT, 70)
    d = ImageDraw.Draw(c)
    mark = font(F_MARK, 132)
    sub1 = font(F_TITLE, 46, index=2)
    sub2 = font(F_SUB, 33, index=0)
    # Wordmark N1KO STATE (STATE in accent)
    n = "N1KO "
    s = "STATE"
    wn = d.textlength(n, font=mark)
    ws = d.textlength(s, font=mark)
    x0 = W / 2 - (wn + ws) / 2
    d.text((x0, 250), n, font=mark, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0, 60))
    d.text((x0 + wn, 250), s, font=mark, fill=ACCENT, stroke_width=2, stroke_fill=(0, 0, 0, 60))
    text_center(d, W // 2, 430, "用 AI Vibecoding 写一个 Mac 菜单栏监控", sub1, INK)
    text_center(d, W // 2, 506, "CPU · GPU · 内存 · 磁盘 · 风扇 · 电池 · 温度  全都有", sub2, SUB)
    # gauges screenshot lower
    im = fit(Image.open(os.path.join(SHOTS, src)), 560, 720)
    paste_with_shadow(c, im, W // 2, 1010, rad=38)
    # footer chip
    chip = font(F_SUB, 30, index=2)
    label = "开源 · 免费 · 原生 SwiftUI"
    cw = d.textlength(label, font=chip)
    cx0, cy0 = W / 2 - cw / 2 - 26, 1372
    d.rounded_rectangle([cx0, cy0, cx0 + cw + 52, cy0 + 50], 25,
                        fill=(255, 255, 255, 18), outline=(*ACCENT, 180), width=2)
    text_center(d, W // 2, cy0 + 9, label, chip, INK)
    c.convert("RGB").save(os.path.join(OUT, out), quality=95)
    print("wrote", out)

cover_panel("00_cover.jpg", "popover_gauges.png")
feature_panel("01_gauges.jpg", "popover_gauges.png",
              "环形仪表盘 · 一眼看尽全身状态",
              "颜值与信息密度兼得，常驻菜单栏随时一瞥", maxw=600, maxh=900, cy=890)
feature_panel("02_cpu.jpg", "card_cpu.png",
              "CPU 占用 + Top 进程实时排行",
              "P 核 / E 核分布 · 负载均值 · 开机时长", maxw=660, maxh=900, cy=900)
feature_panel("03_sensors.jpg", "card_sensors.png",
              "风扇手动调速 · 全核温度监控",
              "Auto / Manual 一键切换 · 拖动设定目标 RPM", maxw=600, maxh=1000, cy=910)
feature_panel("04_memdisk.jpg", "card_memdisk.png",
              "内存压力 + 多磁盘容量",
              "应用/缓存明细 · 读写速度 · 多卷支持", maxw=600, maxh=1010, cy=915)
feature_panel("05_netbat.jpg", "card_netbat.png",
              "网络速率 + 电池健康 + GPU",
              "实时上下行 · 循环次数 · 功率 · 显存占用", maxw=600, maxh=1010, cy=915)
print("done ->", OUT)
