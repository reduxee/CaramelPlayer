import Foundation
import AVFoundation
import AppKit

/// 音频元信息统一读取模块
///
/// 职责：给定一个本地音频文件，读取 歌曲名 / 歌手 / 专辑 / 时长 / 内嵌专辑封面 / 内嵌歌词。
///
/// 读取策略（按容器格式自动分流）：
/// 1. **FLAC**：AVFoundation 对 FLAC 的 Vorbis Comment 暴露不完整，
///    直接走 `FlacMetadataParser` 手动解析（含内嵌歌词与封面）；
/// 2. **mp3 / m4a / aac / wav 等**：走 AVFoundation 的 AVMetadataItem：
///    - 常规标签（标题/歌手/专辑/封面）用 Common Identifier 读取，跨容器最稳；
///    - 【内嵌歌词重点】用 KeySpace + Key 精确匹配：
///        · ID3（mp3）   → keySpace `AVMetadataKeySpace.id3`，key `USLT` / `ULT`（ID3v2.2）
///        · iTunes（m4a）→ keySpace `AVMetadataKeySpace.iTunes`，key `©lyr`
///      内嵌歌词字段里存的往往就是完整 LRC 文本（同步歌词）。
/// 3. 时长统一用 AVAsset 的 duration（对损坏文件会抛错 → 调用方据此跳过该歌曲）。
struct SongMetadata {

    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval
    /// 内嵌专辑封面原始数据
    var artworkData: Data?
    /// 【内嵌歌词】原始文本（可能是 LRC 同步歌词，也可能是纯文本，由 LyricsLoader 判定）
    var lyricsText: String?
}

enum SongMetadataReader {

    /// 支持的音频扩展名（导入文件夹时按此过滤）
    static let supportedExtensions: Set<String> = ["mp3", "flac", "wav", "m4a", "aac"]

    /// 异步读取单个文件的完整元数据。
    /// 文件损坏 / 无法解码时返回 nil，调用方负责「跳过不崩溃」。
    static func read(from url: URL) async -> SongMetadata? {
        let asset = AVAsset(url: url)

        // duration：损坏文件在这里就会失败
        var duration: TimeInterval = 0
        do {
            let d = try await asset.load(.duration)
            duration = CMTimeGetSeconds(d)
            if duration.isNaN || duration <= 0 { duration = 0 }
        } catch {
            return nil
        }

        // FLAC：直接走手动解析（标签 + 封面 + 内嵌歌词一步到位）
        if url.pathExtension.lowercased() == "flac" {
            if let info = try? FlacMetadataParser.parse(url: url) {
                let lyrics = firstNonEmpty(
                    info.tags["LYRICS"],
                    info.tags["UNSYNCEDLYRICS"],
                    info.tags["SYNCEDLYRICS"]
                )
                return SongMetadata(
                    title: nonEmpty(info.tags["TITLE"]),
                    artist: nonEmpty(info.tags["ARTIST"]),
                    album: nonEmpty(info.tags["ALBUM"]),
                    duration: duration,
                    artworkData: info.pictureData,
                    lyricsText: lyrics
                )
            }
            // FLAC 解析失败但能播 → 至少返回时长，标签全部留空回退默认值
            return SongMetadata(title: nil, artist: nil, album: nil,
                                duration: duration, artworkData: nil, lyricsText: nil)
        }

        // 其他格式：AVFoundation 元数据
        var metadata: [AVMetadataItem] = []
        if let items = try? await asset.load(.commonMetadata) {
            metadata.append(contentsOf: items)
        }
        if let items = try? await asset.load(.metadata) {
            metadata.append(contentsOf: items)
        }

        // 常规标签：common identifier 读取（AVF 已帮我们抹平 ID3 / iTunes / RIFF 差异）
        let title = await stringValue(from: metadata, identifier: .commonIdentifierTitle)
        let artist = await stringValue(from: metadata, identifier: .commonIdentifierArtist)
        let album = await stringValue(from: metadata, identifier: .commonIdentifierAlbumName)
        let artworkData = await firstArtwork(from: metadata)

        // 【内嵌歌词重点】按 KeySpace + Key 精确匹配歌词字段
        let lyricsText = await embeddedLyrics(from: metadata)

        return SongMetadata(title: title, artist: artist, album: album,
                            duration: duration, artworkData: artworkData, lyricsText: lyricsText)
    }

    // MARK: - 【内嵌歌词读取逻辑】AVMetadataItem 匹配规则
    //
    // 内嵌歌词在不同容器中的存放位置：
    //   mp3 (ID3v2.3/v2.4)  → USLT 帧（Unsynchronized Lyric Text）,很多人直接把 LRC 整段塞进去
    //   mp3 (ID3v2.2)       → ULT 帧
    //   m4a / aac (iTunes)  → ©lyr atom
    // AVFoundation 把它们原样暴露在 AVMetadataItem 中（key/keySpace），取stringValue即可。
    private static func embeddedLyrics(from items: [AVMetadataItem]) async -> String? {
        // (keySpace, key) 候选列表，按优先级排列（AVMetadataKeySpace 为结构体，比较 rawValue）
        let candidates: [(keySpace: AVMetadataKeySpace, key: String)] = [
            (AVMetadataKeySpace.id3, "USLT"),             // ID3v2.3/2.4 歌词帧（最常见）
            (AVMetadataKeySpace.id3, "ULT"),              // ID3v2.2 歌词帧
            (AVMetadataKeySpace.iTunes, "\u{00A9}lyr")    // m4a/aac 的 ©lyr
        ]
        for (space, key) in candidates {
            for item in items {
                if let itemKey = item.key as? String,
                   itemKey.caseInsensitiveCompare(key) == .orderedSame,
                   item.keySpace?.rawValue == space.rawValue {
                    // macOS 13 起 stringValue 弃用，改用 async load（结果一致）
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        return value
                    }
                }
            }
        }
        return nil
    }

    // MARK: - 小工具

    private static func stringValue(from items: [AVMetadataItem],
                                     identifier: AVMetadataIdentifier) async -> String? {
        let matched = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
        guard let first = matched.first else { return nil }
        return nonEmpty(try? await first.load(.stringValue))
    }

    /// 封面：common identifier artwork 优先，其次 iTunes covr
    private static func firstArtwork(from items: [AVMetadataItem]) async -> Data? {
        let common = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork)
        if let first = common.first, let data = try? await first.load(.dataValue), !data.isEmpty {
            return data
        }
        for item in items {
            if let key = item.key as? String,
               key.caseInsensitiveCompare("covr") == .orderedSame,
               item.keySpace?.rawValue == AVMetadataKeySpace.iTunes.rawValue,
               let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for v in values {
            if let v = nonEmpty(v) { return v }
        }
        return nil
    }
}
