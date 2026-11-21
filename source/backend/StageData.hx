package backend;

#if MODS_ALLOWED
import sys.io.File;
import sys.FileSystem;
#else
import openfl.utils.Assets;
#end
import tjson.TJSON as Json;
import backend.Song;

typedef StageFile = {
	var directory:String;
	var defaultZoom:Float;
	var isPixelStage:Bool;
	var stageUI:String;

	var boyfriend:Array<Dynamic>;
	var girlfriend:Array<Dynamic>;
	var opponent:Array<Dynamic>;
	var hide_girlfriend:Bool;

	var camera_boyfriend:Array<Float>;
	var camera_opponent:Array<Float>;
	var camera_girlfriend:Array<Float>;
	var camera_speed:Null<Float>;

	// Psych 1.0.x stage editor 导出的物件表（本引擎此前不支持 → 这类模组背景全黑）。
	@:optional var preload:Dynamic;
	@:optional var objects:Array<Dynamic>;
	@:optional var _editorMeta:Dynamic;
}

/** stage objects 的显示条件位（对齐 Psych 1.0.x StageData.LoadFilters）。 */
enum abstract LoadFilters(Int) from Int from UInt to Int to UInt
{
	var LOW_QUALITY:Int = (1 << 0);
	var HIGH_QUALITY:Int = (1 << 1);

	var STORY_MODE:Int = (1 << 2);
	var FREEPLAY:Int = (1 << 3);
}

class StageData {
	public static function dummy():StageFile
	{
		return {
			directory: "",
			defaultZoom: 0.9,
			isPixelStage: false,
			stageUI: "normal",

			boyfriend: [770, 100],
			girlfriend: [400, 130],
			opponent: [100, 100],
			hide_girlfriend: false,

			camera_boyfriend: [0, 0],
			camera_opponent: [0, 0],
			camera_girlfriend: [0, 0],
			camera_speed: 1
		};
	}

	public static var forceNextDirectory:String = null;
	public static function loadDirectory(SONG:SwagSong) {
		var stage:String = '';
		if(SONG.stage != null) {
			stage = SONG.stage;
		} else if(SONG.song != null) {
			switch (SONG.song.toLowerCase().replace(' ', '-'))
			{
				case 'spookeez' | 'south' | 'monster':
					stage = 'spooky';
				case 'pico' | 'blammed' | 'philly' | 'philly-nice':
					stage = 'philly';
				case 'milf' | 'satin-panties' | 'high':
					stage = 'limo';
				case 'cocoa' | 'eggnog':
					stage = 'mall';
				case 'winter-horrorland':
					stage = 'mallEvil';
				case 'senpai' | 'roses':
					stage = 'school';
				case 'thorns':
					stage = 'schoolEvil';
				case 'ugh' | 'guns' | 'stress':
					stage = 'tank';
				default:
					stage = 'stage';
			}
		} else {
			stage = 'stage';
		}

		var stageFile:StageFile = getStageFile(stage);
		if(stageFile == null) { //preventing crashes
			forceNextDirectory = '';
		} else {
			forceNextDirectory = stageFile.directory;
		}
	}

	public static function getStageFile(stage:String):StageFile {
		var rawJson:String = null;
		var path:String = Paths.getPreloadPath('stages/' + stage + '.json');

		#if MODS_ALLOWED
		var modPath:String = Paths.modFolders('stages/' + stage + '.json');
		if(FileSystem.exists(modPath)) {
			rawJson = File.getContent(modPath);
		} else if(FileSystem.exists(path)) {
			rawJson = File.getContent(path);
		}
		#else
		if(Assets.exists(path)) {
			rawJson = Assets.getText(path);
		}
		#end
		else
		{
			return null;
		}
		return cast Json.parse(rawJson);
	}

	public static function vanillaSongStage(songName):String
	{
		switch (songName)
		{
			case 'spookeez' | 'south' | 'monster':
				return 'spooky';
			case 'pico' | 'blammed' | 'philly' | 'philly-nice':
				return 'philly';
			case 'milf' | 'satin-panties' | 'high':
				return 'limo';
			case 'cocoa' | 'eggnog':
				return 'mall';
			case 'winter-horrorland':
				return 'mallEvil';
			case 'senpai' | 'roses':
				return 'school';
			case 'thorns':
				return 'schoolEvil';
			case 'ugh' | 'guns' | 'stress':
				return 'tank';
		}
		return 'stage';
	}

	/** 保留名：stage editor 不允许这些名字占用角色/组变量。 */
	public static var reservedNames:Array<String> = ['gf', 'gfGroup', 'dad', 'dadGroup', 'boyfriend', 'boyfriendGroup'];

	/**
	 * 按 stage JSON 的 `objects` 表创建 sprite（对齐 Psych 1.0.x StageData.addObjectsToState）。
	 *
	 * 为什么加：Psych 1.0.x stage editor 导出的舞台把背景拆成 `objects` 数组，
	 * 由引擎在角色创建后实例化；本引擎此前没有这套逻辑 → 这类模组背景全黑。
	 *
	 * @param objectList objects 数组
	 * @param gf / dad / boyfriend 对应角色组（type=gf/dad/boyfriend 的条目用它定位）
	 * @param group 非 null 时把创建出的物件加入该容器（PlayState 自身传 this）
	 * @param ignoreFilters 为真时忽略 filters 位，全部创建
	 */
	public static function addObjectsToState(objectList:Array<Dynamic>, gf:Dynamic, dad:Dynamic, boyfriend:Dynamic, ?group:Dynamic = null, ?ignoreFilters:Bool = false):Map<String, Dynamic>
	{
		// ⚠ 参数与返回值都用 Dynamic，不要用 FlxSprite：
		//   模组脚本传的 gf/dad/boyfriend 实际是 gfGroup/dadGroup（FlxSpriteGroup），
		//   字典里同时混装 FlxSprite 与 FlxSpriteGroup；若声明为 FlxSprite，
		//   hxcpp 会按 FlxSprite 的字段偏移去读 FlxSpriteGroup → 原生 SEGV。
		var addedObjects:Map<String, Dynamic> = new Map<String, Dynamic>();
		if (objectList == null) return addedObjects;

		for (num in 0...objectList.length)
		{
			var data:Dynamic = objectList[num];
			if (data == null || data.type == null) continue;
			// ⚠ hxcpp 下 Map 的 null 键是原生解引用（gf/dad/boyfriend 条目的 name 就是 null）
			if (data.name != null && addedObjects.exists(data.name)) continue;

			switch (data.type)
			{
				case 'gf', 'gfGroup':
					if (gf != null)
					{
						gf.ID = num;
						if (group != null) group.add(gf);
						addedObjects.set('gf', gf);
					}
				case 'dad', 'dadGroup':
					if (dad != null)
					{
						dad.ID = num;
						if (group != null) group.add(dad);
						addedObjects.set('dad', dad);
					}
				case 'boyfriend', 'boyfriendGroup':
					if (boyfriend != null)
					{
						boyfriend.ID = num;
						if (group != null) group.add(boyfriend);
						addedObjects.set('boyfriend', boyfriend);
					}

				case 'square', 'sprite', 'animatedSprite':
					if (!ignoreFilters && !validateVisibility(data.filters)) continue;

					var spr:scripting.lua.ModchartSprite = new scripting.lua.ModchartSprite(data.x, data.y);
					spr.ID = num;
					if (data.type != 'square')
					{
						if (data.type == 'sprite')
						{
							if (data.image == null || data.image.length < 1) continue;
							spr.loadGraphic(Paths.image(data.image));
						}
						else if (data.image != null && data.image.length > 0)
							spr.frames = Paths.getAtlas(data.image);

						if (data.type == 'animatedSprite' && data.animations != null)
						{
							var anims:Array<objects.Character.AnimArray> = cast data.animations;
							for (anim in anims)
							{
								if (anim == null || anim.anim == null) continue;
								if (anim.indices == null || anim.indices.length < 1)
									spr.animation.addByPrefix(anim.anim, anim.name, anim.fps, anim.loop);
								else
									spr.animation.addByIndices(anim.anim, anim.name, anim.indices, '', anim.fps, anim.loop);

								if (anim.offsets != null) spr.addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);

								if (spr.animation.curAnim == null || data.firstAnimation == anim.anim)
									spr.playAnim(anim.anim, true);
							}
						}

						for (varName in ['antialiasing', 'flipX', 'flipY'])
						{
							var dat:Dynamic = Reflect.getProperty(data, varName);
							if (dat != null) Reflect.setProperty(spr, varName, dat);
						}
						if (!ClientPrefs.data.antialiasing) spr.antialiasing = false;
					}
					else
					{
						spr.makeGraphic(1, 1, FlxColor.WHITE);
						spr.antialiasing = false;
					}

					if (data.scale != null && (data.scale[0] != 1.0 || data.scale[1] != 1.0))
					{
						spr.scale.set(data.scale[0], data.scale[1]);
						spr.updateHitbox();
					}
					if (data.scroll != null) spr.scrollFactor.set(data.scroll[0], data.scroll[1]);
					if (data.color != null) spr.color = CoolUtil.colorFromString(data.color);

					for (varName in ['alpha', 'angle'])
					{
						var dat:Dynamic = Reflect.getProperty(data, varName);
						if (dat != null) Reflect.setProperty(spr, varName, dat);
					}

					if (group != null) group.add(spr);
					addedObjects.set(data.name, spr);

				default:
					FlxG.log.error('[Stage .JSON] Unknown sprite type: ' + data.type);
			}
		}
		return addedObjects;
	}

	/** filters 位是否允许当前显示（低画质 / 故事模式 等）。 */
	public static function validateVisibility(filters:LoadFilters):Bool
	{
		// 0 = 未设置任何 filters 位（旧版 stage 编辑器导出的物件）→ 一律显示
		if (filters == 0) return true;
		if ((filters & STORY_MODE) == STORY_MODE)
		{
			if (!PlayState.isStoryMode) return false;
		}
		else if ((filters & FREEPLAY) == FREEPLAY)
		{
			if (PlayState.isStoryMode) return false;
		}

		return ((ClientPrefs.data.lowQuality && (filters & LOW_QUALITY) == LOW_QUALITY) ||
			(!ClientPrefs.data.lowQuality && (filters & HIGH_QUALITY) == HIGH_QUALITY));
	}
}
