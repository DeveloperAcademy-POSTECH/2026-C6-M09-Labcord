"""외부 문서 없이 HWP 5.0.2.2 레코드와 CFB 컨테이너를 생성한다."""
from pathlib import Path
import zlib
import sys
sys.dont_write_bytecode = True
from compound_fixture import make_compound, pack

ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / 'ResearchersTests' / 'Fixtures'


def record(tag, level, payload):
    if len(payload) < 4095:
        return pack('I', tag | level << 10 | len(payload) << 20) + payload
    return pack('II', tag | level << 10 | 4095 << 20, len(payload)) + payload


def paragraph(text, level=0):
    payload = (text + '\r').encode('utf-16-le')
    header = pack('IIHBBHHHI', len(payload) // 2, 0, 0, 0, 0, 1, 0, 0, 1)
    return (record(66, level, header) + record(67, level + 1, payload)
            + record(68, level + 1, bytes(8)))


def main():
    header = (b'HWP Document File'.ljust(32, b'\0') + pack('II', 0x05000202, 0)).ljust(256, b'\0')
    properties = pack('H', 1) + pack('6H', *([1] * 6)) + bytes(12)
    mapping = pack('16I', 1, *([0] * 15))
    binary = pack('HHH', 1, 1, 3) + 'png'.encode('utf-16-le')
    info = record(16, 0, properties) + record(17, 0, mapping) + record(18, 1, binary)
    section = paragraph('HWP body marker')
    common = pack('II4Ii4HI', 0x74626C20, 0, 0, 0, 30000, 6000, 0, 0, 0, 0, 0, 1)
    section += record(71, 1, common)
    table = pack('I7H', 0, 1, 2, 0, 0, 0, 0, 0) + pack('3H', 2, 0, 0)
    section += record(77, 2, table)
    for column, text in enumerate(['HWP cell marker', '42']):
        cell = pack('HIH', 1, 0, 0) + pack('4H2I5H', column, 0, 1, 1, 15000, 6000, 0, 0, 0, 0, 0)
        section += record(72, 2, cell) + paragraph(text, 2)
    picture = (DESTINATION / 'LegacyImage.png').read_bytes()
    output = make_compound({'FileHeader': header, 'DocInfo': info,
                            'BodyText/Section0': section, 'BinData/BIN0001.png': picture})
    (DESTINATION / 'BinarySample.hwp').write_bytes(output)
    def deflate(data):
        encoder = zlib.compressobj(wbits=-15)
        return encoder.compress(data) + encoder.flush()
    compressed_header = bytearray(header)
    compressed_header[36:40] = pack('I', 1)
    compressed = make_compound({'FileHeader': bytes(compressed_header),
                                'DocInfo': deflate(info), 'BodyText/Section0': deflate(section),
                                'BinData/BIN0001.png': deflate(picture)})
    (DESTINATION / 'BinaryCompressed.hwp').write_bytes(compressed)
    print('Generated uncompressed and compressed HWP fixtures')


if __name__ == '__main__':
    main()
