package backend;

import haxe.Json;
import backend.Paths;
import states.PlayState;
#if sys
import sys.io.File;
import sys.FileSystem;
#end
import lime.utils.Assets;

/**
 * 演出编排（相机编排）数据层 —— 与 Different Creatingness Engine（DCE）同构兼容。
 *
 * 文件：谱面同目录 `cam.json`（psych_cam_v1 格式，legacy `<chart>-cam.json` 仍可读）：
 *   { "format": "psych_cam_v1", "initialized": true,
 *     "events": [[time, [[name, v1, v2, layer, 'camera'|'chart'], ...]], ...] }
 * 运行时：载谱时把 cam.json 事件并入谱面事件流（先 stripManaged 剔除旧托管事件），
 * 由 EventDomain 的 DCE 兼容处理器回放（Focus Camera / Zoom Camera / Camera Angle 等）。
 * 编辑器状态（图层定义等）存 `mods/camera_editor_prefs.json`。
 */
typedef EdEvent =
{
	var time:Float;
	var name:String;
	var v1:String;
	var v2:String;
	var layer:Int;
	@:optional var source:String;
}

typedef EditorLayer = {name:String, typeName:String, color:Int}

class CameraEditorData
{
	static inline final MAX_JSON_BYTES:Int = 8 * 1024 * 1024;
	static inline final MAX_PREFS_BYTES:Int = 1024 * 1024;
	static inline final MAX_EVENTS:Int = 20000;
	static inline final MAX_EVENT_TIME_MS:Float = 86400000;
	static inline final MAX_EVENT_TEXT:Int = 4096;

	// 内建图层类型序（DCE 同序；图层 = 事件类型的可视轨道，+层 可绑自定义事件名）
	public static final LAYER_FOCUS:Int = 0;
	public static final LAYER_ZOOM:Int = 1;
	public static final LAYER_ADD_ZOOM:Int = 2;
	public static final LAYER_FOLLOW_POS:Int = 3;
	public static final LAYER_PLAY_ANIM:Int = 4;
	public static final LAYER_ANGLE:Int = 5;
	public static final LAYER_OTHER:Int = 6;
	public static final BUILTIN_LAYER_COUNT:Int = 7;

	public static final DEFAULT_LAYER_COLORS:Array<Int> = [0xFF99C198, 0xFF70959D, 0xFF8070A0, 0xFFC19FB1, 0xFFFFFFCC];

	/** 由 cam.json 托管的事件名（运行时载谱时从谱面事件流剔除、以 cam.json 为准）。 */
	public static final MANAGED_EVENTS:Array<String> =
	[
		'Focus Camera',
		'Zoom Camera',
		'Play Animation',
		'Add Camera Zoom',
		'Camera Follow Pos',
		'Camera Angle'
	];

	public static final BUILTIN_EVENTS:Array<String> =
	[
		'Focus Camera',
		'Zoom Camera',
		'Add Camera Zoom',
		'Camera Follow Pos',
		'Play Animation',
		'Camera Angle'
	];

	/** 图层定义（含自定义层），Default 层 = 兜底普通事件层。 */
	public static var layers:Array<EditorLayer> = [{name: 'Default', typeName: '', color: DEFAULT_LAYER_COLORS[0]}];

	// ================= 图层 =================

	public static function builtinEvents():Array<String> return BUILTIN_EVENTS.copy();

	public static function layerCount():Int
	{
		return layers.length;
	}

	public static function layerIndex(layer:Int):Int
	{
		if (layer < 0) return 0;
		if (layer >= layers.length) return layers.length - 1;
		return layer;
	}

	public static function layerName(layer:Int):String
	{
		if (layers.length == 0) return 'Default';
		return layers[layerIndex(layer)].name;
	}

	public static function layerType(layer:Int):String
	{
		if (layers.length == 0) return '';
		return layers[layerIndex(layer)].typeName;
	}

	public static function layerColor(layer:Int):Int
	{
		if (layers.length == 0) return DEFAULT_LAYER_COLORS[0];
		return layers[layerIndex(layer)].color;
	}

	public static function layerColors():Array<Int>
	{
		return [for (l in layers) l.color];
	}

	public static function setLayerColors(colors:Array<Int>):Void
	{
		if (colors == null) return;
		for (i in 0...layers.length)
			if (i < colors.length) layers[i].color = colors[i];
	}

	/** 事件名 → 图层下标（按 typeName 匹配，找不到 = Default 层）。 */
	public static function layerOf(name:String):Int
	{
		for (i in 0...layers.length)
			if (layers[i].typeName == name && name != null && name.length > 0) return i;
		return 0;
	}

	public static function eventNameOfLayer(layer:Int):String
	{
		return layerType(layer);
	}

	public static function nextLayerColor():Int
	{
		return DEFAULT_LAYER_COLORS[layers.length % DEFAULT_LAYER_COLORS.length];
	}

	public static function addLayer(name:String, typeName:String, color:Int):Int
	{
		var nm:String = (name == null || name.length < 1) ? 'Layer ' + (layers.length + 1) : name;
		layers.push({name: nm, typeName: (typeName == null) ? '' : typeName, color: color});
		return layers.length - 1;
	}

	public static function isDefaultLayer(idx:Int):Bool
	{
		return idx >= 0 && idx < layers.length && layers[idx].name == 'Default';
	}

	public static function removeLayer(idx:Int):Bool
	{
		if (layers.length <= 1) return false;
		if (idx < 0 || idx >= layers.length) return false;
		if (isDefaultLayer(idx)) return false;
		layers.splice(idx, 1);
		return true;
	}

	public static function moveLayer(idx:Int, dir:Int):Bool
	{
		if (idx < 0 || idx >= layers.length) return false;
		var tgt:Int = idx + dir;
		if (tgt < 0 || tgt >= layers.length) return false;
		var tmp:EditorLayer = layers[idx];
		layers[idx] = layers[tgt];
		layers[tgt] = tmp;
		return true;
	}

	public static function renameLayer(idx:Int, name:String):Void
	{
		if (idx < 0 || idx >= layers.length) return;
		if (name == null || name.length < 1) return;
		if (isDefaultLayer(idx)) return;
		layers[idx].name = name;
	}

	public static function setLayerType(idx:Int, typeName:String):Void
	{
		if (idx < 0 || idx >= layers.length) return;
		layers[idx].typeName = (typeName == null) ? '' : typeName;
	}

	public static function setLayerColor(idx:Int, color:Int):Void
	{
		if (idx < 0 || idx >= layers.length) return;
		layers[idx].color = color;
	}

	/** 事件是否由 cam 文件托管（内建六类 + 任意自定义图层绑定名）。 */
	public static function isManaged(name:String):Bool
	{
		if (MANAGED_EVENTS.contains(name)) return true;
		for (l in layers)
			if (l.typeName == name && name != null && name.length > 0) return true;
		return false;
	}

	/** 无绑定类型的图层下标（Default 兜底层）。 */
	public static function eventLayerIndex():Int
	{
		for (i in 0...layers.length)
			if (layers[i].typeName == '') return i;
		return 0;
	}

	// ================= 事件语义（值提示 / 默认值 / 中文名） =================

	public static function eventHint(name:String):String
	{
		return switch (name)
		{
			case 'Focus Camera':
				'值1: 对焦目标\n  boyfriend / dad / girlfriend\n  pos = 固定坐标\n值2: "偏移X,偏移Y,时长,缓动"\n  （后两项可省略，默认 2,CLASSIC）\n  CLASSIC / INSTANT 忽略时长';
			case 'Zoom Camera':
				'值1: 目标缩放\n  （如 1.1）\n值2: "时长,缓动,模式"\n  （如 "2,linear,direct"）\n  模式 direct = 绝对缩放\n  模式 stage = 舞台缩放倍数';
			case 'Add Camera Zoom':
				'值1: 摄像机加量\n  （默认 0.015）\n值2: UI 加量\n  （默认 0.03）';
			case 'Camera Follow Pos':
				'值1: X 坐标\n值2: "Y,时长,缓动"\n  （后两项可省略，默认 0.5,quadInOut）\n  INSTANT 忽略时长\n留空两个 = 恢复自动跟随';
			case 'Play Animation':
				'值1: 动画名\n值2: 角色\n  boyfriend / dad / girlfriend';
			case 'Camera Angle':
				'值1: 角度(度)\n  （如 -10 / 10，0 = 回正）\n值2: "时长,缓动"\n  （如 "0.3,quadOut"）';
			case 'Screen Shake':
				'触发摄像机与 HUD 震动\n值1: 摄像机"时长,强度"\n值2: HUD"时长,强度"';
			case 'Change Character':
				'切换角色\n值1: dad / boyfriend / girlfriend\n值2: 新角色的角色 ID';
			case 'Change Scroll Speed':
				'改变音符滚动速度\n值1: 速度倍率（1 为标准速度）\n值2: 过渡时长（秒）';
			case 'Set Property':
				'设置游戏对象属性\n值1: 属性路径\n值2: 要写入的值';
			case 'Play Sound':
				'播放音效\n值1: 音效文件名\n值2: 音量（0 到 1，默认 1）';
			case 'Hey!':
				'触发 Hey! 动作\n值1: BF、GF 或留空（两人）\n值2: 动作时长（秒），留空默认 0.6';
			case 'Set GF Speed':
				'设置 GF 点头速度\n值1: 正整数速度倍率，例如 1、2、4';
			case 'Alt Idle Animation':
				'设置角色 idle 动画后缀\n值1: dad / boyfriend / girlfriend\n值2: 后缀，例如 -alt；留空清除';
			default:
				'自定义事件：\n值1 / 值2 任意内容\n（由 Lua / HScript 处理）';
		}
	}

	public static function defaultValues(name:String):{v1:String, v2:String}
	{
		return switch (name)
		{
			case 'Focus Camera': {v1: 'boyfriend', v2: '0,0,2,CLASSIC'};
			case 'Zoom Camera': {v1: '1.1', v2: '2,linear,direct'};
			case 'Add Camera Zoom': {v1: '0.015', v2: '0.03'};
			case 'Camera Follow Pos': {v1: '', v2: ''};
			case 'Play Animation': {v1: 'idle', v2: 'boyfriend'};
			case 'Camera Angle': {v1: '0', v2: '0.3,quadOut'};
			default: {v1: '', v2: ''};
		}
	}

	public static function displayEventName(name:String):String
	{
		// 走 i18n（choreo.evn.* 键；缺键回退 DCE 同款中文）
		var localized:String = Lang.tOr('choreo.evn.' + name, '');
		if (localized != null && localized.length > 0) return localized;
		return switch (name)
		{
			case 'Focus Camera': '聚焦镜头';
			case 'Zoom Camera': '缩放镜头';
			case 'Add Camera Zoom': '镜头冲击';
			case 'Camera Follow Pos': '跟随坐标';
			case 'Play Animation': '播放动画';
			case 'Camera Angle': '镜头角度';
			case 'Screen Shake': '屏幕震动';
			case 'Change Character': '切换角色';
			case 'Change Scroll Speed': '改变滚动速度';
			case 'Set Property': '设置属性';
			case 'Play Sound': '播放声音';
			case 'Hey!': 'Hey! 动作';
			case 'Set GF Speed': 'GF 点头速度';
			case 'Alt Idle Animation': '待机动画后缀';
			default: name;
		}
	}

	// ================= 路径 =================

	/** cam.json 路径 = 谱面同目录（解析口径与 Song.resolveChartPath 一致）。
	 *  谱面在打包资产里（目录不在 mods/ 下）= 不可写，返回 null（编辑器走导出对话框兜底）。 */
	public static function camPathForSong(songName:String, ?diff:String):Null<String>
	{
		#if sys
		var folder:String = Paths.formatToSongPath(songName);
		if (folder == null || folder.length < 1) return null;
		var candidates:Array<String> = [];
		if (diff != null && diff.length > 0 && diff != 'normal')
			candidates.push(folder + '-' + diff);
		candidates.push(folder);
		for (ck in candidates)
		{
			var chartFile:String = Song.resolveChartPath(ck, folder);
			if (chartFile != null && chartFile.length > 0)
			{
				var slash:Int = Std.int(Math.max(chartFile.lastIndexOf('/'), chartFile.lastIndexOf('\\')));
				if (slash > 0)
				{
					var dir:String = chartFile.substr(0, slash + 1);
					// 只允许写模组目录；打包资产目录不可写
					if (dir.indexOf('mods/') >= 0 || dir.indexOf('mods\\') >= 0 || dir.indexOf('/mods/') >= 0)
						return dir + 'cam.json';
					return null;
				}
			}
		}
		#end
		return null;
	}

	/** legacy 读取：优先 cam.json，其次 <chart>-cam.json（DCE 旧版命名）。 */
	static function readableCamPath(camPath:String, chartFile:String):String
	{
		if (camPath != null && camFileReadable(camPath)) return camPath;
		if (chartFile != null && chartFile.length > 0)
		{
			var legacy:String = haxe.io.Path.withoutExtension(chartFile) + '-cam.json';
			if (camFileReadable(legacy)) return legacy;
		}
		return null;
	}

	static function camFileReadable(path:String):Bool
	{
		#if sys
		return path != null && FileSystem.exists(path);
		#end
		return path != null && Assets.exists(path);
	}

	// ================= 读写 =================

	static function readBoundedText(path:String, maxBytes:Int = MAX_JSON_BYTES):String
	{
		#if sys
		if (path == null || !FileSystem.exists(path)) throw 'File does not exist';
		if (FileSystem.stat(path).size > maxBytes) throw 'JSON file exceeds the size limit';
		return File.getContent(path);
		#end
		if (path == null || !Assets.exists(path)) throw 'File does not exist';
		return Assets.getText(path);
	}

	static function safeEventText(value:Dynamic):String
	{
		var text:String = (value == null) ? '' : Std.string(value);
		return text.length > MAX_EVENT_TEXT ? text.substr(0, MAX_EVENT_TEXT) : text;
	}

	static function safeEventTime(value:Dynamic):Float
	{
		var time:Float = Std.parseFloat(Std.string(value));
		if (!Math.isFinite(time)) return 0;
		return Math.max(-MAX_EVENT_TIME_MS, Math.min(MAX_EVENT_TIME_MS, time));
	}

	static function sortByTime(events:Array<EdEvent>):Void
	{
		events.sort(function(a:EdEvent, b:EdEvent):Int {
			return a.time > b.time ? 1 : (a.time < b.time ? -1 : 0);
		});
	}

	static function convertRawEvents(arr:Array<Dynamic>):Array<EdEvent>
	{
		var result:Array<EdEvent> = [];
		for (entry in arr)
		{
			if (result.length >= MAX_EVENTS) break;
			if (entry == null) continue;
			var time:Float = safeEventTime(entry[0]);
			var list:Dynamic = entry[1];
			if (list == null) continue;
			for (sub in cast(list, Array<Dynamic>))
			{
				if (result.length >= MAX_EVENTS) break;
				if (sub == null) continue;
				var name:String = safeEventText(sub[0]);
				var v1:String = (sub.length > 1) ? safeEventText(sub[1]) : '';
				var v2:String = (sub.length > 2) ? safeEventText(sub[2]) : '';
				var layer:Int = layerOf(name);
				if (sub.length > 3 && sub[3] != null)
				{
					var lv:Float = Std.parseFloat(Std.string(sub[3]));
					if (!Math.isNaN(lv) && lv >= 0) layer = layerIndex(Std.int(lv));
				}
				var source:String = (sub.length > 4 && Std.string(sub[4]) == 'chart') ? 'chart' : 'camera';
				result.push({time: time, name: name, v1: v1, v2: v2, layer: layer, source: source});
			}
		}
		sortByTime(result);
		return result;
	}

	static function loadCamFrom(path:String):Array<EdEvent>
	{
		if (path == null || !camFileReadable(path)) return [];
		try
		{
			var parsed:Dynamic = Json.parse(readBoundedText(path));
			var arr:Array<Dynamic> = null;
			if (Std.isOfType(parsed, Array)) arr = cast parsed;
			else if (parsed != null && Reflect.hasField(parsed, 'events')) arr = cast Reflect.field(parsed, 'events');
			if (arr == null) return [];
			return convertRawEvents(arr);
		}
		catch (e:Dynamic)
		{
			trace('[CameraEditor] loadCamFrom error: $e');
			return [];
		}
	}

	public static function loadCamEvents(songName:String, ?diff:String):Array<EdEvent>
	{
		var camPath:String = camPathForSong(songName, diff);
		if (camPath == null) return [];
		var chartFile:Null<String> = null;
		#if sys
		var folder:String = Paths.formatToSongPath(songName);
		if (folder != null && folder.length > 0)
		{
			var chartKey:String = (diff != null && diff.length > 0 && diff != 'normal') ? folder + '-' + diff : folder;
			chartFile = Paths.chartPath(chartKey);
		}
		#end
		var readable:String = readableCamPath(camPath, chartFile);
		return readable != null ? loadCamFrom(readable) : [];
	}

	public static function camFileExists(songName:String, ?diff:String):Bool
	{
		var camPath:String = camPathForSong(songName, diff);
		if (camPath == null) return false;
		#if sys
		var chartFile:String = null;
		var folder:String = Paths.formatToSongPath(songName);
		if (folder != null && folder.length > 0)
		{
			var chartKey:String = (diff != null && diff.length > 0 && diff != 'normal') ? folder + '-' + diff : folder;
			chartFile = Paths.chartPath(chartKey);
		}
		return readableCamPath(camPath, chartFile) != null;
		#end
		return camFileReadable(camPath);
	}

	/**Psych 原始格式（编辑器 3 元组，无 layer）：[[time, [[name, v1, v2], ...]], ...] */
	public static function eventsToRaw(events:Array<EdEvent>):Array<Dynamic>
	{
		var sorted:Array<EdEvent> = events.copy();
		sortByTime(sorted);
		var out:Array<Dynamic> = [];
		var curTime:Float = -1;
		var curList:Array<Dynamic> = [];
		for (ev in sorted)
		{
			if (ev.name.length < 1) continue;
			if (curTime != ev.time)
			{
				if (curList.length > 0) out.push([curTime, curList]);
				curTime = ev.time;
				curList = [];
			}
			curList.push([ev.name, ev.v1, ev.v2]);
		}
		if (curList.length > 0) out.push([curTime, curList]);
		return out;
	}

	/** cam 文件格式（layered）：[[time, [[name, v1, v2, layer, source], ...]], ...] */
	public static function eventsToRawLayered(events:Array<EdEvent>):Array<Dynamic>
	{
		var sorted:Array<EdEvent> = events.copy();
		sortByTime(sorted);
		var out:Array<Dynamic> = [];
		var curTime:Float = -1;
		var curList:Array<Dynamic> = [];
		for (ev in sorted)
		{
			if (ev.name.length < 1) continue;
			if (curTime != ev.time)
			{
				if (curList.length > 0) out.push([curTime, curList]);
				curTime = ev.time;
				curList = [];
			}
			curList.push([ev.name, ev.v1, ev.v2, ev.layer, ev.source == 'chart' ? 'chart' : 'camera']);
		}
		if (curList.length > 0) out.push([curTime, curList]);
		return out;
	}

	/** 保存 cam.json。谱面在打包资产里时返回 null（编辑器走导出对话框兜底）。 */
	public static function saveCamEvents(events:Array<EdEvent>, songName:String, ?diff:String):Null<String>
	{
		var camPath:String = camPathForSong(songName, diff);
		if (camPath == null) return null;
		#if sys
		try
		{
			var cameraEvents:Array<EdEvent> = events == null ? [] : [for (ev in events) if (ev.source != 'chart') ev];
			var data:Dynamic = {format: 'psych_cam_v1', initialized: true, events: eventsToRawLayered(cameraEvents)};
			File.saveContent(camPath, Json.stringify(data, '\t'));
			return camPath;
		}
		catch (e:Dynamic)
		{
			trace('[CameraEditor] saveCamEvents error: $e');
			return null;
		}
		#end
		return null;
	}

	// ================= 运行时合并 =================

	/** 从谱面事件流里剔除托管事件（cam.json 为准）。 */
	public static function stripManaged(entries:Array<Dynamic>):Array<Dynamic>
	{
		var kept:Array<Dynamic> = [];
		if (entries == null) return kept;
		for (entry in entries)
		{
			if (entry == null) continue;
			var time:Float = Std.parseFloat(Std.string(entry[0]));
			if (Math.isNaN(time)) time = 0;
			var list:Dynamic = entry[1];
			if (list == null) continue;
			var keptSub:Array<Dynamic> = [];
			for (sub in cast(list, Array<Dynamic>))
			{
				if (sub == null) continue;
				if (isManaged(Std.string(sub[0]))) continue;
				keptSub.push(sub);
			}
			if (keptSub.length > 0) kept.push([time, keptSub]);
		}
		return kept;
	}

	/**
	 * 运行时合并（PlayState 载谱后调用）：谱面同目录存在 cam.json 时，
	 * 把其中事件（Psych 原始格式）并入谱面事件流并按时间排序。
	 * 没有 cam 文件 = 原样返回（零行为变化）。
	 */
	public static function mergeIntoEventsData(songName:String, eventsData:Array<Dynamic>, ?diff:String):Array<Dynamic>
	{
		if (!camFileExists(songName, diff)) return eventsData;
		var camEvents:Array<EdEvent> = loadCamEvents(songName, diff);
		var cameraEvents:Array<EdEvent> = camEvents == null ? [] : [for (ev in camEvents) if (ev.source != 'chart') ev];
		if (cameraEvents.length <= 0) return eventsData;
		var merged:Array<Dynamic> = stripManaged(eventsData);
		merged = merged.concat(eventsToRaw(cameraEvents));
		merged.sort(function(a:Dynamic, b:Dynamic):Int {
			var ta:Float = Std.parseFloat(Std.string(a[0]));
			var tb:Float = Std.parseFloat(Std.string(b[0]));
			if (Math.isNaN(ta)) ta = 0;
			if (Math.isNaN(tb)) tb = 0;
			return (ta < tb) ? -1 : (ta > tb ? 1 : 0);
		});
		trace('[CameraEditor] 已合并 cam 编排: ' + cameraEvents.length + ' 事件');
		return merged;
	}

	// ================= 迁移（首次打开从谱面生成基准编排） =================

	/**
	 * 首次打开且无 cam.json：从谱面小节结构（mustHitSection/gfSection）合成
	 * Focus Camera 基准编排 + 吸收谱面既有的托管事件，写出 cam.json。
	 * 返回是否写出了新文件。
	 */
	public static function migrateFromSong(songName:String, notes:Array<Dynamic>, eventsData:Array<Dynamic>, songBpm:Float, ?diff:String):Bool
	{
		if (camFileExists(songName, diff)) return false;
		var camEvents:Array<EdEvent> = [];
		var sources:Array<Dynamic> = eventsData == null ? [] : eventsData;
		var seen:Map<String, Bool> = [];
		for (entry in sources)
		{
			if (entry == null) continue;
			var time:Float = Std.parseFloat(Std.string(entry[0]));
			if (Math.isNaN(time)) time = 0;
			var list:Dynamic = entry[1];
			if (list == null) continue;
			for (sub in cast(list, Array<Dynamic>))
			{
				if (sub == null) continue;
				var name:String = Std.string(sub[0]);
				if (!isManaged(name)) continue;
				var v1:String = (sub.length > 1 && sub[1] != null) ? Std.string(sub[1]) : '';
				var v2:String = (sub.length > 2 && sub[2] != null) ? Std.string(sub[2]) : '';
				var key:String = time + ':' + name + ':' + v1 + ':' + v2;
				if (!seen.exists(key))
				{
					camEvents.push({time: time, name: name, v1: v1, v2: v2, layer: layerOf(name), source: 'camera'});
					seen.set(key, true);
				}
			}
		}
		// 小节镜头切换 → Focus Camera 基准编排（编谱器的 mustHitSection/gfSection = 游玩自动切镜）
		var previousTarget:String = null;
		var bpmMap:Array<Conductor.BPMChangeEvent> = Conductor.bpmChangeMap;
		var secTime:Float = 0;
		for (secIdx in 0...notes.length)
		{
			var sec:Dynamic = notes[secIdx];
			if (sec == null) continue;
			var target:String = sec.gfSection == true ? 'girlfriend' : (sec.mustHitSection != false ? 'boyfriend' : 'dad');
			if (target == previousTarget) continue;
			previousTarget = target;
			var hasExplicit:Bool = false;
			for (ev in camEvents)
				if (ev.name == 'Focus Camera' && Math.abs(ev.time - secTime) < 1) { hasExplicit = true; break; }
			if (!hasExplicit)
				camEvents.push({time: secTime, name: 'Focus Camera', v1: target, v2: '0,0,0,CLASSIC', layer: layerOf('Focus Camera'), source: 'camera'});
			// 下一小节时间（4 拍，走 bpm 表；无匹配 = 谱面 BPM 均速）
			var beatB:Float = (secIdx + 1) * 4;
			var t:Float = -1;
			for (i in 0...bpmMap.length)
			{
				var ch:Conductor.BPMChangeEvent = bpmMap[i];
				var chBeat:Float = ch.stepTime / 4;
				if (beatB >= chBeat)
					t = ch.songTime + (beatB - chBeat) * (ch.bpm > 0 ? 60000 / ch.bpm : 500);
			}
			if (t < 0)
			{
				var bpm:Float = (songBpm > 0) ? songBpm : 100;
				t = beatB * (60000 / bpm);
			}
			secTime = t;
		}
		sortByTime(camEvents);
		var saved:String = saveCamEvents(camEvents, songName, diff);
		if (saved != null)
		{
			trace('[CameraEditor] 已从谱面生成基准编排 cam.json (' + camEvents.length + ' 事件)');
			return true;
		}
		return false;
	}

	// ================= 图层偏好 =================

	public static function prefsPath():String
	{
		#if MODS_ALLOWED
		return Paths.mods('camera_editor_prefs.json');
		#else
		return 'mods/camera_editor_prefs.json';
		#end
	}

	public static function loadPrefs():Void
	{
		try
		{
			var path:String = prefsPath();
			if (path == null || !camFileReadable(path)) return;
			var parsed:Dynamic = Json.parse(readBoundedText(path, MAX_PREFS_BYTES));
			if (parsed != null && Reflect.hasField(parsed, 'layers')
				&& parsed.layers != null && Std.isOfType(parsed.layers, Array))
			{
				var loaded:Array<EditorLayer> = [];
				for (l in cast(parsed.layers, Array<Dynamic>))
				{
					if (l == null) continue;
					var nm:String = Std.string(Reflect.field(l, 'name'));
					if (nm.length < 1) continue;
					var ty:String = Reflect.hasField(l, 'typeName') ? Std.string(Reflect.field(l, 'typeName')) : '';
					var cv:Null<Int> = Std.parseInt(Std.string(Reflect.field(l, 'color')));
					loaded.push({name: nm, typeName: ty, color: cv == null ? nextLayerColor() : cv});
				}
				if (loaded.length > 0)
				{
					// Default 层永远在第一位
					var hasDefault:Bool = false;
					for (l in loaded)
						if (l.name == 'Default') { hasDefault = true; break; }
					if (!hasDefault)
						loaded.unshift({name: 'Default', typeName: '', color: DEFAULT_LAYER_COLORS[0]});
					layers = loaded;
				}
			}
		}
		catch (e:Dynamic)
		{
			trace('[CameraEditor] loadPrefs error: $e');
		}
	}

	public static function savePrefs():Void
	{
		#if sys
		try
		{
			var path:String = prefsPath();
			if (path == null) return;
			var data:Dynamic = {layers: [for (l in layers) {name: l.name, typeName: l.typeName, color: l.color}]};
			File.saveContent(path, Json.stringify(data, '\t'));
		}
		catch (e:Dynamic)
		{
			trace('[CameraEditor] savePrefs error: $e');
		}
		#end
	}

	// ================= 备份（谱面同目录 cam_backups/） =================

	static function backupsDir(songName:String, ?diff:String):Null<String>
	{
		var camPath:String = camPathForSong(songName, diff);
		if (camPath == null) return null;
		return haxe.io.Path.directory(camPath) + '/cam_backups/';
	}

	static function pad2(n:Int):String
	{
		return (n < 10 ? '0' : '') + Std.string(n);
	}

	public static function backupName(songName:String, ?diff:String):String
	{
		var d:Date = Date.now();
		var stamp:String = pad2(d.getFullYear() % 100) + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + '_' + pad2(d.getHours()) + pad2(d.getMinutes()) + pad2(d.getSeconds());
		var base:String = 'chart';
		var camPath:String = camPathForSong(songName, diff);
		if (camPath != null)
		{
			base = haxe.io.Path.withoutDirectory(camPath);
			if (base.toLowerCase().endsWith('.json')) base = base.substr(0, base.length - 5);
		}
		var dir:String = backupsDir(songName, diff);
		return dir != null ? dir + base + '_' + stamp + '.json' : null;
	}

	public static function writeBackup(events:Array<EdEvent>, songName:String, ?diff:String):String
	{
		#if sys
		var file:String = backupName(songName, diff);
		if (file == null) return null;
		try
		{
			var dir:String = backupsDir(songName, diff);
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			var data:Dynamic = {format: 'psych_cam_backup_v1', savedAt: Date.now().toString(), events: eventsToRawLayered(events)};
			File.saveContent(file, Json.stringify(data, '\t'));
			// 只留最近 10 份
			var dirPath:String = dir;
			var files:Array<String> = [];
			if (FileSystem.exists(dirPath))
				for (f in FileSystem.readDirectory(dirPath))
					if (f.toLowerCase().endsWith('.json')) files.push(f);
			if (files.length > 10)
			{
				files.sort(function(a:String, b:String):Int { return a < b ? 1 : (a > b ? -1 : 0); });
				for (i in 10...files.length)
					FileSystem.deleteFile(dirPath + files[i]);
			}
			return file;
		}
		catch (e:Dynamic)
		{
			trace('[CameraEditor] writeBackup error: $e');
			return null;
		}
		#end
		return null;
	}
}
