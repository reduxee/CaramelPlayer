import Foundation
import AVFoundation
import AppKit
import SwiftUI
import MediaPlayer
import Combine

/// 播放管理器（单例，统一持有并驱动 AVPlayer）
///
/// 架构职责：
/// - 唯一的 AVPlayer 实例，负责 播放/暂停/上一首/下一首/Seek/音量/静音；
/// - 曲库（全部导入歌曲）+ 歌单（我喜欢的音乐 / 用户自建歌单）；
/// - 播放队列：跟随当前浏览的歌单/列表，上下曲在队列内流转；
/// - 播放模式：单曲循环 / 列表循环 / 随机（对外提供 repeat / shuffle 两个开关）；
/// - 文件夹导入与递归扫描、异步批量读取元数据；
/// - 封面缓存（列表缩略图 + 当前大图）与「封面主色」提取（播放器页背景取色）；
/// - 当前歌词加载（内嵌优先 → 外部 lrc 降级）与进度同步；
/// - 状态持久化（重启恢复列表/歌单/模式/音量）。
///
/// 所有 UI 状态都以 @Published 暴露，SwiftUI 视图直接订阅刷新。
@MainActor
final class PlayerManager: ObservableObject {

    static let shared = PlayerManager()

    // MARK: - UI 状态

    /// 曲库：全部导入的歌曲
    @Published private(set) var songs: [Song] = []
    /// 歌单集合（index 0 恒为内置「我喜欢的音乐」）
    @Published private(set) var playlists: [Playlist] = []
    /// 当前播放索引（相对 songs，nil = 尚未播放）
    @Published private(set) var currentIndex: Int?
    /// 是否正在播放
    @Published private(set) var isPlaying = false
    /// 当前播放时间（秒），由周期时间观察器驱动
    @Published private(set) var currentTime: TimeInterval = 0
    /// 当前歌曲总时长（秒）
    @Published private(set) var duration: TimeInterval = 0
    /// 进度条是否正在被用户拖拽（拖拽期间不回写周期时间，避免跳变）
    @Published var isScrubbing = false
    /// 音量 0...1
    @Published var volume: Double = 0.8 {
        didSet {
            player.volume = Float(volume)
            if volume > 0 { isMuted = false }
            persist()
        }
    }
    /// 静音
    @Published var isMuted: Bool = false {
        didSet {
            player.isMuted = isMuted
            persist()
        }
    }
    /// 播放模式（内部仍是三态枚举，对外拆成 repeat / shuffle 两个开关）
    @Published var playbackMode: PlaybackMode = .listLoop {
        didSet { persist() }
    }
    /// 上次停留的页面（0 = 列表页，1 = 播放器页），重启恢复
    @Published var activePage: Int = 0 {
        didSet { persist() }
    }
    /// 当前歌曲大图封面（播放器页展示）
    @Published private(set) var currentArtwork: NSImage?
    /// 播放器页背景色（由当前封面主色派生，深浅模式自动切换；nil = 默认材质）
    @Published private(set) var playerBackground: Color?
    /// 封面缓存版本号：列表缩略图异步加载完成后 +1，驱动行视图重取
    @Published private(set) var artworkRevision = 0
    /// 当前歌词（内嵌优先 → 外部 lrc 降级后的结果）
    @Published private(set) var currentLyrics: Lyrics = .empty
    /// 当前高亮的歌词行（同步歌词用）
    @Published private(set) var activeLyricIndex: Int?
    /// 面向用户的轻量状态提示（如「已跳过损坏文件」），视图以 toast 形式短暂展示
    @Published var statusMessage: String?
    /// 正在批量扫描/读取元数据
    @Published private(set) var isLoadingLibrary = false

    // MARK: - 播放器核心

    /// 唯一 AVPlayer 实例（单例管理器统一驱动）
    private let player = AVPlayer()
    /// 周期时间观察器（0.25s 一次，主队列回调）
    private var timeObserver: Any?
    /// Combine 订阅回收
    private var cancellables = Set<AnyCancellable>()
    /// 封面缓存（key = Song.id，列表缩略图与当前大图共用）
    private var artworkCache: [UUID: NSImage] = [:]
    /// 内嵌歌词原文缓存（key = Song.id，播放时交给 LyricsLoader 判定来源）
    private var embeddedLyricsCache: [UUID: String] = [:]
    /// 歌词加载令牌：切歌后旧异步任务的结果作废，避免过期歌词覆盖新歌
    private var lyricLoadToken = UUID()
    /// 当前播放队列（歌曲 id 顺序表）：上下曲按队列流转；
    /// 从侧边栏某列表点播时队列 = 该列表，从曲库点播时队列 = 全部歌曲
    private var queueIDs: [UUID] = []

    /// 当前播放歌曲
    var currentSong: Song? {
        guard let i = currentIndex, songs.indices.contains(i) else { return nil }
        return songs[i]
    }

    private init() {
        setupPlayer()
        restoreState()
    }

    // MARK: - 初始化与恢复

    /// 配置 AVPlayer：音量、周期时间观察器、播放结束/失败通知
    private func setupPlayer() {
        player.volume = Float(volume)

        // 周期时间观察器：驱动进度条与歌词同步（0.25s 足够平滑且省电）
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.handleTimeUpdate(seconds: CMTimeGetSeconds(time))
            }
        }

        // 单曲自然播完 → 按播放模式决定流转（单曲循环重新播放）
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] note in
                Task { @MainActor [weak self] in
                    guard let self,
                          let item = note.object as? AVPlayerItem,
                          item === self.player.currentItem else { return }
                    self.handleTrackFinished()
                }
            }
            .store(in: &cancellables)

        // 损坏 / 无法解码的音频：AVFoundation 抛出 FailedToPlayToEndTime 通知
        // → 友好提示并自动跳过下一首，绝不崩溃
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
            .sink { [weak self] note in
                Task { @MainActor [weak self] in
                    guard let self,
                          let item = note.object as? AVPlayerItem,
                          item === self.player.currentItem else { return }
                    let name = self.currentSong?.title ?? "未知文件"
                    self.statusMessage = "无法解码「\(name)」，已自动跳过"
                    self.advanceAfterFailure()
                }
            }
            .store(in: &cancellables)
    }

    /// 重启后恢复：曲库 / 歌单 / 索引 / 模式 / 音量（不自动续播，等待用户按下播放）
    private func restoreState() {
        let saved = AppSettings.restore()
        songs = saved.songs
        playlists = saved.playlists
        playbackMode = saved.mode
        volume = saved.volume
        isMuted = saved.isMuted
        currentIndex = saved.currentIndex
        activePage = (0...1).contains(saved.activePage) ? saved.activePage : 0
        queueIDs = songs.map { $0.id } // 默认队列 = 全部歌曲

        if let idx = saved.currentIndex {
            // 恢复当前曲目的封面 / 歌词（不开始播放）
            Task { await self.loadAttachments(for: idx) }
        }
        // 恢复整个列表的元数据（列表页要显示歌名/歌手/专辑/时长）
        Task { await self.loadMetadataForAll() }
    }

    private func handleTimeUpdate(seconds: TimeInterval) {
        guard !seconds.isNaN else { return }
        currentTime = seconds
        updateActiveLyricIndex()
    }

    // MARK: - 基础播放控制

    /// 播放指定索引的歌曲（相对曲库；队列重置为全部歌曲）
    func play(at index: Int) {
        guard songs.indices.contains(index) else { return }
        queueIDs = songs.map { $0.id }
        currentIndex = index
        playSong()
    }

    /// 播放某一首歌，并把队列设为它所在的列表（列表页 / 歌单内点播用）
    func play(_ song: Song, from sectionSongs: [Song]) {
        guard let globalIndex = songs.firstIndex(where: { $0.id == song.id }) else { return }
        queueIDs = sectionSongs.map { $0.id }
        currentIndex = globalIndex
        playSong()
    }

    /// 播放 / 暂停切换
    func togglePlayPause() {
        if currentIndex == nil, !songs.isEmpty {
            play(at: 0)
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if player.currentItem == nil, currentIndex != nil {
                // 首次播放：还没有装载任何 item
                playSong()
            } else {
                player.play()
                isPlaying = true
            }
        }
        updateNowPlayingInfo()
    }

    /// 上一首：播放超过 3 秒则回到本曲开头，否则切换到上一首（符合主流播放器习惯）
    func previous() {
        guard let idx = positionInQueue() else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        let prev = (idx - 1 + queueIDs.count) % queueIDs.count
        playQueuePosition(prev)
    }

    /// 下一首（用户手动触发）
    func next() {
        advance(auto: false)
    }

    /// 进度跳转（进度条拖拽结束 / 远程指令 seek）
    func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        updateActiveLyricIndex()
        updateNowPlayingInfo()
    }

    /// 静音切换
    func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - 播放模式（单按钮循环切换：列表循环 → 单曲循环 → 随机播放）

    /// 循环切换播放模式：列表循环 → 单曲循环 → 随机播放 → 列表循环
    func cyclePlaybackMode() {
        let all: [PlaybackMode] = [.listLoop, .repeatOne, .shuffle]
        let idx = all.firstIndex(of: playbackMode) ?? 0
        playbackMode = all[(idx + 1) % all.count]
        statusMessage = "已切换：\(playbackMode.label)"
    }

    // MARK: - 内部播放流转

    /// 装载并播放当前索引指向的歌曲
    private func playSong() {
        guard let idx = currentIndex, let song = currentSong else { return }

        let item = AVPlayerItem(url: song.fileURL)
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = song.duration
        player.play()
        isPlaying = true
        persist()
        updateNowPlayingInfo()

        // 异步补齐：元数据（时长/标签）、封面、歌词
        Task { await loadAttachments(for: idx) }
    }

    /// 播放结束后的自动流转（模式：单曲循环 / 列表循环 / 随机）
    private func handleTrackFinished() {
        switch playbackMode {
        case .repeatOne:
            // 单曲循环：回到本曲开头继续播（不切歌）
            player.seek(to: .zero)
            player.play()
            isPlaying = true
        case .listLoop, .shuffle:
            advance(auto: true)
        }
    }

    /// 当前歌曲在队列中的位置（找不到时按曲库索引兜底）
    private func positionInQueue() -> Int? {
        guard let currentID = currentSong?.id else { return nil }
        if let pos = queueIDs.firstIndex(of: currentID) { return pos }
        return currentIndex
    }

    /// 播放队列中指定位置的歌曲
    private func playQueuePosition(_ position: Int) {
        guard queueIDs.indices.contains(position) else { return }
        let id = queueIDs[position]
        guard let globalIndex = songs.firstIndex(where: { $0.id == id }) else { return }
        currentIndex = globalIndex
        playSong()
    }

    /// 选取下一首并播放
    /// - auto: true 表示自然播完的自动流转；false 为用户手动点下一首
    private func advance(auto: Bool) {
        guard !queueIDs.isEmpty else { return }
        let current = positionInQueue() ?? 0

        let nextPosition: Int
        if playbackMode == .shuffle, queueIDs.count > 1 {
            // 随机但避免连续重复当前曲
            var candidate = current
            while candidate == current {
                candidate = Int.random(in: 0..<queueIDs.count)
            }
            nextPosition = candidate
        } else {
            // 列表循环：到末尾回到开头；单曲循环手动点下一首也顺延
            nextPosition = (current + 1) % queueIDs.count
        }
        playQueuePosition(nextPosition)
    }

    /// 解码失败自动跳过：寻找下一首可用的歌曲（避免连续损坏造成死循环）
    private func advanceAfterFailure() {
        guard !queueIDs.isEmpty else { return }
        let start = positionInQueue() ?? 0
        for step in 1..<max(queueIDs.count, 2) {
            let candidate = (start + step) % queueIDs.count
            if candidate == start { break }
            playQueuePosition(candidate)
            return
        }
        stopEverything()
    }

    /// 全部失败 / 空列表时的兜底
    private func stopEverything() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        currentArtwork = nil
        playerBackground = nil
        currentLyrics = .empty
        activeLyricIndex = nil
    }

    // MARK: - 元数据 / 封面 / 歌词加载

    /// 为指定歌曲补齐 时长/标签（若缺失）、封面、歌词。
    /// 一次 AVAsset 读取尽量复用（metadata / artwork / lyrics 都来自同一次解析）。
    private func loadAttachments(for index: Int) async {
        guard songs.indices.contains(index) else { return }
        let song = songs[index]
        let songID = song.id
        let fileURL = song.fileURL

        let needsMetadata = song.duration <= 0
            || song.title == Song.fallbackTitle(from: song.fileURL)
        let needsArtwork = artworkCache[songID] == nil
        let needsLyrics = embeddedLyricsCache[songID] == nil

        // 三者任一缺失才读一次 AVAsset（nonisolated async，文件 IO 不占主线程）
        var meta: SongMetadata?
        if needsMetadata || needsArtwork || needsLyrics {
            meta = await SongMetadataReader.read(from: fileURL)
        }

        // ---- 元数据回写列表 ----
        if needsMetadata, let meta {
            applyMetadata(meta, to: index)
        }

        // ---- 封面：优先内存缓存，其次本次读取结果 ----
        if let cached = artworkCache[songID] {
            currentArtwork = cached
        } else if let data = meta?.artworkData, let image = NSImage(data: data) {
            storeArtwork(image, for: songID)
            currentArtwork = image
        } else {
            currentArtwork = nil // 视图层显示默认占位图
        }
        refreshPlayerBackground()

        // ---- 【重点：歌词加载】内嵌歌词优先，外部 lrc 降级 ----
        // LyricsLoader 内部完成来源判定与降级；
        // lyricLoadToken 防止快速切歌时旧任务的结果覆盖新歌的歌词。
        let token = UUID()
        lyricLoadToken = token

        let embedded = embeddedLyricsCache[songID] ?? meta?.lyricsText
        if let text = meta?.lyricsText, embeddedLyricsCache[songID] == nil {
            embeddedLyricsCache[songID] = text
        }

        let lyrics = await LyricsLoader.load(fileURL: fileURL, embeddedText: embedded)
        guard lyricLoadToken == token, currentSong?.id == songID else { return }
        currentLyrics = lyrics
        updateActiveLyricIndex()
    }

    /// 把读到的元数据回写到列表（异步加载完成后列表刷新时长/标签）
    private func applyMetadata(_ meta: SongMetadata, to index: Int) {
        guard songs.indices.contains(index) else { return }
        var song = songs[index]
        if let t = meta.title { song.title = t }
        if let a = meta.artist { song.artist = a }
        if let al = meta.album { song.album = al }
        if meta.duration > 0 { song.duration = meta.duration }
        songs[index] = song
        if let text = meta.lyricsText {
            embeddedLyricsCache[song.id] = text
        }
        if index == currentIndex {
            duration = song.duration
        }
        persist()
    }

    // MARK: - 封面缓存（列表缩略图）与背景取色

    /// 列表行/迷你条用的封面查询：有缓存直接返回，没有则返回 nil 并触发异步加载
    func artwork(for song: Song) -> NSImage? {
        if let cached = artworkCache[song.id] { return cached }
        Task { [weak self] in
            guard let self else { return }
            let meta = await SongMetadataReader.read(from: song.fileURL)
            guard let data = meta?.artworkData, let image = NSImage(data: data) else { return }
            self.storeArtwork(image, for: song.id)
        }
        return nil
    }

    /// 存入封面缓存；如果这首歌正好是当前播放曲，同步更新大图与背景色
    private func storeArtwork(_ image: NSImage, for songID: UUID) {
        guard artworkCache[songID] == nil else { return }
        artworkCache[songID] = image
        artworkRevision += 1 // 让列表行重新查询缓存
        if currentSong?.id == songID {
            currentArtwork = image
            refreshPlayerBackground()
        }
    }

    /// 播放器页背景取色：从当前封面提取主色，派生浅色/深色两个变体（跟随系统切换）
    private func refreshPlayerBackground() {
        guard let artwork = currentArtwork else {
            playerBackground = nil
            return
        }
        playerBackground = CoverColorExtractor.background(from: artwork)
    }

    // MARK: - 歌单操作

    /// 指定分区的歌曲列表（侧边栏选择：曲库 / 我喜欢的音乐 / 某歌单）
    func songs(in section: ListSection) -> [Song] {
        switch section {
        case .library:
            return songs
        case .favorites:
            guard let fav = playlists.first(where: { $0.isFavorites }) else { return [] }
            return fav.songIDs.compactMap { id in songs.first { $0.id == id } }
        case .playlist(let id):
            guard let pl = playlists.first(where: { $0.id == id }) else { return [] }
            return pl.songIDs.compactMap { songID in songs.first { $0.id == songID } }
        }
    }

    /// 是否已收藏（在「我喜欢的音乐」中）
    func isLiked(_ song: Song) -> Bool {
        guard let fav = playlists.first(where: { $0.isFavorites }) else { return false }
        return fav.songIDs.contains(song.id)
    }

    /// 收藏 / 取消收藏
    func toggleLike(_ song: Song) {
        guard let favIndex = playlists.firstIndex(where: { $0.isFavorites }) else { return }
        if let pos = playlists[favIndex].songIDs.firstIndex(of: song.id) {
            playlists[favIndex].songIDs.remove(at: pos)
        } else {
            playlists[favIndex].songIDs.append(song.id)
        }
        persist()
    }

    /// 新建歌单并返回
    @discardableResult
    func createPlaylist(named name: String) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(name: trimmed.isEmpty ? "新建歌单" : trimmed)
        playlists.append(playlist)
        persist()
        return playlist
    }

    /// 把歌曲加入歌单（已存在则忽略）
    func add(_ song: Song, to playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if !playlists[idx].songIDs.contains(song.id) {
            playlists[idx].songIDs.append(song.id)
            persist()
        }
    }

    /// 从歌单移除歌曲
    func remove(_ song: Song, from playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }),
              let pos = playlists[idx].songIDs.firstIndex(of: song.id) else { return }
        playlists[idx].songIDs.remove(at: pos)
        persist()
    }

    /// 删除自建歌单（内置「我喜欢的音乐」不可删除）
    func deletePlaylist(_ playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[idx].isFavorites else { return }
        playlists.remove(at: idx)
        persist()
    }

    // MARK: - 文件夹导入（递归扫描）

    /// 从文件夹导入：递归扫描所有支持的音频，异步批量读取元数据
    func importFolder(_ url: URL) {
        isLoadingLibrary = true
        let existing = Set(songs.map { $0.fileURL.standardizedFileURL.path })

        // 目录扫描放后台线程（目录可能很大）
        Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { () -> [URL] in
                scanAudioFiles(in: url)
            }.value

            guard let self else { return }

            // 相对已导入列表去重
            let newURLs = found.filter { !existing.contains($0.standardizedFileURL.path) }
            guard !newURLs.isEmpty else {
                self.isLoadingLibrary = false
                self.statusMessage = "没有发现新的音频文件"
                return
            }

            // 先用文件名占位入表（UI 立即有反馈），再异步补齐元数据
            let newSongs = newURLs.map { Song(fileURL: $0) }
            let insertAt = self.songs.count
            self.songs.append(contentsOf: newSongs)
            self.queueIDs = self.songs.map { $0.id }
            self.persist()

            await self.loadMetadataForAll()

            self.isLoadingLibrary = false
            if self.currentIndex == nil {
                self.currentIndex = insertAt
            }
            self.statusMessage = "已导入 \(newSongs.count) 首歌曲"
        }
    }

    /// 批量读取列表中所有元数据不完整的歌曲（TaskGroup 限制并发，避免瞬时大开销）
    private func loadMetadataForAll() async {
        let pending = songs.enumerated().filter {
            $0.element.duration <= 0 || $0.element.title == Song.fallbackTitle(from: $0.element.fileURL)
        }
        guard !pending.isEmpty else { return }

        var skipped = 0
        await withTaskGroup(of: (Int, SongMetadata?).self) { group in
            var iterator = pending.makeIterator()
            let maxConcurrent = 6

            func addNext(_ group: inout TaskGroup<(Int, SongMetadata?)>) {
                guard let (idx, song) = iterator.next() else { return }
                group.addTask {
                    // SongMetadataReader.read 是 nonisolated async，文件 IO 不占主线程
                    let meta = await SongMetadataReader.read(from: song.fileURL)
                    return (idx, meta)
                }
            }
            for _ in 0..<maxConcurrent { addNext(&group) }

            for await (idx, meta) in group {
                addNext(&group)
                if let meta {
                    applyMetadata(meta, to: idx)
                } else {
                    skipped += 1
                }
            }
        }

        if skipped > 0 {
            statusMessage = "有 \(skipped) 个文件无法解码，已忽略"
        }
    }

    /// 清空曲库（歌单记录一并清空）
    func clearPlaylist() {
        stopEverything()
        songs = []
        queueIDs = []
        currentIndex = nil
        artworkCache.removeAll()
        embeddedLyricsCache.removeAll()
        for idx in playlists.indices {
            playlists[idx].songIDs = []
        }
        persist()
        statusMessage = "播放列表已清空"
    }

    // MARK: - 歌词同步

    /// 根据当前播放时间计算高亮的歌词行（同步歌词）。
    /// 逻辑：最后一个 time <= currentTime 的行；歌曲前奏期（无行命中）不高亮。
    private func updateActiveLyricIndex() {
        guard currentLyrics.isSynced, !currentLyrics.isEmpty else {
            activeLyricIndex = nil
            return
        }
        let lines = currentLyrics.lines
        var result: Int? = nil
        for (i, line) in lines.enumerated() {
            if line.time <= currentTime + 0.05 {
                result = i
            } else {
                break
            }
        }
        activeLyricIndex = result
    }

    // MARK: - Now Playing（媒体按键 / 系统控制中心联动）

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        if let song = currentSong {
            info[MPMediaItemPropertyTitle] = song.title
            info[MPMediaItemPropertyArtist] = song.artist
            info[MPMediaItemPropertyAlbumTitle] = song.album
            info[MPMediaItemPropertyPlaybackDuration] = song.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 持久化

    private func persist() {
        AppSettings.save(songs: songs, playlists: playlists, currentIndex: currentIndex,
                         mode: playbackMode, volume: volume, isMuted: isMuted,
                         activePage: activePage)
    }
}

// MARK: - 封面主色提取

/// 封面主色提取器：播放器页背景取色用
///
/// 算法：封面降采样到 48×48 像素 → 颜色量化分桶（每通道 16 级）→
/// 以「出现次数 × (0.3 + 饱和度)」为权重挑出主色（偏向鲜艳色而非背景灰）→
/// 派生 浅色模式（提亮降饱和）/ 深色模式（压暗）两个变体，合成动态色。
enum CoverColorExtractor {

    static func background(from image: NSImage) -> Color {
        guard let (light, dark) = dominantColors(from: image) else {
            return Theme.defaultBackground
        }
        let dynamic = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua ? dark : light
        }
        return Color(nsColor: dynamic)
    }

    /// 返回 (浅色变体, 深色变体)；提取失败返回 nil
    private static func dominantColors(from image: NSImage) -> (light: NSColor, dark: NSColor)? {
        let size = 48
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                          pixelsWide: size, pixelsHigh: size,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .low
            image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        }
        NSGraphicsContext.restoreGraphicsState()

        // 颜色分桶：key = 量化后的 RGB（每通道 16 级），累计次数与通道和
        var buckets: [UInt32: (count: Int, r: Double, g: Double, b: Double)] = [:]
        for y in 0..<size {
            for x in 0..<size {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let r = Double(color.redComponent)
                let g = Double(color.greenComponent)
                let b = Double(color.blueComponent)
                let key = (UInt32(r * 15) << 8) | (UInt32(g * 15) << 4) | UInt32(b * 15)
                if var bucket = buckets[key] {
                    bucket.count += 1
                    bucket.r += r; bucket.g += g; bucket.b += b
                    buckets[key] = bucket
                } else {
                    buckets[key] = (1, r, g, b)
                }
            }
        }
        guard !buckets.isEmpty else { return nil }

        // 主色桶 = max(次数 × (0.3 + 饱和度))，鲜艳色优先，避免整片灰白
        var bestKey: UInt32?
        var bestScore = 0.0
        for (key, bucket) in buckets {
            let r = bucket.r / Double(bucket.count)
            let g = bucket.g / Double(bucket.count)
            let b = bucket.b / Double(bucket.count)
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC <= 0 ? 0 : (maxC - minC) / maxC
            let score = Double(bucket.count) * (0.3 + saturation)
            if score > bestScore {
                bestScore = score
                bestKey = key
            }
        }
        guard let key = bestKey, let bucket = buckets[key] else { return nil }

        let r = bucket.r / Double(bucket.count)
        let g = bucket.g / Double(bucket.count)
        let b = bucket.b / Double(bucket.count)
        let base = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)

        // 浅色模式：提亮、降饱和（细腻的浅色调背景，不抢内容）
        let light = NSColor(hue: hue, saturation: min(1, sat * 0.30),
                            brightness: min(1, 0.55 + bri * 0.40), alpha: 1)
        // 深色模式：压暗、保留部分饱和（浓郁的深色氛围）
        let dark = NSColor(hue: hue, saturation: min(1, sat * 0.75),
                           brightness: min(0.42, 0.12 + bri * 0.30), alpha: 1)
        return (light, dark)
    }
}

// MARK: - 递归扫描（独立函数，后台线程执行）

/// 递归遍历目录，收集所有受支持的音频文件 URL（按名称排序）
private func scanAudioFiles(in folder: URL) -> [URL] {
    let fileManager = FileManager.default
    var results: [URL] = []

    // enumerator 自动递归子目录；跳过隐藏文件（.Trash 等）
    guard let enumerator = fileManager.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isAliasFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return [] }

    for case let url as URL in enumerator {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isAliasFileKey])
        if values?.isDirectory == true {
            // 套娃符号链接 / 别名会引入死循环，直接跳过其子树
            if values?.isAliasFile == true { enumerator.skipDescendants() }
            continue
        }
        guard values?.isRegularFile == true else { continue }
        let ext = url.pathExtension.lowercased()
        if SongMetadataReader.supportedExtensions.contains(ext) {
            results.append(url)
        }
    }
    return results.sorted { $0.lastPathComponent < $1.lastPathComponent }
}
