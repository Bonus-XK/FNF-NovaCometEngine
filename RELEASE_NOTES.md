# NovaComet Engine v1.2.0 Pre-release 3 — "crazymidnight"

> 基于 Psych Engine 0.7.1h 深度魔改的 FNF 引擎。**v1.2.0 Pre-release 3（代号 crazymidnight）** 汇总 Pre-release 2（mooncat，`v1.2.0-20261108-1710`）以来的全部更新：模组谱面压缩 `.mec`、模表（Modchart）运行时与编舞编辑器、JS 脚本层、TCM 真舞台、四代 Psych 模组兼容接线，以及一批游玩/存档/性能与判定线高亮修复。

---

## ✨ 版本亮点

- **模组谱面压缩 `.mec`**：64B 头（MEC1 / version / flags / 尺寸 / crc32 / blockSize）+ 原 JSON 前 8192B 未压缩预览；三 codec 全部字节级无损（deflate 单流 / LZMA 16MB 分块 / struct 列式 LZMA1 帧 + 原字节字典重建元组）。同一 648.9MiB 粪谱实测：deflate L9 10.8MiB → LZMA 6.85MiB → **struct 857.4KiB（739×）**。CLI `tools/chartpack/chartpack.py`（pack/unpack/info/verify/scancheck/selftest），路径统一走 `Paths.chartPath()`；只有 `.mec` 存在时生效，无压缩文件零行为变化。
- **模表运行时**（FNF-Modcharting-Tools v1.0.1 移植，默认关）：~35 内建修饰器 + hscript 自定义修饰器、多 Playfield、3D 透视渲染器、`modchart.json` 按拍事件排程（ease/set/hscript）、1–12 键泛化。接管绘制但音符生成 / 判定 / 丢失 / 结算零侵入；无模表数据的谱面零开销。
- **编舞编辑器与 TCM 真舞台**：`ChoreoEditorState` 镜头与事件轨道编排（cam 事件合并/预览），`StageTcm` 作为引擎真舞台（背景覆盖按实测几何校正、zoom / 素材缩放 / 角色位统一），`CameraEditorData` / `ChoreoEase` 支撑事件数据与缓动。
- **JS 脚本层**（默认关）：QuickJS 2024-01-13 `@:native` 静态绑定（`third_party/quickjs/` + `QjsNative.hx`），不产 ndll、不改 codesign；脚本发现与 `HostDomain.callOnScripts/setOnScripts` 派发已接入。
- **Psych 四代模组兼容**：0.6.3 Lua 兼容总开关（哨兵数字 / version / changePresence 空桩）、0.7.3 脚本 API 与五个 Pre 系回调取消语义分流、模组管理页「引擎版本」手动循环匹配（持久化 `meteoric-mod-versions.txt`；指纹自动识别方案已废弃）；两代模组可同场混跑，legacy 模组手动启用不受 1.0.4 开关限制。
- **转场 / 脚本 / i18n**：FADE（默认）/ MOVE / METEOR / STAR 四档转场重构（ErrorState 不挂转场、横幅类 close）；语言包扩充与 `tools/i18n/check_i18n.py` 门禁；HScript 脚本层 `String.trim/replace` 空指针类坑的兜底与状态脚本生命周期修正。

## 🛠 自 Pre-release 2 以来的修复

- **modchart 长条渲染**：渲染器接管绘制时 `SustainStrip` 从 `updateFramePixels()` 拿到 null（tile 渲染不生成 framePixels），`loadGraphic(null)` 静默失败 → 长条网格整批隐身。改用音符图集 + `frame.uv` 采样，零额外纹理、可合批、保留 RGB 染色；真机确认长条可见。
- **判定线高亮**：AutoPlay 命中高亮与人物动画共用批处理节流标志，导致高亮被整批跳过；改为独立节流。长条按住期间按 parent 剩余时长续住 `confirm`（`Math.max` 防短命中截短），玩家侧与**对手侧**（含 `NoteHoldCover` 覆盖层）均可持续亮；对手轨偏移改用 `ExtraKeys.songKeys` 适配 >4K。
- **存档 / 界面稳定性**：存档迁移 JSON 备份不再动态补写匿名对象字段（修迁移期启动即退）；偏移校准返回时落盘 `ClientPrefs`；自由模式返回按钮命中独占 + 行热区禁区（修下滚后误进曲）；FPS 统计编辑器补 `ToggleSwitch.destroy()` 配对与选中态 alpha。
- **性能**：Lua `getMouseX/getMouseY` 复用 `FlxPoint`、崩溃回调上下文去重先比分量再拼串、`_settleAnimDone` 每帧 new 数组改原地清零；游玩期分配压平、进曲洪峰 GC 自适应（堆 >256MB 才跑 major）。
- **TCM 曲目演出**：背景覆盖与镜头瞬移按真机实测校正；中段 modchart 改为全轨同步冲击（Beat / Scale / Bumpy / X / Y），不再启用会让相邻轨音符汇聚交叉、读谱难的 3D/旋转/压缩族效果。
- **清理与归档**：`source/` 遗留备份与未用代码移入 `archives/`（不参与编译、清理检索污染）；Vulkan 实验轨整条删除，仅在 `docs/VULKAN-ROADMAP.md` 留废弃归档（本版未恢复该轨）。

---

## 📦 包含平台

- Windows x64 / x86（zip，解压即用）
- macOS x86_64 / arm64（zip 内含 Meteoric.app）
- Android arm64（APK）
- Linux x86_64（tar.gz，解压后运行 bin/Meteoric；视频支持暂缺）
- iOS（未签名 IPA，AltStore/Sideloadly 侧载自动重签）

SHA256 见 SHA256SUMS.txt · 构建自 commit {SHA}
