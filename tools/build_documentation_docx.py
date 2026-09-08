#!/usr/bin/env python3
"""Build the Study Planner documentation DOCX without third-party packages."""

from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
from xml.sax.saxutils import escape


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "STUDY_PLANNER_DOCUMENTATION.html"
OUTPUT = ROOT / "STUDY_PLANNER_DOCUMENTATION.docx"


class DocumentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.blocks: list[tuple[str, object]] = []
        self.active: str | None = None
        self.text: list[str] = []
        self.in_table = False
        self.row: list[str] = []
        self.cell: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"h1", "h2", "h3", "p", "li", "pre"}:
            self.active = tag
            self.text = []
        elif tag == "table":
            self.in_table = True
            self.blocks.append(("table", []))
        elif tag == "tr" and self.in_table:
            self.row = []
        elif tag in {"td", "th"} and self.in_table:
            self.cell = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "tr" and self.in_table:
            tables = self.blocks[-1][1]
            assert isinstance(tables, list)
            tables.append(self.row)
        elif tag in {"td", "th"} and self.in_table:
            self.row.append("".join(self.cell).strip())
        elif tag == "table":
            self.in_table = False
        elif tag == self.active:
            value = "".join(self.text).strip()
            if value:
                self.blocks.append((tag, value))
            self.active = None
            self.text = []

    def handle_data(self, data: str) -> None:
        if self.active is not None:
            self.text.append(data)
        elif self.in_table and self.cell is not None:
            self.cell.append(data)


def run(tag: str, text: str, style: str = "Normal") -> str:
    return f'<w:p><w:pPr><w:pStyle w:val="{style}"/></w:pPr><w:r><w:t xml:space="preserve">{escape(text)}</w:t></w:r></w:p>'


def table(rows: list[list[str]]) -> str:
    output = ['<w:tbl><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders></w:tblPr>']
    for row_index, row in enumerate(rows):
        output.append("<w:tr>")
        for cell in row:
            bold = "<w:rPr><w:b/></w:rPr>" if row_index == 0 else ""
            output.append(f'<w:tc><w:p><w:r>{bold}<w:t xml:space="preserve">{escape(cell)}</w:t></w:r></w:p></w:tc>')
        output.append("</w:tr>")
    output.append("</w:tbl>")
    return "".join(output)


def build() -> None:
    parser = DocumentParser()
    parser.feed(SOURCE.read_text(encoding="utf-8"))
    body: list[str] = []
    for kind, value in parser.blocks:
        if kind == "table":
            body.append(table(value))
        elif kind == "h1":
            body.append(run(kind, str(value), "Heading1"))
        elif kind == "h2":
            body.append(run(kind, str(value), "Heading2"))
        elif kind == "h3":
            body.append(run(kind, str(value), "Heading3"))
        elif kind == "li":
            body.append(run(kind, "• " + str(value)))
        elif kind == "pre":
            body.append(run(kind, str(value), "Code"))
        else:
            body.append(run(kind, str(value)))

    document = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>{''.join(body)}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1000"/></w:sectPr></w:body></w:document>'''
    styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="Heading 1"/><w:basedOn w:val="Normal"/><w:rsid w:val="00000001"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:color w:val="234D4A"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="Heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="220" w:after="100"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="2F6F68"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="Heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="160" w:after="80"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/><w:color w:val="345F5B"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="60" w:after="60"/></w:pPr><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:sz w:val="19"/></w:rPr></w:style></w:styles>'''
    content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>'''
    rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'''
    document_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'''
    with ZipFile(OUTPUT, "w", ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types)
        archive.writestr("_rels/.rels", rels)
        archive.writestr("word/document.xml", document)
        archive.writestr("word/styles.xml", styles)
        archive.writestr("word/_rels/document.xml.rels", document_rels)


if __name__ == "__main__":
    build()
