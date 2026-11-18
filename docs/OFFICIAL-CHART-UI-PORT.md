# 官方 FNF 编谱器 UI 移植（阶段 1）

## 来源

- 代码/布局参考：`FunkinCrew/Funkin` `main` @ `94ee0f2a9386d80e445be39ee2ed4b4a630cfbac`
  （v0.8.7 / build 102），`source/funkin/ui/debug/charting/`。
- UI 结构参考（只读，不提交资源）：
  - `Funkin.assets:exclude/data/ui/chart-editor/main-view.xml`
  - `components/menubar.xml`、`components/playbar.xml`、`components/style.xml`
  - `toolboxes/*.xml`
- 官方编辑器使用 HaxeUI + `funkin.*` 游戏核心 + Funkin 的 flixel fork；本仓库工具链是
  Haxe 4.2.5 + flixel 6.2，不能直接编译官方 HaxeUI 代码（实测 `Function body required` /
  `FlxSpriteContainer` 缺失）。因此这里只移植 **UI 结构/布局/视觉**，用原生 Flixel 实现，
  不引入 HaxeUI、funkin 核心或官方资源。

## 已实现（阶段 1.1）

| 官方 UI | 本实现 |
|---|---|
| 顶部菜单栏 File / Edit / View / Playtest / Help | `OfficialChartEditorState` 顶部菜单，可展开基础菜单项 |
| 底部播放条：时间、剩余时间、Beat/Step、`\|< << > >> >\|`、难度/BPM/吸附 | 同布局；按钮可 seek/播放暂停，吸附可左右切换 |
| 居中的 9 列网格（事件轨 + 8 轨） | 紫底 `0xFF673AB7`、浅色网格、红色播放头、小节号 |
| 轨道表头按钮 | EVT / OPPONENT / PLAYER + 四色方向箭头 |
| Notes 工具箱 | 左侧浮动面板：吸附、音符类型、操作提示 |
| 节拍/小节分割线 | 每个 step / beat / measure 三级线宽与颜色 |
| 音符/长条 | 按轨道颜色绘制，时间随播放头滚动 |

数据仍为 Psych `SwagSong`；保存输出 `psych_v1` JSON，桌面端写回
`mods/data/<song>/<song>-<diff>.json`（仅当当前模组已有该曲目录时才写当前模组），
并删除旧 `.mec`。

补充可用能力：

- 真实歌曲加载：`--meteoric-song=<song>` + `--meteoric-editor=chartui`，或 `METEORIC_UI_SONG=<song>`；
  不再只能用空 `Test` 谱。
- 逐小节 BPM 的 step 坐标：音符/网格按 `stepAtTime/timeAtStep` 对齐，变速段不再错位。
- 右侧 `Section / Events` 面板：BPM ±、MustHit、Add/Remove Section、Event Type、Add/Del Event。
- 打开谱面：左侧 `Song folder` 输入框 + Open，或 `Ctrl+O`；支持当前难度后缀与模组数据目录。
- 事件值：选中事件后，右侧 `Event Value 1/2` 直接编辑。
- 撤销/重做：`Ctrl+Z / Ctrl+Y`，最多 40 步；覆盖音符、小节、BPM、事件编辑。
- 音符选中/长条/类型：左键选中，`Hold -/+` 调整长条，`Cycle Type` 切换类型，`Delete Note` 删除。
- `ESC` 试玩（`EditorPlayState`），`Backspace` 返回编辑器菜单。
- 入口改为默认：`EditorBridge.openChartEditor()` / 编辑器菜单的「编谱器」默认进官方 UI 版；
  Help → `Classic Editor` 可切回旧版（本次会话有效；存档位 `classicChartEditor=true` 也可回退）。

## 入口

当前**不改默认入口**，用调试参数启动：

```bash
cd export/release/macos/bin/Meteoric.app/Contents/MacOS
METEORIC_SAVE_DIR=/tmp/meteoric-chartui ./Meteoric --meteoric-editor=chartui
```

`--meteoric-editor=official` 同义。经典编谱器入口保持原样。

## 未完成 / 明确不是官方版的部分

- 没有引入 HaxeUI，因此菜单/工具箱是原生 Flixel 重绘，不是官方 HaxeUI 控件树。
- 官方完整工具箱（Metadata / Difficulty / Offsets / Freeplay / Playtest properties / 角色预览）
  只做了 Notes + Section/Events，其余待继续。
- 左键在空网格放置音符、在已有音符上选中；右键删除。官方的框选、Ctrl 多选、剪贴板
  还没接到这套新界面。
- 事件只能加默认事件名，值 1/值 2 还没有输入框；BPM 只能 ±5，不能直接输入。
- 音符长条只能按 step 调整，不能拖拽拉长。
- 官方资源（图标、字体 Inconsolata、对话框 XML）是 proprietary，未复制进仓库。
- 官方编辑器支持变奏/难度/时间变化等 `SongData` 结构；本实现只映射 Psych 的 section/note。

## 验证

- `python3 tools/i18n/check_i18n.py`：PASS。
- `./compile-mac.sh typecheck`：exit 0。
- 真机启动 `--meteoric-editor=chartui`，日志确认
  `[OfficialChartEditor] create ...` / `first frame ...`；窗口截图确认菜单栏、网格、
  播放条、工具箱和自检音符可见。
- 已验证：真实 `bopeebo` 加载（38 小节 / 118 音符）、鼠标点击放置音符、`Ctrl+Z` 撤销、
  `Ctrl+S` 保存到 `mods/data/bopeebo/bopeebo.json` 并保持 118 音符。
- 已验证：`ESC` 进入 `EditorPlayState` 试玩并返回编辑器；`Ctrl+O` 打开 `fresh`（42 小节 / 238 音符），
  `Ctrl+S` 保存为合法 `psych_v1`。
- 未验证：面板按钮的真实鼠标命中（注入坐标与窗口缩放不一致）、事件输入框的真实键盘输入。
