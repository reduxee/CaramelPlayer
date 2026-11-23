import Foundation
import MediaPlayer

/// 全局媒体按键管理器
///
/// 通过 MediaPlayer 的 MPRemoteCommandCenter 接入 macOS 原生媒体按键：
/// - 键盘 / Touch Bar / 耳机线控上的 播放、暂停、上一首、下一首
/// - 控制中心（Control Center）里的播放控件与进度条拖动
///
/// 原理：当 App 开始用 AVPlayer 播放音频并更新 MPNowPlayingInfoCenter 后，
/// 系统会把它注册为「当前正在播放的 App」，此时媒体按键自动路由给本 App。
/// 该模块在 App 启动时调用 `activate()` 一次性挂载命令回调即可。
final class MediaKeysManager {

    static let shared = MediaKeysManager()
    private var isActivated = false

    private init() {}

    /// 挂载全部远程命令回调（幂等，重复调用无副作用）
    func activate() {
        guard !isActivated else { return }
        isActivated = true

        let center = MPRemoteCommandCenter.shared()

        // 播放 / 暂停 / 切换（PlayerManager 是 @MainActor 单例，回调内用 Task 切主线程访问）
        center.playCommand.addTarget { _ in
            Task { @MainActor in
                let player = PlayerManager.shared
                if !player.isPlaying { player.togglePlayPause() }
            }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in
                let player = PlayerManager.shared
                if player.isPlaying { player.togglePlayPause() }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in PlayerManager.shared.togglePlayPause() }
            return .success
        }

        // 上一首 / 下一首
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in PlayerManager.shared.previous() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in PlayerManager.shared.next() }
            return .success
        }

        // 控制中心进度条拖动（changePlaybackPosition）
        center.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let seconds = positionEvent.positionTime
            Task { @MainActor in PlayerManager.shared.seek(to: seconds) }
            return .success
        }
    }
}
