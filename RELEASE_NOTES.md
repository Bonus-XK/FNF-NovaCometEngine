# NovaComet Engine v1.2.0 Pre-release 4 — "stagecraft"

> 基于 Psych Engine 0.7.1h 深度魔改的 FNF 引擎。**v1.2.0 Pre-release 4（代号 stagecraft）** 汇总 Pre-release 3（crazymidnight）以来的更新，主题是**老世代模组的演出兼容**：macOS 原生视频层、Psych 0.6.3 的 `vlc.MP4Handler` 兼容壳、8K 角色图集绘制，以及脚本层一批“代码写了但从未执行”的坑。验收样本是 PE 0.6.3 制作的 `Megamix2-LeafTeam`（1.1GB、11 分钟整曲、背景视频 + 相机后处理 + 90 个角色）。

---

## ✨ 版本亮点

- **macOS 视频层打通**：`VIDEOS_ALLOWED` 增加 mac。hxCodec 3.0.2 无需单独编 ndll（`@:include` + `@:buildXml` 把 libvlc 直接链进主程序），真正的坑是 haxelib 包内 `libvlc.dylib` / `libvlccore.dylib` 被 zip 压成了 14 字节文本（软链丢失）——现在由构建脚本还原软链，app 包内自带 `MacOS/lib/*.dylib` 与 347 个 VLC 插件。实测 1920×960 HEVC 整曲播放正常。
- **`vlc.MP4Handler` 兼容壳（Psych 0.6.3）**：新增 `source/vlc/MP4Handler.hx`，实现 `playVideo` / `bitmapData` / `volume` / `time` / `pause` / `resume` / `visible` / `update`。0.6.x 模组把视频帧当 BitmapData 贴到 Lua 精灵上做背景，接口一一对齐；`visible` 映射到 alpha（hxCodec 的帧上传受 `__renderable` 门控，真设 `visible=false` 会把上传一起停掉）。
- **8K 图集角色不再隐身**：`Paths.image()` 的 GPU 缓存对大于 4096 的位图关闭。大图上传纹理后，tile 渲染器按图集帧矩形采样会取到全透明且不报错；小图因为先进 `packImageIntoAtlas`（普通纹理）不受影响——这正是“场景/音符都正常、只有角色不显示”的根因。
- **脚本层三处“代码从未跑过”的修复**：① `initHaxeModuleCode` 把整段代码当文件路径传给 HScript，导致**每个脚本的第一条 `runHaxeCode` 永远不执行**；② `FlxRuntimeShader` 的运行时 FRAG_HEADER 缺 `flixel_texture2D`，模组 shader（`#define texture flixel_texture2D`）编译必失败；③ macOS 上 `setSpriteShader` 直接拒绝挂载、`runHaxeCode` 见 `.shader` 就整段跳过。

## 🛠 自 Pre-release 3 以来的修复

- **堆崩溃（SIGABRT / 二次释放）**：`removeLuaSprite(tag, true)` 直接 `destroy()` 会把精灵当前帧（与同图集角色共用的 `FlxFrame`）的 parent 置 null、rect 归还池——同图集角色随即画不出来，重复销毁则 `malloc: pointer being freed was not allocated`。改为先摘 `frames` 与 `_frame`/`_frameGraphic` 再销毁；密集谱“每颗音符建 ghost 再删”的写法不再崩。
- **macOS shader 容器**：`setSpriteShader` 不再直接 return false，改为“挂载 + 登记”，入列（`addLuaSprite` / `addInstance`）前自动摘除；`runHaxeCode` 的 `.shader` 拦截收窄为只拦**赋值**，放行 `new ShaderFilter(sprite.shader)` 这类只读用法，相机后处理路径在 macOS 上恢复。
- **HScript 类反射**：`MP4Handler` 这类“只被脚本 `new` 出来”的类，`@:keep` 不足以进构建，需 `--macro include('vlc')`；`addHaxeLibrary` 在 `onCreate` 阶段 `funk.hscript` 仍为 null，注册不进去，改在 `HScript.preset()` 预注册；属性访问器不能 `inline`（hxcpp 无函数指针，反射取到 null）。
- **NoteSplash 兜底**：皮肤贴图彻底缺失（模组只给了 XML 或皮肤名不存在）时不再往 null frames 上 `addByPrefix`，本局直接跳过溅射且不刷屏。
- **CI**：`build-macos.yml` 增加 hxCodec 软链还原步骤（幂等），保证 macOS x86_64 / arm64 两条产物都能链接 VLC。

---

## 📦 包含平台

- Windows x64 / x86（zip，解压即用）
- macOS x86_64 / arm64（zip 内含 Meteoric.app）
- Android arm64（APK）
- Linux x86_64（tar.gz，解压后运行 bin/Meteoric；视频支持暂缺）
- iOS（未签名 IPA，AltStore/Sideloadly 侧载自动重签）

SHA256 见 SHA256SUMS.txt · 构建自 commit {SHA}
