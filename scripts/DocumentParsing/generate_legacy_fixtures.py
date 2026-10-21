"""자체 작성 ODF를 로컬 LibreOffice로 변환한 바이너리 Office 검증 자산."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / 'ResearchersTests' / 'Fixtures'
NAMESPACES = '''xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
 xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
 xmlns:xlink="http://www.w3.org/1999/xlink"
 xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
 xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"'''
TABLE = '''<table:table table:name="Measurements"><table:table-column table:number-columns-repeated="2"/>
 <table:table-row><table:table-cell office:value-type="string"><text:p>Legacy cell marker</text:p>
 </table:table-cell><table:table-cell office:value-type="string"><text:p>42</text:p>
 </table:table-cell></table:table-row></table:table>'''
PICTURE = '''<draw:frame draw:name="Image" svg:x="1cm" svg:y="8cm" svg:width="16cm" svg:height="3.2cm">
 <draw:image xlink:href="Pictures/label.png" xlink:type="simple" xlink:show="embed"/>
 </draw:frame>'''


def create_odf(directory, extension, kind, body, image):
    path = directory / ('LegacySample.' + extension)
    content = f'''<?xml version="1.0" encoding="UTF-8"?>
    <office:document-content {NAMESPACES} office:version="1.2">
    <office:automatic-styles><style:style style:name="P1" style:family="paragraph">
    <style:text-properties fo:font-size="18pt"/></style:style></office:automatic-styles>
    <office:body><office:{kind}>{body}</office:{kind}></office:body></office:document-content>'''
    mimetype = 'application/vnd.oasis.opendocument.' + kind
    manifest = f'''<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">
    <manifest:file-entry manifest:full-path="/" manifest:media-type="{mimetype}"/>
    <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
    <manifest:file-entry manifest:full-path="Pictures/label.png" manifest:media-type="image/png"/>
    </manifest:manifest>'''
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('mimetype', mimetype)
        archive.writestr('content.xml', content)
        archive.writestr('META-INF/manifest.xml', manifest)
        archive.write(image, 'Pictures/label.png')
    return path


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix='labcord-generated-') as temporary:
        directory = Path(temporary)
        image_path = directory / 'label.png'
        image = Image.new('RGB', (1200, 240), 'white')
        draw = ImageDraw.Draw(image)
        font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 72)
        draw.text((40, 75), 'IMAGE OCR MARKER 123', font=font, fill='black')
        image.save(image_path)
        paragraph = '<text:p text:style-name="P1">Legacy body marker</text:p>'
        word = create_odf(directory, 'odt', 'text', paragraph + TABLE +
                          '<text:p>' + PICTURE + '</text:p>', image_path)
        sheet = TABLE.replace('<table:table-row>', '<table:shapes>' + PICTURE +
                              '</table:shapes><table:table-row>', 1)
        sheet = sheet.replace('Legacy cell marker', 'Legacy body marker')
        sheet = sheet.replace('>42<', '>Legacy cell marker<')
        excel = create_odf(directory, 'ods', 'spreadsheet', sheet, image_path)
        slide = '''<draw:page draw:name="Slide One"><draw:frame svg:x="1cm" svg:y="1cm"
        svg:width="20cm" svg:height="2cm"><draw:text-box>''' + paragraph + '''</draw:text-box>
        </draw:frame><draw:frame svg:x="1cm" svg:y="4cm" svg:width="20cm" svg:height="3cm">'''
        slide += TABLE + '</draw:frame>' + PICTURE + '</draw:page>'
        powerpoint = create_odf(directory, 'odp', 'presentation', slide, image_path)
        for path, target in [(word, 'doc:MS Word 97'), (excel, 'xls:MS Excel 97'),
                             (powerpoint, 'ppt:MS PowerPoint 97')]:
            subprocess.run(['soffice', '--headless', '--convert-to', target,
                            '--outdir', str(DESTINATION), str(path)], check=True)
            result = DESTINATION / ('LegacySample.' + target.split(':')[0])
            assert result.read_bytes().startswith(bytes.fromhex('D0CF11E0A1B11AE1'))
        image_path.replace(DESTINATION / 'LegacyImage.png')


if __name__ == '__main__':
    main()
