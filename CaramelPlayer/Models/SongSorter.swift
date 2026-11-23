import Foundation

/// 歌曲排序索引：按「拼音首字母 / 英文首字母」分组排序
///
/// 性能设计（实测 2000 首歌名）：
/// - 单条取首字母约 50µs（`String.applyingTransform(.toLatin)` 是系统自带能力，无第三方依赖），
///   2000 首合计约 0.1s —— 因此按 `id + 歌名` 缓存结果，只在新增歌曲 / 元数据补全时重算；
/// - 排序本身 2000 首约 12ms —— 调用方（SongListView）只在曲库变化时重建一次，不随渲染重复计算。
enum SongSorter {

    /// 单首歌的排序信息
    struct Entry {
        /// 生成缓存时使用的歌名（歌名变了要重算）
        let title: String
        /// 分组字母："A"..."Z"，或 "#"（数字 / 符号 / 其它语言，统一排最后）
        let group: String
        /// 组内排序键：汉字的全拼 / 英文原名的小写
        let key: String
    }

    /// id → 排序信息缓存（只在主线程访问）
    private static var cache: [UUID: Entry] = [:]

    // MARK: - 单首

    static func entry(for song: Song) -> Entry {
        if let cached = cache[song.id], cached.title == song.title { return cached }
        let computed = makeEntry(title: song.title)
        cache[song.id] = computed
        return computed
    }

    static func makeEntry(title: String) -> Entry {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first else {
            return Entry(title: title, group: "#", key: "")
        }

        // ① 汉字开头：转拼音取首字母（"知足" → zhi zu → Z）
        if (0x4E00...0x9FFF).contains(Int(first.value)) {
            let latin = trimmed.applyingTransform(.toLatin, reverse: false) ?? trimmed
            let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
            let lower = plain.lowercased()
            if let head = lower.first, ("a"..."z").contains(head) {
                return Entry(title: title, group: String(head).uppercased(), key: lower)
            }
            return Entry(title: title, group: "#", key: lower)
        }

        // ② 英文字母开头：直接用首字母
        if let ch = trimmed.first, ch.isASCII, ch.isLetter {
            return Entry(title: title, group: String(ch).uppercased(), key: trimmed.lowercased())
        }

        // ③ 数字 / 符号 / 其它语言：排到最后
        return Entry(title: title, group: "#", key: trimmed.lowercased())
    }

    // MARK: - 排序与分组

    /// A–Z 在前、"#" 组压到最后；同组按全拼/全名，最后按原名兜底保证稳定
    static func sorted(_ songs: [Song]) -> [Song] {
        songs
            .map { (song: $0, entry: entry(for: $0)) }
            .sorted { lhs, rhs in
                if lhs.entry.group != rhs.entry.group {
                    if lhs.entry.group == "#" { return false }
                    if rhs.entry.group == "#" { return true }
                    return lhs.entry.group < rhs.entry.group
                }
                if lhs.entry.key != rhs.entry.key { return lhs.entry.key < rhs.entry.key }
                return lhs.entry.title.localizedStandardCompare(rhs.entry.title) == .orderedAscending
            }
            .map(\.song)
    }

    /// 每个分组的第一首（右侧字母索引跳转用），返回顺序与传入的已排序数组一致
    static func groups(of sortedSongs: [Song]) -> [(letter: String, firstID: UUID)] {
        var result: [(letter: String, firstID: UUID)] = []
        var last: String?
        for song in sortedSongs {
            let group = entry(for: song).group
            if group != last {
                result.append((letter: group, firstID: song.id))
                last = group
            }
        }
        return result
    }
}
