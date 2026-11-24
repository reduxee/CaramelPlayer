import SwiftUI
import AppKit

/// 页面：歌曲列表页（跟随侧边栏选中项：歌曲列表 / 喜欢 / 自建歌单）
///
/// - 顶部工具栏与列表同用白色背景（一体化），并从窗口最上沿开始，不留空白
/// - 右上角是「搜索框样式」的入口按钮：不是输入框，点击后切到独立搜索页
/// - 行：封面缩略图（点击直接跳转播放器页）+ 歌曲名 / 歌手 / 专辑 / 时长 + 收藏心形
/// - 右键菜单：添加到歌单 / 从歌单移除 / 收藏
/// - 当前播放歌曲高亮；列表自动滚动跟随正在播放的曲目
/// - 空状态：引导用户导入本地音乐文件夹
struct SongListView: View {

    let section: ListSection
    /// 点击顶部搜索入口 → 由外层切到搜索页
    var onSearch: () -> Void = {}

    @ObservedObject private var player = PlayerManager.shared

    /// 新建歌单弹窗（从右键菜单触发）
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""

    /// 当前分区按「拼音/英文首字母」排序后的歌曲（显示与播放队列共用同一顺序）
    @State private var sortedSongs: [Song] = []
    /// 字母分组索引（每个字母的第一首歌，右侧索引条跳转用）
    @State private var letterGroups: [(letter: String, firstID: UUID)] = []

    /// 当前分区的原始歌曲
    private var rawSongs: [Song] {
        player.songs(in: section)
    }

    /// 分区标题
    private var sectionTitle: String {
        switch section {
        case .library: return "歌曲列表"
        case .favorites: return "喜欢"
        case .playlist(let id):
            return player.playlists.first(where: { $0.id == id })?.name ?? "歌单"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
                .opacity(0.5)
            if rawSongs.isEmpty {
                emptyState
            } else {
                songTable
            }
        }
        .background(Theme.pageBackground)
        // 曲库 / 歌单 / 分区变化时重建排序结果（带缓存，不会随渲染重复计算）
        .onAppear { rebuildIndex() }
        .onChange(of: section) { _ in rebuildIndex() }
        .onChange(of: player.songs) { _ in rebuildIndex() }
        .onChange(of: player.playlists) { _ in rebuildIndex() }
        .alert("新建歌单", isPresented: $showCreatePlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") {
                _ = player.createPlaylist(named: newPlaylistName)
                newPlaylistName = ""
            }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        }
    }

    // MARK: - 顶部工具栏（白色一体化背景，右上角搜索栏）

    private var toolbar: some View {
        HStack(spacing: 12) {
            // 标题稍大一些；导入 / 清空等操作已移到「设置 → 设置歌单」
            Text(sectionTitle)
                .font(.system(size: 22, weight: .semibold))

            Spacer()

            if player.isLoadingLibrary {
                ProgressView()
                    .controlSize(.small)
                    .help("正在扫描并读取音频信息…")
            }
            Text("共 \(rawSongs.count) 首")
                .font(.callout)
                .foregroundStyle(Theme.secondary)

            // 右上角搜索入口（长得像输入框，但点击是跳转搜索页，不能直接输入）
            searchEntry
        }
        .padding(.horizontal, 16)
        // 与侧边栏 Logo 区同高：两条分隔线严格对齐
        .frame(height: Theme.topBarHeight)
    }

    /// 搜索入口：视觉上与搜索框一致，但是按钮 —— 点击进入独立搜索页
    private var searchEntry: some View {
        Button(action: onSearch) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                Text("搜索歌名、歌手、专辑")
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 200)
            .hoverHighlight(cornerRadius: 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.10))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("点击进入搜索页")
    }

    // MARK: - 歌曲列表

    /// 列表主体：可滚动（显示滚动条）+ 右下角定位按钮 + 右侧字母索引
    private var songTable: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    ScrollView(showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            // 列头（歌曲名 / 歌手 / 专辑 / 时长）
                            headerRow
                                .padding(.horizontal, 16)

                            ForEach(sortedSongs) { song in
                                SongRow(song: song,
                                        isCurrent: player.currentSong?.id == song.id,
                                        isPlaying: player.isPlaying,
                                        section: section,
                                        queue: sortedSongs)
                                    .id(song.id)
                                    // 双击行（任意位置）→ 在当前列表的队列内播放
                                    .onTapGesture(count: 2) {
                                        player.play(song, from: sortedSongs)
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.bottom, 40)
                    }

                    // 右下角：定位到当前播放歌曲（歌曲较多时才有意义）
                    if player.currentSong != nil, sortedSongs.count > 8 {
                        locateButton(proxy)
                            .opacity(0.88)
                            .padding(.trailing, 26)
                            .padding(.bottom, 14)
                    }
                }

                // 右侧字母索引（只有 2 个及以上分组时才显示）
                if letterGroups.count > 1 {
                    letterIndexBar(proxy: proxy)
                }
            }
            // 进入页面（含重启 App 后恢复）→ 直接把列表定位到当前选中的歌曲
            .onAppear {
                guard let id = player.currentSong?.id else { return }
                DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                // LazyVStack 首帧可能还没完成布局，稍后再补一次（无动画，避免看到跳动）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            // 切歌时滚动跟随
            .onChange(of: player.currentSong?.id) { newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    /// 重建排序结果与字母分组（曲库 / 歌单变化时调用；纯计算 + 缓存，不随渲染重复跑）
    private func rebuildIndex() {
        let sorted = SongSorter.sorted(rawSongs)
        sortedSongs = sorted
        letterGroups = SongSorter.groups(of: sorted)
    }

    /// 右下角「定位到当前歌曲」按钮
    private func locateButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            guard let id = player.currentSong?.id else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.caramel)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Color.primary.opacity(0.10))
                        )
                        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
                )
                .hoverHighlight(cornerRadius: 9)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("定位到正在播放的歌曲")
    }

    /// 右侧字母索引条：点击跳到该字母的第一首歌
    private func letterIndexBar(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 1) {
            ForEach(letterGroups, id: \.letter) { group in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(group.firstID, anchor: .top)
                    }
                } label: {
                    Text(group.letter)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 15, height: 13)
                        .hoverHighlight(cornerRadius: 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("跳到 \(group.letter) 开头的第一首")
            }
        }
        .padding(.trailing, 3)
        .padding(.vertical, 8)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("歌曲名")
                .frame(width: 260, alignment: .leading)
            Text("歌手")
                .frame(width: 130, alignment: .leading)
            Text("专辑")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("时长")
                .frame(width: 96, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: section == .library ? "music.note.house" : "music.note")
                .font(.system(size: 56))
                .foregroundStyle(Theme.caramel.opacity(0.6))
            Text(section == .library ? "还没有导入音乐" : "这个列表还没有歌曲")
                .font(.title2)
                .foregroundStyle(.primary)
            Text(section == .library
                 ? "点击上方「选择文件夹」，导入 mp3 / flac / wav / m4a / aac 音频\n支持递归扫描子文件夹"
                 : "在歌曲列表里右键歌曲，即可添加到这个歌单")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondary)
            if section == .library {
                Button {
                    presentImportPanel()
                } label: {
                    Label("选择音乐文件夹", systemImage: "folder.badge.plus")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 导入面板

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择音乐文件夹"
        panel.message = "将递归扫描文件夹（含子文件夹）内的音频文件"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .folder]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        player.importFolder(url)
    }
}

/// 单行歌曲视图
///
/// - 封面缩略图：**点击直接播放并跳转播放器页**
/// - 歌曲名 / 歌手 / 专辑 / 时长；当前播放行高亮
/// - 右侧心形收藏按钮；右键菜单：添加到歌单 / 从歌单移除 / 收藏
struct SongRow: View {

    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool
    let section: ListSection
    /// 当前列表（已按首字母排序）的播放队列：点封面小三角时按这个顺序续播；
    /// 不传时退回该分区的默认顺序（搜索页等场景）
    var queue: [Song]? = nil

    @ObservedObject private var player = PlayerManager.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // 封面缩略图：正在播放时叠动态音柱；鼠标悬浮时中间出现小三角（点击即播）
            ZStack {
                ArtworkThumb(song: song, isPlayingIndicator: isCurrent && isPlaying)

                if isHovering {
                    Button {
                        if isCurrent {
                            player.togglePlayPause()
                        } else {
                            player.play(song, from: queue ?? player.songs(in: section))
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.45))
                                .frame(width: 22, height: 22)
                            Image(systemName: (isCurrent && isPlaying) ? "pause.fill" : "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: (isCurrent && isPlaying) ? 0 : 0.5)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isCurrent ? (isPlaying ? "暂停" : "继续播放") : "播放")
                }
            }

            Text(song.title)
                .lineLimit(1)
                .foregroundStyle(isCurrent ? Theme.caramel : .primary)
                .frame(width: 200, alignment: .leading)

            Text(song.artist)
                .lineLimit(1)
                .foregroundStyle(Theme.secondary)
                .frame(width: 130, alignment: .leading)

            Text(song.album)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 收藏按钮（悬浮时更明显）
            Button {
                player.toggleLike(song)
            } label: {
                Image(systemName: player.isLiked(song) ? "heart.fill" : "heart")
                    .font(.system(size: 13))
                    .foregroundStyle(player.isLiked(song)
                                     ? Theme.caramel
                                     : Theme.secondary.opacity(isHovering ? 0.9 : 0.4))
                    .frame(width: 24, height: 22)
                    .hoverHighlight(cornerRadius: 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.isLiked(song) ? "取消收藏" : "收藏到我喜欢的音乐")
            .frame(width: 28)

            Text(song.duration > 0 ? Theme.formatTime(song.duration) : "--:--")
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            // 当前播放行：半透明焦糖底；普通行：鼠标悬浮时用与侧边栏一致的浅灰
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent
                      ? Theme.caramel.opacity(0.14)
                      : (isHovering ? Theme.hoverFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .contextMenu { rowContextMenu }
        .padding(.horizontal, 8)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private var rowContextMenu: some View {
        Button(player.isLiked(song) ? "取消收藏" : "收藏到我喜欢的音乐") {
            player.toggleLike(song)
        }

        Menu("添加到歌单") {
            ForEach(player.playlists.filter { !$0.isFavorites }) { playlist in
                Button(playlist.name) {
                    player.add(song, to: playlist.id)
                }
            }
            Divider()
            Button("新建歌单…") {
                NotificationCenter.default.post(name: .requestCreatePlaylist, object: nil)
            }
        }

        // 仅在歌单视图中提供移除
        if case .playlist(let id) = section {
            Divider()
            Button("从「\(player.playlists.first(where: { $0.id == id })?.name ?? "歌单")」移除", role: .destructive) {
                player.remove(song, from: id)
            }
        }
    }
}

/// 正在播放的动态音柱（列表封面上叠加的播放指示）
///
/// 用 `TimelineView(.animation)` 每 1/18 秒按正弦函数重算三根柱子的高度，
/// 形成上下跳动的均衡器效果；只在「当前正在播放」的那一行创建。
struct PlayingBars: View {

    var color: Color = .white
    var barCount: Int = 3
    var barHeight: CGFloat = 12

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = 0.30 + 0.70 * abs(sin(t * 5.2 + Double(index) * 1.15))
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: max(2.5, barHeight * level))
                }
            }
            .frame(height: barHeight)
        }
    }
}

/// 封面缩略图：内存缓存命中直接显示，未命中显示占位并异步加载
struct ArtworkThumb: View {

    let song: Song
    /// 当前播放行：在封面上叠加小小的播放指示
    var isPlayingIndicator: Bool = false
    /// 缩略图边长（列表 36，迷你播放器 44）
    var size: CGFloat = 36

    @ObservedObject private var player = PlayerManager.shared

    private var image: NSImage? { player.artwork(for: song) }

    var body: some View {
        // 依赖 artworkRevision：缩略图异步加载完成后触发重绘
        let _ = player.artworkRevision

        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.caramel.opacity(0.18))
                Image(systemName: "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.caramel.opacity(0.8))
            }

            if isPlayingIndicator {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.38))
                PlayingBars(color: .white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}

extension Notification.Name {
    /// 行右键菜单「新建歌单」→ 通知 ContentView 弹出新建歌单弹窗
    static let requestCreatePlaylist = Notification.Name("caramel.requestCreatePlaylist")
}
