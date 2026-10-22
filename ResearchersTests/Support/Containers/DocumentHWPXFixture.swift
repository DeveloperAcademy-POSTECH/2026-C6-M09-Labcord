import Foundation

/// 본문·표·그림 참조가 있는 최소 HWPX를 직접 만든다. 실제 편집기의 모든 기능을 대표하는 샘플은 아니다.
nonisolated enum DocumentHWPXFixture {
  static func make(imageData: Data) -> Data {
    DocumentArchiveFixtureBuilder.make([
      ("mimetype", Data("application/hwp+zip".utf8)),
      ("version.xml", Data(version.utf8)),
      ("Contents/content.hpf", Data(manifest.utf8)),
      ("Contents/header.xml", Data(header.utf8)),
      ("Contents/section0.xml", Data(section.utf8)),
      ("BinData/image1.png", imageData)
    ])
  }

  private static let version = """
    <hv:HCFVersion
      xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version"
      tagetApplication="WORDPROCESSOR"
      major="5"
      minor="1"
      micro="1"
      buildNumber="0"/>
    """

  private static let manifest = """
    <opf:package xmlns:opf="http://www.idpf.org/2007/opf/">
      <opf:manifest>
        <opf:item
          id="header"
          href="Contents/header.xml"
          media-type="application/xml"/>
        <opf:item
          id="section0"
          href="Contents/section0.xml"
          media-type="application/xml"/>
        <opf:item id="image1" href="BinData/image1.png" media-type="image/png"/>
      </opf:manifest>
      <opf:spine>
        <opf:itemref idref="header"/>
        <opf:itemref idref="section0"/>
      </opf:spine>
    </opf:package>
    """

  private static let header = """
    <hh:head
      xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head"
      version="1.5"
      secCnt="1">
      <hh:beginNum
        page="1"
        footnote="1"
        endnote="1"
        pic="1"
        tbl="1"
        equation="1"/>
      <hh:refList>
        <hh:fontfaces itemCnt="1">
          <hh:fontface lang="HANGUL" fontCnt="1">
            <hh:font id="0" face="함초롬바탕" type="TTF" isEmbedded="0"/>
          </hh:fontface>
        </hh:fontfaces>
        <hh:charProperties itemCnt="1">
          <hh:charPr id="0" height="1000" textColor="#000000"/>
        </hh:charProperties>
        <hh:paraProperties itemCnt="1">
          <hh:paraPr id="0">
            <hh:align horizontal="JUSTIFY"/>
          </hh:paraPr>
        </hh:paraProperties>
        <hh:styles itemCnt="1">
          <hh:style
            id="0"
            type="PARA"
            name="Normal"
            engName="Normal"
            paraPrIDRef="0"
            charPrIDRef="0"
            nextStyleIDRef="0"/>
        </hh:styles>
      </hh:refList>
    </hh:head>
    """

  private static let section = """
    <hs:sec
      xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section"
      xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">
      <hp:p
        id="3121190098"
        paraPrIDRef="0"
        styleIDRef="0"
        pageBreak="0"
        columnBreak="0"
        merged="0">
        <hp:run charPrIDRef="0">
          <hp:secPr id="" spaceColumns="1134" tabStop="8000">
            <hp:startNum pageStartsOn="BOTH" page="0" pic="0" tbl="0" equation="0"/>
            <hp:pagePr landscape="WIDELY" width="59528" height="84186">
              <hp:margin
                header="4252"
                footer="4252"
                gutter="0"
                left="8504"
                right="8504"
                top="5668"
                bottom="4252"/>
            </hp:pagePr>
          </hp:secPr>
          <hp:ctrl>
            <hp:colPr
              id=""
              type="NEWSPAPER"
              layout="LEFT"
              colCount="1"
              sameSz="1"
              sameGap="0"/>
          </hp:ctrl>
        </hp:run>
        <hp:run charPrIDRef="0">
          <hp:t>HWPX marker</hp:t>
        </hp:run>
        <hp:linesegarray>
          <hp:lineseg
            textpos="0"
            vertpos="0"
            vertsize="1000"
            textheight="1000"
            baseline="850"
            spacing="600"
            horzpos="0"
            horzsize="42520"
            flags="393216"/>
        </hp:linesegarray>
      </hp:p>
      <hp:p id="2" paraPrIDRef="0" styleIDRef="0">
        <hp:run charPrIDRef="0">
          <hp:tbl rowCnt="1" colCnt="1">
            <hp:tr>
              <hp:tc>
                <hp:subList>
                  <hp:p paraPrIDRef="0">
                    <hp:run charPrIDRef="0">
                      <hp:t>HWPX table marker</hp:t>
                    </hp:run>
                  </hp:p>
                </hp:subList>
                <hp:cellAddr colAddr="0" rowAddr="0"/>
              </hp:tc>
            </hp:tr>
          </hp:tbl>
        </hp:run>
      </hp:p>
    </hs:sec>
    """
}
