import AppKit
import Foundation
import SwiftUI

// MARK: - 快捷键动作

/// 可在设置页自定义的播放器动作
///
/// 说明：这些快捷键通过 `NSEvent.addLocalMonitorForEvents` 挂载在**应用内**，
/// 只有「焦糖音乐」窗口处于前台时才生效，不会注册系统全局热键（不打扰其它 App）。
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {

    case playPause
    case previous
    case next
    case cyclePlaybackMode

    var id: String { rawValue }

    /// 设置页展示名称
    var title: String {
        switch self {
        case .playPause:         return "播放 / 暂停"
        case .previous:          return "上一首"
        case .next:              return "下一首"
        case .cyclePlaybackMode: return "切换播放模式"
        }
    }

    /// 设置页行首图标（SF Symbols）
    var iconName: String {
        switch self {
        case .playPause:         return "playpause.fill"
        case .previous:          return "backward.fill"
        case .next:              return "forward.fill"
        case .cyclePlaybackMode: return "repeat"
        }
    }

    /// 出厂默认组合键
    var defaultCombo: KeyCombo {
        switch self {
        case .playPause:         return KeyCombo(keyCode: 49,  modifiers: [])                    // 空格
        case .previous:          return KeyCombo(keyCode: 123, modifiers: [.command])           // ⌘←
        case .next:              return KeyCombo(keyCode: 124, modifiers: [.command])           // ⌘→
        case .cyclePlaybackMode: return KeyCombo(keyCode: 46,  modifiers: [.command, .shift])   // ⇧⌘M
        }
    }

    /// 执行动作（统一走主线程，PlayerManager 为 @MainActor 单例）
    @MainActor
    func perform() {
        let player = PlayerManager.shared
        switch self {
        case .playPause:         player.togglePlayPause()
        case .previous:          player.previous()
        case .next:              player.next()
        case .cyclePlaybackMode: player.cyclePlaybackMode()
        }
    }
}

// MARK: - 键位组合

/// 一个可匹配/可展示的键位组合（物理键码 + 修饰键）
///
/// - 用 `keyCode` 而不是字符匹配：与输入法状态、大小写、键盘布局无关；
/// - 只保留 ⌘ / ⌥ / ⌃ / ⇧ 四个修饰键，忽略 CapsLock、Fn 等；
/// - `Codable` 以便持久化到 UserDefaults。
struct KeyCombo: Codable, Equatable {

    /// 物理键码（NSEvent.keyCode）
    var keyCode: UInt16
    /// 修饰键集合（NSEvent.ModifierFlags 的 device-independent rawValue，已过滤）
    var modifiers: UInt

    /// 参与匹配与展示的修饰键
    static let relevantMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantMask).rawValue
    }

    /// 从键盘事件捕获；无法识别的键（无键名映射）返回 nil，避免用户绑到无名键
    init?(event: NSEvent) {
        guard KeyCombo.keyName(for: event.keyCode) != nil else { return nil }
        self.init(keyCode: event.keyCode,
                  modifiers: event.modifierFlags.intersection(Self.relevantMask))
    }

    var flagSet: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantMask)
    }

    /// 是否与键盘事件完全一致（键码 + 修饰键都要相同）
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        return event.modifierFlags.intersection(Self.relevantMask) == flagSet
    }

    /// 展示文本，如「空格」「⇧⌘M」「⌘←」
    var display: String {
        var text = ""
        let f = flagSet
        if f.contains(.control) { text += "⌃" }
        if f.contains(.option)  { text += "⌥" }
        if f.contains(.shift)   { text += "⇧" }
        if f.contains(.command) { text += "⌘" }
        return text + (KeyCombo.keyName(for: keyCode) ?? "Key\(keyCode)")
    }

    // MARK: 键码 → 键名（美式键盘键位，覆盖字母/数字/符号/方向键/功能键）

    static func keyName(for code: UInt16) -> String? { keyNames[code] }

    private static let keyNames: [UInt16: String] = [
        // 字母
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        // 数字
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        // 符号
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        // 控制键 / 方向键
        36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "Esc", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // 功能键
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
        107: "F14", 113: "F15"
    ]
}

// MARK: - 快捷键仓库（读取 / 录制 / 匹配 / 持久化）

/// 快捷键配置中心：单例 + ObservableObject，设置页与键盘监视器共用同一份数据
///
/// - 只在应用前台拦截按键：用的是**本地**事件监视器（local monitor），
///   系统其它 App 中按空格不会影响播放器；
/// - 录制模式：`recordingAction != nil` 时，下一次 keyDown 直接写入该动作的绑定；
/// - 冲突处理：同一组合只允许绑定一个动作，新绑定会清掉其它动作上的重复项。
final class ShortcutStore: ObservableObject {

    static let shared = ShortcutStore()

    /// 当前绑定（未出现在字典里的动作 = 未设置）
    @Published private(set) var combos: [ShortcutAction: KeyCombo]
    /// 正在等待用户按键的动作（nil = 未处于录制状态）
    @Published private(set) var recordingAction: ShortcutAction?

    private static let storageKey = "caramel.shortcuts"
    private var monitor: Any?

    private init() {
        combos = ShortcutStore.load()
    }

    // MARK: - 查询

    func combo(for action: ShortcutAction) -> KeyCombo? { combos[action] }

    /// 是否被用户改过（决定设置页是否显示「恢复默认」按钮）
    func isCustomized(_ action: ShortcutAction) -> Bool {
        combos[action] != action.defaultCombo
    }

    // MARK: - 修改

    func beginRecording(_ action: ShortcutAction) {
        recordingAction = action
    }

    func cancelRecording() {
        recordingAction = nil
    }

    /// 设置 / 清除绑定
    func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        var next = combos
        if let combo {
            // 组合键唯一：先移除其它动作上重复的绑定，再写入当前动作
            let conflicts = next.filter { $0.key != action && $0.value == combo }.map(\.key)
            for other in conflicts { next[other] = nil }
            next[action] = combo
        } else {
            next[action] = nil
        }
        combos = next
        persist()
    }

    func resetToDefault(_ action: ShortcutAction) {
        set(action.defaultCombo, for: action)
    }

    func resetAll() {
        combos = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultCombo) })
        persist()
    }

    // MARK: - 键盘监视（仅应用内）

    /// 挂载本地键盘监视器（幂等）
    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// 处理一次按键：命中返回 nil（吃掉事件），否则原样放行
    private func handle(_ event: NSEvent) -> NSEvent? {        // 正在输入文字 / 弹出对话框时不抢键（保证空格能正常输入、回车能确认按钮）
        if isTextEntryContext() { return event }

        // ① 录制模式：捕获下一个按键
        if let recording = recordingAction {
            if event.keyCode == 53 {            // Esc = 取消录制
                recordingAction = nil
                return nil
            }
            guard let combo = KeyCombo(event: event) else { return nil }
            set(combo, for: recording)
            recordingAction = nil
            return nil
        }

        // ② 匹配已绑定的动作
        guard let action = ShortcutAction.allCases.first(where: { combos[$0]?.matches(event) == true })
        else { return event }

        // 长按重复时只吞掉事件，避免疯狂切歌 / 反复暂停
        if event.isARepeat { return nil }

        Task { @MainActor in action.perform() }
        return nil
    }

    /// 当前是否处于文字输入上下文（搜索框、歌单名输入、对话框等）
    private func isTextEntryContext() -> Bool {
        guard let window = NSApp.keyWindow else { return false }
        if window.attachedSheet != nil { return true }
        if let responder = window.firstResponder {
            if responder is NSTextView { return true }                  // SwiftUI TextField / TextEditor 的 field editor
            if let field = responder as? NSTextField, field.isEditable { return true }
        }
        return false
    }

    // MARK: - 持久化

    /// 存储结构（包一层，避免空字典被当成「没有配置」而回落到默认值）
    private struct StoredConfig: Codable {
        var bindings: [String: KeyCombo]
    }

    private func persist() {
        let bindings = Dictionary(uniqueKeysWithValues: combos.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(StoredConfig(bindings: bindings)) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> [ShortcutAction: KeyCombo] {
        let defaults = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultCombo) })
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(StoredConfig.self, from: data)
        else { return defaults }

        var result: [ShortcutAction: KeyCombo] = [:]
        for (key, combo) in config.bindings {
            if let action = ShortcutAction(rawValue: key) { result[action] = combo }
        }
        return result
    }
}
