import SwiftUI
import AppKit

/// 底部迷你播放器（仅歌曲列表页显示；播放器页自带完整控件时自动隐藏）
///
/// 布局（左右分区 + 居中传输控件）：
/// 左：当前曲目封面 + 信息（点击进入播放器页）｜中：上一首 / 播放 / 下一首（水平居中）｜右：收藏 + 模式 + 音量
/// - 背景 #EEEEEE（深色模式自动适配深灰）
/// - 取消常规进度条（拖拽跳转去播放器页），只保留上沿 2pt 歌曲进度条（兼作分隔线）
struct PlayerControlsBar: View {

    @ObservedObject private var player = PlayerManager.shared

    /// 顶部 2pt 进度条使用的进度（0...1）
    private var progressFraction: Double {
        player.duration > 0 ? max(0, min(1, player.currentTime / player.duration)) : 0
    }

    var body: some View {
        ZStack {
            // 左右两端的固定内容
            HStack(spacing: 12) {
                currentSongInfo
                Spacer(minLength: 12)
                trailingControls
            }

            // 居中的播放 / 切歌按钮
            transportControls
        }
        .padding(.horizontal, 16)
        .frame(height: 74)
        .background(Theme.miniBarBackground)
        // 上沿：2pt 歌曲进度条（浅轨道 + 焦糖填充），兼作与主页的分隔
        .overlay(alignment: .top) { topProgress }
        .animation(.easeInOut(duration: 0.2), value: player.isPlaying)
    }

    /// 上沿 2pt 进度条（唯一的进度展示，替代原来的滑块）
    private var topProgress: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                Rectangle()
                    .fill(Theme.caramel)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * progressFraction)))
            }
        }
        .frame(height: 2)
    }

    // MARK: - 中间：播放 / 切歌（水平居中）

    private var transportControls: some View {
        HStack(spacing: 18) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 30, height: 30)
                    .hoverHighlight(cornerRadius: 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("上一首")

            Button {
                player.togglePlayPause()
            } label: {
                // 圆角方形按钮：整个方块都是命中区域（不只是中间的三角）
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.caramel)
                    .offset(x: player.isPlaying ? 0 : 1)
                    .frame(width: 38, height: 38)
                    .hoverHighlight(cornerRadius: 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.caramel.opacity(0.14))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .help("播放 / 暂停")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 30, height: 30)
                    .hoverHighlight(cornerRadius: 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("下一首")
        }
        .disabled(player.songs.isEmpty)
    }

    // MARK: - 左侧：当前曲目信息（点击进入播放器页）

    private var isCurrentLiked: Bool {
        player.currentSong.map { player.isLiked($0) } ?? false
    }

    private var currentSongInfo: some View {
        HStack(spacing: 10) {
            if let song = player.currentSong {
                ArtworkThumb(song: song, isPlayingIndicator: false, size: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.showPlayerDetail()
                    }
                    .help("查看播放详情")
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.caramel.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.caramel)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentSong?.title ?? "焦糖音乐")
                    .font(.callout)
                    .lineLimit(1)
                Text(player.currentSong?.artist ?? "本地播放器")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                player.showPlayerDetail()
            }
        }
        .help("点击进入播放器页")
    }

    // MARK: - 右侧：收藏 / 播放模式 / 音量

    private var trailingControls: some View {
        HStack(spacing: 12) {
            Button {
                if let song = player.currentSong { player.toggleLike(song) }
            } label: {
                Image(systemName: isCurrentLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isCurrentLiked ? Theme.caramel : Theme.secondary)
                    .frame(width: 24, height: 22)
                    .hoverHighlight(cornerRadius: 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCurrentLiked ? "取消收藏" : "收藏")

            Button {
                player.cyclePlaybackMode()
            } label: {
                Image(systemName: player.playbackMode.iconName)
                    .foregroundStyle(Theme.caramel)
                    .frame(width: 24, height: 22)
                    .hoverHighlight(cornerRadius: 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.playbackMode.label)

            volumeControls
        }
        .imageScale(.medium)
    }

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
            .frame(width: 80)
            .controlSize(.mini)
            .tint(Theme.caramel)
            .help("音量")
        }
    }
}
