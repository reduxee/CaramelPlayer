import SwiftUI

/// 歌词滚动面板（播放器页右侧）
///
/// 展示状态：
/// 1. 同步歌词：**当前演唱行始终居中**，歌词以平滑连续滚动跟随；
///    面板上下用渐变遮罩淡出，**不显示进度条与滚动条**；
///    鼠标悬浮某行时显示背景色，**点击该行即 seek 到这句歌词的时间点**（高亮随之切换）；
/// 2. 纯文本歌词（内嵌但没有时间标签）：按普通文本居中展示，不滚动；
/// 3. 暂无歌词：居中占位提示。
struct LyricsView: View {

    @ObservedObject private var player = PlayerManager.shared

    var body: some View {
        Group {
            if player.currentLyrics.isEmpty {
                emptyState
            } else if player.currentLyrics.isSynced {
                syncedLyrics
            } else {
                plainTextLyrics
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 同步歌词（当前行居中 + 连续滚动 + 点击跳转）

    private var syncedLyrics: some View {
        ScrollViewReader { proxy in
            // showsIndicators: false → 不出现滚动条
            ScrollView(showsIndicators: false) {
                // 用普通 VStack（歌词行数有限）：
                // LazyVStack 的行按需创建，滚动定位时会出现「先建行再滚动」的一帧跳动（闪烁来源之一）
                VStack(spacing: 22) {
                    ForEach(Array(player.currentLyrics.lines.enumerated()), id: \.element.id) { index, line in
                        LyricRowView(line: line,
                                     isActive: player.activeLyricIndex == index) {
                            // 点击歌词行 → 跳转到这句歌词的时间点（高亮随播放进度切换）
                            player.seek(to: line.time)
                        }
                        .id(line.id)
                    }
                }
                // 上下大留白：保证首行/末行也能滚动到屏幕中央
                .padding(.vertical, 260)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            // 【闪烁修复】换歌时按歌曲 id 整体重建滚动容器：
            // 若不重建，SwiftUI 会用 diff 动画把旧歌词逐行删除、新歌词逐行插入，
            // 中间会渲染出「空列表」的一帧 → 肉眼看到闪一下
            .id(player.currentSong?.id)
            // 上下渐隐遮罩：滚出视野的歌词柔和淡出
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.12),
                    .init(color: .white, location: 0.88),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            // 歌词跟随播放进度：当前行变化 → 平滑滚动让它居中
            .onChange(of: player.activeLyricIndex) { index in
                guard let index, index < player.currentLyrics.lines.count else { return }
                let id = player.currentLyrics.lines[index].id
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            // 换歌后歌词列表重建：回到顶部（无动画，避免二次闪动）
            .onChange(of: player.currentSong?.id) { _ in
                if let first = player.currentLyrics.lines.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
        }
    }

    // MARK: - 纯文本歌词

    private var plainTextLyrics: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(player.currentLyrics.lines) { line in
                    Text(line.text)
                        .font(.system(size: 17))
                        .foregroundStyle(.primary.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 60)
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
        }
    }

    // MARK: - 暂无歌词占位

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 40))
                .foregroundStyle(.primary.opacity(0.35))
            Text("暂无歌词")
                .font(.title3)
                .foregroundStyle(.primary.opacity(0.6))
            Text("本歌曲没有内嵌歌词，同目录下也没有同名 .lrc 文件")
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 单行歌词：当前行加粗高亮；悬浮显示背景色；点击 seek 到该行时间
private struct LyricRowView: View {

    let line: LyricLine
    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        let text = line.text.isEmpty ? "♪" : line.text
        return Text(text)
            .font(.system(size: isActive ? 21 : 19, weight: isActive ? .bold : .regular))
            .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.35))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(
                // 悬浮背景色（与按钮一致的半透明白色；当前行不重复加背景，保持高亮主导）
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering && !isActive ? Theme.hoverFill : Color.clear)
            )
            .scaleEffect(isActive ? 1.03 : 1.0)
            // 注意：不放 blur——blur 在高亮切换时整行重新栅格化，会加重闪烁感
            .animation(.easeInOut(duration: 0.3), value: isActive)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .contentShape(Rectangle())
            .onHover { hovering in isHovering = hovering }
            .onTapGesture(perform: onTap)
            .help("点击跳转到这句歌词")
    }
}
