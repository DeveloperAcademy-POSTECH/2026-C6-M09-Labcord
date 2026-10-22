import Foundation

/// 본문·셀·슬라이드 텍스트를 확인할 작은 OOXML 문서를 만든다. 외부 원본 코퍼스와 역할을 구분한다.
nonisolated enum DocumentOfficeFixtures {
  static func word() -> Data {
    DocumentArchiveFixtureBuilder.make([
      ("[Content_Types].xml", Data(wordTypes.utf8)),
      ("_rels/.rels", Data(wordRelationships.utf8)),
      ("word/document.xml", Data(wordDocument.utf8))
    ])
  }

  static func excel() -> Data {
    DocumentArchiveFixtureBuilder.make([
      ("[Content_Types].xml", Data(excelTypes.utf8)),
      ("_rels/.rels", Data(excelRelationships.utf8)),
      ("xl/workbook.xml", Data(excelWorkbook.utf8)),
      ("xl/_rels/workbook.xml.rels", Data(excelWorkbookRelationships.utf8)),
      ("xl/sharedStrings.xml", Data(excelSharedStrings.utf8)),
      ("xl/worksheets/sheet1.xml", Data(excelSheet.utf8))
    ])
  }

  static func slides() -> Data {
    DocumentArchiveFixtureBuilder.make([
      ("[Content_Types].xml", Data(slideTypes.utf8)),
      ("_rels/.rels", Data(slideRelationships.utf8)),
      ("ppt/presentation.xml", Data(presentation.utf8)),
      ("ppt/_rels/presentation.xml.rels", Data(presentationRelationships.utf8)),
      ("ppt/slides/slide1.xml", Data(slide.utf8))
    ])
  }

  private static let officeContentType = "application/vnd.openxmlformats-officedocument"

  private static let wordTypes = """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default
        Extension="rels"
        ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override
        PartName="/word/document.xml"
        ContentType="\(officeContentType).wordprocessingml.document.main+xml"/>
    </Types>
    """

  private static let wordRelationships = """
    <Relationships
      xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship
        Id="r1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
        Target="word/document.xml"/>
    </Relationships>
    """

  private static let wordDocument = """
    <w:document
      xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p>
          <w:r>
            <w:t>Word body marker</w:t>
          </w:r>
        </w:p>
        <w:tbl>
          <w:tr>
            <w:tc>
              <w:p>
                <w:r>
                  <w:t>Word cell marker</w:t>
                </w:r>
              </w:p>
            </w:tc>
          </w:tr>
        </w:tbl>
      </w:body>
    </w:document>
    """

  private static let excelTypes = """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default
        Extension="rels"
        ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override
        PartName="/xl/workbook.xml"
        ContentType="\(officeContentType).spreadsheetml.sheet.main+xml"/>
      <Override
        PartName="/xl/sharedStrings.xml"
        ContentType="\(officeContentType).spreadsheetml.sharedStrings+xml"/>
    </Types>
    """

  private static let excelRelationships = """
    <Relationships
      xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship
        Id="r1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
        Target="xl/workbook.xml"/>
    </Relationships>
    """

  private static let excelWorkbook = """
    <workbook
      xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="Sheet One" sheetId="1" r:id="r1"/>
      </sheets>
      <definedNames/>
    </workbook>
    """

  private static let excelWorkbookRelationships = """
    <Relationships
      xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship
        Id="r1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
        Target="worksheets/sheet1.xml"/>
      <Relationship
        Id="r2"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings"
        Target="sharedStrings.xml"/>
    </Relationships>
    """

  private static let excelSharedStrings = """
    <sst
      xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
      count="1"
      uniqueCount="1">
      <si>
        <t>Sheet cell marker</t>
      </si>
    </sst>
    """

  private static let excelSheet = """
    <worksheet
      xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <sheetData>
        <row r="1">
          <c r="A1" t="s">
            <v>0</v>
          </c>
        </row>
      </sheetData>
    </worksheet>
    """

  private static let slideTypes = """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default
        Extension="rels"
        ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override
        PartName="/ppt/presentation.xml"
        ContentType="\(officeContentType).presentationml.presentation.main+xml"/>
    </Types>
    """

  private static let slideRelationships = """
    <Relationships
      xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship
        Id="r1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
        Target="ppt/presentation.xml"/>
    </Relationships>
    """

  private static let presentation = """
    <p:presentation
      xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <p:sldIdLst>
        <p:sldId id="1" r:id="r1"/>
      </p:sldIdLst>
    </p:presentation>
    """

  private static let presentationRelationships = """
    <Relationships
      xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship
        Id="r1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"
        Target="slides/slide1.xml"/>
    </Relationships>
    """

  private static let slide = """
    <p:sld
      xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
      xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
      <p:cSld>
        <p:spTree>
          <p:sp>
            <p:txBody>
              <a:p>
                <a:r>
                  <a:t>Slide text marker</a:t>
                </a:r>
              </a:p>
            </p:txBody>
          </p:sp>
        </p:spTree>
      </p:cSld>
    </p:sld>
    """
}
