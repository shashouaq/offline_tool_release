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


def register_font():
    candidates = [
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\simsun.ttc"),
    ]
    for font_path in candidates:
        if font_path.exists():
            pdfmetrics.registerFont(TTFont("ManualFont", str(font_path)))
            return "ManualFont"
    return "Helvetica"


def build_styles(font_name):
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="ManualTitle",
            parent=styles["Title"],
            fontName=font_name,
            fontSize=20,
            leading=28,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#0f3a5f"),
            spaceAfter=18,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ManualH1",
            parent=styles["Heading1"],
            fontName=font_name,
            fontSize=15,
            leading=22,
            textColor=colors.HexColor("#14517d"),
            spaceBefore=12,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ManualH2",
            parent=styles["Heading2"],
            fontName=font_name,
            fontSize=12,
            leading=18,
            textColor=colors.HexColor("#176b8f"),
            spaceBefore=8,
            spaceAfter=5,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ManualBody",
            parent=styles["BodyText"],
            fontName=font_name,
            fontSize=9.6,
            leading=15.5,
            wordWrap="CJK",
            spaceAfter=5,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ManualCode",
            parent=styles["Code"],
            fontName=font_name,
            fontSize=8.5,
            leading=13,
            backColor=colors.HexColor("#f3f6f9"),
            borderColor=colors.HexColor("#d9e2ec"),
            borderWidth=0.5,
            borderPadding=6,
            wordWrap="CJK",
        )
    )
    return styles


def paragraph(text, style):
    escaped = html.escape(text).replace("\n", "<br/>")
    return Paragraph(escaped, style)


def render_markdown(md_text, styles):
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
                story.append(Spacer(1, 6))
                in_code = False
            i += 1
            continue

        if in_code:
            code_lines.append(line)
            i += 1
            continue

        if not line.strip():
            story.append(Spacer(1, 4))
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
                items.append(ListItem(paragraph(lines[i][2:].strip(), styles["ManualBody"])))
                i += 1
            story.append(ListFlowable(items, bulletType="bullet", leftIndent=16))
            story.append(Spacer(1, 4))
            continue

        if line[:2].isdigit() and ". " in line:
            items = []
            while i < len(lines):
                cur = lines[i].strip()
                if not cur or not cur[0].isdigit() or ". " not in cur:
                    break
                items.append(ListItem(paragraph(cur.split(". ", 1)[1], styles["ManualBody"])))
                i += 1
            story.append(ListFlowable(items, bulletType="1", leftIndent=18))
            story.append(Spacer(1, 4))
            continue

        paragraph_lines = [line]
        i += 1
        while i < len(lines):
            nxt = lines[i].rstrip()
            if not nxt.strip() or nxt.startswith(("#", "- ", "```")):
                break
            if nxt[:2].isdigit() and ". " in nxt:
                break
            paragraph_lines.append(nxt)
            i += 1
        story.append(paragraph("\n".join(paragraph_lines), styles["ManualBody"]))

    return story


def main():
    font_name = register_font()
    styles = build_styles(font_name)
    md_text = SOURCE.read_text(encoding="utf-8")
    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        leftMargin=36,
        rightMargin=36,
        topMargin=36,
        bottomMargin=34,
        title="离线工具平台 V1.0 使用说明书",
        author="Codex",
    )
    doc.build(render_markdown(md_text, styles))
    print(OUTPUT)


if __name__ == "__main__":
    main()
