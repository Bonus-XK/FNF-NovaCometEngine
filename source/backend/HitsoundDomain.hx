package backend;

import openfl.media.Sound;

/**
 * 打击音效域：玩家自定义打击音的发现、解析与缓存。
 *
 * - 存档值 ClientPrefs.data.hitsoundName，默认 'hitsound'（引擎内置打击音，模组可覆盖，
 *   仍走 Paths.sound 正常查找链）→ 默认值 = 零行为变化。
 * - 玩家自定义：把 ogg/mp3/wav 放进存档目录的 hitsounds/ 文件夹，
 *   文件名（去扩展名）即音效 key，重新打开判定设置页后出现在选项里。
 * - 音效实例按 key 缓存（Map<String, Sound>）：命中是高频路径，
 *   绝不允许每次命中重新解码；缓存的是解码后的短音效实例，量级可控。
 */
class HitsoundDomain
{
	public static inline var DEFAULT_KEY:String = 'hitsound';

	static var soundCache:Map<String, Sound> = [];

	/** 用户自定义音效目录（存档根/hitsounds；隔离/携带模式下自动跟随 getSavePath） */
	public static function customDir():String
	{
		return CoolUtil.getSavePath() + '/hitsounds';
	}

	/**
	 * 引擎内置打击音合集（assets/shared/sounds/hitsounds/，资源前缀 'hitsounds/'）。
	 * 搬运自 Kathy Engine（Apache 2.0，见该目录 SOURCE.md）；硬编码清单 = 跨平台稳定
	 * （APK/APK 内无法枚举目录），重复项需与目录内文件同步维护。
	 */
	public static inline var BUILTIN_PREFIX:String = 'hitsounds/';
	public static var BUILTIN_LIST:Array<String> = [
		'21st_century_humor', 'camellia', 'clap', 'daveandbambi', 'osu_mania',
		'pipe', 'quaver', 'snap', 'stepmania', 'vine_boom'
	];

	/** 可选打击音 key 列表：默认音 → 内置合集 → 用户自定义（按文件名排序） */
	public static function listAvailable():Array<String>
	{
		var list:Array<String> = [DEFAULT_KEY];
		#if sys
		// 内置合集：按清单过滤资源是否实际存在（防止清单与打包内容脱节）
		for (k in BUILTIN_LIST)
		{
			if (list.indexOf(k) >= 0) continue;
			if (sys.FileSystem.exists('assets/shared/sounds/' + BUILTIN_PREFIX + k + '.' + Paths.SOUND_EXT))
				list.push(k);
		}
		#end
		#if (sys && !android)
		var dir:String = customDir();
		try
		{
			if (sys.FileSystem.exists(dir))
			{
				var names:Array<String> = [];
				for (f in sys.FileSystem.readDirectory(dir))
				{
					var lower:String = f.toLowerCase();
					var isAudio:Bool = false;
					for (ext in ['.ogg', '.mp3', '.wav'])
					{
						if (lower.endsWith(ext))
						{
							isAudio = true;
							break;
						}
					}
					if (!isAudio) continue;
					var dot:Int = f.lastIndexOf('.');
					if (dot <= 0) continue; // 空文件名/纯扩展名
					var key:String = f.substr(0, dot);
					if (key == DEFAULT_KEY || names.indexOf(key) >= 0) continue;
					names.push(key);
				}
				names.sort(function(a:String, b:String):Int
				{
					return a < b ? -1 : (a > b ? 1 : 0);
				});
				for (n in names)
					list.push(n);
			}
		}
		catch (e:Dynamic) {} // 目录不可读：只列默认音，不影响游玩
		#end
		return list;
	}

	/**
	 * key → Sound。默认音走 Paths（保留模组覆盖）；
	 * 内置合集走 Paths（'hitsounds/<key>'，模组可覆盖）；
	 * 其余从用户目录加载并按 key 缓存；解析失败返回 null（调用方静默不播）。
	 */
	public static function resolveSound(key:String):Sound
	{
		if (key == null || key.length == 0 || key == DEFAULT_KEY)
			return Paths.sound(DEFAULT_KEY);
		if (BUILTIN_LIST.indexOf(key) >= 0)
			return Paths.sound(BUILTIN_PREFIX + key);
		if (soundCache.exists(key))
		{
			var cached:Sound = soundCache.get(key);
			if (cached != null) return cached;
		}
		var snd:Sound = tryLoadFile(key);
		if (snd != null) soundCache.set(key, snd);
		return snd;
	}

	/**
	 * 打击音是否启用（hitsoundVolume > 0）。
	 * ⚠ **必须 null 安全**：ClientPrefs.data 声明即 null，loadPrefs 之后才有值；
	 * FlxSoundTray 构造期就存在、且可能在 loadPrefs 之前响应 +/- 键 →
	 * 在托盘里直接解引用 ClientPrefs.data 会 SEGV（2026-11-06 实测，三份 ips 同型）。
	 */
	public static function isEnabled():Bool
	{
		var d = ClientPrefs.data;
		return d != null && d.hitsoundVolume > 0;
	}

	/**
	 * 播放点统一入口：note.hitsound 为音符类型/谱面显式指定的音效（原样走 Paths）；
	 * 仅默认档 'hitsound' 才替换为玩家自定义音。
	 */
	public static function soundForNote(noteHitsound:String):Sound
	{
		if (noteHitsound == DEFAULT_KEY)
			return resolveSound(ClientPrefs.data.hitsoundName);
		return Paths.sound(noteHitsound);
	}

	static function tryLoadFile(key:String):Sound
	{
		#if (sys && !android)
		var base:String = customDir() + '/' + key;
		for (ext in ['.ogg', '.mp3', '.wav'])
		{
			var p:String = base + ext;
			try
			{
				if (sys.FileSystem.exists(p))
					return Sound.fromFile(p);
			}
			catch (e:Dynamic) {} // 解码失败：试下一个扩展名，最后返回 null
		}
		#end
		return null;
	}
}
