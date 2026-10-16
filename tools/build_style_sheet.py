# -*- coding: utf-8 -*-
"""把四张原始风格图去背景、裁切、统一身高，合成一张对比图。"""
import os
import numpy as np
from PIL import Image

SRC = r"E:\GameProject\SurvivalDemo\UI\原始风格图"
OUT = r"E:\GameProject\SurvivalDemo\UI\原始风格图"
ORDER = ["工装丧尸", "男主角", "女性丧尸", "上班族丧尸"]
TARGET_H = 900
BG_THRESH = 40          # 与背景色的差异阈值（0-255）


def remove_bg(img):
    """从四边向内做容差漫填，去掉连通背景，保留角色内部的浅色。"""
    img = img.convert("RGBA")
    a = np.asarray(img).astype(np.int16)
    rgb = a[:, :, :3]
    # 估计背景色 = 四角像素的中位色
    corners = np.concatenate([
        rgb[:5, :5].reshape(-1, 3), rgb[:5, -5:].reshape(-1, 3),
        rgb[-5:, :5].reshape(-1, 3), rgb[-5:, -5:].reshape(-1, 3),
    ])
    bg = np.median(corners, axis=0)
    dist = np.abs(rgb - bg).sum(axis=2)
    bgmask = dist <= BG_THRESH * 3

    h, w = bgmask.shape
    visited = np.zeros_like(bgmask)
    stack = []
    for x in range(w):
        for y in (0, h - 1):
            if bgmask[y, x] and not visited[y, x]:
                stack.append((y, x)); visited[y, x] = True
    for y in range(h):
        for x in (0, w - 1):
            if bgmask[y, x] and not visited[y, x]:
                stack.append((y, x)); visited[y, x] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and bgmask[ny, nx] and not visited[ny, nx]:
                visited[ny, nx] = True
                stack.append((ny, nx))

    out = np.asarray(img).copy()
    out[:, :, 3] = np.where(visited, 0, 255)
    return Image.fromarray(out, "RGBA")


def main():
    cut_dir = os.path.join(OUT, "抠图")
    os.makedirs(cut_dir, exist_ok=True)
    figures = []
    for name in ORDER:
        p = os.path.join(SRC, name + ".png")
        im = Image.open(p)
        fg = remove_bg(im)
        bbox = fg.getbbox()
        fg = fg.crop(bbox)
        w, h = fg.size
        nw = max(1, round(w * TARGET_H / h))
        fg = fg.resize((nw, TARGET_H), Image.LANCZOS)
        fg.save(os.path.join(cut_dir, name + "_抠图.png"))
        figures.append((name, fg))
        print(name, "原图", im.size, "-> 裁切", (w, h), "-> 统一高", fg.size)

    pad = 60
    gap = 50
    W = sum(f.width for _, f in figures) + gap * (len(figures) - 1) + pad * 2
    H = TARGET_H + pad * 2
    canvas = Image.new("RGB", (W, H), (238, 238, 240))
    x = pad
    for name, f in figures:
        canvas.paste(f, (x, pad), f)
        x += f.width + gap
    dst = os.path.join(OUT, "四角色统一身高对比.png")
    canvas.save(dst)
    print("合成:", dst, canvas.size)


if __name__ == "__main__":
    main()