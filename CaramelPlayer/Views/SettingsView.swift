import SwiftUI
import AppKit

/// 设置页左侧的设置项
enum SettingsTab: String, CaseIterable, Identifiable {
    case shortcuts
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcuts: return "快捷键"
        case .library:   return "设置歌单"
        }
    }

    var icon: String {
        switch self {
        case .shortcuts: return "keyboard"
        case .library:   return "music.note.list"
        }
    }

    var subtitle: String {
        switch self {
        case .shortcuts: return "自定义播放控制快捷键，仅在本应用窗口前台时生效"
        case .library:   return "导入本地音乐、清空当前歌曲列表"
        }
    }
}

/// 页面：设置
///
/// 由左侧边栏左下角的齿轮按钮进入，内容区整块切换为本页；
/// 本页自身再分两栏：左边是设置项列表（快捷键 / 设置歌单），右边是对应面板。
struct SettingsView: View {

    @ObservedObject private var store = ShortcutStore.shared
    @ObservedObject private var player = PlayerManager.shared

    @State private var tab: SettingsTab = .shortcuts
    @State private var hoveredTab: SettingsTab?

    var body: some View {
        HStack(spacing: 0) {
            tabList
                .frame(width: 168)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.pageBackground)
        // 离开设置页时若仍在录制，视为放弃
        .onDisappear { store.cancelRecording() }
    }

    // MARK: - 左：设置项列表

    private var tabList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.topBarHeight)

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                ForEach(SettingsTab.allCases) { item in
                    tabRow(item)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .background(Theme.pageBackground)
    }

    private func tabRow(_ item: SettingsTab) -> some View {
        let selected = tab == item
        return HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Theme.caramel : Theme.secondary)
                .frame(width: 20)
            Text(item.title)
                .font(.system(size: 14, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? .primary : Theme.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected
                      ? Theme.caramel.opacity(0.15)
                      : (hoveredTab == item ? Theme.hoverFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { tab = item }
        .onHover { hovering in
            hoveredTab = hovering ? item : nil
        }
    }

    // MARK: - 右：对应面板

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .shortcuts: shortcutsPane
        case .library:   libraryPane
        }
    }

    private func paneHeader(_ subtitle: String) -> some View {
        HStack(spacing: 10) {
            Text(tab.title)
                .font(.system(size: 20, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: Theme.topBarHeight)
    }

    // MARK: - 面板一：快捷键

    private var shortcutsPane: some View {
        VStack(spacing: 0) {
            paneHeader(SettingsTab.shortcuts.subtitle)
            Divider().opacity(0.5)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element.id) { index, action in
                            if index > 0 {
                                Divider().padding(.leading, 44)
                            }
                            shortcutRow(for: action)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )

                    Text("快捷键仅在「焦糖音乐」窗口处于前台时生效，不会注册系统全局热键。点击右侧按键框后按下新的组合键即可修改（支持 ⌘ / ⌥ / ⌃ / ⇧ 组合），按 Esc 取消。")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            store.resetAll()
                        } label: {
                            Label("恢复全部默认", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 12))
                        }
                        .controlSize(.small)
                        .help("把所有快捷键恢复为出厂设置")
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 面板二：设置歌单（承接原首页顶部的两个按钮）

    private var libraryPane: some View {
        VStack(spacing: 0) {
            paneHeader(SettingsTab.library.subtitle)
            Divider().opacity(0.5)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        actionRow(
                            icon: "folder.badge.plus",
                            title: "选择文件夹…",
                            detail: "递归扫描所选文件夹（含子文件夹）内的 mp3 / flac / wav / m4a / aac 音频",
                            actionTitle: "选择",
                            actionTint: Theme.caramel,
                            action: { presentImportPanel() }
                        )

                        Divider().padding(.leading, 44)

                        actionRow(
                            icon: "trash",
                            title: "清空列表",
                            detail: "当前共 \(player.songs.count) 首歌曲；清空后曲库与各歌单中的歌曲都会被移除",
                            actionTitle: "清空",
                            actionTint: .red,
                            actionDisabled: player.songs.isEmpty,
                            action: { player.clearPlaylist() }
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )

                    Text("导入的歌曲只保存在本机播放列表中，不上传、不联网。清空后可用「选择文件夹」重新导入。")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func actionRow(icon: String,
                           title: String,
                           detail: String,
                           actionTitle: String,
                           actionTint: Color,
                           actionDisabled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.caramel)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .controlSize(.small)
                .tint(actionTint)
                .disabled(actionDisabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 单行：动作名 + 快捷键录制按钮 + 恢复默认

    private func shortcutRow(for action: ShortcutAction) -> some View {
        let isRecording = store.recordingAction == action
        let customized = store.isCustomized(action)

        return HStack(spacing: 12) {
            Image(systemName: action.iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.caramel)
                .frame(width: 18)

            Text(action.title)
                .font(.system(size: 13))

            Spacer(minLength: 12)

            recorderButton(for: action, isRecording: isRecording)

            Button {
                store.resetToDefault(action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 22, height: 22)
                    .hoverHighlight(cornerRadius: 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(customized ? 1 : 0)
            .disabled(!customized)
            .help("恢复该项默认快捷键")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// 快捷键录制按钮：点击进入捕获状态，按下任意组合键即写入
    private func recorderButton(for action: ShortcutAction, isRecording: Bool) -> some View {
        let combo = store.combo(for: action)
        let text = isRecording ? "请按新快捷键…" : (combo?.display ?? "未设置")

        return Button {
            if isRecording { store.cancelRecording() } else { store.beginRecording(action) }
        } label: {
            Text(text)
                .font(.system(size: 12, weight: isRecording ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isRecording ? Theme.caramel : (combo == nil ? Theme.secondary : Color.primary))
                .lineLimit(1)
                .frame(minWidth: 96)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .hoverHighlight(cornerRadius: 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isRecording ? Theme.caramel.opacity(0.12) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            isRecording ? Theme.caramel.opacity(0.85) : Color.primary.opacity(0.10),
                            lineWidth: isRecording ? 1.5 : 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(isRecording ? "按下新的快捷键组合，Esc 取消" : "点击后按下新的快捷键组合")
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
