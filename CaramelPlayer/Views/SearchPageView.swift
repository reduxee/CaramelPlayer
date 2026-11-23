import SwiftUI
import AppKit

/// 页面：搜索（点击歌曲列表右上角的搜索入口进入）
///
/// - 与列表页共用同一套视觉：白色背景、同款工具栏高度
/// - 顶部：返回按钮 + 真实输入框（进入即聚焦）+ 命中数量
/// - 结果：复用 `SongRow`，点击即在「搜索结果」队列内播放
/// - 空态区分「未输入」与「无命中」两种情况
struct SearchPageView: View {

    /// 点击返回按钮时回调（回到进入前的列表页）
    let onBack: () -> Void

    @ObservedObject private var player = PlayerManager.shared

    @State private var keyword = ""
    @FocusState private var inputFocused: Bool

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespaces)
    }

    /// 命中结果（歌名 / 歌手 / 专辑，忽略大小写）
    private var results: [Song] {
        guard !trimmedKeyword.isEmpty else { return [] }
        return player.songs.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedKeyword)
                || $0.artist.localizedCaseInsensitiveContains(trimmedKeyword)
                || $0.album.localizedCaseInsensitiveContains(trimmedKeyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
        }
        .background(Theme.pageBackground)
        // 进入搜索页即把光标放进输入框（延迟一点，等视图挂载完成）
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { inputFocused = true }
        }
    }

    // MARK: - 顶部工具栏

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("返回列表")

            Text("搜索")
                .font(.title3)
                .fontWeight(.semibold)

            searchField
                .frame(maxWidth: 380)

            Spacer()

            if !trimmedKeyword.isEmpty {
                Text("共 \(results.count) 首")
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.topBarHeight)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)

            TextField("搜索歌名、歌手、专辑", text: $keyword)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($inputFocused)

            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(inputFocused ? Theme.caramel.opacity(0.55) : Color.primary.opacity(0.10))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { inputFocused = true }
    }

    // MARK: - 结果 / 空态

    @ViewBuilder
    private var content: some View {
        if trimmedKeyword.isEmpty {
            placeholder(icon: "magnifyingglass",
                        title: "搜索本地音乐",
                        detail: "输入歌名、歌手或专辑关键词，支持模糊匹配")
        } else if results.isEmpty {
            placeholder(icon: "music.note",
                        title: "没有找到匹配的歌曲",
                        detail: "换个关键词试试，例如只输入歌手名或专辑名")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(results) { song in
                        SongRow(song: song,
                                isCurrent: player.currentSong?.id == song.id,
                                isPlaying: player.isPlaying,
                                section: .library)
                            .onTapGesture {
                                // 在「本次搜索结果」范围内播放，上下首接着结果走
                                inputFocused = false    // 交还焦点，之后按空格才能播放/暂停
                                player.play(song, from: results)
                            }
                    }
                }
                .padding(.vertical, 4)
                .padding(.bottom, 12)
            }
        }
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Theme.caramel.opacity(0.55))
            Text(title)
                .font(.title2)
                .foregroundStyle(.primary)
            Text(detail)
                .font(.callout)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
