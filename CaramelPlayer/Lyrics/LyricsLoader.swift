import Foundation

/// 歌词加载模块：统一「内嵌歌词 → 外部 .lrc 文件」两条来源的优先级与降级逻辑
///
/// 【重点：歌词来源优先级】
/// 1. 音频文件**内部嵌入**的同步歌词（内嵌 LRC，即 ID3 USLT / iTunes ©lyr / FLAC LYRICS
///    字段里保存的 LRC 文本）——判断标准：文本包含标准 LRC 时间标签；
/// 2. 内嵌歌词格式异常（存在文本但没有时间标签，是纯文本歌词）时，
///    **降级**尝试读取同目录下同名 `.lrc` 文件（例如 `歌曲.flac` → `歌曲.lrc`）；
/// 3. 外部 lrc 也不存在 → 回退展示内嵌的纯文本歌词（不能同步滚动）；
/// 4. 两者都不存在 → 歌词面板显示「暂无歌词」。
enum LyricsLoader {

    /// 加载一首歌的完整歌词。
    /// - Parameters:
    ///   - fileURL: 音频文件路径（用于定位同名 .lrc）
    ///   - embeddedText: 从音频内嵌标签读出的歌词原文（可能为 nil）
    static func load(fileURL: URL, embeddedText: String?) async -> Lyrics {
        // ---------- 1. 内嵌同步歌词（最高优先级） ----------
        if let text = embeddedText, LyricsParser.looksLikeLRC(text) {
            let lines = LyricsParser.parse(text)
            if !lines.isEmpty {
                return Lyrics(lines: lines, isSynced: true)
            }
        }

        // ---------- 2. 降级：外部同名 .lrc 文件 ----------
        // 内嵌歌词缺失，或内嵌文本不含时间标签（格式异常）时走这里。
        // 文件读取放在后台线程，避免大目录 / 网络卷拖慢主线程。
        let external = await Task.detached(priority: .userInitiated) { () -> Lyrics? in
            for ext in ["lrc", "LRC"] {
                let lrcURL = fileURL.deletingPathExtension().appendingPathExtension(ext)
                guard let raw = try? String(contentsOf: lrcURL, encoding: .utf8) else { continue }
                let lines = LyricsParser.parse(raw)
                if !lines.isEmpty {
                    return Lyrics(lines: lines, isSynced: true)
                }
            }
            return nil
        }.value
        if let external = external {
            return external
        }

        // ---------- 3. 内嵌纯文本歌词（不可同步，但比「暂无歌词」好） ----------
        if let text = embeddedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            // 纯文本拆行展示，time 统一为 0，界面按 isSynced == false 处理
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { LyricLine(time: 0, text: String($0)) }
            return Lyrics(lines: lines, isSynced: false)
        }

        // ---------- 4. 完全没有歌词 ----------
        return Lyrics.empty
    }
}
