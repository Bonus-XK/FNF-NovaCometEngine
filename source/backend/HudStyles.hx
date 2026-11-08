package backend;

import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.display.Shape;

/** 簇渲染内容：main = 主行文本；sub = 次行文本（可为空 = 只画主行）；danger = 次行染红 */
typedef ClusterText = { main:String, sub:String, danger:Bool }

/**
 * 游玩 HUD 样式常量 + 计分簇共享构建器 —— 单一实现点（2026-11-06 PlayState UI 重设计）。
 *
 * 为什么抽出来：PlayState（实机 GameHUD）与 HUDCustomizeState（自定义界面预览）要长一个样，
 * 「预览 = 实机」靠的是**两边调同一个构建函数**（与 TimeBarColor.resolveFill 同一条纪律）。
 *
 * 档位约定（照 PopupAnim / IconBop 同款）：
 *  - 常量同时是存档值（`ClientPrefs.SaveVariables.*` 与本文件常量保持一致）；
 *  - CHOICES 下标 i 对应语言包 `optionValue.<variable>.<i>` —— 调整顺序要同步改两份语言包；
 *  - **全部默认 classic / 关** = 上游原行为，零行为变化（AGENTS.md 产品约束）。
 *
 * 各档位语义（见选项页描述，此处只写实现口径）：
 *  - 计分簇（scoreHudStyle=meteor）：血条正下两行 —— 主行 = 分数（26px 白 + 黑描边），
 *    次行 = `Miss n · 98.75% · FC`（16px 次级灰；Miss>0 整行染语义红 0xFFFF6B6B）。
 *    内容来源 scoreClusterSource：fixed = 固定字段；format = 解析 scoreTxtFormat 分段
 *   （解析失败回退单行 = 经典 scoreTxt）。
 *  - 血条样式（healthBarStyle）：classic 贴图 / old 0.6.3 旧版（镂空填充）/ new 新版自绘
 *   （白边框）/ rounded 流星圆角（黑色圆角底 + 内缩 2px 圆角填充，TimeBar newTimeBarStyle 同款）。
 *    旧双布尔 `oldHealthBar` / `newHealthBar` 保留**镜像写入**给脚本读（见选项 onChange）。
 */
class HudStyles
{
	// ==================== 档位常量（同时是存档值） ====================

	// ---- 计分栏样式 ----
	public static inline final SCORE_CLASSIC:String = 'classic';
	public static inline final SCORE_METEOR:String = 'meteor';
	/** 计分栏样式档位顺序（optionValue.scoreHudStyle.<i>） */
	public static final SCORE_STYLE_CHOICES:Array<String> = [SCORE_CLASSIC, SCORE_METEOR];

	// ---- 计分簇内容 ----
	public static inline final CLUSTER_FIXED:String = 'fixed';
	public static inline final CLUSTER_FORMAT:String = 'format';
	/** 计分簇内容档位顺序（optionValue.scoreClusterSource.<i>） */
	public static final CLUSTER_SOURCE_CHOICES:Array<String> = [CLUSTER_FIXED, CLUSTER_FORMAT];

	// ---- 血条样式 ----
	public static inline final HB_CLASSIC:String = 'classic'; // 经典贴图（healthBar.png）
	public static inline final HB_OLD:String = 'old';         // 0.6.3 旧版（填充裁剪为贴图内部形状）
	public static inline final HB_NEW:String = 'new';         // 新版自绘（白边框 + 内部填充）
	public static inline final HB_ROUNDED:String = 'rounded'; // 流星圆角（黑色圆角底 + 圆角填充）
	/** 血条样式档位顺序（optionValue.healthBarStyle.<i>） */
	public static final HB_STYLE_CHOICES:Array<String> = [HB_CLASSIC, HB_OLD, HB_NEW, HB_ROUNDED];

	// ==================== 计分簇视觉参数（实机与预览共用） ====================

	/** 主行（分数）字号 */
	public static inline final CLUSTER_MAIN_SIZE:Int = 26;
	/** 次行（Miss/准度/FC）字号 */
	public static inline final CLUSTER_SUB_SIZE:Int = 16;
	/** 主行与次行的行距（次行 y = 主行 y + MAIN_STEP） */
	public static inline final CLUSTER_MAIN_STEP:Float = 30;
	/** 次行中性色（次级灰，非 DesignTokens.secondary —— 那是暖黄，禁止当正文色） */
	public static inline final CLUSTER_SUB_COLOR:FlxColor = 0xFFB9B9C4;
	/** Miss>0 的语义红（判定/语义色例外，永不主题化） */
	public static inline final CLUSTER_DANGER_COLOR:FlxColor = 0xFFFF6B6B;
	/** 内嵌时间文字字号 */
	public static inline final TIME_INLINE_SIZE:Int = 14;
	/** 内嵌时间文字：白 92%（黑描边兜底，黑底/亮填充上均可读） */
	public static inline final TIME_INLINE_COLOR:FlxColor = 0xEBFFFFFF;
	/** 内嵌时间文字距时间条右缘的缩进 */
	public static inline final TIME_INLINE_RIGHT_PAD:Float = 12;
	/** 图标软投影精灵透明度 */
	public static inline final ICON_SHADOW_ALPHA:Float = 0.4;
	/** 水印减淡后的透明度 */
	public static inline final WATERMARK_DIM_ALPHA:Float = 0.55;
	/** 自动游玩徽标底色（FPS 方块徽章同款语言：固定深色 85% + 发丝描边，不随主题） */
	public static inline final PILL_BG_RGB:Int = 0x161622;
	public static inline final PILL_BG_ALPHA:Float = 0.85;

	// ==================== 档位判定 ====================

	/** 血条是否处于「贴图可见」的档位（经典贴图 / 0.6.3 旧版共用贴图，血条阴影 overlay 仅此二档有意义） */
	public static function healthBarTextureVisible():Bool
	{
		var s:String = ClientPrefs.data.healthBarStyle;
		return s == HB_CLASSIC || s == HB_OLD;
	}

	/** 计分簇是否启用（meteor 档 + 非极简血条——极简模式 scoreTxt 嵌入血条，簇让位） */
	public static function clusterActive():Bool
	{
		return ClientPrefs.data.scoreHudStyle == SCORE_METEOR && !ClientPrefs.data.minimalHealthBar;
	}

	// ==================== 计分簇文本构建 ====================

	/**
	 * 固定字段簇：主行 = 分数；次行 = `Miss n · 98.75% · FC`。
	 * @param accPercent 已换算好的准度字符串（如 "98.75"，不带 % 号，与 buildScoreText 口径一致）
	 */
	public static function buildClusterFixed(score:String, misses:String, accPercent:String, fc:String):ClusterText
	{
		var sub:String = 'Miss ' + misses + ' · ' + accPercent + '%' + (fc.length > 0 ? ' · ' + fc : '');
		return { main: score, sub: sub, danger: parseMisses(misses) > 0 };
	}

	/**
	 * 跟随格式串簇：把 scoreTxtFormat 按 `|` 分段、逐段替换变量后重排为「主行 + 次行」。
	 * - 含 `{score}` 的段 → 剥掉标签前缀后作为主行（通常只剩数字）；
	 * - 其余段 → 以 `段文本` 用 ` · ` 连接作为次行；
	 * - 格式串没有 `|` 分段或没有 `{score}` → 返回 null（调用方回退单行经典 scoreTxt）。
	 *
	 * @param rawFormat  原始格式串（未替换变量）
	 * @param substituted buildScoreText 已逐变量替换完成的整串（复用它，避免二次替换口径漂移）
	 */
	public static function buildClusterFromFormat(rawFormat:String, substituted:String):Null<ClusterText>
	{
		var rawSegs:Array<String> = rawFormat.split('|');
		if (rawSegs.length < 2) return null; // 没有分段可拆 → 单行
		var scoreIdx:Int = -1;
		for (i in 0...rawSegs.length)
			if (rawSegs[i].indexOf('{score}') >= 0) { scoreIdx = i; break; }
		if (scoreIdx < 0) return null;

		var segs:Array<String> = substituted.split('|');
		if (segs.length != rawSegs.length) return null; // showNPS 注入等改写了段数 → 保守回退单行

		var main:String = '';
		var subParts:Array<String> = [];
		for (i in 0...segs.length)
		{
			var text:String = StringTools.trim(segs[i]);
			if (text.length == 0) continue;
			if (i == scoreIdx)
			{
				main = stripSegmentLabel(text);
				continue;
			}
			// 段里的标签（如 "Misses:"）原样保留可读性；纯变量段（如 "{fc}"）替换后直接进次行
			subParts.push(text);
		}
		if (main.length == 0) return null;
		// 危险色语义：次行里含 "Misses 0" 之外的 Miss 数才染红 —— 从替换串里判不了干净，
		// 统一交由调用方用 songMisses 判（与 fixed 口径一致）。
		return { main: main, sub: subParts.join(' · '), danger: false };
	}

	/** 主行剥标签：取 `标签: 值` 的值部分（第一个冒号之后）；无标签则原样返回 */
	static function stripSegmentLabel(text:String):String
	{
		var colon:Int = text.indexOf(':');
		if (colon >= 0 && colon < text.length - 1) return StringTools.trim(text.substr(colon + 1));
		return text;
	}

	static function parseMisses(s:String):Int
	{
		var v:Null<Int> = Std.parseInt(StringTools.trim(s));
		return v == null ? 0 : v;
	}

	// ==================== 共享位图工厂（create 时各画一次，运行时零重绘） ====================

	/**
	 * 图标底部静态软投影位图：N 层同心椭圆递减透明度（CustomFade「星辉」辉光同款手法，
	 * 禁真实模糊）。宽 = 图标 150 + 两侧余量，高 ~26px，压在血条上缘。
	 */
	public static function buildIconShadowBitmap():BitmapData
	{
		var w:Int = 170;
		var h:Int = 26;
		var bd:BitmapData = new BitmapData(w, h, true, 0x00000000);
		var shape:Shape = new Shape();
		// 由外向内 5 层，α 单调上升；整体再由精灵 alpha 0.4 压暗
		var layers:Int = 5;
		for (i in 0...layers)
		{
			var t:Float = (i + 1) / layers; // 0.2 .. 1.0
			var rw:Float = w / 2 * t;
			var rh:Float = h / 2 * t;
			shape.graphics.beginFill(0x000000, 0.10 + 0.06 * i);
			shape.graphics.drawEllipse(w / 2 - rw, h / 2 - rh, rw * 2, rh * 2);
			shape.graphics.endFill();
		}
		bd.draw(shape);
		return bd;
	}

	/**
	 * 自动游玩圆角胶囊徽标底：FPS 方块徽章同款语言（固定深色 0x161622 @ 85% + 27% 白发丝描边）。
	 * 尺寸由调用方按文本量好传入；makeGraphic 必须 unique = true（同尺寸命中缓存会串图）。
	 */
	public static function buildPillSprite(w:Int, h:Int):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		var shape:Shape = new Shape();
		shape.graphics.beginFill(PILL_BG_RGB, PILL_BG_ALPHA);
		shape.graphics.drawRoundRect(0, 0, w, h, h, h); // 全圆胶囊：圆角 = 高的一半
		shape.graphics.endFill();
		shape.graphics.lineStyle(1, 0xFFFFFF, 0.27);
		shape.graphics.drawRoundRect(0.5, 0.5, w - 1, h - 1, h - 1, h - 1);
		var bd:BitmapData = new BitmapData(w, h, true, 0x00000000);
		bd.draw(shape);
		spr.pixels = bd;
		return spr;
	}

	// ==================== 水印文本（两行） ====================

	/**
	 * 水印文本（2026-11-07 改版，两行）：
	 *   第一行：曲目名 - 难度
	 *   第二行：NCE 引擎版本 + 兼容引擎版本（简便写法 `PE v1.0.4`，不带「兼容」字样）
	 * 兼容版本取**当前曲目所属模组**的生效引擎版本——用户在模组管理页手动指定的优先，
	 * 未指定（跟随）回退全局手动开关（luaUse063Compat / psychV073Compat / psychV104Compat，
	 * 可多开、按版本升序标注）。0.7.1 = 引擎基座本体（原生化运行），不算兼容不标。
	 * modFolder 传 null/'' = 原版曲（无 per-mod 指定，按全局开关）。
	 * PlayState 实机与 HUDCustomizeState 预览共用本函数（预览=实机纪律）。
	 */
	public static function buildWatermark(songName:String, diffText:String, modFolder:String):String
	{
		var line1:String = songName + ' - ' + diffText;
		var line2:String = Lang.tOr('play.watermarkSuffix', 'NCE v') + Main.meVersion;

		var ver:String = Mods.getModEngineVersion(modFolder);
		var compat:String = '';
		if (ver != null)
		{
			// 手动指定档：per-mod 生效语义（FunkinLua.use063Sentinels/use073Compat 同源）
			if (ver == '0.6.3') compat = Lang.tOr('play.watermarkCompat063', ' · PE v0.6.3');
			else if (ver == '0.7.3') compat = Lang.tOr('play.watermarkCompat073', ' · PE v0.7.3');
			else if (ver == '1.0') compat = Lang.tOr('play.watermarkCompat104', ' · PE v1.0.4');
			// ver == '0.7.1'：与引擎基座同版本，无兼容档可标
		}
		else
		{
			// 跟随：全局手动开关（可多开）
			if (ClientPrefs.data.luaUse063Compat) compat += Lang.tOr('play.watermarkCompat063', ' · PE v0.6.3');
			if (Paths.psych073Compat()) compat += Lang.tOr('play.watermarkCompat073', ' · PE v0.7.3');
			if (Paths.psychCompat()) compat += Lang.tOr('play.watermarkCompat104', ' · PE v1.0.4');
		}
		return line1 + '\n' + line2 + compat;
	}

	// ==================== 布局辅助 ====================

	/**
	 * 内嵌时间文字：定位到时间条内右端（右缘缩进 TIME_INLINE_RIGHT_PAD，垂直居中）。
	 * timeTxt 保持 400 宽 CENTER 盒（文本 M:SS 定宽，中心锚点稳定）——
	 * 只把盒子中心挪到「条右缘 - 缩进 - 半个文本宽」，避免 alignment=RIGHT 的折行/裁切问题。
	 * 由 GameHUD.update 每帧调用（文本每秒才变一次，textWidth 有 OpenFL 缓存，开销可忽略）。
	 */
	public static function layoutInlineTimeTxt(timeTxt:FlxText, timeBarX:Float, timeBarW:Float, timeBarY:Float, timeBarH:Float):Void
	{
		if (timeTxt == null) return;
		var textW:Float = timeTxt.textField.textWidth;
		var center:Float = timeBarX + timeBarW - TIME_INLINE_RIGHT_PAD - textW / 2;
		// CENTER 盒宽 400：视觉中心 = x + 200
		var targetX:Float = center - 200;
		if (Math.abs(timeTxt.x - targetX) > 0.5) timeTxt.x = targetX;
		var targetY:Float = timeBarY + (timeBarH - timeTxt.height) / 2;
		if (Math.abs(timeTxt.y - targetY) > 0.5) timeTxt.y = targetY;
	}
}
