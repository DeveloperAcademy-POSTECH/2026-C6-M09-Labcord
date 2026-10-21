"""자체 검증 자산에 사용하는 CFB 작성기. 외부 문서는 읽지 않는다."""
import struct

FREE = 0xFFFFFFFF
END = 0xFFFFFFFE
FAT = 0xFFFFFFFD


def pack(kind, *values):
    return struct.pack('<' + kind, *values)


def make_compound(streams):
    entries = [{'name': 'Root Entry', 'type': 5, 'children': []}]
    storages = {'': 0}
    for path, content in streams.items():
        parent = ''
        parts = path.split('/')
        for name in parts[:-1]:
            current = (parent + '/' + name).strip('/')
            if current not in storages:
                storages[current] = len(entries)
                entries.append({'name': name, 'type': 1, 'children': []})
                entries[storages[parent]]['children'].append(storages[current])
            parent = current
        entries[storages[parent]]['children'].append(len(entries))
        entries.append({'name': parts[-1], 'type': 2, 'data': content, 'children': []})
    mini = bytearray()
    mini_fat = []
    sectors = []
    fat = []

    def allocate(data):
        first = len(sectors)
        chunks = [data[i:i + 512].ljust(512, b'\0') for i in range(0, len(data), 512)]
        sectors.extend(chunks)
        fat.extend([i + 1 for i in range(first, first + len(chunks))])
        if chunks:
            fat[-1] = END
        return first if chunks else END

    for entry in entries[1:]:
        if entry['type'] != 2:
            entry.update(first=END, size=0)
            continue
        data = entry['data']
        entry['size'] = len(data)
        if len(data) >= 4096:
            entry['first'] = allocate(data)
        else:
            first = len(mini_fat)
            chunks = [data[i:i + 64].ljust(64, b'\0') for i in range(0, len(data), 64)]
            mini.extend(b''.join(chunks))
            mini_fat.extend(range(first + 1, first + len(chunks) + 1))
            if chunks:
                mini_fat[-1] = END
            entry['first'] = first if chunks else END
    entries[0].update(first=allocate(mini), size=len(mini))
    mini_start = allocate(b''.join(pack('I', value) for value in mini_fat))
    mini_sectors = (len(mini_fat) * 4 + 511) // 512
    for entry in entries:
        entry.update(left=FREE, right=FREE, child=FREE, color=1)
    for entry in entries:
        children = sorted(entry['children'], key=lambda index: (len(entries[index]['name']),
                                                                entries[index]['name'].upper()))
        maximum_depth = len(children).bit_length() - 1

        def tree(indices, depth=0):
            if not indices:
                return FREE
            middle = len(indices) // 2
            index = indices[middle]
            node = entries[index]
            node['color'] = 0 if depth == maximum_depth and depth > 0 else 1
            node['left'] = tree(indices[:middle], depth + 1)
            node['right'] = tree(indices[middle + 1:], depth + 1)
            return index
        entry['child'] = tree(children)
    directory = bytearray()
    for entry in entries:
        name = (entry['name'] + '\0').encode('utf-16-le')
        record = name.ljust(64, b'\0') + pack('HBBIII', len(name), entry['type'], entry['color'],
                                           entry['left'], entry['right'], entry['child'])
        record += bytes(36) + pack('IQ', entry['first'], entry['size'])
        assert len(record) == 128
        directory.extend(record)
    directory_start = allocate(directory)
    fat_index = len(sectors)
    fat.append(FAT)
    assert len(fat) <= 128
    sectors.append(b''.join(pack('I', value) for value in fat).ljust(512, b'\xff'))
    header = bytes.fromhex('D0CF11E0A1B11AE1') + bytes(16)
    header += pack('HHHHH', 0x003E, 3, 0xFFFE, 9, 6) + bytes(6)
    header += pack('IIIIIIIII', 0, 1, directory_start, 0, 4096,
                   mini_start, mini_sectors, END, 0)
    header += pack('I', fat_index) + pack('I', FREE) * 108
    assert len(header) == 512
    return header + b''.join(sectors)
