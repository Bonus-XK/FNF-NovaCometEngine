# 演出编排编辑器（Choreo Editor）设计稿 v2

> v2 = DCE（Different Creatingness Engine）语义兼容重做（2026-11-15）。
> 参考实现：github.com/D-C-Fantasy-Land/Different-Creatingness-Engine
> `source/developer/editors/CameraEditorState.hx`（7634 行）+ `source/general/backend/cameraeditor/`。
> 参考图（chart-editor-mockup.html「Adobe Style v4」）即出自 DCE。

## 1. 数据与运行时（DCE 同构兼容）

- **文件**：谱面同目录 `cam.json`（`psych_cam_v1`）：
  `{format, initialized:true, events: [[time, [[name, v1, v2, layer, 'camera'|'chart'], ...]], ...]}`
  legacy `<chart>-cam.json` 仍可读。**谱面在打包资产里 = 只读**（saveCamEvents 返回 null，编辑器提示走导出）。
- **图层**：`{name, typeName, color}` 数组。Default 层（typeName=''，兜底普通事件层，不可删/改）+
  六内建类型（Focus Camera/Zoom Camera/Add Camera Zoom/Camera Follow Pos/Play Animation/Camera Angle）+
  自定义绑定层（typeName=事件名 → 该名成为托管事件）。图层存 `mods/camera_editor_prefs.json`。
- **运行时**：PlayState 载谱后 `CameraEditorData.mergeIntoEventsData`（NoteChartDomain）：
  有 cam.json 才合并（stripManaged 剔除托管事件 → eventsToRaw 并入排序）——无文件 = 零行为变化。
  事件由 EventDomain 的 DCE 兼容处理器回放：
  - **Focus Camera**：值1 = boyfriend/dad/girlfriend/pos；值2 = "偏移X,偏移Y,时长,缓动"（默认 2,CLASSIC）。
    **钉住相机**（isCameraOnForcedPos=true，与 Move Camera 相反），落点走 tweenCameraScroll。
  - **Zoom Camera**：值1 = 目标缩放；值2 = "时长,缓动,模式"（direct=绝对 / stage=×defaultZoom）。
  - **Camera Angle**：值1 = 角度；值2 = "时长,缓动"（camGame.angle 补间，重开时归零）。
  - **Camera Follow Pos**（双格式兼容）：DCE "值1=X，值2=Y,时长,缓动" / 旧格式瞬时直设（值2 纯数字）。
  - INSTANT/CLASSIC token = 忽略时长直接落位（ChoreoEase.isSnapToken）。
- **custom: 缓动**：16 个 0..1 采样点逗号串（`custom:0,0.05,...`），ChoreoEase 编解码/求值与 DCE
  CustomEase 完全同构；CameraHudDomain.getEase 支持 custom: token。
- **migrateFromSong**：首次打开无 cam.json → 从谱面小节结构（mustHitSection/gfSection）合成
  Focus Camera 基准编排 + 吸收既有托管事件 → 写 cam.json（真机实测：sadness 生成 21 事件）。

## 2. 编辑器（states.editors.ChoreoEditorState v2）

- **布局**（DCE 结构对位）：菜单条（6 菜单）+ 状态行（TOP_H 60）→ 预览区 → 信息行 →
  时间轴工具栏 38 + 滚动条 16 → 标尺 28 → 图层行（标签列 140）→ 音符条 44；右面板 440；
  时间轴区默认 300px，分隔条可拖（180..500）。
- **预览 = 全屏观察相机**（真机铁律沿用 v1）+ **取景框 overlay**（青框+角标+跟点红点+框外暗化）：
  camZoom = previewZoom × vcamZoom ÷ vfWinScale；框屏幕尺寸 = 1280×720×previewZoom。
  交互：框内拖动平移 / Alt+拖旋转（0.35°/px ±180）/ IJKL 平移 / 滚轮三级（plain=预览缩放、
  Ctrl=镜头缩放、Shift=框世界尺寸）；**拖框时选中 FollowPos/Focus 事件 = 直接改写该事件坐标**（DCE 语义）。
- **vcam 模拟**（DCE stepVirtualCamera 语义）：follow 点 lerp（clamp(elapsed*7, 0.03, 1)）+
  zoom/angle/follow 三通道补间插值器；**seek = 全量重模拟（瞬时落位）**、播放 = 增量触发（带缓动）。
- **时间轴**：图层行（层色卡、选中黄框、瞬时事件三角标、时长卡宽 = v2 时长×px/ms）、标尺
  measure.beat（DCE 1-based）、网格小节/拍/细分、播放头、滚动条（滑块+点击居中）、
  吸附 1/4..1/192（Shift 反转）、自动滚动 关/翻页/平滑（手动滚动后 1.5s 抑制）、
  边界自动滚动、多选（Ctrl+点）/框选（>6px）/Ctrl+A、拖卡改时间+垂直拖换层、拖边改时长
  （20ms..30s 写回 v2 时长槽）、内存剪贴板（相对偏移粘贴）、Ctrl+D 副本到下一小节、
  **撤销/重做 = 50 层全量快照**。
- **面板**：事件名下拉（DCE displayEventName 中文）、时间（ms）直编、v1/v2 + 值提示
  （CameraEditorData.eventHint，DCE 同款中文文案）、添加/复制/删除/粘贴。
- **音符条**：双排 marker（对手红 FF857B/玩家绿 9AE881，长条拉宽，绝对列号协议）——
  角色联动 sing 是 DCE 的 CameraEditorNotePreview，后续迭代。
- **键位**（DCE 主集）：空格播放 · N 添加 · Shift+A 提示 · Del/Backspace 删 · Ctrl+Z/Y 撤销重做 ·
  Ctrl+C/X/V 复制剪切粘贴 · Ctrl+D 副本 · Ctrl+A 全选 · Q/E 吸附档 · A/D 时间轴平移 ±500ms ·
  F 定位选中 · Home 回开头 · IJKL 移镜（Shift ×3） · R 回正位置 · Ctrl+G 回正缩放 ·
  `,`/`.` 快速 Focus dad/bf · Ctrl+S 保存 · Esc 返回。

## 3. 直启参数（真机验证用）

`--meteoric-editor=choreo`（主菜单自动进入）+ `--meteoric-song=<曲>`（直选曲目）+
`--meteoric-mod=<模组目录名>`（激活模组——谱面解析依赖它）。三者可组合。

## 4. 复用与规范

- 组件复用 ChartWidgets（EditorButton/EditorInput/EditorDropdown/EditorToggle）+ makePanel + WheelScroll。
- trace 一律 `[Choreo]` / `[CameraEditor]` 前缀（i18n 豁免约定）；
  CameraEditorData 的中文值提示 = 数据表 RAW（SKIP_REASONS 已登记，Achievements.hx 先例）。

## 5. 真机踩坑（本次新增）

- **followLerp 陷阱**：`follow(LOCKON, 0)` 永不收敛（flixel 5.2.2 死区分支 × lerp=0）；
  Meteoric PlayState 靠每帧手写 followLerp 才动。编辑器解法 = 每帧 snapToTarget / 直接驱动 scroll。
- **内窗相机不可行**：flixel 5.2.2 scrollRect = width × initialZoom，内窗裁剪结构性不成立 → 全屏相机 + overlay。
- **载曲后必须重设 Paths.setCurrentLevel**（StageData.loadDirectory + forceNextDirectory 同款），
  否则舞台贴图按上一个 level 解析全 null。
- **先舞台后角色**：舞台 bg 后 add 会盖住整组角色。
- **paths 口径**：cam.json 目录解析必须走 `Song.resolveChartPath`（谱面 = data/<song>/<song>-<diff>.json
  目录结构，`chartPath('<song>')` 是错的 key）；仅 mods/ 目录可写。
- **DebugLaunch 测试双实例坑**：`open` 会竞态拉起第二个实例；pkill -f 的模式要匹配实际命令行。

## 6. 真机验证记录（2026-11-15）

- 直启 sadness（tcm 内容模组）→ migrateFromSong 生成 cam.json（21 事件）✓
- 编辑器：DCE 布局全渲染（图层行/标尺 measure.beat/双排音符条/取景框+跟点红点/右面板）✓
- 播放推进 + 自动滚动翻页 ✓
- 真实 PlayState 回归：cam.json 合并（trace 21 事件）→ Focus Camera 驱动镜头无崩溃 ✓
- 门禁：typecheck + i18n 双过 ✓
- 未验证（合成输入噪声）：拖框编辑事件的精确手感、框选/多选组合键、Ctrl+S 落盘内容比对、
  自定义缓动曲线拖拽、Zoom stage 模式实机观感

## 7. 与 DCE 的差异（有意裁剪）

| DCE 特性 | 处置 |
|---|---|
| 开在真 PlayState 上的子状态预览 | 用独立状态 + 真舞台类挂接（等价保真度，不耦合游玩系统） |
| CameraEditorNotePreview 角色 sing 联动 | 简化为双排 marker 条（后续迭代） |
| 键位重绑定 / 书签 / 面板拖动 / mini-map | 不做（DCE 的面板拖动与 mini-map 也是死代码） |
| 移动端 UI 缩放（mobileUiScale） | 不做（桌面端工具） |
| FileDialogHandler 打开任意谱面 | 不做（跟随本引擎模组选曲流程） |
| 事件源 custom_events/<name>.txt 提示 | 不做（值提示走内置表） |
