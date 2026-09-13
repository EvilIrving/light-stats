#!/usr/bin/env python3
"""Generate the app's blank OOXML templates using only Python's standard library."""

import argparse
import io
from pathlib import Path
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1] / "Light Stats/Resources"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
WORD = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
SHEET = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
DRAW = "http://schemas.openxmlformats.org/drawingml/2006/main"
PRES = "http://schemas.openxmlformats.org/presentationml/2006/main"


def relationships(items):
    root = ET.Element("Relationships", xmlns="http://schemas.openxmlformats.org/package/2006/relationships")
    for index, (kind, target) in enumerate(items, 1):
        ET.SubElement(root, "Relationship", Id=f"rId{index}", Type=f"{REL}/{kind}", Target=target)
    return ET.tostring(root, encoding="unicode")


def content_types(parts):
    root = ET.Element("Types", xmlns="http://schemas.openxmlformats.org/package/2006/content-types")
    ET.SubElement(root, "Default", Extension="rels", ContentType="application/vnd.openxmlformats-package.relationships+xml")
    ET.SubElement(root, "Default", Extension="xml", ContentType="application/xml")
    for name, kind in parts:
        ET.SubElement(root, "Override", PartName=f"/{name}", ContentType=f"application/vnd.openxmlformats-officedocument.{kind}+xml")
    return ET.tostring(root, encoding="unicode")


def word():
    return {
        "[Content_Types].xml": content_types([("word/document.xml", "wordprocessingml.document.main")]),
        "_rels/.rels": relationships([("officeDocument", "word/document.xml")]),
        "word/document.xml": f'''<w:document xmlns:w="{WORD}"><w:body><w:p/>
          <w:sectPr><w:pgSz w:w="11906" w:h="16838"/>
          <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
          </w:sectPr></w:body></w:document>''',
    }


def excel():
    return {
        "[Content_Types].xml": content_types([
            ("xl/workbook.xml", "spreadsheetml.sheet.main"),
            ("xl/worksheets/sheet1.xml", "spreadsheetml.worksheet"),
        ]),
        "_rels/.rels": relationships([("officeDocument", "xl/workbook.xml")]),
        "xl/_rels/workbook.xml.rels": relationships([("worksheet", "worksheets/sheet1.xml")]),
        "xl/workbook.xml": f'''<workbook xmlns="{SHEET}" xmlns:r="{REL}">
          <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>''',
        "xl/worksheets/sheet1.xml": f'<worksheet xmlns="{SHEET}"><sheetData/></worksheet>',
    }


def theme():
    colors = "".join(f'<a:{name}><a:srgbClr val="{color}"/></a:{name}>' for name, color in [
        ("dk1", "000000"), ("lt1", "FFFFFF"), ("dk2", "44546A"), ("lt2", "E7E6E6"),
        ("accent1", "4472C4"), ("accent2", "ED7D31"), ("accent3", "A5A5A5"),
        ("accent4", "FFC000"), ("accent5", "5B9BD5"), ("accent6", "70AD47"),
        ("hlink", "0563C1"), ("folHlink", "954F72"),
    ])
    fonts = "".join(f'<a:{kind}><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:{kind}>'
                    for kind in ["majorFont", "minorFont"])
    fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    line = f'<a:ln w="9525">{fill}<a:prstDash val="solid"/></a:ln>'
    return f'''<a:theme xmlns:a="{DRAW}" name="Light Stats"><a:themeElements>
      <a:clrScheme name="Office">{colors}</a:clrScheme><a:fontScheme name="Office">{fonts}</a:fontScheme>
      <a:fmtScheme name="Office"><a:fillStyleLst>{fill * 3}</a:fillStyleLst>
      <a:lnStyleLst>{line * 3}</a:lnStyleLst>
      <a:effectStyleLst>{'<a:effectStyle><a:effectLst/></a:effectStyle>' * 3}</a:effectStyleLst>
      <a:bgFillStyleLst>{fill * 3}</a:bgFillStyleLst></a:fmtScheme>
      </a:themeElements></a:theme>'''


def powerpoint():
    namespaces = f'xmlns:p="{PRES}" xmlns:a="{DRAW}" xmlns:r="{REL}"'
    tree = '''<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>
      <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree>'''
    color_map = 'bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" ' + " ".join(
        f'{name}="{name}"' for name in ["accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"])
    parts = [
        ("ppt/presentation.xml", "presentationml.presentation.main"),
        ("ppt/slides/slide1.xml", "presentationml.slide"),
        ("ppt/slideMasters/slideMaster1.xml", "presentationml.slideMaster"),
        ("ppt/slideLayouts/slideLayout1.xml", "presentationml.slideLayout"),
        ("ppt/theme/theme1.xml", "theme"),
    ]
    return {
        "[Content_Types].xml": content_types(parts),
        "_rels/.rels": relationships([("officeDocument", "ppt/presentation.xml")]),
        "ppt/presentation.xml": f'''<p:presentation {namespaces}>
          <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
          <p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>
          <p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>''',
        "ppt/_rels/presentation.xml.rels": relationships([
            ("slideMaster", "slideMasters/slideMaster1.xml"), ("slide", "slides/slide1.xml"),
        ]),
        "ppt/slides/slide1.xml": f'''<p:sld {namespaces}><p:cSld>{tree}</p:cSld>
          <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>''',
        "ppt/slides/_rels/slide1.xml.rels": relationships([("slideLayout", "../slideLayouts/slideLayout1.xml")]),
        "ppt/slideLayouts/slideLayout1.xml": f'''<p:sldLayout {namespaces} type="blank" preserve="1">
          <p:cSld name="Blank">{tree}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>''',
        "ppt/slideLayouts/_rels/slideLayout1.xml.rels": relationships([("slideMaster", "../slideMasters/slideMaster1.xml")]),
        "ppt/slideMasters/slideMaster1.xml": f'''<p:sldMaster {namespaces}><p:cSld>
          <p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>
          {tree}</p:cSld>
          <p:clrMap {color_map}/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
          <p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>''',
        "ppt/slideMasters/_rels/slideMaster1.xml.rels": relationships([
            ("slideLayout", "../slideLayouts/slideLayout1.xml"), ("theme", "../theme/theme1.xml"),
        ]),
        "ppt/theme/theme1.xml": theme(),
    }


def archive(parts):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as zipped:
        for name, content in sorted(parts.items()):
            ET.fromstring(content)
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            zipped.writestr(info, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + content)
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify committed templates without changing them")
    args = parser.parse_args()
    for extension, parts in [("docx", word()), ("xlsx", excel()), ("pptx", powerpoint())]:
        target = ROOT / f"FinderBlank.{extension}"
        data = archive(parts)
        if args.check:
            if not target.exists() or target.read_bytes() != data:
                raise SystemExit(f"Template differs: {target}")
        else:
            target.write_bytes(data)
        print(f"{'Verified' if args.check else 'Generated'} {target.name} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
