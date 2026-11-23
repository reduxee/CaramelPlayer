# CaramelPlayer · 焦糖音乐

macOS 原生本地音乐播放器（Swift + SwiftUI + AVFoundation）。

**纯本地运行：不联网、不请求任何网络接口，只读取本地音频文件。**

---

## 一、运行环境

| 项目 | 要求 |
|---|---|
| macOS | 13.0 Ventura 及以上（窗口自适应、深浅色自动切换） |
| Xcode | 15.0 及以上（推荐 16.x；本项目已在 **Xcode 16.2** 实测 Build Succeeded 并冒烟运行） |
| 语言/框架 | Swift 5.9 语法 · SwiftUI · AVFoundation · MediaPlayer（全部系统原生框架，零第三方依赖） |
| 架构 | arm64 / x86_64 均可 |

## 二、使用方式

1. 双击 `CaramelPlayer.xcodeproj`（或 `open CaramelPlayer.xcodeproj`）在 Xcode 打开；
2. 选中 scheme `CaramelPlayer`，直接 **⌘R** 运行（Ad-hoc 签名，无需开发者账号）；
3. 首页点击「选择文件夹」导入本地音乐目录（递归扫描子文件夹）；
4. 点击列表中任意歌曲开始播放。

支持格式：`mp3 / flac / wav / m4a / aac`。

命令行构建（可选）：

```bash
xcodebuild -project CaramelPlayer.xcodeproj -scheme CaramelPlayer -configuration Debug build
```

## 三、功能清单

### 核心播放
- 播放 / 暂停 / 上一首 / 下一首（上一首在播放超过 3 秒时回到本曲开头）
- 播放模式：**单曲循环 / 列表循环 / 随机播放**（底部控制条按钮循环切换）
- 进度条拖拽跳转，实时显示「当前播放时间 / 歌曲总时长」
- 音量滑块 + 静音按钮
- 自动读取内嵌元数据：歌曲名 / 歌手 / 专辑 / 内嵌专辑封面

### 歌词（重点）
**歌词来源优先级：**
1. **音频文件内部嵌入的同步歌词（内嵌 LRC）**——mp3 的 ID3 `USLT/ULT` 帧、m4a/aac 的 iTunes `©lyr`、FLAC 的 Vorbis `LYRICS/UNSYNCEDLYRICS` 字段；
2. 内嵌歌词缺失或**格式异常**（纯文本无时间标签）时，**自动降级**读取同目录同名 `.lrc` 文件（如 `歌曲.flac` → `歌曲.lrc`）；
3. 外部 lrc 也不存在时，回退展示内嵌纯文本歌词（不可同步滚动）；
4. 两者都不存在 → 歌词面板显示「暂无歌词」。

歌词解析兼容标准 LRC 时间标签：`[mm:ss]` / `[mm:ss.xx]` / `[mm:ss.xxx]` / `[mm:ss:xx]`，一行多时间标签自动拆分为多行，按时间排序。同步逻辑：当前行高亮 + 自动居中滚动。

### 播放列表
- 点击歌曲直接播放，当前播放行高亮，列表自动滚动跟随正在播放曲目
- 清空列表、重新选择文件夹（增量去重导入）
- 损坏 / 无法解码的文件自动跳过并 toast 提示，不崩溃

### 界面（三个主页面）
- **页面1 · 歌曲列表页**：歌曲名 / 歌手 / 时长 三列；工具栏从窗口最上沿开始，不留顶部空白；
  「选择文件夹 / 清空列表」已移入「设置 → 设置歌单」，顶栏只保留标题、歌曲数与搜索入口
- **页面2 · 播放详情页**：左侧 CD 圆盘（播放时 20°/s 匀速线性旋转，暂停保持角度、恢复连续；中央为专辑封面或简约默认 CD 占位图），下方歌曲名称/歌手/专辑；右侧同步歌词滚动面板；
  全屏与收起按钮统一在右上角，播放模式按钮移到收藏心形左侧
- **页面3 · 搜索页**：右上角搜索入口只做「长得像输入框」的按钮，点击后进入独立搜索页（真实输入框自动聚焦，
  命中结果按歌名/歌手/专辑模糊匹配，点击即在结果集内播放，返回按钮回到原列表）
- **迷你播放器**：加高至 74pt，去掉常规进度滑块（跳转去播放器页），只保留上沿 2pt 进度条，
  上一首/播放/下一首水平居中，播放按钮为圆角方形（整块可点）
- 宽窗口左右分栏，窄窗口自动上下堆叠；窗口自由缩放自适应
- 时尚简约焦糖主题，跟随系统浅色/深色模式自动切换，macOS 原生质感

### 辅助
- **应用内快捷键**（仅窗口处于前台时生效，不注册系统全局热键）：
  空格 = 播放/暂停，⌘← / ⌘→ = 上下首，⇧⌘M = 切换播放模式；
  全部可在「设置」页里点击按键框后按下任意 ⌘/⌥/⌃/⇧ 组合键自定义，Esc 取消录制；
- **媒体按键**：F7/F8/F9（播放/暂停/上下曲）、耳机线控、控制中心播放控件与进度拖动（MPRemoteCommandCenter）
- 菜单快捷键：⌘O = 导入文件夹，⌘, = 打开设置
- **设置页**：左侧边栏左下角齿轮按钮进入（图标按钮，无文字），右侧内容区切换为设置页
- **状态记忆**：重启后恢复播放列表、当前曲目、播放模式、音量、静音状态、停留页面（不自动续播，等待用户按下播放）
- 缺失封面 / 歌词均有友好占位提示

## 四、代码结构

```
CaramelPlayer/
├── CaramelPlayer.xcodeproj        # Xcode 工程文件
└── CaramelPlayer/
    ├── CaramelPlayerApp.swift     # App 入口（媒体按键挂载、菜单快捷键）
    ├── Models/
    │   └── Song.swift             # Song / LyricLine / Lyrics / PlaybackMode 数据模型
    ├── Player/
    │   ├── PlayerManager.swift    # ★ 播放管理器（单例 AVPlayer）：队列/模式/进度/导入/歌词调度/持久化
    │   └── MediaKeysManager.swift # 媒体按键（MPRemoteCommandCenter + Now Playing）
    ├── Lyrics/
    │   ├── LyricsParser.swift     # ★ LRC 解析器（纯函数，时间标签解析）
    │   └── LyricsLoader.swift     # ★ 歌词加载：内嵌优先 → 外部 .lrc 降级 → 纯文本 → 暂无歌词
    ├── Metadata/
    │   ├── SongMetadataReader.swift # ★ 元数据统一读取（AVFoundation + 内嵌歌词匹配规则）
    │   └── FlacMetadataParser.swift # FLAC Vorbis Comment / PICTURE 手动解析（含内嵌歌词）
    ├── Persistence/
    │   └── AppSettings.swift      # UserDefaults 状态记忆
    ├── Shortcuts/
    │   └── Shortcuts.swift        # ★ 应用内快捷键：组合键模型 / 录制 / 匹配 / 持久化
    ├── Views/
    │   ├── ContentView.swift      # 主框架（自绘侧边栏 + 内容区 + 设置/搜索页切换 + toast）
    │   ├── SongListView.swift     # 页面1：歌曲列表
    │   ├── SearchPageView.swift   # 页面3：搜索（点顶部搜索入口进入）
    │   ├── PlayerDetailView.swift # 页面2：左右分栏详情
    │   ├── CDPlayerView.swift     # CD 圆盘组件（TimelineView 线性旋转）
    │   ├── LyricsView.swift       # 歌词滚动面板（同步/纯文本/空三态）
    │   ├── PlayerControlsBar.swift# 底部常驻迷你控制条（居中三键 + 音量）
    │   └── SettingsView.swift     # 设置页（左：设置列表；右：快捷键 / 设置歌单）
    └── Resources/
        ├── Info.plist
        └── Assets.xcassets
```

★ 标注文件含「内嵌歌词读取逻辑」等重点注释，代码内以 `【重点：…】` 标记。

### 内嵌歌词读取逻辑摘要

- **mp3 / m4a / aac**：AVFoundation 把 ID3 `USLT`（v2.3/2.4）、`ULT`（v2.2）、iTunes `©lyr` 暴露为 `AVMetadataItem`，按 `keySpace + key` 精确匹配取原文（见 `SongMetadataReader.embeddedLyrics(from:)`）；
- **FLAC**：AVFoundation 对 Vorbis Comment 暴露不完整，直接按 FLAC 规范手动解析 metadata block（`FlacMetadataParser`），读取 `LYRICS / UNSYNCEDLYRICS / SYNCEDLYRICS` 字段与 PICTURE 封面；
- 拿到内嵌文本后由 `LyricsLoader` 判定：含 LRC 时间标签 → 同步歌词；否则降级外部 `.lrc`；再否则作为纯文本展示。

## 五、已验证

- ✅ Xcode 16.2 `xcodebuild` 构建 **BUILD SUCCEEDED**，Debug 构建冒烟运行无崩溃
- ✅ `swiftc -typecheck`（macOS 13 target）0 error / 0 warning
- ✅ LRC 解析单元断言：多时间标签拆行、冒号毫秒、纯文本判别、异常输入不崩溃
- ✅ 端到端断言：wav 时长读取、无内嵌歌词 → 外部 lrc 降级、内嵌格式异常 → 降级外部 lrc、无来源 → 「暂无歌词」

> 说明：本机未安装完整 Xcode 时可用命令行验证；已在本机（Xcode 16.2, macOS 14 SDK）完整构建通过。

## 六、可选扩展功能（当前未实现，后续新增指引）

| 功能 | 新增方式 |
|---|---|
| **菜单栏常驻控件**（MenuBar 播放控制） | 新建 `MenuBarExtra` Scene（macOS 13+ 原生 API）：`MenuBarExtra("焦糖", systemImage: "opticaldisc") { 迷你控制视图 }`，直接复用 `PlayerManager` |
| **歌曲排序**（按歌名/歌手/时长/加入顺序） | `SongListView` 增加 `@State var sortOrder`，对 `player.songs` 派生排序；或在列表头加点击排序按钮，持久化进 `AppSettings` |
| **搜索过滤** | `SongListView` 加 `.searchable(text:)`，filter 歌名/歌手 |
| **播放列表编辑**（拖拽排序、删除单曲） | 列表行加 `.draggable/.dropDestination`（或上下文菜单删除），`PlayerManager` 增加 `move/remove` 方法并持久化 |
| **均衡器 EQ** | `AVAudioEngine` + `AVAudioUnitEQ` 替换直接 `AVPlayer` 输出（复杂度较高） |
| **输出设备选择** | 读取 `AVAudioSession`（macOS 上为 `NSSound`/CoreAudio），或切换 `AVPlayer` 的 `audioOutputDevice` |
| **多媒体按键** | ✅ 已实现（含控制中心进度拖动），无需扩展 |
| **迷你悬浮歌词窗** | 新增 `Window("歌词", id: "lyrics")` Scene + `MenuBarExtra` 控制显隐 |
| **App 沙盒上架** | 开启 App Sandbox + 将 `AppSettings` 的路径持久化改为 security-scoped bookmarks |

## 七、设计约束

- 不做云音乐、登录、在线搜索、广告、推荐——**只做本地播放器**；
- 音频全部走 AVFoundation 系统框架，无第三方音视频 SDK；
- UI 全部 SwiftUI，无 WebView / 无移动端移植样式。

## 八、许可证

本项目基于 [MIT License](LICENSE) 开源 —— 可自由使用、修改、分发，保留版权声明即可。

```
MIT © 2026 Yee Qee
```
