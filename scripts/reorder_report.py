"""Reorder the report, draw the architecture, and render all content to PDF.

Uses the current report as input on the first run, with immutable pre-reorder
backups. Requires Pandoc, Microsoft Edge, Pillow and pypdf on Windows.
"""
from pathlib import Path
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / 'docs/reports'
ASSETS = REPORTS / 'assets/report-structure'
BACKUPS = REPORTS / 'backups'
MD = REPORTS / 'report-web-v1.0.md'
PDF = REPORTS / 'report-web-v1.0.pdf'
STAMP = 'before-reorder-20261109'


def remap(text, mapping):
    text = re.sub(r'(?m)^(#{2,3} )(\d+)(?=[ .])',
                  lambda m: m[1]+str(mapping.get(int(m[2]), int(m[2]))), text)
    return re.sub(r'§(\d+)(?=[.\s、，。；：—\-）)或的]|$)',
                  lambda m: '§'+str(mapping.get(int(m[1]), int(m[1]))), text)


def architecture():
    im = Image.new('RGB', (1800, 1710), '#f5f8fb')
    d = ImageDraw.Draw(im)
    font = lambda size: ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', size)
    bold = lambda size: ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', size)
    d.text((70, 35), '拾光书店 · 当前系统分层架构', font=bold(46), fill='#16384c')
    d.text((70, 106), '四个应用层 + 两个数据库层；一次写入由数据库过程持有事务', font=font(27), fill='#4a6173')
    boxes = [
        ('① 页面交互层', '浏览器 / Jinja2 模板 / HTML 表单与 JSON', '#e5effa'),
        ('② 路由与请求控制层', 'URL 分派 · 会话身份 · CSRF · 输入与响应', '#e5effa'),
        ('③ 业务服务层', '预览 / 确认 · 签名校验 · 业务流程编排', '#e5effa'),
        ('④ 数据访问层 DAO', 'app/dao.py · 受限连接选择 · 参数绑定 · 错误转换', '#e5effa'),
        ('⑤ 数据库业务过程层', 'api.usp_* · 岗位复核 · 加锁 · 事务 · 请求幂等', '#e4f2ec'),
        ('⑥ 数据存储与约束层', '21 个经营实体 + 技术对象 · 主外码 / CHECK / 索引', '#e4f2ec'),
    ]
    x1,x2 = 80,1280
    tops = []
    for i,(title,desc,bg) in enumerate(boxes):
        y=200+i*207
        tops.append(y)
        d.rounded_rectangle((x1,y,x2,y+153), radius=18, fill=bg, outline='#7b9aaf', width=2)
        d.text((x1+30,y+23),title,font=bold(34),fill='#183e53')
        d.text((x1+30,y+83),desc,font=font(27),fill='#345065')
        if i<5:
            cy=y+153
            d.line((680,cy+4,680,cy+46),fill='#407da2',width=5)
            d.polygon([(669,cy+34),(691,cy+34),(680,cy+49)],fill='#407da2')
    # The query bypass ends at DAO, never at the tables.
    route_mid=tops[1]+76; dao_mid=tops[3]+76
    for y in range(route_mid,dao_mid,20):
        d.line((1340,y,1340,min(y+11,dao_mid)),fill='#bd7b2f',width=4)
    d.line((1280,route_mid,1340,route_mid),fill='#bd7b2f',width=4)
    d.line((1340,dao_mid,1294,dao_mid),fill='#bd7b2f',width=4)
    d.polygon([(1282,dao_mid),(1298,dao_mid-9),(1298,dao_mid+9)],fill='#bd7b2f')
    for k,line in enumerate(['部分只读查询', '鉴权后直达 DAO', '（绕过服务层）']):
        d.text((1380,605+k*45),line,font=font(26),fill='#8b5a20')
    d.rounded_rectangle((1375,1040,1730,1270),radius=15,fill='#fff2dd',outline='#cca46d',width=2)
    for k,line in enumerate(['独立到期任务', 'app/expiry.py', 'task 身份调用过程', '默认每 60 秒扫描']):
        d.text((1395,1065+k*45),line,font=font(25),fill='#765324')
    y=tops[4]+77
    d.line((1375,y,1294,y),fill='#b68b4f',width=4)
    d.polygon([(1282,y),(1298,y-9),(1298,y+9)],fill='#b68b4f')
    d.text((80,1505),'贯穿能力：角色权限 / 会话与 CSRF / 请求编号 / 错误映射 / 日志与运行配置',font=font(29),fill='#344f63')
    d.text((80,1570),'部署组成：浏览器 → Flask Web 进程 → SQL Server；到期任务为独立进程',font=font(29),fill='#344f63')
    d.text((80,1632),'说明：分层表示职责，不表示六台服务器；CLI 建库、迁移和部署属于独立运维入口。',font=font(25),fill='#5e7485')
    im.save(ASSETS/'project-architecture.png')


def main():
    ASSETS.mkdir(parents=True,exist_ok=True)
    BACKUPS.mkdir(exist_ok=True)
    old_md=BACKUPS/f'report-web-v1.0-{STAMP}.md'
    old_pdf=BACKUPS/f'report-web-v1.0-{STAMP}.pdf'
    for source,target in [(MD,old_md),(PDF,old_pdf)]:
        if not target.exists(): shutil.copy2(source,target)
    source=old_md.read_text(encoding='utf-8')
    original,supp=source.split('# 拾光书店实验报告：Week 5–6 详细补充',1)
    original=original.rstrip().removesuffix('---').rstrip()+'\n\n'
    intro=original[:original.index('## 1 实验目标与范围')]
    goals=original.split('## 1 实验目标与范围\n',1)[1].split('## 2 前置基线',1)[0]
    old_scope='范围只覆盖第 7—9 周 Web；第 5—6 周的 ER、范式、迁移与回归不在本文重复。'
    goals=goals.replace(old_scope,'本报告覆盖第 5—9 周：第 2、3 章先给出设计与迁移成果，第 4—8 章再介绍 Web 设计、实现、运行与测试。')
    baseline=original.split('## 2 前置基线（第 5—6 周结果路径）\n',1)[1].split('## 3 Web 设计',1)[0]
    web=original[original.index('## 3 Web 设计'):original.index('## 附录')]
    appendix=original[original.index('## 附录'):]
    week5=supp[supp.index('## 8 第五周'):supp.index('## 9 第六周')]
    week6=supp[supp.index('## 9 第六周'):]
    metadata=supp[supp.index('本次内容依据仓库'):supp.index('| 新增章节')].strip()
    reading=supp[supp.index('| 新增章节'):supp.index('## 8 第五周')].strip()
    intro=intro.replace('第 7—9 周 · Web v1.0','第 5—9 周 · Web v1.0')
    intro=intro.replace('第 7—9 周 Web 构建；第 5—6 周设计与迁移只给路径','项目总体架构、第 5—6 周设计与迁移、第 7—9 周 Web 构建与验证')
    intro=intro.replace('第 5—6 周内容见 §2。','第 5 周 ER 成果见 §2，第 6 周规范化与迁移成果见 §3，Web 成果见 §4—§8。')
    intro=intro.replace('**摘要**：','**摘要**：项目以 ER 建模、规范化分析和副本迁移建立数据库基线，再将其封装为 Web 应用。')
    overview=(REPORTS/'project-overview-v1.0.md').read_text(encoding='utf-8')
    overview+=goals+'\n**前置成果与证据路径**\n\n'+baseline
    week5=remap(week5,{8:2,9:3}).replace('补充图 33','图 W5-1')
    week5=week5.replace('原 §2 的 `.png` 简写','§1.6 证据入口的 `.png` 简写')
    week6=remap(week6,{8:2,9:3})
    week6=week6.replace('原报告 §3—§6','本报告 §4—§7')
    week6=week6.replace('本次新增内容与原 35 页合订，形成第二阶段从模型到应用的连续实验记录。','本报告按“项目总体介绍、第五周、第六周、后续 Web 成果”编排，形成第二阶段从模型到应用的连续实验记录。')
    web=remap(web,{3:4,4:5,5:6,6:7,7:8})
    # Bare section numbers in design-to-implementation mapping tables.
    web=re.sub(r'(?m)^(\| )(3\.\d+)( )',lambda m:m[1]+'4'+m[2][1:]+m[3],web)
    appendix=appendix.replace('## 附录','## 附录 A 证据与协作资料',1)
    appendix+='\n## 附录 B 资料来源与原稿编排记录\n\n'+metadata+'\n\n'
    appendix+='**第 5—6 周成果阅读索引**\n\n'+remap(reading,{8:2,9:3}).replace('新增章节','章节')+'\n\n'
    appendix+='原稿最初围绕第 7—9 周 Web 实验编写，以下保留原范围表述，供追溯版本时参考；当前正文范围以 §0 和 §1 为准。\n\n'
    appendix+='> 原范围表项：第 7—9 周 Web 构建；第 5—6 周设计与迁移只给路径。\n\n> '+old_scope+'\n\n'
    appendix+='原补充稿曾接在 35 页 Web 报告之后，新增章节为 §8、§9；该编排已调整为正文 §2、§3，原文件及调整前版本保存在 `docs/reports/backups/`。本次保留业务分析、表格、代码、截图和验收记录，更新章节编号及引用，原页面编号随重新排版变化。\n'
    updated=intro+overview+'\n'+week5+'\n'+week6+'\n'+web+'\n'+appendix
    updated=updated.replace('# 拾光书店 Web 实验报告','# 拾光书店第二阶段实验报告',1)
    MD.write_text(updated,encoding='utf-8')
    architecture()
    render_current_report(source, old_md, old_pdf)


def render_current_report(source=None, old_md=None, old_pdf=None):
    """Render the current Markdown without replaying the historical reordering."""
    updated = MD.read_text(encoding='utf-8')
    source = source if source is not None else updated
    old_md = old_md or MD
    old_pdf = old_pdf or PDF
    previous_pages = len(PdfReader(old_pdf).pages)
    css='''
@page { size: A4; margin: 17mm 15mm 18mm; }
html { font-size: 10pt; } body { font-family: "Microsoft YaHei", "SimSun", sans-serif; color: #243544; line-height: 1.7; margin:0; }
h1 { font-size:23pt; color:#173e54; line-height:1.4; margin-top:8mm; }
h2 { font-size:17pt; color:#173e54; border-bottom:1px solid #b6cbd6; padding-bottom:3mm; break-before:page; }
h3 { font-size:12pt; color:#245974; margin-top:6mm; break-after:avoid; }
p { orphans:3; widows:3; } a { color:#245974; text-decoration:none; overflow-wrap:anywhere; }
table { border-collapse:collapse; width:100%; font-size:8.1pt; line-height:1.55; margin:4mm 0; table-layout:fixed; }
th,td { border:1px solid #c1d0d8; padding:1.7mm; text-align:left; vertical-align:top; overflow-wrap:anywhere; }
th { background:#e7f0f5; color:#183f55; } tr:nth-child(even) { background:#f6f9fa; }
thead { display:table-header-group; } tr { break-inside:avoid; }
img { display:block; max-width:100%; max-height:155mm; object-fit:contain; margin:3mm auto; }
figure { margin:4mm 0; break-inside:avoid; } figcaption { font-size:9pt; color:#526c7b; }
pre { white-space:pre-wrap; overflow-wrap:anywhere; background:#f0f4f6; padding:3mm; font-size:8pt; line-height:1.5; }
code { font-family:Consolas,"Microsoft YaHei",monospace; font-size:.9em; overflow-wrap:anywhere; }
blockquote { border-left:3px solid #9db8c8; margin:3mm 0; padding:1mm 3mm; color:#496273; font-size:9pt; }
#TOC { font-size:9.5pt; } #TOC ul { list-style:none; padding-left:5mm; } #TOC>ul { padding-left:0; }
#TOC a { color:#284f65; } #TOC::before { content:"报告目录"; font-size:17pt; font-weight:bold; color:#173e54; }
.report-cover { margin-bottom:10mm; } .report-cover p { color:#496777; }
'''
    (ASSETS/'report.css').write_text(css,encoding='utf-8')
    rendered=ASSETS/'report-web-v1.0.html'
    template=ASSETS/'report-template.html'
    template.write_text('''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>拾光书店第二阶段实验报告</title>
$for(css)$<link rel="stylesheet" href="$css$">$endfor$</head><body>
<header class="report-cover"><h1>拾光书店第二阶段实验报告</h1><p>第二阶段 · 第 5—9 周 · Web v1.0 · 2026-11-09</p>
<p>项目总体架构 → 第五周 ER 建模 → 第六周规范化与迁移 → 第七至九周 Web 成果</p>
<div class="report-credits"><p>组长：林泽群<br>组员：黄智亮、梁宇聪<br>指导老师：赖韩江<br>完成日期：2026 年 11 月 9 日</p></div></header>
<nav id="TOC">$table-of-contents$</nav><main>$body$</main></body></html>''',encoding='utf-8')
    body_input=updated[updated.index('## 0 文档信息与摘要'):]
    subprocess.run([shutil.which('pandoc'),'--from=gfm','--to=html5','--standalone','--embed-resources','--toc','--toc-depth=2','--resource-path='+str(REPORTS),'--css='+str(ASSETS/'report.css'),'--template='+str(template),'--output='+str(rendered)],input=body_input,encoding='utf-8',check=True,cwd=ROOT)
    edge=Path('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe')
    candidate=ASSETS/'report-reordered.tmp.pdf'
    with tempfile.TemporaryDirectory(prefix='bookstore-report-browser-') as profile:
        cmd=[str(edge),'--headless','--disable-gpu','--no-first-run','--disable-extensions',
             '--user-data-dir='+profile,'--no-pdf-header-footer',
             '--print-to-pdf='+str(candidate),rendered.as_uri()]
        result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90,creationflags=subprocess.CREATE_NO_WINDOW)
        if not candidate.exists():
            raise RuntimeError(result.stderr.decode('utf-8',errors='replace')[-2500:])
    reader=PdfReader(candidate)
    writer=PdfWriter()
    page_text=[p.extract_text() for p in reader.pages]
    for i,page in enumerate(reader.pages):
        footer=io.BytesIO()
        c=canvas.Canvas(footer,pagesize=(float(page.mediabox.width),float(page.mediabox.height)))
        c.setFont('Helvetica',8)
        c.setFillColorRGB(.32,.43,.50)
        c.drawCentredString(float(page.mediabox.width)/2,22,f'{i+1} / {len(reader.pages)}')
        c.save()
        page.merge_page(PdfReader(footer).pages[0])
    writer.append(reader)
    for heading in re.findall(r'^## (.+)$',updated,re.M):
        for i,text in enumerate(page_text):
            if i>0 and heading in text:
                writer.add_outline_item(heading,i)
                break
    writer.add_metadata({'/Title':'拾光书店第二阶段实验报告：项目总体架构、第五至九周成果','/Author':'拾光书店项目'})
    with PDF.open('wb') as f: writer.write(f)
    candidate.unlink()
    # Every existing embedded image must remain in the reordered report.
    old_images=re.findall(r'!\[[^]]*\]\(([^)]+)\)',source)
    new_images=re.findall(r'!\[[^]]*\]\(([^)]+)\)',updated)
    assert all(x in new_images for x in old_images)
    assert all((REPORTS/x).resolve().exists() for x in new_images)
    headings=re.findall(r'^## (.+)$',updated,re.M)
    assert [x.split()[0] for x in headings[:9]]==list(map(str,range(9)))
    info={'pages':len(reader.pages),'previous_pages':previous_pages,
          'old_images_retained':len(old_images),'current_images':len(new_images),
          'chapter_order':headings,'markdown_sha256':hashlib.sha256(MD.read_bytes()).hexdigest(),
          'pdf_sha256':hashlib.sha256(PDF.read_bytes()).hexdigest(),
          'backup_markdown':str(old_md.relative_to(ROOT)),'backup_pdf':str(old_pdf.relative_to(ROOT))}
    (ASSETS/'verification.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(info,ensure_ascii=False,indent=2))


if __name__=='__main__':
    import sys
    if '--render-only' in sys.argv:
        render_current_report()
    else:
        main()
