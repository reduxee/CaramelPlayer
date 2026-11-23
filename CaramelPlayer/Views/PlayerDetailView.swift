import SwiftUI
import AppKit

/// 播放器页（参考图一：Apple Music 风格，全窗覆盖层）
///
/// 布局：
/// - 整页铺满窗口（覆盖侧边栏）：背景取自当前封面主色（深浅模式自动派生变体）
/// - 左上角：全屏切换按钮；右上角：收起播放器（回到列表页）
/// - 左侧：大号方形圆角封面 → 歌曲名 / 歌手·专辑 → 音量+收藏+加入歌单 → 细进度条 → 五键控件
/// - 右侧：歌词面板（当前行居中连续滚动，无进度条）
/// - 窄窗口：上下堆叠自适应
struct PlayerDetailView: View {

    /// 点击右上角「收起播放器」时回调（回到列表页）
    let onCollapse: () -> Void

    @ObservedObject private var player = PlayerManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景取色：铺满整个窗口（含红绿灯按钮区域）
                (player.playerBackground ?? Theme.defaultBackground)
                    .ignoresSafeArea()
                    // 顶部到中央的柔和明暗过渡，增强质感
                    .overlay(
                        LinearGradient(colors: [.black.opacity(0.14), .clear],
                                       startPoint: .top, endPoint: .center)
                            .ignoresSafeArea()
                    )

                VStack(spacing: 0) {
                    // 顶部：右上角全屏 / 收起按钮
                    topBar

                    if geo.size.width >= 760 {
                        HStack(spacing: 0) {
                            playerPane(width: geo.size.width * 0.42)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            LyricsView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.vertical, 16)
                                .padding(.trailing, 32)
                        }
                    } else {
                        VStack(spacing: 0) {
                            playerPane(width: geo.size.width)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            LyricsView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
                // 忽略隐藏标题栏的顶部安全区：顶部按钮可以真正贴到窗口最上沿
                .ignoresSafeArea(edges: .top)
            }
        }
    }

    // MARK: - 顶部按钮（全屏 / 收起，统一放右上角）

    private var topBar: some View {
        HStack(spacing: 10) {
            Spacer()

            // 全屏切换
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .hoverHighlight(cornerRadius: 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.08)))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("切换全屏")

            // 收起播放器，回到普通列表页
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .hoverHighlight(cornerRadius: 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.08)))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("收起播放器")
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)   // 右侧内边距 20
        .padding(.top, 20)        // 距顶部 20
    }

    // MARK: - 左侧：封面 + 信息 + 控件

    private func playerPane(width: CGFloat) -> some View {
        // 封面边长：信息区（标题行 + 作者行）与进度条都按这个宽度对齐，绝不超出封面
        let artSize = min(width * 0.82, 500)

        return VStack(spacing: 0) {
            Spacer(minLength: 6)

            // 大号方形圆角封面（窄窗口自动压缩）
            bigArtwork
                .frame(width: artSize, height: artSize)

            Color.clear.frame(height: 34)   // 封面 → 标题：固定留白，比之前大一点

            infoBlock
                .frame(width: artSize, alignment: .leading)

            Spacer(minLength: 14)

            // 细进度条 + 两侧时长（宽度与封面一致）
            progressSection
                .frame(width: artSize)

            Spacer(minLength: 10)

            // 三键控件：上一首 / 播放 / 下一首
            transportControls

            Spacer(minLength: 16)
        }
        .padding(.top, 6)
        .padding(.bottom, 34)   // 底部多留一点 → 整块（含封面）整体上移
    }

    /// 曲目信息：第一行「标题 + 右侧操作按钮」，第二行「作者 · 专辑」
    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                Text(player.currentSong?.title ?? "未在播放")
                    .font(.system(size: 23, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                volumeControls
                modeButton
                likeButton
                addToPlaylistMenu
            }

            Text("\(player.currentSong?.artist ?? "—") · \(player.currentSong?.album ?? "—")")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// 大号封面（无封面时用简约占位）
    private var bigArtwork: some View {
        ZStack {
            if let artwork = player.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.caramel.opacity(0.2))
                Image(systemName: "music.note")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Theme.caramel.opacity(0.8))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.30), radius: 18, y: 12)
    }

    // MARK: - 音量 / 收藏 / 加入歌单

    private var volumeControls: some View {
        HStack(spacing: 6) {
            Button {
                player.toggleMute()
            } label: {
                Image(systemName: player.isMuted || player.volume == 0
                      ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 24, height: 22)
                    .hoverHighlight(cornerRadius: 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "取消静音" : "静音")

            Slider(value: Binding(
                get: { player.isMuted ? 0 : player.volume },
                set: { player.volume = $0 }
            ), in: 0...1)
            .frame(width: 72)
            .tint(Theme.caramel)
            .controlSize(.mini)
            .help("音量")
        }
    }

    /// 播放模式切换（列表循环 → 单曲循环 → 随机），位于收藏心形左侧
    private var modeButton: some View {
        Button {
            player.cyclePlaybackMode()
        } label: {
            Image(systemName: player.playbackMode.iconName)
                .font(.system(size: 15))
                .foregroundStyle(Theme.caramel)
                .frame(width: 26, height: 24)
                .hoverHighlight(cornerRadius: 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("播放模式：\(player.playbackMode.label)（点击切换）")
    }

    private var likeButton: some View {
        Button {
            if let song = player.currentSong { player.toggleLike(song) }
        } label: {
            Image(systemName: isCurrentLiked ? "heart.fill" : "heart")
                .font(.system(size: 15))
                .foregroundStyle(isCurrentLiked ? Theme.caramel : .secondary)
                .frame(width: 24, height: 22)
                .hoverHighlight(cornerRadius: 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCurrentLiked ? "取消收藏" : "收藏到我喜欢的音乐")
        .disabled(player.currentSong == nil)
    }

    private var isCurrentLiked: Bool {
        player.currentSong.map { player.isLiked($0) } ?? false
    }

    private var addToPlaylistMenu: some View {
        Menu {
            ForEach(player.playlists.filter { !$0.isFavorites }) { playlist in
                Button(playlist.name) {
                    if let song = player.currentSong { player.add(song, to: playlist.id) }
                }
            }
            Divider()
            Button("新建歌单…") {
                NotificationCenter.default.post(name: .requestCreatePlaylist, object: nil)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 26, height: 24)
                .hoverHighlight(cornerRadius: 6)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("添加到歌单")
        .disabled(player.currentSong == nil)
    }

    // MARK: - 进度条（细线样式，支持拖拽/点按跳转）

    private var progressSection: some View {
        HStack(spacing: 8) {
            // 已播时间：在进度条左侧
            Text(Theme.formatTime(player.isScrubbing ? scrubFraction * player.duration : player.currentTime))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            ThinProgressBar(
                fraction: progressFraction,
                onScrub: { editing, value in
                    if editing {
                        player.isScrubbing = true
                        scrubFraction = value
                    } else {
                        player.seek(to: value * player.duration)
                        player.isScrubbing = false
                    }
                }
            )
            .frame(height: 14)
            .disabled(player.duration <= 0)

            // 总时长：在进度条右侧
            Text(Theme.formatTime(player.duration))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    @State private var scrubFraction: Double = 0

    private var progressFraction: Double {
        if player.isScrubbing { return scrubFraction }
        return player.duration > 0 ? player.currentTime / player.duration : 0
    }

    // MARK: - 播放控件（三键：上一首 / 播放 / 下一首；模式按钮已移到收藏左侧）

    private var transportControls: some View {
        HStack(spacing: 44) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .hoverHighlight(cornerRadius: 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("上一首")

            Button {
                player.togglePlayPause()
            } label: {
                // 圆角方形按钮：整个方块都是命中区域
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.caramel)
                    .offset(x: player.isPlaying ? 0 : 2)
                    .frame(width: 56, height: 56)
                    .hoverHighlight(cornerRadius: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.caramel.opacity(0.16))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .help("播放 / 暂停")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .hoverHighlight(cornerRadius: 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("下一首")
        }
        .disabled(player.songs.isEmpty)
    }
}

// MARK: - 细进度条（图一样式：4pt 高的细线 + 圆点）

/// 自绘细进度条：点击 / 拖拽跳转播放位置
/// - Parameters:
///   - fraction: 0...1 的进度（已完成的填充）
///   - onScrub: (是否开始拖拽, 当前分数位置)；开始与结束时各回调一次
struct ThinProgressBar: View {

    let fraction: Double
    let onScrub: (_ editing: Bool, _ value: Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let current = dragFraction ?? fraction

            // 点击 + 拖拽手势（minimumDistance 0 让点击也能触发）
            ZStack(alignment: .leading) {
                // 轨道
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                // 填充
                Capsule()
                    .fill(Theme.caramel)
                    .frame(width: max(4, size.width * current), height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                // 拖拽圆点
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .offset(x: max(0, min(size.width - 10, size.width * current - 5)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = max(0, min(1, value.location.x / max(size.width, 1)))
                        if dragFraction == nil {
                            onScrub(true, f) // 开始拖拽
                        }
                        dragFraction = f
                    }
                    .onEnded { value in
                        let f = max(0, min(1, value.location.x / max(size.width, 1)))
                        onScrub(false, f) // 松手 → seek
                        dragFraction = nil
                    }
            )
        }
    }
}
