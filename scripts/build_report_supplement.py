"""Render the Week 5–6 addendum and append it without re-rendering old PDF pages.

Dependencies: reportlab, pypdf. Windows fonts are embedded for Chinese text.
Run from any directory: python scripts/build_report_supplement.py
"""
from __future__ import annotations

import hashlib
import html
import io
import json
from pathlib import Path
import re
import shutil

from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, LongTable, TableStyle, Image,
    PageBreak,
)

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "docs/reports"
SUPPLEMENT = REPORTS / "report-web-v1.0-week5-6-supplement.md"
ASSETS = REPORTS / "assets/week5-6-supplement"
BACKUPS = REPORTS / "backups"
PDF = REPORTS / "report-web-v1.0.pdf"
MD = REPORTS / "report-web-v1.0.md"
OLD_PDF = BACKUPS / "report-web-v1.0-before-week5-6-20261109.pdf"
OLD_MD = BACKUPS / "report-web-v1.0-before-week5-6-20261109.md"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r'<font color="#255777">\1</font>', text)
    return re.sub(r"\*\*([^*]+)\*\*", r'<b>\1</b>', text)


def render(destination: Path, text: str, old_pages: int) -> None:
    pdfmetrics.registerFont(TTFont("ReportSong", "C:/Windows/Fonts/simsun.ttc", subfontIndex=0))
    pdfmetrics.registerFont(TTFont("ReportHei", "C:/Windows/Fonts/simhei.ttf"))
    pdfmetrics.registerFontFamily("ReportSong", normal="ReportSong", bold="ReportHei")
    base = dict(fontName="ReportSong", fontSize=10, leading=16.5,
                wordWrap="CJK", spaceAfter=8)
    body = ParagraphStyle("body", **base)
    title = ParagraphStyle("title", fontName="ReportHei", fontSize=20,
                           leading=29, spaceAfter=15, wordWrap="CJK")
    h2 = ParagraphStyle("h2", fontName="ReportHei", fontSize=15,
                        leading=23, spaceBefore=15, spaceAfter=10,
                        keepWithNext=True, wordWrap="CJK")
    h3 = ParagraphStyle("h3", fontName="ReportHei", fontSize=12,
                        leading=19, spaceBefore=11, spaceAfter=7,
                        keepWithNext=True, wordWrap="CJK")
    cell = ParagraphStyle("cell", fontName="ReportSong", fontSize=8.4,
                          leading=13, wordWrap="CJK", spaceAfter=0)
    head = ParagraphStyle("head", parent=cell, fontName="ReportHei",
                          textColor=colors.HexColor("#17394e"))
    code = ParagraphStyle("code", fontName="ReportSong", fontSize=8.4,
                          leading=13, wordWrap="CJK", leftIndent=9,
                          rightIndent=5, spaceAfter=0,
                          backColor=colors.HexColor("#f1f4f6"))
    width = A4[0] - 96
    story = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith("```"):
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                story.append(Paragraph(html.escape(lines[i]).replace(" ", "&#160;") or "&#160;", code))
                i += 1
            story.append(Spacer(1, 9))
            i += 1
            continue
        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                parts = [x.strip() for x in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-+:?", x.replace(" ", "")) for x in parts):
                    rows.append(parts)
                i += 1
            count = len(rows[0])
            ratios = {2: [0.25, 0.75], 3: [0.24, 0.38, 0.38],
                      4: [0.21, 0.19, 0.27, 0.33]}.get(count, [1/count]*count)
            table = LongTable(
                [[Paragraph(inline(x), head if idx == 0 else cell) for x in row]
                 for idx, row in enumerate(rows)],
                colWidths=[width*r for r in ratios], repeatRows=1,
                hAlign="LEFT", spaceAfter=12,
            )
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e5eef3")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f7f9fa")]),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#b7c9d3")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]))
            story.append(table)
            continue
        picture = re.fullmatch(r"!\[([^]]*)\]\(([^)]+)\)", line)
        if picture:
            img = Image(str((SUPPLEMENT.parent / picture[2]).resolve()))
            ratio = min(width / img.imageWidth, 260 / img.imageHeight)
            img.drawWidth, img.drawHeight = img.imageWidth*ratio, img.imageHeight*ratio
            story.extend([img, Spacer(1, 8)])
        elif line.startswith("# "):
            story.append(Paragraph(inline(line[2:]), title))
        elif line.startswith("## "):
            if line.startswith("## 8 ") or line.startswith("## 9 "):
                story.append(PageBreak())
            story.append(Paragraph(inline(line[3:]), h2))
        elif line.startswith("### "):
            story.append(Paragraph(inline(line[4:]), h3))
        else:
            paragraph = [line]
            while i+1 < len(lines) and lines[i+1].strip() and not lines[i+1].startswith(("#", "|", "```", "![")):
                i += 1
                paragraph.append(lines[i].strip())
            story.append(Paragraph(inline(" ".join(paragraph)), body))
        i += 1

    def page(canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor("#b7c9d3"))
        canvas.line(48, A4[1]-37, A4[0]-48, A4[1]-37)
        canvas.setFont("ReportSong", 8)
        canvas.setFillColor(colors.HexColor("#476172"))
        canvas.drawString(48, A4[1]-29, "拾光书店 · 第 5—6 周详细补充")
        canvas.drawRightString(A4[0]-48, A4[1]-29, "2026-11-09")
        canvas.drawCentredString(A4[0]/2, 26, f"合订页 {old_pages+doc.page} · 补充第 {doc.page} 页")
        canvas.restoreState()

    doc = SimpleDocTemplate(str(destination), pagesize=A4,
                            leftMargin=48, rightMargin=48, topMargin=49,
                            bottomMargin=44, title="Week 5–6 详细补充", author="拾光书店项目")
    doc.build(story, onFirstPage=page, onLaterPages=page)


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    BACKUPS.mkdir(parents=True, exist_ok=True)
    if not OLD_PDF.exists():
        assert len(PdfReader(PDF).pages) == 35, "Original PDF must be the 35-page version."
        shutil.copy2(PDF, OLD_PDF)
    if not OLD_MD.exists():
        assert b"## 8 " not in MD.read_bytes(), "Markdown already contains an addendum."
        shutil.copy2(MD, OLD_MD)
    original = PdfReader(OLD_PDF)
    old_count = len(original.pages)
    supplement_text = SUPPLEMENT.read_text(encoding="utf-8")
    rendered = ASSETS / "week5-6-supplement.pdf"
    render(rendered, supplement_text, old_count)
    addition = PdfReader(rendered)
    writer = PdfWriter()
    writer.append(original, import_outline=True)
    writer.append(addition, import_outline=False)
    writer.add_outline_item("Week 5–6 详细补充", old_count)
    writer.add_outline_item("第五周：ER 建模与原设计审查", old_count+1)
    addition_text = [p.extract_text() for p in addition.pages]
    for idx, value in enumerate(addition_text):
        if "9 第六周：函数依赖" in value:
            writer.add_outline_item("第六周：函数依赖、规范化、迁移与验证", old_count+idx)
            break
    writer.add_metadata({"/Title": "拾光书店 Web 实验报告（含 Week 5–6 详细补充）",
                         "/Subject": "Original 35 pages preserved; Week 5–6 addendum appended",
                         "/Author": "拾光书店项目"})
    candidate = ASSETS / "report-web-v1.0-merged.tmp.pdf"
    with candidate.open("wb") as stream:
        writer.write(stream)
    merged = PdfReader(candidate)
    preserved = []
    for idx, old in enumerate(original.pages):
        new = merged.pages[idx]
        assert old.mediabox == new.mediabox, idx
        assert old.get_contents().get_data() == new.get_contents().get_data(), idx
        assert old.extract_text() == new.extract_text(), idx
        preserved.append(idx+1)
    assert len(merged.pages) == old_count + len(addition.pages)
    assert "函数依赖" in "".join(addition_text)
    old_md = OLD_MD.read_bytes()
    combined_md = old_md + b"\n\n---\n\n" + supplement_text.encode("utf-8")
    assert combined_md.startswith(old_md)
    # Validate the candidate before replacing the requested deliverable.
    shutil.copyfile(candidate, PDF)
    MD.write_bytes(combined_md)
    candidate.unlink()
    result = {
        "original_pages": old_count,
        "added_pages": len(addition.pages),
        "total_pages": len(merged.pages),
        "preserved_page_content_streams": preserved,
        "markdown_original_bytes_preserved_as_prefix": True,
        "original_pdf_sha256": digest(OLD_PDF.read_bytes()),
        "original_markdown_sha256": digest(old_md),
        "updated_pdf_sha256": digest(PDF.read_bytes()),
        "supplement_characters": len(supplement_text),
        "note": "Historical database evidence was reviewed; database experiments were not rerun.",
    }
    (ASSETS / "verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
