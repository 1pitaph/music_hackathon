# Discover 页 — 视觉设计系统

> **暗色高级感 · 苹果原生克制**
>
> 暖近黑背景 + 米白文字 + 酒红唯一强调。无旋钮、无木质、无拟物装饰。

---

## 1. 色彩

```
background    #1A1715  暖近黑  页面主背景
surface       #24211E  暖灰黑  卡片
label         #F5F0E8  米白    主文字
secondary     rgba(245,240,232,.60)  次文字
tertiary      rgba(245,240,232,.35)  三级文字
separator     rgba(245,240,232,.12)  分割线
accent        #722F37  酒红    唯一强调 (播放/收藏激活)
accentGlow    rgba(114,47,55,.35)  封面氛围光
```

---

## 2. 排版 (iOS HIG)

| 用途 | 规格 |
|------|------|
| 页面标题 | Large Title: 34pt · Regular |
| 卡片标题 | Title 2: 22pt · Regular |
| 发布者 | Subhead: 15pt · Regular |
| 热门电台项 | Callout: 16pt + Subhead: 15pt |
| 抽屉标签 | Caption1: 12pt · uppercase |

---

## 3. 页面结构 (三段式)

```
┌──────────────────────────┐
│  发现              [↗]    │  ← header + 分享按钮
├──────────────────────────┤
│     ┌───────────────┐    │
│     │  封面 + 光晕   │    │  ← 卡片堆叠 (左右滑动切台)
│     │  标题  发布者  │    │    封面区域触发手势
│     │         [♥]    │    │    收藏按钮在信息行右侧
│     ├───────────────┤    │
│     │ 查看详情   ⌄   │    │  ← 展开把手 (点击展开抽屉)
│     │ 电台说明+歌单  │    │    说明 + 歌曲列表
│     └───────────────┘    │
├──────────────────────────┤
│  热门电台                │  ← 首屏之外，下滑出现
│  [🎵] 深夜爵士电台    ›  │
│  [🎵] 电子漫游指南    ›  │
│  ...                    │
├──────────────────────────┤
│ ┌─ 深夜爵士电台 ▶️ ═══ ─┐│  ← 悬浮播放胶囊 (播放时出现)
│ └───────────────────────┘│    fixed bottom, 左右留白
└──────────────────────────┘
```

---

## 4. 组件

### 卡片 (StationCard)
- `surface` 背景 · `borderRadius: 12`
- 封面图 `aspectRatio: 1` + 同色氛围光晕 (accentGlow)
- 信息行: 标题 + 发布者 + 收藏按钮 (SF Symbol heart/heart.fill, 激活时酒红)
- 播放: 点击封面区域切换播放/暂停

### 展开抽屉 (ExpandableDrawer)
- P0: 卡片底部把手条 → 点击展开 → 电台说明 + 歌曲列表 (前5首)
- P1: "查看全部" 按钮 (占位，显示即可)

### 悬浮播放栏 (FloatingPlayer)
- 播放状态出现 · `position: absolute; bottom: 0`
- 胶囊条: `surface` 95% 半透明 + separator 边框 · 左右 20px 留白
- 电台名 + 播放/暂停图标 + 频谱指示

### 热门电台 (HotStationsList)
- 中文标签 "热门电台"
- 64×64 封面 + 标题 + 发布者 + chevron
- 点击跳回卡片并自动播放

### 分享按钮
- 右上角 SF Symbol `square.and.arrow.up`
- 调用系统 `Share.share()`

---

## 5. 手势边界

| 区域 | 手势 |
|------|------|
| 卡片封面区域 | PanGesture 左右滑动 → 切台 |
| 收藏按钮 | Pressable → toggle 收藏状态 |
| 展开把手 | Pressable → toggle 抽屉 |
| 卡片信息区 | 透传给 ScrollView 滚动 |
| 热门电台各项 | Pressable → 跳转播放 |

---

## 6. 动效

- 所有按钮: Spring `0.92 → 1.05 → 1.0`
- 卡片飞出: `Easing.out(Easing.cubic)` 280ms
- 卡片回弹: `damping:15, stiffness:170`
- 抽屉展开: Spring `damping:14, stiffness:140` (maxHeight)
- 仅用 `transform` + `opacity`
