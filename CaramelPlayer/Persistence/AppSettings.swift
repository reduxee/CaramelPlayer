import Foundation

/// 状态记忆持久化模块
///
/// 用 UserDefaults 保存：
/// - 播放列表（Song 数组的 JSON，内含文件绝对路径）
/// - 用户歌单（Playlist 数组：我喜欢的音乐 + 自建歌单）
/// - 当前播放索引 / 播放模式 / 音量 / 是否静音 / 上次停留的页面
///
/// App 重启后由 PlayerManager 在初始化时调用 `restore()` 恢复。
/// 说明：本项目未开启 App Sandbox（纯本地播放器，无网络权限需求），
/// 直接用绝对路径持久化即可；若日后上沙盒，需改为存储 security-scoped bookmark。
enum AppSettings {

    private static let playlistKey = "caramel.playlist"
    private static let userPlaylistsKey = "caramel.userPlaylists"
    private static let indexKey = "caramel.currentIndex"
    private static let modeKey = "caramel.playbackMode"
    private static let volumeKey = "caramel.volume"
    private static let mutedKey = "caramel.isMuted"
    private static let pageKey = "caramel.activePage"

    struct SavedState {
        var songs: [Song]
        var playlists: [Playlist]
        var currentIndex: Int?
        var mode: PlaybackMode
        var volume: Double
        var isMuted: Bool
        var activePage: Int
    }

    // MARK: - 保存

    static func save(songs: [Song], playlists: [Playlist], currentIndex: Int?,
                     mode: PlaybackMode, volume: Double, isMuted: Bool, activePage: Int) {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(songs) {
            d.set(data, forKey: playlistKey)
        }
        if let data = try? JSONEncoder().encode(playlists) {
            d.set(data, forKey: userPlaylistsKey)
        }
        d.set(currentIndex ?? -1, forKey: indexKey)
        d.set(mode.rawValue, forKey: modeKey)
        d.set(volume, forKey: volumeKey)
        d.set(isMuted, forKey: mutedKey)
        d.set(activePage, forKey: pageKey)
    }

    // MARK: - 恢复

    /// 读取上次的全部状态；文件已被移动/删除的歌曲会被自动过滤
    static func restore() -> SavedState {
        let d = UserDefaults.standard
        var songs: [Song] = []
        if let data = d.data(forKey: playlistKey),
           let decoded = try? JSONDecoder().decode([Song].self, from: data) {
            // 只保留磁盘上仍然存在的文件
            songs = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        }
        var playlists: [Playlist] = []
        if let data = d.data(forKey: userPlaylistsKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        // 保证「我喜欢的音乐」始终存在且排第一
        if !playlists.contains(where: { $0.isFavorites }) {
            playlists.insert(Playlist(name: "我喜欢的音乐", isFavorites: true), at: 0)
        } else if let idx = playlists.firstIndex(where: { $0.isFavorites }), idx != 0 {
            playlists.swapAt(0, idx)
        }
        let idx = d.integer(forKey: indexKey)
        let index = (idx >= 0 && idx < songs.count) ? idx : nil
        let mode = PlaybackMode(rawValue: d.string(forKey: modeKey) ?? "") ?? .listLoop
        let volume = d.object(forKey: volumeKey) as? Double ?? 0.8
        let isMuted = d.bool(forKey: mutedKey)
        let page = d.object(forKey: pageKey) as? Int ?? 0
        return SavedState(songs: songs, playlists: playlists, currentIndex: index, mode: mode,
                          volume: volume, isMuted: isMuted, activePage: page)
    }
}
