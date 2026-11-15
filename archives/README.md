# archives — 死代码存档

2026-11-08 全仓死代码排查（4 路审查 + 三轮脚本交叉验证）后归档。`Project.xml` 的 classpath 只挂 `source/`，本目录不参与编译；`--dce full` 构建下零引用类本来就不进二进制，迁出 = 运行时零变化。

规则：确认零引用后 `git mv` 迁入并保留原相对路径。想彻底删除直接删对应子目录即可（git 历史都在）。

## source/（原 source/ 下零引用文件，保留原路径）

| 路径 | 说明 |
|---|---|
| `source/unused/` | Psych 0.7.1h 官方自带的 unused 目录（ButtonRemapSubstate / ChartParser / GitarooPause / LatencyState / Snd / SndTV + readme）。Snd/SndTV 引用本项目不存在的 faxe、h2d 库，本来就编不过；全目录零引用 |
| `source/objects/AttachedAchievement.hx` | 成就挂件类，零引用 |
| `source/objects/AttachedText.hx` | 同上 |
| `source/objects/CheckboxThingie.hx` | 同上（选项页复选框，引擎用的是 ToggleSwitch） |
| `source/objects/VideoSprite.hx` | 自称 Psych 0.6.3 mod 兼容 shim，但 `--dce full` 下零引用类不在产物里，shim 从未生效过 |
| `source/shaders/BlendModeEffect.hx` | 零引用 |
| `source/shaders/OverlayShader.hx` | 零引用 |
| `source/shaders/WiggleEffect.hx` | 零引用 |
| `source/shaders/ErrorHandledShader.hx` | 零代码引用，仅 CRTShader.hx / HostDomain.hx 注释里提到「照它的做法」 |
| `source/states/stages/Template.hx` | 舞台模板类（新舞台的复制起点），有文档价值故归档不删。注意 PlayState.hx 头注释指向的路径已过时 |
| `source/animateatlas/Main.hx` | 上游库自带的 demo Main（与 source/Main.hx 同名的地雷），零引用 |
| `source/hx/StdLibs.cpp` | 旧版 hxcpp StdLibs.cpp 拷贝（825 行，与现装版本 939 行不符），不参与 hxcpp 构建，仅作注释出处引用 |
| `Preloader.hx`（根级） | 原版 FNF preloader，不在任何 classpath；Project.xml 实际用 flixel.system.FlxPreloader |

## residue/（未入库的本地残渣，.gitignore 已排除本目录）

- `Project.xml.bak`、`crash/perf_probe.txt`、`tools/lime.ndll.app-9db2e17d.bak`、`tools/wallclock-stash/`、`tools/sscript_makeIterator_nullfix.hx.bak`、`source/states/editors/content/CneExport.hx.orig`

## 排查过但刻意没动的

- `tools/lime.ndll.stable`（compile-mac.sh 的对照基线）、`tools/lime.ndll.wallclock*`（构建活源）、`tools/lime.ndll.win64.wallclock`（无脚本引用，疑似 Windows 手动取用件，动前需确认）
- `source/ex/`、`source/luagraph/`、`source/bridge/`、`source/cutscenes/`、`source/flxanimate/`、`source/flixel/` override、`source/openfl/display/FPS.hx` —— 全部确认在用
- Vulkan 轨：2026-11-10 已整体删除（含 `Project.xml` 的 `lime-vulkan` haxedef）。`docs/VULKAN-ROADMAP.md` 与 `ci/vk-sandbox/` 仅作历史留档，不参与编译
- `source/flixel/FlxGame.hx` 的 `#if FLX_RECORD` 块：对 flixel haxelib 的上游同步 override，保持与上游一致
- `source/states/stages/objects/ABotSpeaker.hx` 的 `#if funkin.vis` 块：Project.xml 未挂 funkin-vis 库，块内代码从不编译（活文件里的死块，处理方式待议）
