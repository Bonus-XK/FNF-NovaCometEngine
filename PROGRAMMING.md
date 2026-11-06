# Meteoric 脚本系统（编程层）

> 让 mod 作者**不碰引擎源码**也能改玩法 / 界面：用 HScript 写脚本，改一行按 F5 即生效。
>
> 实现说明：脚本引擎复用 Meteoric 自身的 `scripting.lua.HScript`（SScript 4.0.1 + 187 项 preset API），
> **不复制任何第三方引擎的 hscript 实现**；宿主、目录约定、事件层、生命周期全是 Meteoric 自研。
> 入口：设置 → **编程**（主设置与暂停内设置两个入口都���）。

## 0. 模组元数据与启用（2026-10-29 独立化）

Meteoric 有自己的模组格式，与 Psych Engine 的 `pack.json` / `modsList.txt` 彻底分开：

- **元数据**：`mods/<mod>/mod.json`（引擎只读这个，不再读 `pack.json`）。
- **启用列表**：桌面 `meteoric-mods.txt`、安卓外部存储同名文件（引擎只读/写这个，不再碰 `modsList.txt`）。
- **默认启用**：带 `mod.json` 的 Meteoric 原生模组在首次扫描时**自动启用**（开箱即用）；
  只有旧 `pack.json` 或没有元数据的目录**默认关闭**，可到 Mods 菜单手动启用 —— 这样半成品 / Psych 格式模组不会被突然加载导致崩溃，磁盘现状也保持零行为变化。
- **脚本目录**：Meteoric 自研脚本走 `mods/<mod>/scripting/`（下文各节）；Psych 风格的
  `scripts/`、`data/<歌曲名>/`、`characters/*.lua` 等**执行点已停用**（独立化后不再加载），
  但 Lua / HScript 运行时 API（`addLuaScript` / `addHScript`）仍保留。
- **内容目录重分类（2026-10-30）**：模组侧启用 Meteoric 语义化目录名，
  映射集中在 `Paths.modRelPath`（引擎内置资源目录**不变**，覆盖仍靠 key 一致）：

  | 旧（Psych/FNF 通用） | 新（Meteoric） | 说明 |
  |---|---|---|
  | `data/` | `charts/` | 谱面 JSON、events.json、credits.txt、introText.txt |
  | `images/` | `gfx/` | 贴图；**内部子路径不变**（`characters/`、`noteSkins/`、`icons/` …，须与内置侧对齐） |
  | `music/` + `sounds/` | `audio/` | BGM 与音效合并 |
  | `custom_notetypes/` | `noteTypes/` | 仅保留 `.txt` 属性文件；`.lua`/`.hx` 脚本已停用（改用 `scripting/notes/`） |
  | `songs/` | `songs/`（不变） | 音频 Inst/Voices；该名字同时是「Vorbis 流式 vs 全量解码」的判定开关，不能改 |
  | `characters/` `stages/` `weeks/` `shaders/` `videos/` `fonts/` | 不变 | 与内置侧同名 |
  | `achievements/` `scripts/` `custom_events/` `menus/` | 删除 | 模组侧已无消费者 |

  完整布局：

  ```
  mods/<mod>/
  ├── mod.json            ★ 元数据（有它 → 自动启用）
  ├── scripting/          ★ 自研 HScript（global/ states/ songs/ stages/ characters/ notes/ events/ libs/ redirects.txt）
  ├── source/             ★ Haxe 类库（需开「模组类库」开关）
  ├── charts/             ← 谱面 + events.json + credits.txt + introText.txt
  ├── songs/              ← 音频（Inst/Voices）
  ├── audio/              ← BGM + 音效
  ├── gfx/                ← 贴图（内部子路径与内置侧对齐）
  ├── characters/ stages/ weeks/
  ├── noteTypes/          ← 音符类型属性 .txt
  └── shaders/ videos/ fonts/
  ```

`mod.json` 字段（全部可选，缺失用兜底值）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | String | 显示名；缺省用目录名 |
| `description` | String | 简介 |
| `version` | String | 版本（仅展示） |
| `color` | [R,G,B] | 菜单主题色，缺省 `[170,0,255]` |
| `restart` | Bool | 切换启用后是否提示重启 |
| `runsGlobally` | Bool | 是否作为「全局模组」在所有场景提供资源覆盖（见 `Mods.pushGlobalMods`） |

模板见 `example_mods/mod.json`。**从 Psych 迁移**：把 `pack.json` 改名为 `mod.json`、删掉 `discordRPC` 字段即可，
目录结构（`data/`、`songs/`、`weeks/`、`images/` …）原样保留。

> 脚本能力默认常开（2026-10-29 产品决策）：`Scripting.isEnabled()` 目前恒为开，
> 装着 `scripting/` 的模组放进来即生效；分项开关仍控制各能力（见第 1 节）。
> 注意这会让设置页的「脚本系统（总开关）」暂时不联动（历史遗留）；以后若恢复存档开关判断，
> 需同步迁移已存过 `scriptingEnabled=false` 的老存档，否则老玩家会被静默关掉脚本系统。

## 0.1 Psych Engine 1.0.4 模组兼容（`psychV104Compat`，默认关）

设置 → 编程 → **Psych 1.0.4 模组兼容**。打开后，引擎会额外认出 Psych 1.0.4 形态的模组
（`pack.json` + 旧目录布局 + Psych 风格 `.lua` 脚本）。**Meteoric 新格式始终优先**，开关关闭时
行为与独立化后的 Meteoric 完全一致（零行为变化）。

| 兼容项 | 开关关闭 | 开关打开 |
|---|---|---|
| 元数据 | 只读 `mod.json` | 无 `mod.json` 时回退 `pack.json`（`runsGlobally` 等字段生效） |
| 启用列表 | `meteoric-mods.txt` | 额外**只读**合并 `modsList.txt`（写入仍走 `meteoric-mods.txt`） |
| 内容目录 | `charts/ gfx/ audio/ noteTypes/` | 找不到时回退 `data/ images/ music+ sounds/ custom_notetypes/` |
| 默认启用 | 带 `mod.json` 才自动启用 | 带 `pack.json` 也算，自动启用 |
| 全局 `scripts/` | 不加载 | 加载 `mods/<mod>/scripts/*.lua|.hx` |
| 单曲 `data/<歌>/` | 不加载 | 加载 `mods/<mod>/data/<歌>/*.lua|.hx` |
| 舞台 / 音符类型 / 自定义事件命名脚本 | 不加载 | `stages/<名>.lua`、`custom_notetypes/<名>.lua`、`custom_events/<名>.lua` 恢复 |
| 角色脚本 | 只读内置 | `characters/<名>.lua|.hx` 允许 mods 覆盖 |
| `instanceArg()` | 未注册 | 已支持（配合 `setProperty(..., true, true)` / `callMethodFromClass`） |

**已知差异（不阻塞运行）**：

- `createInstance` 的变量表仍挂在 `PlayState` 上，随对局销毁；Psych 1.0.4 是跨 State 存活。
  「用谱面做菜单」的模组切歌时可能丢对象。
- Meteoric 的 `FunkinLua.call()` 有重入防护（防 SIGSEGV），脚本里嵌套触发的 Lua 回调会被丢弃。
- 5 个 Pre 系回调（`goodNoteHitPre` / `opponentNoteHitPre` / `onKeyPressPre` /
  `onKeyReleasePre` / `preUpdateScore`，0.7.3 起出现、1.0.4 沿用）按下方 0.2 节的
  `psychV073Compat` 开关接入；仅开 1.0.4 开关、不开 0.7.3 开关时它们不派发。
- 成就 / 翻译类 1.0.4 新 API（`unlockAchievement` 等）语义与 Meteoric 不同，未接入。

参考实现来源：`FNF-PsychEngine-1.0.4`（pack.json 解析、脚本加载点、`instanceArg`）
与 `mods/SonicTheFunkChinese`（真实 1.0.4 模组，60 个 `.lua`）。

## 0.2 Psych Engine 0.7.3 脚本系统兼容（`psychV073Compat`，默认关）

设置 → 编程 → **Psych 0.7.3 脚本兼容**。引擎基座是 0.7.1h，原先已散布一批常开的 0.7.3 垫片
（Lua `version='0.7.3'`、HScript 侧 `getModSetting`、`varsToBring`、手柄函数族、Aseprite 图集、
mod settings.json 等，**不受本开关控制**）；本开关补齐的是剩余的 0.7.3 脚本面。关闭时新 API
不注册、新回调不派发，行为与补齐前完全一致（零行为变化）。

| 兼容项 | 开关关闭 | 开关打开 |
|---|---|---|
| Lua `getModSetting`（Lua 侧此前未注册） | 不可用 | 可用；`modName` 缺省时按脚本路径 `mods/<mod>/` 解析，解析不到回退 `Mods.currentModDirectory` |
| Lua `removeHScript` | 不可用 | 可用（与 `removeLuaScript` 同构） |
| `getSoundPitch` / `setSoundPitch(tag, value, doPause)` | 不可用 | 可用（作用于 `modchartSounds`，上游包在 `FLX_PITCH` 里，Meteoric 自带 flixel 恒可用） |
| `eraseSaveData` | 不可用 | 可用（抹除 `initSaveData` 初始化的模组存档） |
| `setTextAutoSize` | 不可用 | 可用；`setTextHeight` 仅保留名字、无效果（Meteoric 的 FlxText 恒自动高度，无 fieldHeight 字段） |
| `setTextBorder` 第 4 参 `style`（shadow / outline_fast 等） | 忽略，恒 OUTLINE/NONE | 走 `CoolUtil.setTextBorderFromString` |
| `setHealthBarColors` / `setTimeBarColors` 传 `''`/null | 照旧解析（0.7.1h 语义） | 该侧保留原色（0.7.3 语义） |
| `LuaUtils.addAnimByIndices` indices 缺省 | `[]`（动画不指向任何帧） | `[0]` |
| `addHaxeLibrary` 类解析失败 | 直接失败 | 回退枚举解析（`Type.resolveEnum`） |
| `CustomFlxColor` | 无 `fromInt` / `fromCMYK` | 补齐（纯新增，不受开关控制的静态方法） |
| `addAnimationByIndices` indices 参数类型 | String | Any（签名放宽，无条件生效） |

**Pre 系回调（0.7.3 新增）**——派发条件：`psychV073Compat` 或 `psychV104Compat` 任一开启：

| 回调 | 触发点 | 取消语义 |
|---|---|---|
| `preUpdateScore(miss)` | 记分文本更新前 | 返回 `Function_Stop` 跳过整个记分更新（两版一致） |
| `onKeyPressPre(key)` / `onKeyReleasePre(key)` | 按键守卫之后、命中计算之前（回放录制之后） | 返回 `Function_Stop` 取消本次按键（两版一致）；回放录制不受取消影响 |
| `goodNoteHitPre(index, col, type, isSus)` / `opponentNoteHitPre(index, col, type, isSus)` | 命中处理前 | **按版本分流**：0.7.3 仅通知（返回值不取消）；叠开 `psychV104Compat` 时按 1.0.4 语义，Lua/HScript 任一返回 `Function_Stop` 跳过整个命中处理（含场景回调） |

**已知差异（不阻塞运行）**：

- **不移植** `PsychCamera`（引擎自有摄像机体系）与 `MusicBeatState` 集成、转场时长 0.7→0.6；
  0.7.3 模组 HScript 里引用 `PsychCamera` 类不可用。
- HScript 的 `game` 仍指 `PlayState.instance`（0.7.3 改绑 `FlxG.state`）——对局内两者恒等，
  仅非对局场景脚本语义不同；`add/insert/remove` 同理仍绑 `PlayState`。
- `LuaL.dofile` 不支持字符串脚本（0.7.3 的 dofile→dostring 分支）；Meteoric 脚本一律来自文件。
- `luaTrace` 保留控制台 `trace` 输出（0.7.3 移除了 console 行）。
- `getModSetting` 的 modName 缺省解析比 0.7.3 宽容：0.7.3 解析不到 modFolder 直接报错，
  Meteoric 回退 `Mods.currentModDirectory`（与 HScript 侧既有行为一致）。
- `setTextHeight` 是保留名字的空实现（引擎自带 flixel 的 FlxText 无 `fieldHeight`，恒自动高度），
  调用不报错但无任何效果（与 Discord 桩同一先例）。
- 模组设置只有 `getModSetting` 读取 `data/settings.json`，没有 0.7.3 的模组设置界面。

参考实现来源：`FNF-PsychEngine-0.7.1h` 与 `FNF-PsychEngine-0.7.3` 逐文件 diff
（`psychlua/` 全部 + `backend/` 脚本可见面）。

## 0.3 Psych Engine 0.6.3 模组支持（`luaUse063Compat`，默认关）

0.6.3 模组的**装载路径不新增开关**：开 `psychV104Compat`（见 0.1）即可——0.6.3 模组的目录布局
（`data/ images/ songs/ ...` + `pack.json` 可选）、`modsList.txt`（CWD 根，`名字|0/1` 行格式）、
谱面/事件/角色/舞台/周目 JSON 与 0.7.x 完全同构。纯文件夹模组（无任何元数据）也能被
`Mods.isLegacyLayout()` 磁盘判定识别。箭头烘焙/RGB 关闭走既有 **Psych 0.6.3 兼容模式**
（`psych063Mode`）；自定义箭头平铺路径 `images/<skin>.png` 已有自动补 `noteSkins/` 前缀的回退。

本节开关 **Lua 0.6.3 兼容**（`luaUse063Compat`）只管脚本层的代际差异。关闭时零行为变化：

| 兼容项 | 开关关闭 | 开关打开 |
|---|---|---|
| 哨兵约定 | 字符串哨兵（`##PSYCHLUA_*`），与 0.7.x 一致 | Lua 全局 `Function_Continue/Function_Stop/Function_StopLua` 改为 0.6.3 数字（0/1/2）；脚本返回的数字 0/1/2 在进引擎前归一化为字符串哨兵，引擎判定零改动 |
| 脚本硬编码 `return 0/1/2` | 不被识别为停止/继续（派发照常） | 正确按 0.6.3 语义终止/继续派发 |
| 全局 `version` | `'0.7.3'` | `'0.6.3'`（老模组 `version:find('0.6')` 版本门才能通过） |
| Lua `changePresence(...)` | 未注册（调用报 undefined） | 保留名空实现（本引擎无 Discord 集成，对齐 `setTextHeight` 桩先例） |

**0.6.3 API 面核对结论**：以 0.6.3 `FunkinLua.hx` 实际注册集（剥注释后 201 个）与引擎注册集
（263 个）做对称差，**唯一缺失就是 `changePresence`**——`getPropertyAdvanced`/`setPropertyAdvanced`/
`getGlobals` 在 0.6.3 源码里本就是注释掉的死代码，模组实际调不到，无需移植。

**已知差异（不阻塞运行）**：

- **两代模组不要同时启用**：`version` 全局只能报告一个版本；0.6.3 兼容开启时 0.7.x 模组的
  `version:find('7.3')` 版本门会失败。脚本层哨兵全局同样二选一。
- 未登记进 `modsList.txt` 的 0.6.3 模组不会自动启用（0.6.3 原版会自动发现并启用；
  Meteoric 保守不自动启用，与 1.0.4 兼容同一约定），手动在模组列表启用即可。
- 0.6.3 模组的 `.hx` 文件原生就不会被加载（0.6.3 无脚本文件式 HScript），引擎行为一致。
- `callOnLuas` 等 Lua 侧派发回调恒返回 `true`，不回传脚本结果值（0.7.x 起即如此，
  与 0.6.3 回传结果值不同；依赖该返回值的老模组极少，暂不兼容）。
- `onEvent`/`onSpawnNote`/`eventEarlyTrigger` 参数尾部比 0.6.3 多（`strumTime` 等）——
  老模组按位置取前几个参数不受影响；`eventEarlyTrigger` 返回数字 0 的「不提前触发」语义已兼容。

## 0.4 模组引擎版本自动识别（`modsAutoVersion`，默认关）

设置 → 编程 → **模组引擎版本自动识别**。开启后引擎探测每个模组的目标 Psych 版本，脚本按
**所属模组的检测版本**自动匹配兼容行为——**两代模组可以同场混跑**（各拿各的语义），
0.3 节「两代模组勿混用」的限制只在手动开关模式下成立。

**探测规则**（`Mods.getDetectedEngineVersion`，按优先级；依据四代上游引擎实际读取的字段/文件）：

| 优先级 | 标记 | 推断 |
|---|---|---|
| 1 | 模组根有 `mod.json` | `native`（Meteoric 原生，无需兼容） |
| 2 | 模组内有 `data/*.lang`（或 `charts/*.lang`） | `1.0`（1.0.x 官方语言文件，唯一官方级 1.0 独有标记） |
| 3 | pack.json 带 `iconFramerate` 字段，或模组内有 `data/settings.json` | `0.7.3`（两者均 0.7.3 首发） |
| 4 | pack.json 带 `discordRPC` 字段 | `0.7.1`（0.7 系新增读取，0.6.3 引擎不读） |
| 5 | 其余有 pack.json 的 | `0.6.3`（0.6 模板形态） |
| 6 | 无任何元数据 | `unknown` |

Psych 1.0.x **没有官方版本声明字段**（1.0.4 的 pack.json 与 0.7.3 逐字节一致），只能靠
`data/*.lang` 与模板级新目录区分；pack.json 单独无法区分 0.7.3 与 1.0.x。探测结果缓存于
`Mods.detectedEngineCache`，随模组安装/删除/启停（`clearLegacyLayoutCache`）失效。

**自动匹配的兼容行为（脚本级，按 `FunkinLua.modFolder` → 检测版本判定）**：

| 行为 | 检测 0.6.3 | 检测 0.7.3 / 1.0 | 检测不到（native/unknown/自动识别关） |
|---|---|---|---|
| 哨兵语义（数字 0/1/2 + `call()` 归一化） | 生效 | 不生效（字符串哨兵） | 回退手动开关 `luaUse063Compat` |
| 全局 `version` 报告值 | `'0.6.3'` | `'0.7.3'` / `'1.0'` | 手动开关决定（默认 `'0.7.3'`） |
| `changePresence` | 注册（空实现） | 不注册 | 回退手动开关 |
| 0.7.3 补齐 API（getModSetting / pitch 族 / eraseSaveData / 文本族 / 血条颜色语义） | 不注册 | 注册 | 回退手动开关 `psychV073Compat` |

**边界与已知差异**：

- 0.7.3 API 的 per-mod 覆盖只接了 **Lua 侧有 funk 上下文的注册点**（FunkinLua 构造块、
  TextFunctions、ExtraFunctions、SoundCommands、ScoreCommands）；HScript 侧与无 funk 上下文的
  `LuaUtils.addAnimByIndices` 缺省值仍走全局 `psychV073Compat`。
- **Pre 系回调的取消语义仍由全局 `psychV104Compat` 决定**：派发点（命中/按键/记分）一次派发
  混合所有版本的脚本，无法按脚本分流；需要 1.0.4 式命中取消时仍手动开 1.0.4 兼容。
- 探测是**启发式**：手写极简 pack.json 的 0.7.x 模组（无 discordRPC）会被推断为 0.6.3；
  模组管理页会显示检测结果，发现不对时改用手动开关即可（检测版本只影响自动路径）。
- 模组管理页（主菜单 → 模组）在列表行状态列、选中卡片与右侧信息面板显示检测结果
  （`· 引擎 0.6.3` 样式）；自动识别关闭时不显示，界面零变化。

## 1. 开关

全部在 设置 → 编程 里。**总开关默认关**；关闭时引擎行为与本系统落地前完全一致（不加载脚本、
不注册事件钩子、不轮询热重载按键）。
（注：见第 0 节 —— 脚本能力当前默认常开，上方的总开关暂不联动；此处描述的是存档字段的原始设计语义。）

| 选项 | 存档字段 | 默认 | 作用 |
|---|---|---|---|
| 脚本系统（总开关） | `scriptingEnabled` | **关** | 总闸；关闭时下面所有能力都不生效 |
| 全局常驻脚本 | `scriptingGlobalScripts` | 开 | 允许 `scripting/global/` 下的脚本（跨界面常驻） |
| 状态脚本（覆盖界面） | `scriptingStateScripts` | 开 | 允许 `scripting/states/<界面名>.hx` |
| 脚本热重载 | `scriptingHotReload` | 开 | F5 重建当前界面脚本；Shift+F5 重建全局脚本 |
| 可取消事件 | `scriptingEvents` | 开 | 允许脚本拦截引擎决策点（见第 5 节） |
| 全曲 / 单曲脚本 | `scriptingSongScripts` | 开 | 允许 `scripting/songs/` 自动发现（见第 11 节） |
| 状态重定向 | `scriptingStateRedirects` | 开 | 允许 `scripting/redirects.txt` 声明式改跳转（见第 12 节） |
| 资源同名脚本 | `scriptingResourceScripts` | 开 | 按舞台/角色/音符类型/事件名加载同名脚本（见第 13 节） |
| 模组类库（source/） | `scriptingModClasses` | **关** | 注册 `mods/<mod>/source/` 下的 class，脚本可 `import` / `new`（见第 14 节） |

> 分项开关只在总开关打开时才有意义；分项在总开关关闭时仍然可见，靠说明文字提示（不引入新的禁用态样式）。
>
> ⚠ 安全提示：HScript 可访问 `Sys` / `File` / `FileSystem` / `Process` 等引擎能力。
> 只在信任的 mod 上开启总开关。

## 2. 目录约定

```
mods/<mod>/scripting/global/<任意名>.hx        # 全局常驻脚本（跨所有界面）
mods/<mod>/scripting/states/<界面名>.hx        # 状态脚本（接管某个界面）
mods/<mod>/scripting/libs/<任意名>.hx          # 共享脚本库（importScript 加载）
mods/<mod>/scripting/songs/<任意名>.hx         # 全曲脚本（每首歌都加载）
mods/<mod>/scripting/songs/<歌曲名>/<任意名>.hx # 单曲脚本（只在该曲目加载）
mods/<mod>/scripting/redirects.txt             # 状态重定向配置
mods/<mod>/scripting/stages/<舞台名>.hx        # 舞台同名脚本
mods/<mod>/scripting/characters/<角色名>.hx    # 角色同名脚本
mods/<mod>/scripting/notes/<音符类型>.hx       # 音符类型同名脚本
mods/<mod>/scripting/events/<事件名>.hx        # 事件同名脚本
```

- 扩展名：`.hx`（`.hscript` / `.hsc` / `.hxs` 亦可）。
- `<界面名>` = 目标界面的 Haxe 类名末段，例如 `MainMenuState`、`PauseSubState`、`PlayState`。
- 每个启用的 mod 各自提供一份；多个 mod 的脚本会在同一个界面里**同时运行**（按 mod 启用顺序）。
- 目录不存在就当没有脚本 —— 引擎不会为每个 mod 反复探盘。
- **执行顺序**：同一组内可用文件名前缀显式控制（`00_`…`999_` 数字越小越先，`z_` 固定最后，
  无前缀默认 500）。同优先级按 mod 启用顺序、再按文件名。**全部不带前缀时顺序与旧版完全一致**。
  例：`00_input.hx` → `50_ui.hx` → `z_debug.hx`。

### 2.1 脚本库复用（importScript）

把可复用逻辑放 `mods/<mod>/scripting/libs/`，脚本里直接加载：

```haxe
var util = importScript('util');        // → mods/<mod>/scripting/libs/util.hx
var helper = importScript('./helper');  // → 当前脚本同目录的 helper.hx
```

- **路径解析**（不写扩展名时自动试 `.hx` / `.hscript` / `.hsc` / `.hxs`）：
  1. `mods/` 开头 → 按仓库根解析（Android 走 `Paths.mods`）；
  2. `./` / `../` 开头 → 相对当前脚本所在目录；
  3. 其它 → 同 mod 的 `scripting/libs/<路径>` 优先，其次相对当前脚本目录。
- **作用域**：库的顶层函数/变量会并入当前脚本（当前脚本已有的名字优先），
  所以直接写 `helper(...)` 即可，不必 `util.helper(...)`。
- **生命周期**：库脚本挂在当前脚本组里，`create` / `update` / `stepHit` / `destroy` 等回调
  与主脚本一样被自动广播（每个库实例各跑一次，不会双重调用）。
- **控制库**：`importScript` 返回库的 `HScript` 实例 —— `lib.active = false` 停用、
  `lib.invoke('fn', [args])` 取原始返回值、`lib.get('x')` / `lib.set('x', v)` 读写变量。
- 同一个库被不同脚本 import 会各得一份独立实例（不共享状态）；要共享状态请只 import 一次，
  再把返回对象传给其它脚本。
- 无脚本组场景（Lua `runHaxeCode`）也能用：库独立加载，随调用方脚本一起销毁。

## 3. 脚本能拿到什么

- `psychlua.HScript` 的 **189 项 preset**（引擎类 `PlayState` / `Paths` / `FlxSprite` / `Character` /
  `Note` / `Mods` / `DesignTokens` / `Lang`、Flixel 类、`Reflect` / `Type` 反射、`sys` 文件系统 …）——
  与既有 mod 脚本同一套 API。
- 编程层额外注入三个变量：

| 变量 | 含义 |
|---|---|
| `state` | 当前界面对象（`TitleState` / `MainMenuState` / `PlayState` …）；状态脚本里固定是自己的宿主，全局脚本里随界面切换刷新 |
| `game` | PlayState 实例（非游玩界面为 null） |
| `scripting` | 编程层 API（`scripting.ScriptingApi` 实例）：`openState` / `openSubState` / `closeSubState` / `backToMainMenu` / `center` / `centerAxes` / `getPerfStats` / `setPerfOption` / `collectGarbage` / `openRepl` / `log` / `logError` / `reloadGlobalScripts` / `reloadCurrentStateScripts`（完整清单见 `source/scripting/ScriptingApi.hx`）|
| `data` | 仅脚本界面：打开界面时传入的数据（脚本界面里也有 `state.data`，两者同值）|

- **脚本可以直接 `import` 引擎类**（SScript 4.0.1 没有 import 白名单，走 `Type.resolveClass`）：
  ```haxe
  import flixel.group.FlxTypedGroup;
  import states.FreeplayState;
  import objects.Character;
  ```
  ⚠ 被 `--dce full` 裁掉的类解析不到（`Type.resolveClass` 返回 null）—— 引擎内被 Haxe 引用过的类都在。
- 多语言：`Lang`（整个类）、`tr(key[, args])`、`trOr(key, fallback)`、`getLanguage()`。
  模组脚本里推荐 `trOr(key, '自带的原文')` —— 玩家语言包没这个 key 时自动显示原文，不会露出裸 key。

## 4. 生命周期回调

在脚本顶层定义同名函数即可；**未定义的回调会被静默跳过**，单个脚本报错不会中断同组其它脚本。

| 回调 | 时机 | 范围 |
|---|---|---|
| `create()` | 脚本加载完成 | 状态脚本 + 全局脚本 |
| `update(elapsed)` | 每帧 | 状态脚本（由宿主界面驱动）+ 全局脚本（由 `FlxG.signals.postUpdate` 驱动） |
| `postUpdate(elapsed)` | `update` 之后 | 同上 |
| `stepHit(step)` | 步进变化 | 状态脚本 + 全局脚本 |
| `beatHit(beat)` | 节拍变化 | 状态脚本 + 全局脚本 |
| `destroy()` | 界面销毁 / 热重载替换旧脚本**之前** | 状态脚本 + 全局脚本 |

引擎级回调（**仅全局脚本**，来自 Flixel 信号）：

`preUpdate` / `postUpdate` / `preStateSwitch` / `postStateSwitch` / `preDraw` / `postDraw` /
`focusGained` / `focusLost` / `gameResized(w, h)` / `preGameStart` / `postGameStart`

## 5. 可取消事件（`scriptingEvents` 打开时）

事件在引擎的**关键决策点**派发。脚本可以：

- 改事件字段（都是 public var，直接赋值）；
- `event.cancel()` —— **阻止引擎的默认行为**（自己接管这一段逻辑）；
- `event.cancel(true)` —— 阻止默认行为，但**继续**广播给后续脚本（默认 `cancel()` 会中断广播）。

| 事件 | 派发点 | 脚本能改什么 | `cancel()` 的含义 |
|---|---|---|---|
| `onNoteCreation` | 音符生成后 | `event.note`（可改 `noteType` / `texture` / `hitHealth` …） | 这根音符不参与判定与计分（仍显示） |
| `onChartEvent` | 谱面事件处理前 | `event.value1` / `event.value2`（字符串参数） | 跳过这条谱面事件的默认处理（舞台回调与旧脚本回调仍会走） |
| `onRatingShown` | 评级弹窗前 | `event.ratingImage`（换评级贴图）、`event.visible` | 不显示评级弹窗 |
| `onCameraMove` | 相机移动后 | `event.x` / `event.y`（落点）、`event.zoom` | 这一次相机不移动（回到移动前的位置） |
| `onSongEnd` | 歌曲结算前 | `event.songName` | 不结算（停在游玩界面） |
| `onGameOver` | 死亡判定时 | `event.health`（> 0 则作为复活后的血量） | 不死（血量被拉回 0 以上，避免下一帧再次判定死亡） |

事件对象类型：`ScriptEvent`（基类）/ `ScriptNoteEvent` / `ScriptChartEvent` / `ScriptRatingEvent` /
`ScriptCameraEvent` / `ScriptLifecycleEvent`（都在 `source/scripting/`）。

示例：

```haxe
// 谱面事件：把 Camera Movement 的第一个参数翻倍
function onChartEvent(event) {
    if (event.eventName == 'Camera Movement') event.value1 = '2.0';
}

// 评级：换一张评级贴图
function onRatingShown(event) {
    if (event.ratingName == 'sick') event.ratingImage = 'mySick';
}
```

## 6. 界面跳转

全局脚本（或即将被销毁的旧界面的状态脚本）的 `preStateSwitch` 里 **return 一个界面名**，
即可改写这次跳转的目标：

```haxe
function preStateSwitch() {
    if (FlxG.state is MainMenuState) return 'FreeplayState'; // 跳到自由模式
}
```

- 值为 Haxe 类名末段（按 `states.<名>` 解析）或带包名的完整类名（`'options.OptionsState'`）。
- 解析不到 → 打日志并**保持原目标**（不改变引擎行为）。
- 改写点：`FlxG.signals.preStateSwitch`（`FlxGame.switchState()` 在真正换 state 之前派发）。

## 7. 脚本界面（用脚本写完整界面）

除了「接管已有界面」（第 2 节的状态脚本），脚本还可以**自己写一个新界面**。

```haxe
// 在任意脚本里：
scripting.openState('MyScreen');                  // 打开脚本界面
scripting.openState('MyScreen', ['数据', 3]);      // 带数据（数组/任何 Dynamic）
scripting.openSubState('MyPanel', ['数据']);       // 打开脚本子状态（盖在当前界面上）
scripting.closeSubState();                        // 关闭当前子状态
scripting.backToMainMenu();                       // 回主菜单
```

- 脚本文件位置：`mods/<mod>/scripting/states/MyScreen.hx`（与状态脚本同一目录约定）。
- 脚本界面里能做什么：
  - `state` —— 宿主（`ScriptState` / `ScriptSubState`）：`state.add(sprite)` 把控件加进界面；
  - `state.data`（或直接用注入的 `data`）—— 打开时传入的数据；
  - `create()` / `update(elapsed)` / `beatHit(beat)` / `stepHit(step)` / `destroy()` 回调；
  - `MenuText` —— 引擎同款字体与描边的文本控件；`FlxSprite` / `FlxText` / `FlxCamera` 等照常可用；
    主题色用 `DesignTokens.*`。
- 生命周期：脚本的 `create()` 在界面初始化过程中执行（宿主 `create()` 末尾），
  `destroy()` 在界面销毁 / F5 重建前执行 —— 脚本自己创建的对象要在 `destroy()` 里清理。
- 界面跳转：`preStateSwitch` 里 return 界面名（见第 6 节）也能跳到脚本界面
  （return 的是**脚本名**，不是类名）。

## 7.1 写脚本必须知道的两个坑（引擎侧限制，不是脚本的错）

**① 只被脚本调用的方法会被 release 构建裁掉**

release 构建开 `--dce full`：只被**脚本反射调用**、Haxe 侧没有引用的方法会被裁掉，
运行时反射拿到 null 方法引用 → 抛 `Null Function Pointer`（脚本表现为「这行一调就炸」）。

- 本引擎的对策：脚本可见的 API 全部做成**实例方法**（`scripting.ScriptingApi`）并标 `@:keep`。
  ⚠ `@:keep` 对 **static 方法无效**（实测：标了照样被裁），对实例方法有效。
- 这条也解释了为什么 `scripting.log()` 一直好用：它同时被引擎侧调用，没被裁。

**② Flixel 的 inline 方法不能被脚本直接调用**

`FlxObject.screenCenter` 是 `inline` 方法，hxcpp 下没有真实函数体 → 反射调用同样抛
`Null Function Pointer`。所以脚本里要写 `scripting.center(sprite)`（Haxe 侧包装），
不能写 `sprite.screenCenter()`。`scripting.centerAxes(sprite, axes)` 是带轴向的版本
（flixel 5.x 的 `screenCenter` 收 `FlxAxes`，不是摄像机）。

## 7.2 性能面（脚本读性能 / 改受控旋钮）

```haxe
var st = scripting.getPerfStats();
trace(st.fps);        // 绘制帧率
trace(st.rssMB);      // 进程常驻内存（MB；采样线程每 2s 问一次 OS，首次调用后约 2s 才有值）
trace(st.visualFold); // 当前视觉折叠档

scripting.setPerfOption('visualFold', 2);   // 0=关 1=75% 2=50% 3=25%（只影响视觉副本，不参与判定）
scripting.setPerfOption('gcBreathing', true);// GC 呼吸阀：进曲设最低空余水位 + 每 20s 强制全量回收
scripting.collectGarbage();                  // 立刻来一次全量 GC（约 20~80ms 顿挫）
```

- **旋钮白名单**（不在名单里的一律拒绝，返回 `false`）：
  `gcBreathing`(bool) / `visualFold`(int 0..3) / `perfMode`(bool) / `runtimePack`(bool)。
- 这 4 个在设置页（性能页 / 图像页）里都能看到，脚本改的就是用户改的那份值。
- **降采样相关项刻意不开放**（`textureScale` / `characterTextureScale` / `backgroundScale`）——
  脚本调它们一律返回 `false`。
- 生效时机：`visualFold` 只影响之后生成的音符，`runtimePack` 只影响之后加载的贴图。

## 8. 热重载语义

- **F5**：原地重建**当前界面**的状态脚本组。
  - 旧脚本先收 `destroy()` 再释放实例，随后从磁盘重读并 `create()`。
  - 宿主界面与它的视觉对象**不重建**、不重进关卡。
  - 新组构建失败（文件被删 / 全部解析失败）→ **保留旧组**并打日志。
- **Shift+F5**：只重建全局脚本组，当前界面不受影响。
- 脚本必须在 `destroy()` 里清理自己创建的对象，否则热重载会留下旧对象。
- 键位固定为 F5 / Shift+F5（不占用引擎其它键位；引擎全仓无 F5 使用）。

## 8. 与既有 mod 脚本（`mods/<mod>/scripts/`）的关系

**两条独立的线**，互不干扰：

| | 既有脚本 | 本编程层 |
|---|---|---|
| 目录 | `mods/<mod>/scripts/`（另有舞台/角色/事件脚本目录） | `mods/<mod>/scripting/` |
| 语言 | Lua + HScript | HScript |
| 生命周期 | Psych 风格 `onCreate` / `onUpdate` / `onBeatHit` … | `create` / `update` / `beatHit` … |
| 存活范围 | 一局 PlayState | 全局脚本跨界面常驻；状态脚本跟随界面 |
| 开关 | 无（随 mod 加载） | 总开关 + 分项开关 |

编程层**只读** `scripting/` 目录，绝不重复加载 `scripts/` 下的旧脚本。

## 9. 排查与调试

- 脚本加载/重载/错误都打印到终端，前缀 `[Scripting]`（错误是 `[Scripting][错误]`）。
  启动游戏必须走终端才能看到：`cd "…/Meteoric.app/Contents/MacOS" && ./Meteoric > /tmp/meteoric_debug.log 2>&1 &`。
- 脚本解析失败不会影响引擎，只跳过这一个脚本并在终端报出首行错误。

## 9.1 游戏内 REPL（F2）

游戏内实时执行 HScript —— **改一行立刻生效，不用重开游戏、不用重开歌曲**。

| 操作 | 效果 |
|---|---|
| **F2** | 打开 / 关闭 REPL |
| 回车 | 执行当前输入 |
| ↑ ↓ | 滚动输出区 |
| ESC | 关闭 REPL |
| 鼠标滚轮 | 滚动输出区 |

- **总开关关闭时 F2 无效**（与本层其它能力一致）。
- REPL 是**盖在当前界面上的覆盖层**，不是子状态：游戏照常运行，改一个变量立刻能看到效果。
- 界面里能拿到的东西和脚本**完全一样**（同一套 preset + `state` / `game` / `scripting` / `data`），
  所以「在脚本里能写的东西，在 REPL 里也能试」。
- 输入框用引擎的 `objects.UIInputBox`（原生 TextField，系统输入法可用）。
- REPL 打开期间会屏蔽游戏输入（打字不会被当成按键 —— 游玩时方向键 = 音符）。
- 脚本也可以开 REPL：`scripting.openRepl()`。

```haxe
// 例子：改一个当前界面的属性
state.alpha = 0.5;
// 例子：看性能快照
var st = scripting.getPerfStats();
trace('fps=' + st.fps + ' rss=' + st.rssMB);
```

**变量跨行保留**：

```
> var x = 41
> x + 1
42
```

> 这一条是**特意实现**的：SScript 4.0.1 的 `Interp.execute()` 每次调用都会重建 locals 表，
> 顶层 `var` 在语句块结束时还会被撤销 —— 直接用它做 REPL 只能当一次性沙盒。
> 引擎改走 `Interp.exprReturn()` 并逐条执行顶层语句，locals 不重置，变量跨行可见。

## 9.2 脚本管理器（暂停菜单 / 自由选歌）

「设置 → 暂停」里的**脚本管理**，现在同时管三类脚本：

| 类型 | 位置 | 标记 |
|---|---|---|
| 旧玩法脚本 | `mods/<mod>/scripts/*.lua` / `*.hx` | 无标记 |
| 全局常驻脚本 | `mods/<mod>/scripting/global/*.hx` | `全局 ·` |
| 状态脚本 | `mods/<mod>/scripting/states/*.hx` | `界面 ·` |

| 操作 | 效果 |
|---|---|
| ↑ ↓ | 选择 |
| 回车 | 开关脚本（关闭 = 文件名加 `.disabled` 后缀） |
| **→** | 把选中的**状态脚本**作为脚本界面打开（`scripting.openState`） |
| ESC | 返回 |

- 列表里的脚本来自**与引擎同一份「已启用的 mod」列表**（`Scripting.listInstalledScripts()`），
  所以列出来的就是引擎真的会加载的，不会「列了但不生效」。
- `.disabled` 后缀的脚本也会列出（标成「关」）；引擎侧天然跳过它们（只认 `.hx` 结尾）。

## 10. 当前限制

- **脚本写界面还缺引擎级控件**：脚本能加 `FlxSprite` / `FlxText` / `MenuText`，
  但引擎自己的成套控件（`BackButton` 这类带主题/动效的组件）**没有暴露给脚本**，
  脚本界面里的「返回按钮」得自己用 `FlxSprite` 拼。
- 没有沙箱 / 权限分级：打开总开关即等于给了脚本完整引擎权限。
- 脚本不能调 GC / 内存水位 / 加载管线 / 渲染批次这类**性能旋钮**（引擎内部硬编码）。
- 普通脚本内不能直接定义 `class`；需要类请放到模组的 `source/` 并打开「模组类库」
  （见第 14 节）。也**不支持 map 字面量** `{...}`（SScript 4.0.1 的限制）——
  传数据用数组或 `__newMap()`。
- 模组类库不是完整 Haxe：只解释普通 `class`（含 `extends` / 实例与静态成员）。
  `typedef` / `enum` / `abstract` / 宏 / 接口默认实现 / 泛型约束不保证支持；
  `import` 必须写在脚本顶部（SScript `execute` 的限制）。共享逻辑仍可写成
  **脚本库**（`scripting/libs/` + `importScript`，见 §2.1）。
- 未在 Android / Windows 实机验证（只在本机 macOS 跑过）。
- 脚本管理器的**列表显示**已实机验证（全局 / 界面两类脚本都正确列出，类型标记、开关状态、
  提示文案都对）；但 **→ 打开脚本界面**这一步未做实机按键验证（自动化按键没送达游戏窗口）。
- REPL 目前只在**当前界面**生效：跨界面的变量（全局脚本里的 var）不在 REPL 的作用域内，
  REPL 的变量也只活在这一次 REPL 会话里（关掉即销毁）。
- 本系统是 **Meteoric 自研**，与 Codename Engine 无关：既不兼容 CNE 格式的 mod，
  也不使用 CNE 的脚本实现或目录约定（历史上那套已于 2026-10-05 移除，理由见
  `source/backend/CneModProbe.hx` 的类头注释）。

## 11. 全曲 / 单曲脚本（`scripting/songs/`）

除了「全局常驻」和「状态脚本」，还有**按歌曲自动发现**的一层：进入 `PlayState` 时，
引擎会扫描启用中的 mod：

```
mods/<mod>/scripting/songs/<任意名>.hx           # 全曲脚本：每首歌都加载
mods/<mod>/scripting/songs/<歌曲名>/<任意名>.hx   # 单曲脚本：只在该曲目加载
```

- **单曲目录优先用谱面目录名**（`PlayState.chartFolder`，与 `data/<目录名>/` 同一套），
  该候选在所有启用 mod 里都没有脚本时，回退到 `Paths.formatToSongPath(SONG.song)`
  （`PlayState.songName`，即 JSON 的 `song` 字段格式化后的名字）。
  例：`data/Obsolescence-spam/` 的谱面里 `song="Obsolescence"` 时，先找
  `scripting/songs/Obsolescence-spam/`，没有再找 `scripting/songs/obsolescence/`。
  两个候选只会加载一个，避免同一脚本放两处被加载两次。
- 全曲层只认 `songs/` 的**直属** `.hx`；子目录一律当单曲目录，所以
  `songs/foo.hx`（全曲）与 `songs/foo/`（曲目 `foo` 的单曲脚本）可以同时存在。
- **顺序**：先全曲、后单曲；每一层都按「文件名前缀 → mod 启用顺序 → 文件名」排序，
  规则与 §2 的脚本前缀一致（`00_`…`999_`、`z_`、无前缀 500）。
- 加载进 `PlayState` 的 HScript 脚本数组，与其它游玩脚本同一套回调：
  `onCreate` / `onCreatePost` / `onUpdate` / `onStepHit` / `onBeatHit` / `onDestroy`。
  脚本里可直接用 `PlayState` / `game` / `dad` / `boyfriend` / `gf` / `camGame` 等
  既有游玩脚本变量（见 `HostDomain.initHScript`）。
- **回放模式不加载**（`initHScript` 的 `replayMode` 拦截），与既有
  `data/<歌曲名>/` 脚本一致。
- 与 Psych 风格的 `mods/<mod>/data/<歌曲名>/*.hx` 是**两条独立的线**：目录不同，
  引擎不会去重；同一个脚本不要在两处各放一份，否则会加载两次。
- 开关：`scriptingSongScripts`（总开关关时整体无效）。歌曲脚本在 `PlayState.create`
  时装载，F5 不会重建；改完请重新进曲。

## 12. 状态重定向（`scripting/redirects.txt`）

把引擎的某个界面**声明式**地改跳到另一个界面，不用写 `preStateSwitch` 脚本。
每个启用中的 mod 可提供 `mods/<mod>/scripting/redirects.txt`：

```ini
# 源界面 = 目标界面
MainMenuState = MyMenu
FreeplayState = script:MyFreeplay
OptionsState = states.OptionsState
```

- 左侧：要拦截的界面类名（短名，如 `MainMenuState`；也接受完整类名）。
- 右侧：目标界面。解析顺序：
  1. 以 `script:` 开头 → 强制找 `scripting/states/<名字>.hx` 脚本界面；
  2. 否则先找引擎类（短名按 `states.<名>`，完整类名按原样），找不到再找脚本界面。
- 多个 mod 提供同名规则时，**后加载的 mod 覆盖先加载的**（按 mod 启用顺序）。
- 生效时机：`preStateSwitch`。脚本自己 `return` 的目标**优先于**配置（脚本是动态的，
  配置是兜底）；脚本没有返回目标时，配置按本次**请求切换到的界面**匹配。
- 目标解析失败只打日志，不改变本次跳转（不会把玩家卡在空界面）。
- 解析脚本界面时使用 `scripting/states/<名字>.hx`；脚本界面的语义见 §7。
  状态脚本开关关闭时，`script:` 目标会解析失败（不会打开一个没有脚本的空界面）。
- 开关：`scriptingStateRedirects`。Shift+F5 重载全局脚本时会一并重读所有
  `redirects.txt`；普通 F5 不重读配置。配置文件不存在 = 没有规则。

## 13. 资源同名脚本（`scripting/stages|characters|notes|events/`）

按资源名自动配对同名 HScript：

```
mods/<mod>/scripting/stages/<舞台名>.hx       # 当前歌曲的 SONG.stage（PlayState.curStage）
mods/<mod>/scripting/characters/<角色名>.hx   # gf / dad / bf 的 curCharacter
mods/<mod>/scripting/notes/<音符类型>.hx      # 谱面里用到的 noteType
mods/<mod>/scripting/events/<事件名>.hx       # 谱面里用到的事件名
```

- 加载时机：`PlayState.create` 期间，每个资源名**只加载一次**（不是每个音符 / 每次事件
  各加载一次；音符数量大，逐实例加载会拖垮进曲）。
- 脚本注入的变量：
  - 舞台脚本：`stage`（本局第一个舞台实例）；
  - 角色脚本：`character`（该角色实例；同名角色只加载一次，变量指向首个实例）；
  - 音符类型脚本：`noteType`（字符串）；
  - 事件脚本：`eventName`（字符串）。
  其余变量与普通游玩脚本一致（`game` / `dad` / `boyfriend` / `gf` / `camGame` …）。
- 覆盖本局初始的 `gf` / `dad` / `bf` 与 `curStage` 构造出的第一个舞台。脚本后续
  `new Character(...)` / `new 舞台类(...)` 出来的对象不会自动配对；需要时在舞台/全局
  脚本里调用 `game.initHScript(path)` 手动加载。
- 与 Psych 风格的 `stages/<名>.hx`、`characters/<名>.hx`、`custom_notetypes/<名>.hx`、
  `custom_events/<名>.hx` 是**两套独立目录**：都放会各加载一次。要避免重复行为，
  只选一套。
- 回放模式不加载；`hudOnly` / TuoboLoad=2 跳过舞台构造时，舞台脚本也不会加载
  （没有舞台实例可绑）；角色脚本仍按实际构造出的角色加载。
- 开关：`scriptingResourceScripts`。F5 不会重建资源脚本；改完请重新进曲。

## 14. 模组 Haxe 类库（`mods/<mod>/source/`）

打开「脚本系统（总开关）」+「模组类库（source/）」后，引擎会扫描所有**已启用模组**的
`source/` 目录，把其中的普通 `class` 注册给 HScript。脚本可以像普通 Haxe 一样
`import`、`new`、读/写实例字段、调用实例方法与静态成员。

```
mods/<mod>/source/mymod/Foo.hx
```

```haxe
package mymod;

class Foo
{
	public var x:Int;

	public function new(x:Int)
	{
		this.x = x;
	}

	public function bar():Int
	{
		return x * 2;
	}

	public static function hello():String
	{
		return 'hi';
	}
}
```

脚本：

```haxe
import mymod.Foo;

var f = new Foo(5);
trace(f.x);          // 5
trace(f.bar());      // 10
trace(Foo.hello());  // hi
```

- 只注册普通 `class`；`typedef` / `enum` / `abstract` / 宏不注册。类可以 `extends`
  另一个模组类或引擎类；`super(...)` 可用，但当前实现最多接收 4 个构造参数
  （`ScriptClass.superConstructor` 的绑定上限；普通方法参数不受此限制）。
- 类代码可以读取宿主脚本的变量（`game` / `FlxG` / `dad` …）以及宿主脚本顶层的 `var`，
  因为找不到的标识符会回退到创建它的脚本变量表 / 局部变量表。静态变量按**每个 HScript
  实例**隔离，不会跨脚本共享。
- 短名只有在**全局唯一**时才可直接用；有重名时请用完整包名或 `import ... as ...`。
- `import` 必须写在脚本顶部（SScript `execute` 的硬限制）；`new 完整包名.Foo(...)`
  不需要 import。**不支持**直接写 `完整包名.类名.静态成员()`（第一段包名会被当成变量）；
  静态成员请先 `import` 再用短名。
- 部分 HScript 写法只在类方法里可用，例如直接读写继承字段；离开类上下文仍按普通
  HScript 规则处理。
- 目录只读 `source/`，不读取 `scripting/` 里的类；两者用途不同：`scripting/` 放脚本，
  `source/` 放可被脚本实例化的类。
- 热重载：F5 / Shift+F5 重建脚本前会重扫类库；改类文件后按 F5 即可。类定义变化不会
  自动重建已经在运行的旧脚本实例。
- 关闭「模组类库」时：不再扫盘，新创建 / 重载的脚本不安装 `ex.InterpEx`；已经运行的
  脚本实例不会被自动销毁，重载或重启后完全回到旧行为。

