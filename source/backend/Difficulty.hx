package backend;

class Difficulty
{
	public static var defaultList(default, never):Array<String> = [
		'Easy',
		'Normal',
		'Hard'
	];
	public static var list:Array<String> = [];
	private static var defaultDifficulty(default, never):String = 'Normal'; //The chart that has no suffix and starting difficulty on Freeplay/Story Mode

	/** Parts 组合难度的条目名（对应 Song 侧的「枚举全部 Part」语义） */
	public static inline var PARTS_DIFFICULTY:String = 'Parts';

	/** 该难度名是否是 Parts 组合难度（大小写不敏感） */
	public static function isPartsDifficulty(name:String):Bool
	{
		return name != null && name.toLowerCase() == PARTS_DIFFICULTY.toLowerCase();
	}

	inline public static function getFilePath(num:Null<Int> = null)
	{
		if(num == null) num = PlayState.storyDifficulty;

		// 越界/缺失一律按「默认难度（无后缀）」处理。
		var fileSuffix:String = (num >= 0 && num < list.length) ? list[num] : null;
		if(fileSuffix == null) return '';

		// ⚠ 必须**大小写不敏感**比较：本引擎默认难度是 'Normal'，而 Psych 模组普遍用
		// 小写写难度表（Sonic 的 `setPropertyFromClass('backend.Difficulty','list',{'normal'})`），
		// 严格比较会拼出 `-normal` 后缀 → 谱面名变成 `break-down-normal` → 文件不存在
		// → loadSongAndSwitchState 静默 return false（2026-10-30 实测：菜单里点歌毫无反应）。
		if(fileSuffix.toLowerCase() == defaultDifficulty.toLowerCase()) return '';

		return Paths.formatToSongPath('-' + fileSuffix);
	}

	inline public static function loadFromWeek(week:WeekData = null)
	{
		if(week == null) week = WeekData.getCurrentWeek();

		// week 可能为 null（storyWeek 越界）；difficulties 允许缺失/空串/全是逗号。
		var diffStr:String = (week != null) ? week.difficulties : null;
		var diffs:Array<String> = null;
		if(diffStr != null && diffStr.length > 0)
		{
			diffs = [];
			for (part in diffStr.trim().split(','))
			{
				var p:String = (part == null) ? null : part.trim();
				if(p != null && p.length > 0) diffs.push(p);
			}
		}

		// 解析为空时必须 resetList()：旧实现只在 `diffs[0].length > 0` 时赋值，
		// 空串/全逗号会**沿用上一周目的列表**，67 难度周切回 3 难度周时尤其明显。
		if(diffs != null && diffs.length > 0)
			list = diffs;
		else
			resetList();

		// Parts 组合难度：设置开启时追加「Parts」条目。选中它 → jsonInput 形如
		// "song-parts" → Song.resolvePartPaths 枚举该歌 data/ 下的全部 Part 并合并叠加。
		// ⚠ 这段必须在上面的 if/else **之外**：早前误把它写成 `if (partsMode) ... else resetList()`，
		//   导致 else 配对错位、**任何时候都执行 resetList()**，难度被重置成 Easy/Normal/Hard。
		if (ClientPrefs.data.partsMode && list.indexOf(PARTS_DIFFICULTY) < 0)
			list = list.copy().concat([PARTS_DIFFICULTY]);

		// 全局难度索引不随列表自动收敛：从 67 难度的 weekSG 切回 3 难度周后
		// storyDifficulty 可能仍是 66，getString() 越界 → UI 显示字面量 "null"。
		if (PlayState.storyDifficulty < 0 || PlayState.storyDifficulty >= list.length)
			PlayState.storyDifficulty = list.length - 1;
	}

	inline public static function resetList()
	{
		list = defaultList.copy();
	}

	inline public static function copyFrom(diffs:Array<String>)
	{
		list = diffs.copy();
	}

	/**
	 * 难度名。越界 / 空元素一律兜底，**永不返回 null** —— 否则调用方用 `+` 拼接时
	 * 会把 Haxe 的 null 变成界面上的字面量 "null"（HUD 水印、暂停页、结算页、
	 * Story/Freeplay 难度文本都吃过这个亏，ChartingState 里甚至有专门的 null 补丁）。
	 * 只有原本会返回 null 的路径行为改变，正常路径零变化。
	 */
	inline public static function getString(num:Null<Int> = null):String
	{
		var idx:Int = (num == null) ? PlayState.storyDifficulty : num;
		if(list == null || list.length < 1) return defaultDifficulty;
		if(idx < 0 || idx >= list.length) idx = 0;
		var value:String = list[idx];
		if(value == null || value.length < 1) value = list[0];
		if(value == null || value.length < 1) return defaultDifficulty;
		return value;
	}

	inline public static function getDefault():String
	{
		return defaultDifficulty;
	}
}