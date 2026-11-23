import Foundation

/// 歌曲数据模型
///
/// 说明：
/// - `fileURL` / 标题 / 歌手 / 专辑 / 时长 参与持久化（App 重启后恢复播放列表）；
/// - `artwork`（专辑封面）仅存在于内存中，不参与 Codable 持久化，
///   封面在需要展示时（列表 / CD 唱片）由 `SongMetadataReader` 异步加载并缓存。
struct Song: Identifiable, Hashable {

    /// 唯一标识（持久化后保持稳定，用于播放列表高亮、封面缓存 key）
    let id: UUID

    /// 音频文件在本地的绝对路径
    var fileURL: URL

    /// 元数据：歌曲名（读取不到时回退为文件名）
    var title: String
    /// 元数据：歌手
    var artist: String
    /// 元数据：专辑
    var album: String
    /// 总时长（秒），异步加载，加载完成前为 0
    var duration: TimeInterval

    init(id: UUID = UUID(),
         fileURL: URL,
         title: String? = nil,
         artist: String? = nil,
         album: String? = nil,
         duration: TimeInterval = 0) {
        self.id = id
        self.fileURL = fileURL
        self.title = title ?? Song.fallbackTitle(from: fileURL)
        self.artist = artist ?? "未知歌手"
        self.album = album ?? "未知专辑"
        self.duration = duration
    }

    /// 无元数据时用「去掉扩展名的文件名」作为歌曲名展示
    static func fallbackTitle(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? url.lastPathComponent : name
    }
}

// MARK: - 持久化编解码（封面等运行时字段不参与）

extension Song: Codable {

    private enum CodingKeys: String, CodingKey {
        case id, fileURL, title, artist, album, duration
    }

    /// 重启恢复时文件可能已被移动 / 删除，解码失败的路径直接丢弃
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fileURL = try c.decode(URL.self, forKey: .fileURL)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? Song.fallbackTitle(from: fileURL)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? "未知歌手"
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? "未知专辑"
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
    }
}

// MARK: - 歌词行模型

/// 一行同步歌词（时间点 + 文本），由 LRC 解析器产出
struct LyricLine: Identifiable, Equatable {
    /// 行ID，用于歌词面板滚动定位
    let id: UUID
    /// 该行歌词出现的精确时间点（秒）
    let time: TimeInterval
    /// 歌词文本
    let text: String

    init(time: TimeInterval, text: String) {
        self.id = UUID()
        self.time = time
        self.text = text
    }
}

/// 一首歌的完整歌词数据
///
/// `lines` 为按时间升序排列的同步歌词；
/// `isSynced == false` 表示这是纯文本歌词（无时间标签，不能同步滚动），界面按普通文本展示。
struct Lyrics {
    var lines: [LyricLine]
    var isSynced: Bool

    static let empty = Lyrics(lines: [], isSynced: false)

    var isEmpty: Bool { lines.isEmpty }
}

// MARK: - 播放列表（歌单）

/// 歌单模型
///
/// - `isFavorites == true` 的歌单是内置的「我喜欢的音乐」，不可删除/重命名；
/// - 歌单只保存歌曲 id 的有序列表，歌曲本体统一存在 PlayerManager.songs 曲库中。
struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// 按加入顺序排列的歌曲 id
    var songIDs: [UUID]
    /// 是否为内置「我喜欢的音乐」歌单
    var isFavorites: Bool

    init(id: UUID = UUID(), name: String, songIDs: [UUID] = [], isFavorites: Bool = false) {
        self.id = id
        self.name = name
        self.songIDs = songIDs
        self.isFavorites = isFavorites
    }
}

// MARK: - 侧边栏列表分区

/// 侧边栏当前选中的歌曲列表：
/// - library   → 歌曲列表（全部导入歌曲）
/// - favorites → 我喜欢的音乐（内置歌单）
/// - playlist  → 用户自建歌单
enum ListSection: Hashable {
    case library
    case favorites
    case playlist(UUID)

    /// 侧边栏 List selection 的 tag 值（稳定字符串，便于恢复）
    var key: String {
        switch self {
        case .library:   return "library"
        case .favorites: return "favorites"
        case .playlist(let id): return "playlist:\(id.uuidString)"
        }
    }
}

// MARK: - 播放模式

/// 播放模式：单曲循环 / 列表循环 / 随机播放
enum PlaybackMode: String, CaseIterable, Codable, Identifiable {
    case repeatOne   // 单曲循环
    case listLoop    // 列表循环
    case shuffle     // 随机播放

    var id: String { rawValue }

    var label: String {
        switch self {
        case .repeatOne: return "单曲循环"
        case .listLoop:  return "列表循环"
        case .shuffle:   return "随机播放"
        }
    }

    /// SF Symbols 图标名，切换按钮复用
    var iconName: String {
        switch self {
        case .repeatOne: return "repeat.1"
        case .listLoop:  return "repeat"
        case .shuffle:   return "shuffle"
        }
    }
}
