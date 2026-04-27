from pathlib import Path
import html

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import ListFlowable, ListItem, Paragraph, Preformatted, SimpleDocTemplate, Spacer


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "offline_tools_user_manual_zh_CN.md"
OUTPUT = ROOT / "docs" / "offline_tools_user_manual_zh_CN.pdf"


def register_fonts():
    candidates = [
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\simsunb.ttf"),
        Path(r"C:\Windows\Fonts\msyh.ttc"),
    ]
    for font_path in candidates:
        if font_path.exists():
            pdfmetrics.registerFont(TTFont("ManualFont", str(font_path)))
            return "ManualFont"
    raise FileNotFoundError("No suitable Chinese font found in C:\\Windows\\Fonts")


def build_styles(font_name: str):
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="ManualTitle",
            parent=styles["Title"],
            fontName=font_name,
            fontSize=20,
            leading=28,
            alignment=TA_CENTER,
            spaceAfter=18,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ManualH1",
            parent=styles["Heading1"],
            fontName=font_name,
            fontSize=16,
            leading=24,
            textColor=colors.HexColor("#16324f"),
            spaceBefore=12,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ManualH2",
            parent=styles["Heading2"],
            fontName=font_name,
            fontSize=13,
            leading=20,
            textColor=colors.HexColor("#244c74"),
            spaceBefore=10,
            spaceAfter=6,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ManualBody",
            parent=styles["BodyText"],
            fontName=font_name,
            fontSize=10.5,
            leading=18,
            wordWrap="CJK",
            spaceAfter=6,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ManualCode",
            parent=styles["Code"],
            fontName=font_name,
            fontSize=9,
            leading=14,
            backColor=colors.HexColor("#f5f7fa"),
            borderPadding=6,
            wordWrap="CJK",
        )
    )
    return styles


def para(text: str, style):
    return Paragraph(html.escape(text).replace("\n", "<br/>"), style)


def render_markdown(md_text: str, styles):
    story = []
    lines = md_text.splitlines()
    i = 0
    in_code = False
    code_lines = []

    while i < len(lines):
        line = lines[i].rstrip()

        if line.startswith("```"):
            if not in_code:
                in_code = True
                code_lines = []
            else:
                story.append(Preformatted("\n".join(code_lines), styles["ManualCode"]))
                story.append(Spacer(1, 8))
                in_code = False
            i += 1
            continue

        if in_code:
            code_lines.append(line)
            i += 1
            continue

        if not line.strip():
            story.append(Spacer(1, 6))
            i += 1
            continue

        if line == "---":
            story.append(Spacer(1, 8))
            i += 1
            continue

        if line.startswith("# "):
            style = styles["ManualTitle"] if not story else styles["ManualH1"]
            story.append(Paragraph(html.escape(line[2:].strip()), style))
            i += 1
            continue

        if line.startswith("## "):
            story.append(Paragraph(html.escape(line[3:].strip()), styles["ManualH1"]))
            i += 1
            continue

        if line.startswith("### "):
            story.append(Paragraph(html.escape(line[4:].strip()), styles["ManualH2"]))
            i += 1
            continue

        if line.startswith("- "):
            items = []
            while i < len(lines) and lines[i].startswith("- "):
                items.append(ListItem(para(lines[i][2:].strip(), styles["ManualBody"])))
                i += 1
            story.append(ListFlowable(items, bulletType="bullet", start="circle", leftIndent=16))
            story.append(Spacer(1, 6))
            continue

        if line[:2].isdigit() and ". " in line:
            items = []
            while i < len(lines):
                cur = lines[i].strip()
                if not cur or not cur[0].isdigit() or ". " not in cur:
                    break
                items.append(ListItem(para(cur.split(". ", 1)[1], styles["ManualBody"])))
                i += 1
            story.append(ListFlowable(items, bulletType="1", leftIndent=18))
            story.append(Spacer(1, 6))
            continue

        paragraph_lines = [line]
        i += 1
        while i < len(lines):
            nxt = lines[i].rstrip()
            if not nxt.strip() or nxt.startswith(("#", "- ", "```")) or nxt == "---":
                break
            if nxt[:2].isdigit() and ". " in nxt:
                break
            paragraph_lines.append(nxt)
            i += 1
        story.append(para("\n".join(paragraph_lines), styles["ManualBody"]))

    return story


def main():
    font_name = register_fonts()
    styles = build_styles(font_name)
    md_text = SOURCE.read_text(encoding="utf-8")
    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        leftMargin=40,
        rightMargin=40,
        topMargin=40,
        bottomMargin=36,
        title="离线工具平台 v1.0 使用说明书",
        author="Codex",
    )
    story = render_markdown(md_text, styles)
    doc.build(story)
    print(OUTPUT)


if __name__ == "__main__":
    main()
