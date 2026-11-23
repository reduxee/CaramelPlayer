import SwiftUI
import AppKit

/// 焦糖音乐 App 入口
///
/// - 启动时挂载媒体按键（MPRemoteCommandCenter）与应用内快捷键；
/// - 主窗口：左侧资料库导航 + 右侧内容页 + 底部常驻播放控制条；
/// - 纯本地运行：不联网、不请求任何网络接口，只读取本地音频文件。
@main
struct CaramelPlayerApp: App {

    init() {
        // 接入 macOS 原生媒体按键（F8 播放/暂停、F9/F7 上下曲等）
        MediaKeysManager.shared.activate()
        // 挂载应用内快捷键（空格播放/暂停、⌘←/⌘→ 切歌…，可在设置页自定义）
        // 仅在本 App 窗口处于前台时生效，不注册系统全局热键
        ShortcutStore.shared.startMonitoring()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 窗口支持自由缩放：给出合理最小尺寸，布局随宽高自适应
                .frame(minWidth: 900, minHeight: 620)
        }
        // 首次打开时的默认窗口尺寸（比系统默认更大一些，列表与播放器页都更舒展）
        .defaultSize(width: 1160, height: 780)
        // 隐藏标题栏：播放器页取色背景可铺满整窗（红绿灯按钮悬浮其上，与参考图一致）
        .windowStyle(.hiddenTitleBar)
        .commands {
            // 设置页（右侧内容区切换，非独立窗口）
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // 说明：播放/切歌等快捷键统一由 ShortcutStore 的「应用内键盘监视器」处理，
            // 这样既支持用户自定义组合键，也不会像菜单快捷键那样抢走输入框里的空格。
            CommandGroup(after: .toolbar) {
                Button("播放 / 暂停") {
                    PlayerManager.shared.togglePlayPause()
                }

                Button("下一首") {
                    PlayerManager.shared.next()
                }

                Button("上一首") {
                    PlayerManager.shared.previous()
                }

                Button("导入音乐文件夹…") {
                    NotificationCenter.default.post(name: .openImportFolderPanel, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    /// 菜单栏「导入音乐文件夹」→ 通知 ContentView 弹出 NSOpenPanel（统一弹窗入口）
    static let openImportFolderPanel = Notification.Name("caramel.openImportFolderPanel")
    /// 菜单栏「设置…」→ 通知 ContentView 把右侧内容区切到设置页
    static let openSettings = Notification.Name("caramel.openSettings")
}
