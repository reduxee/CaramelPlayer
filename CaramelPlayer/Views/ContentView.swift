import SwiftUI
import AppKit

/// 主题色与通用视觉常量（焦糖主题）
///
/// 跟随系统浅色/深色模式：背景一律使用系统语义色（背景/材质自动切换），
/// 只自定义「焦糖」强调色，并分别为浅/深模式微调明度。
enum Theme {
    /// 焦糖主强调色（浅色模式：偏金棕；深色模式：更亮的琥珀，保证对比度）
    static let caramel = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
            ? NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.38, alpha: 1)
            : NSColor(calibratedRed: 0.72, green: 0.49, blue: 0.24, alpha: 1)
    })

    /// 播放器页背景取色失败时的兜底背景（深浅模式自适应的中性焦糖色）
    static let defaultBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
            ? NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.08, alpha: 1)
            : NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.85, alpha: 1)
    })

    /// 主页（列表页 + 顶部工具区）背景：浅色 #FFFFFF，深色对应深灰
    static let pageBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
            ? NSColor(calibratedWhite: 0.11, alpha: 1)
            : NSColor(calibratedWhite: 1.0, alpha: 1)
    })

    /// 迷你播放器背景：浅色 #F6F6F6（比页面稍深一点点，用来分区），深色对应深灰
    static let miniBarBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
            ? NSColor(calibratedWhite: 0.20, alpha: 1)
            : NSColor(calibratedRed: 0xF6 / 255.0, green: 0xF6 / 255.0, blue: 0xF6 / 255.0, alpha: 1)
    })

    /// 次级文本（系统语义色，自动适配深浅模式）
    static let secondary = Color.secondary

    /// 顶部条统一高度：侧边栏 Logo 区与右侧内容区工具栏共用，
    /// 保证两条下划线（分隔线）落在同一水平线上
    static let topBarHeight: CGFloat = 74

    /// 隐藏标题栏后，左上角红绿灯按钮占用的高度（侧边栏顶部留白）
    static let trafficLightInset: CGFloat = 22

    /// 通用鼠标悬停高亮：与侧边栏菜单行完全一致的浅色叠加
    /// （浅色模式下是极淡的灰，深色模式下是极淡的白，跟随系统自动适配）
    static let hoverFill = Color.primary.opacity(0.06)

    /// mm:ss 时间格式化（进度条 / 列表时长共用）
    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 主视图：自绘侧边栏 + 内容区 + 底部迷你控制条 + 全窗播放器覆盖层
///
/// 结构：
/// - 列表模式：左侧固定宽度侧边栏（Logo + 焦糖音乐 / 我喜欢的音乐 / 歌曲列表 / 创建的歌单）
///   + 右侧歌曲列表页 + 底部迷你控制条
/// - 播放器模式（activePage == 1）：PlayerDetailView 以覆盖层形式铺满**整个窗口**
///   （盖住侧边栏），左上角提供全屏按钮、右上角提供「收起播放器」按钮
/// - 设置模式：左下角齿轮按钮把右侧内容区切换为 SettingsView
struct ContentView: View {

    @ObservedObject private var player = PlayerManager.shared

    /// 侧边栏当前选中的列表分区
    @State private var section: ListSection = .library
    /// 新建歌单弹窗
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    /// 侧边栏悬浮态（行高亮用）
    @State private var sidebarHover: ListSection?
    /// 右侧内容区是否显示设置页（左下角齿轮切换）
    @State private var showSettings = false
    /// 右侧内容区是否显示搜索页（点击工具栏里的搜索框进入）
    @State private var showSearch = false
    /// 齿轮按钮悬浮态
    @State private var settingsHover = false

    var body: some View {
        ZStack {
            // 整窗底色：让隐藏标题栏后的顶部区域（红绿灯所在的一条）也保持纯白 / 深色，
            // 而不是透出窗口默认的浅灰
            Theme.pageBackground
                .ignoresSafeArea()

            // ---------- 列表模式主界面 ----------
            VStack(spacing: 0) {
                // 内容区顶到窗口最上沿：忽略隐藏标题栏带来的顶部安全区，
                // 红绿灯按钮只压在左侧边栏上方，右侧列表不受影响
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 210)
                    Divider()
                    detailPage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(edges: .top)

                // 迷你控制条：仅列表页显示；上沿自带 2pt 歌曲进度条
                if player.activePage == 0 {
                    PlayerControlsBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // ---------- 播放器模式：全窗覆盖层 ----------
            if player.activePage == 1 {
                PlayerDetailView(onCollapse: {
                    withAnimation(.easeInOut(duration: 0.3)) { player.activePage = 0 }
                })
                .transition(.opacity.combined(with: .scale(scale: 1.03)))
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.activePage)
        .animation(.easeInOut(duration: 0.18), value: showSettings || showSearch)
        // 释放 SwiftUI 自动塞给搜索框的焦点，否则空格会被当成文字输入
        .releaseAutoTextFocus()
        // 顶部轻量 toast：导入结果 / 跳过损坏文件等状态提示
        .overlay(alignment: .top) { toast }
        .onReceive(NotificationCenter.default.publisher(for: .openImportFolderPanel)) { _ in
            presentImportPanel()
        }
        // 菜单栏「设置…」（⌘,）→ 打开设置页
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        // 行右键菜单 / 播放器页的「新建歌单」→ 弹出新建歌单弹窗
        .onReceive(NotificationCenter.default.publisher(for: .requestCreatePlaylist)) { _ in
            newPlaylistName = ""
            showCreatePlaylist = true
        }
        .alert("新建歌单", isPresented: $showCreatePlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") {
                _ = player.createPlaylist(named: newPlaylistName)
                newPlaylistName = ""
            }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        } message: {
            Text("输入新歌单的名称")
        }
    }

    // MARK: - 侧边栏（自绘：图标 + 文字，不依赖 NavigationSplitView 的折叠机制）

    private var sidebar: some View {
        VStack(spacing: 0) {
            // 隐藏标题栏后，左上角红绿灯按钮悬浮在此处：只留必要的一点空间
            Color.clear.frame(height: Theme.trafficLightInset)

            // 顶部：App Logo + 「焦糖音乐」（整块高度与右侧工具栏一致，下划线与右侧对齐）
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                Text("焦糖音乐")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: Theme.topBarHeight - Theme.trafficLightInset)

            Divider().padding(.horizontal, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    sidebarRow(title: "喜欢", icon: "heart.fill",
                               target: .favorites)
                    sidebarRow(title: "歌曲列表", icon: "music.note.list",
                               target: .library)

                    // 歌单分组头 + 新建按钮
                    HStack {
                        Text("创建的歌单")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                        Button {
                            newPlaylistName = ""
                            showCreatePlaylist = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                                .frame(width: 18, height: 18)
                                .hoverHighlight(cornerRadius: 5)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("新建歌单")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                    ForEach(player.playlists.filter { !$0.isFavorites }) { playlist in
                        sidebarRow(title: playlist.name, icon: "music.note",
                                   target: .playlist(playlist.id))
                            .contextMenu {
                                Button("删除歌单", role: .destructive) {
                                    player.deletePlaylist(playlist.id)
                                    if section == .playlist(playlist.id) { section = .library }
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }

            Spacer(minLength: 0)

            Divider().padding(.horizontal, 10)

            // 底部：左下角设置（齿轮）按钮 + 居中的歌曲数量
            ZStack {
                Text("\(player.songs.count) 首歌曲")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)

                HStack(spacing: 0) {
                    settingsButton
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    /// 左下角设置按钮：只有齿轮图标，点击切换右侧为设置页
    private var settingsButton: some View {
        Button {
            showSearch = false
            showSettings.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(showSettings ? Theme.caramel : Theme.secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(showSettings
                              ? Theme.caramel.opacity(0.15)
                              : (settingsHover ? Theme.hoverFill : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { settingsHover = hovering }
        }
        .help(showSettings ? "返回歌单（再点一次关闭设置）" : "设置")
    }

    /// 侧边栏行（图标 + 文字 + 选中/悬浮高亮）
    ///
    /// 设置页 / 搜索页打开时取消所有行的选中态，避免「歌曲列表高亮着、右侧却是别的页」的错乱感。
    private func sidebarRow(title: String, icon: String, target: ListSection) -> some View {
        let selected = !showSettings && !showSearch && section == target
        return HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? Theme.caramel : Theme.secondary)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 16, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? .primary : Theme.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected
                      ? Theme.caramel.opacity(0.15)
                      : (sidebarHover == target ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            section = target
            showSettings = false     // 点击任意列表即退出设置 / 搜索页
            showSearch = false
        }
        .onHover { hovering in
            sidebarHover = hovering ? target : nil
        }
    }

    // MARK: - 右侧内容页

    @ViewBuilder
    private var detailPage: some View {
        if showSettings {
            SettingsView()
                .transition(.opacity)
        } else if showSearch {
            SearchPageView(onBack: { showSearch = false })
                .transition(.opacity)
        } else {
            SongListView(section: section, onSearch: {
                showSettings = false
                showSearch = true
            })
            .transition(.opacity)
        }
    }

    // MARK: - Toast 状态提示

    @ViewBuilder
    private var toast: some View {
        if let message = player.statusMessage {
            Text(message)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.caramel.opacity(0.35)))
                .shadow(radius: 8, y: 2)
                .padding(.top, 34)
                .transition(.move(edge: .top).combined(with: .opacity))
                // 同一条消息重复出现也要重新计时
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    if player.statusMessage == message {
                        withAnimation(.easeOut(duration: 0.25)) {
                            player.statusMessage = nil
                        }
                    }
                }
        }
    }

    // MARK: - 导入文件夹（NSOpenPanel）

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

// MARK: - 通用悬停高亮

/// 鼠标悬停时在控件背后垫一层半透明白色（全应用按钮共用，保证交互反馈一致）
///
/// 说明：白色叠在纯白页面上几乎不可见，因此额外描一条极淡的边，
/// 让浅色背景上也能看出「这里可点」；深色 / 取色背景上则以白色底为主。
private struct HoverHighlightModifier: ViewModifier {

    var cornerRadius: CGFloat
    var enabled: Bool

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(hovering && enabled ? Theme.hoverFill : Color.clear)
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// 悬停高亮（半透明白色底）
    func hoverHighlight(cornerRadius: CGFloat = 7, enabled: Bool = true) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius, enabled: enabled))
    }
}

// MARK: - 焦点修正

extension View {
    /// 页面出现后主动退出「自动聚焦到文本框」的状态
    ///
    /// macOS 的 SwiftUI 会在窗口 / 页面出现时把其中的 TextField（本项目的搜索框）
    /// 自动设为第一响应者 —— 这会让「空格 = 播放/暂停」变成往搜索框里打空格。
    /// 页面出现后延迟一小段时间（等系统完成自动聚焦）再把焦点交还给窗口本身，
    /// 用户之后点击搜索框仍可正常输入。
    func releaseAutoTextFocus() -> some View {
        onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
                else { return }
                if window.firstResponder is NSTextView {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }
}
