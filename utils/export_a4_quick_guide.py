from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "offline_tools_a4_quick_guide_zh_CN.pdf"


def register_font():
    candidates = [
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\simsun.ttc"),
    ]
    for font_path in candidates:
        if font_path.exists():
            pdfmetrics.registerFont(TTFont("GuideFont", str(font_path)))
            return "GuideFont"
    return "Helvetica"


def draw_round_rect(c, x, y, w, h, fill, stroke=colors.HexColor("#cbd5df")):
    c.setFillColor(fill)
    c.setStrokeColor(stroke)
    c.roundRect(x, y, w, h, 8, fill=1, stroke=1)


def draw_icon(c, kind, x, y, color):
    c.setStrokeColor(color)
    c.setFillColor(color)
    c.setLineWidth(2)
    if kind == "network":
        c.circle(x + 18, y + 24, 7, fill=0)
        c.circle(x + 44, y + 24, 7, fill=0)
        c.circle(x + 31, y + 42, 7, fill=0)
        c.line(x + 24, y + 27, x + 38, y + 27)
        c.line(x + 23, y + 30, x + 28, y + 37)
        c.line(x + 39, y + 30, x + 34, y + 37)
    elif kind == "download":
        c.line(x + 31, y + 44, x + 31, y + 18)
        c.line(x + 21, y + 28, x + 31, y + 18)
        c.line(x + 41, y + 28, x + 31, y + 18)
        c.roundRect(x + 14, y + 8, 34, 8, 3, fill=0, stroke=1)
    elif kind == "box":
        c.rect(x + 13, y + 13, 36, 28, fill=0, stroke=1)
        c.line(x + 13, y + 41, x + 31, y + 52)
        c.line(x + 49, y + 41, x + 31, y + 52)
        c.line(x + 31, y + 52, x + 31, y + 24)
    elif kind == "install":
        c.roundRect(x + 14, y + 12, 34, 38, 5, fill=0, stroke=1)
        c.line(x + 22, y + 36, x + 29, y + 27)
        c.line(x + 29, y + 27, x + 42, y + 43)
    elif kind == "check":
        c.circle(x + 31, y + 30, 21, fill=0)
        c.line(x + 20, y + 30, x + 28, y + 21)
        c.line(x + 28, y + 21, x + 44, y + 40)


def text(c, value, x, y, size, font, color=colors.HexColor("#17212b")):
    c.setFont(font, size)
    c.setFillColor(color)
    c.drawString(x, y, value)


def centered(c, value, x, y, w, size, font, color=colors.HexColor("#17212b")):
    c.setFont(font, size)
    c.setFillColor(color)
    c.drawCentredString(x + w / 2, y, value)


def wrapped(c, value, x, y, width, size, font, leading=15, color=colors.HexColor("#334155")):
    c.setFont(font, size)
    c.setFillColor(color)
    line = ""
    yy = y
    for ch in value:
        candidate = line + ch
        if c.stringWidth(candidate, font, size) > width and line:
            c.drawString(x, yy, line)
            yy -= leading
            line = ch
        else:
            line = candidate
    if line:
        c.drawString(x, yy, line)
    return yy


def step_card(c, font, idx, title, body, icon, x, y, w, h, color):
    draw_round_rect(c, x, y, w, h, colors.HexColor("#ffffff"))
    c.setFillColor(color)
    c.circle(x + 22, y + h - 24, 13, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont(font, 13)
    c.drawCentredString(x + 22, y + h - 29, str(idx))
    draw_icon(c, icon, x + w - 72, y + h - 72, color)
    text(c, title, x + 44, y + h - 31, 13, font, colors.HexColor("#102a43"))
    wrapped(c, body, x + 18, y + h - 58, w - 92, 9.5, font, 14)


def main():
    font = register_font()
    c = canvas.Canvas(str(OUTPUT), pagesize=A4)
    page_w, page_h = A4

    c.setFillColor(colors.HexColor("#f4f8fb"))
    c.rect(0, 0, page_w, page_h, fill=1, stroke=0)

    c.setFillColor(colors.HexColor("#0f3a5f"))
    c.rect(0, page_h - 92, page_w, 92, fill=1, stroke=0)
    text(c, "离线工具平台 V1.0", 36, page_h - 40, 24, font, colors.white)
    text(c, "联网下载完整依赖，离线环境只用本地仓库安装", 38, page_h - 68, 12, font, colors.HexColor("#c9e8ff"))

    steps = [
        ("准备联网机器", "进入项目目录，确认联网机器能访问目标 OS 软件源。", "network", colors.HexColor("#1b7f8c")),
        ("下载并打包", "选择下载模式、目标 OS、架构和工具包组，等待生成 output/offline_*.tar.xz。", "download", colors.HexColor("#2563eb")),
        ("复制离线包", "把 .tar.xz、.sha256、.header 一起复制到离线机器的 output 目录。", "box", colors.HexColor("#7c3aed")),
        ("离线安装", "选择安装模式，选兼容离线包，可安装全部或选择性安装。", "install", colors.HexColor("#16a34a")),
    ]

    x1, x2 = 36, page_w / 2 + 10
    w, h = page_w / 2 - 52, 122
    y_top = page_h - 240
    for i, (title, body, icon, color) in enumerate(steps, 1):
        x = x1 if i % 2 == 1 else x2
        y = y_top if i <= 2 else y_top - 145
        step_card(c, font, i, title, body, icon, x, y, w, h, color)

    draw_round_rect(c, 36, 168, page_w - 72, 125, colors.HexColor("#ffffff"))
    text(c, "常用命令", 54, 268, 15, font, colors.HexColor("#0f3a5f"))
    commands = [
        "启动：bash offline_tools_v1.sh",
        "质量检查：bash utils/quality_gate.sh",
        "源检查：bash utils/check_sources.sh",
        "校验离线包：cd output && sha256sum -c offline_*.sha256",
    ]
    y = 246
    for cmd in commands:
        c.setFillColor(colors.HexColor("#eef4f8"))
        c.roundRect(54, y - 4, page_w - 108, 22, 5, fill=1, stroke=0)
        text(c, cmd, 64, y + 2, 9.5, font, colors.HexColor("#1f2937"))
        y -= 24

    draw_round_rect(c, 36, 66, page_w - 72, 78, colors.HexColor("#fff7ed"), colors.HexColor("#fed7aa"))
    draw_icon(c, "check", 48, 79, colors.HexColor("#ea580c"))
    text(c, "现场确认", 122, 120, 14, font, colors.HexColor("#9a3412"))
    wrapped(
        c,
        "1. OS 和架构必须匹配。2. 安装模式只使用离线包本地仓库。3. 界面只展示工具名，不展开依赖包。4. 遇到问题优先打包 logs 目录。",
        122,
        100,
        page_w - 170,
        9.5,
        font,
        14,
        colors.HexColor("#7c2d12"),
    )

    centered(c, "最新版测试路径：172.18.10.61:/root/offline_tool_release_v1", 36, 32, page_w - 72, 9.5, font, colors.HexColor("#64748b"))
    c.save()
    print(OUTPUT)


if __name__ == "__main__":
    main()
