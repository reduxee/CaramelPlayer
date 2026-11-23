import Foundation

/// LRC 歌词解析器（纯函数模块，无状态、可独立测试）
///
/// 兼容标准 LRC 时间标签格式：
/// - `[mm:ss]` / `[mm:ss.xx]` / `[mm:ss.xxx]` / `[mm:ss:xx]`（冒号毫秒写法）
/// - 一行多时间标签：`[00:12.00][01:30.50]重复的副歌`（同一句歌词出现多次）
/// - 时间标签之后无文本的行（纯间奏标记）解析为空行
/// - 忽略元信息标签 `[ti:]` `[ar:]` `[al:]` `[by:]` `[offset:]` 等（offset 偏移不做补偿，
///   保持与外部 lrc 文件原样一致，避免不同来源的偏移差异引入误差）
enum LyricsParser {

    /// 匹配一个标准 LRC 时间标签，如 `[12:34.567]`
    /// 分组：1=分钟 2=秒 3=毫秒（可空，支持 2~3 位）
    private static let timeTagPattern = #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    private static let timeTagRegex = try? NSRegularExpression(pattern: timeTagPattern)

    /// 判断一段文本是否「看起来像 LRC」（用于内嵌歌词有效性预判）
    /// —— 内嵌歌词可能只是纯文本（无时间标签），此时应降级去读外部 .lrc 文件
    static func looksLikeLRC(_ text: String) -> Bool {
        guard let regex = timeTagRegex else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// 解析 LRC 文本为按时间升序排列的歌词行
    /// 返回空数组表示没有任何有效时间标签（调用方据此走降级逻辑）
    static func parse(_ raw: String) -> [LyricLine] {
        guard let regex = timeTagRegex else { return [] }
        var result: [LyricLine] = []

        // 统一换行符，按行切分
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let nsRange = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }

            // 提取该行所有时间标签 + 去掉全部标签后的歌词正文
            var times: [TimeInterval] = []
            var textStart = line.endIndex
            for m in matches {
                if let t = timeInterval(from: m, in: line) {
                    times.append(t)
                }
                if let r = Range(m.range, in: line), r.lowerBound < textStart {
                    textStart = r.upperBound < line.endIndex ? line.index(r.upperBound, offsetBy: 0) : line.endIndex
                }
            }
            // 正文 = 最后一个时间标签之后的内容
            var text = ""
            if let last = matches.last, let r = Range(last.range, in: line) {
                text = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            // 同一正文对应多个时间点 → 拆成多行歌词（标准 LRC 行为）
            for t in times {
                result.append(LyricLine(time: t, text: text))
            }
        }

        // 按时间排序，保证二分 / 线性查找当前行时顺序正确
        return result.sorted { $0.time < $1.time }
    }

    /// 从正则匹配结果换算秒数
    private static func timeInterval(from match: NSTextCheckingResult, in line: String) -> TimeInterval? {
        func group(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: line) else { return nil }
            return String(line[r])
        }
        guard let minStr = group(1), let secStr = group(2),
              let minutes = Double(minStr), let seconds = Double(secStr) else { return nil }

        // 毫秒部分：`56` 按标准 LRC 语义是 560ms（百分秒），`567` 是 567ms；
        // 统一规则：1 位 = x0ms；2 位 = x00ms? 不对 —— 2 位是百分秒（×10ms），3 位是毫秒
        var millis = 0.0
        if let msStr = group(3) {
            switch msStr.count {
            case 1: millis = (Double(msStr) ?? 0) * 100
            case 2: millis = (Double(msStr) ?? 0) * 10
            default: millis = Double(msStr.prefix(3)) ?? 0
            }
        }
        return minutes * 60 + seconds + millis / 1000.0
    }
}
