#!/usr/bin/env python3
"""
Generate high-quality 512x512 cover art icons for NFSU2 Tools on playOS (R36H / playfe).
Design Theme: Need for Speed: Underground 2 (Tuning / Neon Green / Dark Carbon & Speedometer Gauge)
Safe Zone: Fits both playfe rounded rectangle card and circular mask (>12-15% edge margin).
Compatible with Pillow 5.1.0+.
"""

import os
import math
from PIL import Image, ImageDraw, ImageFont

def get_resample_filter():
    if hasattr(Image, "Resampling"):
        return Image.Resampling.LANCZOS
    return Image.ANTIALIAS

def draw_centered_text(draw, cx, cy, text, fill, font):
    tw, th = draw.textsize(text, font=font)
    draw.text((cx - tw // 2, cy - th // 2), text, fill=fill, font=font)

def draw_thick_arc(draw, cx, cy, r, start_deg, end_deg, fill, width=1):
    for i in range(-width // 2, (width + 1) // 2):
        cr = r + i
        draw.arc([cx - cr, cy - cr, cx + cr, cy + cr], start_deg, end_deg, fill=fill)

def draw_rounded_rect(draw, bbox, radius, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = bbox
    r = radius
    if fill:
        draw.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
        draw.rectangle([x0, y0 + r, x1, y1 - r], fill=fill)
        draw.pieslice([x0, y0, x0 + 2*r, y0 + 2*r], 180, 270, fill=fill)
        draw.pieslice([x1 - 2*r, y0, x1, y0 + 2*r], 270, 360, fill=fill)
        draw.pieslice([x0, y1 - 2*r, x0 + 2*r, y1], 90, 180, fill=fill)
        draw.pieslice([x1 - 2*r, y1 - 2*r, x1, y1], 0, 90, fill=fill)
    if outline:
        for w_i in range(width):
            ox0, oy0, ox1, oy1 = x0 + w_i, y0 + w_i, x1 - w_i, y1 - w_i
            orad = max(1, r - w_i)
            draw.line([(ox0 + orad, oy0), (ox1 - orad, oy0)], fill=outline)
            draw.line([(ox0 + orad, oy1), (ox1 - orad, oy1)], fill=outline)
            draw.line([(ox0, oy0 + orad), (ox0, oy1 - orad)], fill=outline)
            draw.line([(ox1, oy0 + orad), (ox1, oy1 - orad)], fill=outline)
            draw.arc([ox0, oy0, ox0 + 2*orad, oy0 + 2*orad], 180, 270, fill=outline)
            draw.arc([ox1 - 2*orad, oy0, ox1, oy0 + 2*orad], 270, 360, fill=outline)
            draw.arc([ox0, oy1 - 2*orad, ox0 + 2*orad, oy1], 90, 180, fill=outline)
            draw.arc([ox1 - 2*orad, oy1 - 2*orad, ox1, oy1], 0, 90, fill=outline)

def create_base_canvas(scale=2):
    w, h = 512 * scale, 512 * scale
    canvas = Image.new("RGBA", (w, h), (14, 16, 20, 255))
    draw = ImageDraw.Draw(canvas)

    # 1. Background gradient (radial dark glow)
    cx, cy = w // 2, h // 2
    for r in range(w, 0, -12):
        factor = (r / float(w))
        red = int(10 + 12 * (1.0 - factor))
        green = int(14 + 20 * (1.0 - factor))
        blue = int(18 + 24 * (1.0 - factor))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(red, green, blue, 255))

    # 2. Subtle carbon weave / grid pattern
    grid_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grid_img)
    spacing = 10 * scale
    for x in range(0, w, spacing):
        gdraw.line([(x, 0), (x, h)], fill=(255, 255, 255, 8), width=1)
    for y in range(0, h, spacing):
        gdraw.line([(0, y), (w, y)], fill=(255, 255, 255, 8), width=1)
    
    # 3. Dynamic speed lines (diagonal)
    for i in range(-w, w * 2, 48 * scale):
        gdraw.line([(i, 0), (i + h, h)], fill=(0, 255, 128, 10), width=2 * scale)

    canvas = Image.alpha_composite(canvas, grid_img)
    return canvas

def load_fonts(scale=2):
    font_paths = [
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"
    ]
    font_small = None
    font_bold = None
    for fp in font_paths:
        if os.path.exists(fp):
            font_small = ImageFont.truetype(fp, 16 * scale)
            font_bold = ImageFont.truetype(fp, 26 * scale)
            break
    if font_small is None:
        font_small = ImageFont.load_default()
        font_bold = ImageFont.load_default()

    thai_font_paths = [
        "/usr/share/fonts/truetype/tlwg/Waree-Bold.ttf",
        "/usr/share/fonts/truetype/tlwg/Garuda-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    ]
    thai_font = None
    for tfp in thai_font_paths:
        if os.path.exists(tfp):
            thai_font = ImageFont.truetype(tfp, 19 * scale)
            break
    if thai_font is None:
        thai_font = font_small

    return font_small, font_bold, thai_font

def draw_header(draw, scale=2, accent_color=(57, 255, 20), font_small=None, font_bold=None):
    w = 512 * scale
    # Sub-header: NEED FOR SPEED
    draw_centered_text(draw, w // 2, 48 * scale, "NEED FOR SPEED", (210, 220, 225), font_small)
    
    # Header: UNDERGROUND 2 (with drop shadow)
    draw_centered_text(draw, w // 2 + 2, 78 * scale + 2, "UNDERGROUND 2", (0, 0, 0), font_bold)
    draw_centered_text(draw, w // 2, 78 * scale, "UNDERGROUND 2", accent_color, font_bold)

    # Neon separator bar
    bar_w = 160 * scale
    draw.line([(w // 2 - bar_w // 2, 98 * scale), (w // 2 + bar_w // 2, 98 * scale)], fill=accent_color, width=2 * scale)

def draw_gauge_circle(draw, scale=2, ring_color=(57, 255, 20)):
    w, h = 512 * scale, 512 * scale
    cx, cy = w // 2, 235 * scale
    r = 115 * scale

    # Outer speed dial ticks
    for angle_deg in range(-210, 31, 15):
        rad = math.radians(angle_deg)
        x1 = cx + (r + 14 * scale) * math.cos(rad)
        y1 = cy + (r + 14 * scale) * math.sin(rad)
        x2 = cx + (r + 4 * scale) * math.cos(rad)
        y2 = cy + (r + 4 * scale) * math.sin(rad)
        tick_col = ring_color if angle_deg < -30 else (255, 60, 60)
        draw.line([(x1, y1), (x2, y2)], fill=tick_col, width=2 * scale)

    # Dial arc track
    draw_thick_arc(draw, cx, cy, r, -215, 35, ring_color, width=4 * scale)
    # Inner metallic ring
    ir = r - 10 * scale
    draw.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=(22, 26, 32, 240), outline=(80, 90, 100))

    return cx, cy, ir

def draw_thai_flag(draw, x, y, width, height, border_color=(255, 255, 255)):
    stripe_unit = height / 6.0
    # Red top
    draw.rectangle([x, y, x + width, y + stripe_unit], fill=(217, 37, 41))
    # White
    draw.rectangle([x, y + stripe_unit, x + width, y + 2 * stripe_unit], fill=(244, 245, 248))
    # Blue center (double height)
    draw.rectangle([x, y + 2 * stripe_unit, x + width, y + 4 * stripe_unit], fill=(45, 42, 74))
    # White
    draw.rectangle([x, y + 4 * stripe_unit, x + width, y + 5 * stripe_unit], fill=(244, 245, 248))
    # Red bottom
    draw.rectangle([x, y + 5 * stripe_unit, x + width, y + height], fill=(217, 37, 41))
    # Border
    draw.rectangle([x, y, x + width, y + height], outline=border_color)

def draw_uk_flag(draw, x, y, width, height, border_color=(255, 255, 255)):
    # Blue background
    draw.rectangle([x, y, x + width, y + height], fill=(1, 33, 105))
    # White diagonals
    draw.line([(x, y), (x + width, y + height)], fill=(255, 255, 255), width=int(height * 0.2))
    draw.line([(x, y + height), (x + width, y)], fill=(255, 255, 255), width=int(height * 0.2))
    # Red diagonals
    draw.line([(x, y), (x + width, y + height)], fill=(200, 16, 46), width=int(height * 0.1))
    draw.line([(x, y + height), (x + width, y)], fill=(200, 16, 46), width=int(height * 0.1))
    # White cross
    draw.rectangle([x + width * 0.38, y, x + width * 0.62, y + height], fill=(255, 255, 255))
    draw.rectangle([x, y + height * 0.35, x + width, y + height * 0.65], fill=(255, 255, 255))
    # Red cross
    draw.rectangle([x + width * 0.43, y, x + width * 0.57, y + height], fill=(200, 16, 46))
    draw.rectangle([x, y + height * 0.41, x + width, y + height * 0.59], fill=(200, 16, 46))
    # Border
    draw.rectangle([x, y, x + width, y + height], outline=border_color)

def draw_footer_card(draw, scale=2, title="TITLE", sub_thai="คำอธิบายภาษาไทย", font_bold=None, thai_font=None, accent=(57, 255, 20)):
    w = 512 * scale
    card_y = 370 * scale
    card_h = 92 * scale
    card_w = 420 * scale
    card_x = (w - card_w) // 2

    # Draw rounded rect
    draw_rounded_rect(draw, [card_x, card_y, card_x + card_w, card_y + card_h], radius=16 * scale, fill=(20, 24, 30, 230), outline=accent, width=2 * scale)

    # Title text
    draw_centered_text(draw, w // 2, card_y + 30 * scale, title, (255, 255, 255), font_bold)

    # Thai subtitle
    if thai_font:
        draw_centered_text(draw, w // 2, card_y + 64 * scale, sub_thai, accent, thai_font)

def make_border_frame(draw, scale=2, color=(57, 255, 20)):
    w, h = 512 * scale, 512 * scale
    margin = 12 * scale
    draw_rounded_rect(draw, [margin, margin, w - margin, h - margin], radius=24 * scale, outline=color, width=3 * scale)

def generate_setup_icon(out_path):
    scale = 2
    canvas = create_base_canvas(scale)
    draw = ImageDraw.Draw(canvas)
    f_small, f_bold, f_thai = load_fonts(scale)
    accent = (57, 255, 20)
    draw_header(draw, scale, accent, f_small, f_bold)
    cx, cy, ir = draw_gauge_circle(draw, scale, accent)

    # Center Graphic: Thai flag shield + Install badge
    flag_w = 110 * scale
    flag_h = 68 * scale
    draw_thai_flag(draw, cx - flag_w // 2, cy - flag_h // 2 - 14 * scale, flag_w, flag_h)

    # Gear / Tool badge on bottom half of dial
    badge_w = 90 * scale
    badge_h = 28 * scale
    bx = cx - badge_w // 2
    by = cy + 22 * scale
    draw_rounded_rect(draw, [bx, by, bx + badge_w, by + badge_h], radius=6 * scale, fill=(0, 175, 75), outline=(255, 255, 255), width=2 * scale)
    draw_centered_text(draw, cx, by + badge_h // 2, "INSTALL", (255, 255, 255), f_small)

    draw_footer_card(draw, scale, "SETUP THAI EDITION", "ติดตั้งภาษาไทย + เซฟเกม", f_bold, f_thai, accent)
    make_border_frame(draw, scale, accent)

    final = canvas.resize((512, 512), get_resample_filter())
    final.convert("RGB").save(out_path, "PNG")
    print("Generated: {}".format(out_path))

def generate_thai_lang_icon(out_path):
    scale = 2
    canvas = create_base_canvas(scale)
    draw = ImageDraw.Draw(canvas)
    f_small, f_bold, f_thai = load_fonts(scale)
    accent = (57, 255, 20)
    draw_header(draw, scale, accent, f_small, f_bold)
    cx, cy, ir = draw_gauge_circle(draw, scale, accent)

    # Center Graphic: Large Glossy Thai flag
    flag_w = 130 * scale
    flag_h = 84 * scale
    draw_thai_flag(draw, cx - flag_w // 2, cy - flag_h // 2, flag_w, flag_h, border_color=(57, 255, 20))

    draw_footer_card(draw, scale, "SWITCH TO THAI", "สลับภาษาเป็น: ภาษาไทย", f_bold, f_thai, accent)
    make_border_frame(draw, scale, accent)

    final = canvas.resize((512, 512), get_resample_filter())
    final.convert("RGB").save(out_path, "PNG")
    print("Generated: {}".format(out_path))

def generate_english_lang_icon(out_path):
    scale = 2
    canvas = create_base_canvas(scale)
    draw = ImageDraw.Draw(canvas)
    f_small, f_bold, f_thai = load_fonts(scale)
    cyan_col = (0, 220, 255)
    draw_header(draw, scale, cyan_col, f_small, f_bold)
    cx, cy, ir = draw_gauge_circle(draw, scale, cyan_col)

    # Center Graphic: UK Flag
    flag_w = 130 * scale
    flag_h = 84 * scale
    draw_uk_flag(draw, cx - flag_w // 2, cy - flag_h // 2, flag_w, flag_h, border_color=cyan_col)

    draw_footer_card(draw, scale, "SWITCH TO ENGLISH", "สลับภาษาเป็น: ภาษาอังกฤษ", f_bold, f_thai, cyan_col)
    make_border_frame(draw, scale, cyan_col)

    final = canvas.resize((512, 512), get_resample_filter())
    final.convert("RGB").save(out_path, "PNG")
    print("Generated: {}".format(out_path))

def generate_uninstall_icon(out_path):
    scale = 2
    canvas = create_base_canvas(scale)
    draw = ImageDraw.Draw(canvas)
    f_small, f_bold, f_thai = load_fonts(scale)
    amber_col = (255, 90, 60)
    draw_header(draw, scale, amber_col, f_small, f_bold)
    cx, cy, ir = draw_gauge_circle(draw, scale, amber_col)

    # Center Graphic: Restore / Return arrow with red warning background
    circ_r = 45 * scale
    draw.ellipse([cx - circ_r, cy - circ_r, cx + circ_r, cy + circ_r], fill=(180, 30, 25), outline=(255, 255, 255))

    # Revert circular arrow
    draw_thick_arc(draw, cx, cy, 24 * scale, 50, 300, (255, 255, 255), width=6 * scale)
    # Arrow head
    draw.polygon([
        (cx - 30 * scale, cy - 12 * scale),
        (cx - 14 * scale, cy - 26 * scale),
        (cx - 14 * scale, cy - 2 * scale)
    ], fill=(255, 255, 255))

    draw_footer_card(draw, scale, "RESTORE ORIGINAL", "กู้คืนไฟล์เดิม / ถอนภาษาไทย", f_bold, f_thai, amber_col)
    make_border_frame(draw, scale, amber_col)

    final = canvas.resize((512, 512), get_resample_filter())
    final.convert("RGB").save(out_path, "PNG")
    print("Generated: {}".format(out_path))

if __name__ == "__main__":
    base_dir = os.path.dirname(os.path.abspath(__file__))
    if os.path.basename(base_dir) == "app":
        out_dir = os.path.join(base_dir, "images")
        tools_images_dir = os.path.join(base_dir, "..", "images")
    else:
        out_dir = os.path.join(base_dir, "app", "images")
        tools_images_dir = os.path.join(base_dir, "images")

    os.makedirs(out_dir, exist_ok=True)
    generate_thai_lang_icon(os.path.join(out_dir, "NFSU2_Language_Thai-thumb.png"))
    generate_english_lang_icon(os.path.join(out_dir, "NFSU2_Language_English-thumb.png"))
    generate_uninstall_icon(os.path.join(out_dir, "Uninstall_NFSU2_Thai-thumb.png"))

    os.makedirs(tools_images_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.endswith(".png"):
            with open(os.path.join(out_dir, f), "rb") as rf:
                with open(os.path.join(tools_images_dir, f), "wb") as wf:
                    wf.write(rf.read())
    print(f"All icons successfully generated in {out_dir} and {tools_images_dir}!")
