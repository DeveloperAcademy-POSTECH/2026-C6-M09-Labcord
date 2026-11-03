/// CPython 정수 set의 삽입·재배치 순서를 보존해 alias 완전 동점도 재현합니다.
/// 삭제가 없고 입력이 canonical 후보의 음이 아닌 작은 정수인 경우만 다룹니다.
/// 알고리즘: https://github.com/python/cpython/blob/3.12/Objects/setobject.c
nonisolated enum R117IntegerSetOrder {
    static func values(_ input: [Int]) -> [Int] {
        var table = [Int?](repeating: nil, count: 8)
        var count = 0
        for value in input {
            let slot = position(value, table: table)
            guard table[slot] == nil else { continue }
            table[slot] = value
            count += 1
            if count * 5 >= (table.count - 1) * 3 {
                var size = 8
                while size <= count * 4 { size *= 2 }
                var resized = [Int?](repeating: nil, count: size)
                for stored in table.compactMap({ $0 }) {
                    resized[position(stored, table: resized)] = stored
                }
                table = resized
            }
        }
        return table.compactMap { $0 }
    }

    private static func position(_ value: Int, table: [Int?]) -> Int {
        let mask = table.count - 1
        var perturb = value
        var index = value & mask
        while true {
            let count = index + 9 <= mask ? 9 : 0
            for slot in index...(index + count) where table[slot] == nil || table[slot] == value {
                return slot
            }
            perturb >>= 5
            index = ((index &* 5) &+ 1 &+ perturb) & mask
        }
    }
}
