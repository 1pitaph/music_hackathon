# Discover Radio 功能拆解与分工报告

> 日期：2026-06-19  
> 参考：`docs/personal-music-discover-radio-prd-v0.5.2.md`、当前 iOS 工程、三个子 agent 模块研究  
> 目的：把截图中的小需求整理成可分配、可并行推进的功能点，并给出 MVP 闭环与风险边界。

## 1. 结论摘要

当前产品应按 PRD V0.5.2 的三模块来组织任务：

| 模块 | 截图中的需求 | 首要交付 | 当前最大缺口 |
|---|---|---|---|
| 电台模块 | 连接 Apple Music、记忆管理、播放列表、两种播放模式 | 可创建、预览、播放的电台对象 | 还没有 `RadioStation/RadioDraft` 领域模型，播放层仍是单曲播放 |
| 发现页 | 左右滑动切换下一个电台、分享按钮、老式复古电台 UI | 一个可左右切台的复古收音机卡片 | 当前 `DiscoverView` 是单曲 radio 原型，不是公开电台队列 |
| 音乐档案 | 设置页面、音乐数据收集和整理 | 私密声音档案主页和授权管理 | 没有档案事件、授权范围、摘要、数据来源管理 |

建议 MVP 不先追求完整后端和完整 AI，而是先做一条本地可演示闭环：

```text
授权 Apple Music 或使用 preview 兜底
-> 从候选曲 / playlist 选择 3 首歌
-> 生成一个本地 mock 电台草稿
-> 预览并播放电台队列
-> 在发现页左右切换公开 mock 电台
-> 分享当前电台占位链接
-> 声音档案本地记录播放/发布/授权来源
```

这个顺序能让黑客松演示先成立：用户看见的是“调频到不同人的电台”，工程里先立住的是“电台对象 + 播放队列 + 档案事件”。

## 2. PRD 对齐

PRD 已经把产品定义成三段闭环：

```text
声音档案沉淀个人音乐轨迹
-> 电台模块把一段音乐表达制作成可听频道
-> 发现模块把不同用户电台以收音机形式分发
-> 收听、互动、发布结果回流声音档案
```

关键 PRD 条目：

| PRD 编号 | 含义 | 对截图需求的解释 |
|---|---|---|
| `BF-RAD-01` | 电台创建入口与歌曲选择 | 播放列表、候选歌曲、个人模式都应进入电台创建 |
| `BF-RAD-02` | 电台草稿与发布前预览 | 不是选完歌直接公开，必须有预览和确认 |
| `BF-RAD-03` | 电台播放与播放控制 | Apple Music 播放和本地 preview 兜底都要可用 |
| `BF-RAD-04` | 可见性与发布确认 | 记忆/个人模式默认私密，公开必须显式确认 |
| `BF-RAD-05` | 电台分享卡片与链接 | 发现页分享按钮属于 P1，但 MVP 可先做系统分享 |
| `BF-DIS-01` | 发现主入口与收音机卡片 | 第一屏应像电台，不是普通歌单列表 |
| `BF-DIS-02` | 左右滑动切换频道 | 发现页核心交互，P0 |
| `BF-DIS-03` | 发现队列加载与空态兜底 | 无网络/无授权也不能白屏 |
| `BF-ARC-01` | 声音档案入口与个人主页 | `Mine` 不应长期只是 Settings |
| `BF-ARC-04` | 数据来源与授权管理 | 收集、关闭、清空、授权切片是 P0 |
| `AI-RAD-02/03/04` | 电台结构、主题、脚本生成 | 首版可以先 mock JSON，再接模型 |
| `AI-ARC-01/03` | 档案摘要与授权切片 | 不上传完整私密歌单，只给本次可用切片 |
| `AI-DIS-01/02` | 发现排序和卡片文案 | 首版可离线 mock，后续接排序/文案模型 |

## 3. 当前工程现状

### 3.1 已有基础

| 能力 | 当前状态 | 相关文件 |
|---|---|---|
| 系统 tab shell | 已用 SwiftUI `TabView`，默认进入 `.radio`，符合仓库约束 | `apps/ios/MusicHackathon/App/AppView.swift`、`apps/ios/MusicHackathon/App/AppTab.swift` |
| Discover radio 原型 | 有 header、频谱、Now Playing 卡、播放按钮、Up next 文案 | `apps/ios/MusicHackathon/Features/Discover/DiscoverView.swift` |
| Apple Music 授权 | 可请求授权、刷新订阅、判断 catalog playback | `apps/ios/MusicHackathon/Services/MusicAuthorizationService.swift` |
| Apple Music 搜索与 playlist 摘要 | 可搜索曲目、读取 library playlist 摘要、已有 `tracks(in:)` 方法 | `apps/ios/MusicHackathon/Services/AppleMusicCatalogService.swift` |
| 播放控制 | 单曲 Apple Music 播放、本地 preview fallback、进度、Now Playing、远程播放/暂停 | `apps/ios/MusicHackathon/Services/PlaybackController.swift` |
| 曲目模型 | `Track` 已有 title、artist、album、mood、duration、artwork、preview、Apple Music ID | `apps/ios/MusicHackathon/Models/Track.swift` |
| 设置页 | 有 Apple Music 授权/订阅状态和刷新入口 | `apps/ios/MusicHackathon/Features/Settings/SettingsView.swift` |
| 权限 | 已声明 Apple Music、Media Library、Microphone、background audio | `apps/ios/MusicHackathon/Resources/Info.plist` |

### 3.2 主要缺口

| 缺口 | 影响 |
|---|---|
| 缺少 `RadioStation/RadioDraft/RadioTrackRole/RadioVisibility/RadioPlaybackMode` | 无法把“歌”升级成“电台对象”，后续发现页、分享、发布都缺载体 |
| `PlaybackController` 只播放单曲 | 无法实现电台队列、上一首/下一首、自动续播、切台重置 |
| `DiscoverView` 仍以 `Track` 为中心 | 不能表达不同用户的公开电台，也没有左右切台 |
| `LibraryView` 未进入主 tab，详情页只是占位 | 播放列表不能用于选歌、整理档案或生成电台 |
| 没有声音档案数据层 | 播放、收藏、跳过、发布、导入都不能写回档案 |
| Settings 缺隐私管理 | 用户不能查看数据来源、关闭收集、清空主动补充 |
| 没有分享/deeplink | 发现页分享按钮只能先做占位 |
| 没有发现服务和排序事件 | P1 以后需要后端/数据/AI 接上 |

## 4. 模块拆解

### 4.1 电台模块

截图需求：

- 连接 Apple Music
- 记忆管理
- 播放列表
- 两种播放模式

产品解释：

- “连接 Apple Music”是音乐授权与可播放校验，属于 `BF-RAD-03` 和 `BF-ARC-04` 的基础。
- “记忆管理”不要做成泛化笔记，而应落到声音档案授权切片、可见性、删除/关闭。
- “播放列表”是电台创建的歌曲来源之一。
- “两种播放模式”需要统一口径：建议产品层叫“公开电台模式 / 个人模式”，技术层叫“Apple Music backend / preview fallback”，不要混在一个控件里。

建议任务：

| 优先级 | 任务 | 负责人 | 说明 |
|---|---|---|---|
| P0 | 定义电台最小模型 | iOS | `RadioStation`、`RadioDraft`、`RadioTrackSlot`、`RadioVisibility`、`RadioPlaybackMode` |
| P0 | mock 电台数据 | iOS / 产品 | 至少 3 个公开电台，每个 1-3 首歌，有标题、发布者、短文案 |
| P0 | 队列播放控制 | iOS | `play(station:)`、next、previous、切台 reset、preview fallback |
| P0 | 播放列表曲目读取 | iOS | 使用已有 `AppleMusicCatalogService.tracks(in:)` 接入 playlist detail |
| P0 | 电台草稿预览 | iOS / 设计 | 显示标题、曲目、讲解、可见性、播放入口 |
| P0 | 电台生成 JSON 契约 | AI / 后端 | 先 mock：标题、顺序、歌曲角色、开场/过渡讲解 |
| P1 | 发布确认与可见性 | iOS / 后端 | 公开、仅链接、私密草稿；个人模式默认私密 |
| P1 | Apple Music 授权引导 | iOS / 设计 | 拒绝授权、无订阅、preview 兜底状态 |
| P2 | 系统 DJ / 录音开场 | AI / 语音 / iOS | 不进最小 MVP，先保留文本讲解 |

MVP 验收：

- 用户能从 mock/playlist 选 3 首歌生成电台草稿。
- 草稿能播放完整队列，支持播放/暂停/上一首/下一首。
- Apple Music 不可用时仍可用 preview 或 mock 播放。
- 个人模式生成内容默认私密，公开必须确认。

### 4.2 发现页

截图需求：

- 左右滑动切换下一个电台
- 分享按钮
- 老式复古电台 UI

产品解释：

- 发现页是首版最重要的“外向体验”，第一屏应该让人明确感知“正在调到某个人的频道”。
- 不建议为了复古 UI 重写系统 tab bar。保持 `TabView`，只改 `DiscoverView` 内容层。

建议任务：

| 优先级 | 任务 | 负责人 | 说明 |
|---|---|---|---|
| P0 | 本地 Discover 队列 | iOS | 用 mock `RadioStation[]` 代替 `Track[]` |
| P0 | 左右滑动切台 | iOS | `currentStationIndex`，切换后刷新卡片和播放源 |
| P0 | 复古收音机卡片 | 设计 / iOS | 调频窗、刻度、旋钮、扬声器格栅、播放按钮 |
| P0 | 切台播放状态同步 | iOS | 切换电台时 stop/reset，避免外部 `currentTrack` 反向改卡片 |
| P1 | 分享按钮 | iOS / 后端 | MVP 用 `ShareLink` 分享占位 URL；后端补真实 URL/deeplink |
| P1 | 发现队列 API | 后端 / 数据 | 公开电台池、卡片信息、播放/跳过/分享/停留反馈事件 |
| P1 | 卡片文案与排序 | AI | 先离线 mock，后接 `AI-DIS-01/02` |
| P2 | 相邻频道解释和反馈归因 | AI / 数据 / 合规 | 不影响首版演示 |

MVP 验收：

- Discover tab 打开后展示一个复古收音机卡片。
- 至少 3 个 mock 公开电台可左右滑动切换。
- 切换 UI 在 1 秒内完成。
- 播放按钮播放当前电台首个可播曲目。
- 分享按钮调起 iOS 系统分享，分享电台标题和占位链接。
- 无 Apple Music 或加载失败时不白屏。

### 4.3 音乐档案 / 声音档案

截图需求：

- 设置页面
- 音乐数据收集、整理

产品解释：

- `Mine` 不应长期只是 Settings，而应成为声音档案主页：摘要、数据来源、个人模式入口、设置入口。
- MusicKit 不等于完整 Apple Music 历史。MVP 应只承诺“本 App 内播放事件 + 用户主动导入 playlist/自述”，避免说能读取完整听歌历史。

建议任务：

| 优先级 | 任务 | 负责人 | 说明 |
|---|---|---|---|
| P0 | 声音档案主页 | 设计 / iOS | 把 `Mine` 从纯设置升级为档案摘要、数据来源、个人模式入口 |
| P0 | 档案本地模型 | iOS | `ArchiveEvent`、`ArchiveSummary`、`ArchiveDataSource`、`ArchiveConsentScope` |
| P0 | 数据来源与授权开关 | iOS / 合规 | 开启收集、关闭收集、清空本地档案、默认私密 |
| P0 | 播放/发布事件写入 | iOS / 后端 | 先本地，预留同步 API |
| P0 | 摘要与授权切片 JSON | AI / 后端 / 合规 | 先规则生成，后接模型；不得上传完整私密歌单 |
| P1 | Library 主动导入 | iOS | playlist detail 读取曲目，用户主动选择导入 |
| P1 | 档案中的电台集合 | iOS / 设计 | 已发布、收藏、个人模式保存 |
| P1 | 阶段偏好与记忆锚点 | AI / 数据 | 输出置信度，避免心理诊断式文案 |
| P2 | 分身问答 / 语音自述 ASR | AI / 语音 / 合规 | 明确授权和删除策略后再做 |

MVP 验收：

- 用户能在 `Mine` 看到声音档案摘要和数据来源。
- 用户能显式开启/关闭“声音档案收集”。
- 本 App 播放或导入 playlist 后，写入私密 `ArchiveEvent`。
- 本地生成简单摘要：常听歌手、mood、最近播放、数据来源。
- 设置页能清空本地档案；关闭后不再写入或用于 AI。

## 5. 并行分工建议

### 5.1 黑客松 MVP 工作包

| 工作包 | 负责人 | 范围 | 依赖 | 产出 |
|---|---|---|---|---|
| A. 电台领域模型 | iOS 1 | `RadioStation`、mock 数据、草稿结构 | 无 | 可被 Discover 和 Player 消费的数据层 |
| B. 队列播放器 | iOS 2 | `PlaybackController` 队列化、next/previous、切台 reset | A 的模型字段 | 电台可连续播放 |
| C. Discover 复古切台 | iOS 3 + 设计 | 左右滑动、复古 UI、分享按钮 | A 的 mock 队列、B 的播放接口 | 第一屏演示体验 |
| D. 声音档案主页 | iOS 4 + 设计 | Mine 页面、摘要、数据来源、开关 | E 的事件模型可同步进行 | 私密档案入口 |
| E. 档案事件与隐私 | 后端 / 数据 / 合规 | 事件 schema、授权范围、清空/关闭语义 | 无 | 后续 AI 和后端 API 契约 |
| F. AI mock 契约 | AI | 电台生成 JSON、档案摘要 JSON、卡片文案 JSON | A/E 的 schema | 可替换真实模型的 mock 输出 |
| G. 分享与链接 | iOS + 后端 | `ShareLink`、占位 URL、deeplink 预留 | A 的 station id | P1 演示增强 |

### 5.2 推荐推进顺序

| 顺序 | 目标 | 为什么先做 |
|---|---|---|
| 1 | 定义 `RadioStation` / `RadioDraft` / `ArchiveEvent` | 这是所有模块共享语言 |
| 2 | 用 mock 数据跑通 Discover 左右切台 | 最快让产品形态可见 |
| 3 | 把单曲播放升级为电台队列播放 | 解决“这不是歌单 list，而是频道”的核心 |
| 4 | `Mine` 升级为声音档案主页 | 让记忆/数据来源有承载页面 |
| 5 | Playlist detail 支持选歌/导入 | 把 Apple Music 授权变成可用输入 |
| 6 | 接 AI mock JSON | 为真实模型接入留契约 |
| 7 | 分享、发布、发现反馈写回 | 完成外部分发和回流闭环 |

## 6. 关键产品口径

### 6.1 两种播放模式

建议统一成两层口径：

| 层级 | 名称 | 面向谁 | 说明 |
|---|---|---|---|
| 产品模式 | 公开电台模式 | 收听者 / 发布者 | 可进入发现池，可分享 |
| 产品模式 | 个人模式 | 用户本人 | 从声音档案入口进入，默认私密，可生成公开草稿灵感 |
| 技术后端 | Apple Music playback | 工程 | 授权和订阅可用时播放完整 catalog |
| 技术后端 | Preview fallback | 工程 | 无授权/无订阅/失败时仍可演示 |

不要在 UI 里把“Apple Music / preview”叫成“两种播放模式”，否则会和 PRD 的“公开 / 个人”混淆。

### 6.2 记忆管理

“记忆管理”建议拆成四个可落地对象：

| 对象 | 说明 |
|---|---|
| `ArchiveEvent` | 播放、收藏、跳过、发布、导入、自述等事件 |
| `ArchiveSummary` | 本地/AI 生成的可读摘要 |
| `ArchiveConsentScope` | 哪些来源可用于展示、生成、问答 |
| `ArchiveSlice` | 本次生成电台或问答可用的最小授权切片 |

原则：默认私密、可关闭、可清空、公开前确认、不上传完整私密歌单。

### 6.3 老式复古电台 UI

复古不是换一套颜色，建议让首屏有明确实物信号：

- 调频窗口：显示当前频道名、发布者、频率感数字。
- 刻度尺：左右切台时刻度/指针移动。
- 旋钮：播放、切台、收藏/分享可围绕旋钮布局。
- 扬声器格栅：可和当前频谱联动。
- 材质：奶油白/金属/深色胶木都可以，但要避免全页面单色调。

## 7. 风险与待确认

| 风险 | 严重度 | 建议处理 |
|---|---|---|
| Apple Music capability / entitlements 未确认 | P0 | iOS 负责人复核 Apple Developer capability、签名和真机授权 |
| MusicKit 不能读取完整听歌历史 | P0 | MVP 只承诺 App 内事件和用户主动导入 |
| 没有电台对象导致各模块各说各话 | P0 | 第一优先级定义共享模型 |
| 隐私边界不清导致 AI 上传过量数据 | P0 | 先做 `ArchiveSlice`，不传完整私密歌单 |
| 播放队列与切台状态不一致 | P0 | 切台时明确 stop/reset，播放器维护 station/track index |
| 复古 UI 过度改 tab shell | P1 | 保持系统 `TabView`，只改内容层 |
| 分享链接没有后端落点 | P1 | MVP 用占位 URL，后端补 deeplink 和 station lookup |
| 真实模型输出不稳定 | P1 | 先定 JSON schema、schema 校验、mock fallback |

待确认问题：

1. “两种播放模式”最终是否确认为“公开电台 / 个人模式”？
2. 黑客松 MVP 是否允许先用本地 mock 电台池和 mock AI JSON？
3. 真实分享链接是否需要在本轮接后端，还是先系统分享占位链接？
4. 声音档案首版是否只记录 App 内行为和用户主动导入数据？
5. `Mine` 是否改名为“档案 / Archive”，还是保留 Mine 但内容升级？

## 8. MVP 任务清单

| ID | 模块 | 任务 | 优先级 | 建议负责人 | 验收标准 |
|---|---|---|---|---|---|
| MVP-01 | 电台 | 新增 `RadioStation`、`RadioDraft`、mock 电台池 | P0 | iOS | Discover 可读取至少 3 个电台对象 |
| MVP-02 | 电台 | `PlaybackController` 支持 station 队列播放 | P0 | iOS | 可播放/暂停/上一首/下一首 |
| MVP-03 | 发现 | Discover 左右滑动切台 | P0 | iOS | 1 秒内切换卡片和播放源 |
| MVP-04 | 发现 | 复古收音机卡片 UI | P0 | 设计 + iOS | 首屏不像普通列表，有调频识别 |
| MVP-05 | 发现 | 分享按钮 | P1 | iOS | 调起系统分享，包含标题和占位链接 |
| MVP-06 | 档案 | `Mine` 声音档案主页 | P0 | 设计 + iOS | 展示摘要、数据来源、个人模式入口 |
| MVP-07 | 档案 | 本地 `ArchiveEvent` 写入和清空 | P0 | iOS / 数据 | 播放/导入写入，用户可关闭和清空 |
| MVP-08 | 音乐输入 | Playlist detail 读取曲目 | P1 | iOS | 用户能看到 playlist 曲目并选择导入/生成电台 |
| MVP-09 | AI | 电台生成 mock JSON schema | P0 | AI / 后端 | 返回标题、顺序、角色、讲解 |
| MVP-10 | AI | 档案摘要 mock/rule schema | P0 | AI / 后端 / 合规 | 返回摘要、来源、授权切片 |

## 9. 建议本周可交付版本

如果只做一个可演示版本，建议范围收敛为：

- 保留系统 `TabView`。
- `Radio` tab 改为复古 Discover 电台流。
- 本地 3 个 mock 电台，左右切换。
- 播放当前电台队列，Apple Music 失败时 preview 兜底。
- 分享按钮先系统分享占位链接。
- `Mine` 展示声音档案摘要、数据来源、收集开关、清空按钮。
- AI 先使用 mock JSON，接口 shape 按 PRD 留好。

这样演示时可以讲清楚三句话：

1. “我先从自己的听歌和主动导入内容里形成声音档案。”
2. “我可以把一段音乐记忆生成一个可播放、可讲解的电台。”
3. “别人可以像调频一样左右滑动听见不同人的电台，反馈再回流档案。”
