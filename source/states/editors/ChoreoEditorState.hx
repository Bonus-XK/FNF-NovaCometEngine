package states.editors;

import backend.CameraEditorData.EdEvent;
import backend.ChoreoEase;
import backend.ClientPrefs;
import backend.Conductor;
import backend.Conductor.BPMChangeEvent;
import backend.Difficulty;
import backend.Lang;
import backend.Paths;
import backend.StageData;
import backend.StageData.StageFile;
import backend.WheelScroll;
import backend.Section.SwagSection;
import backend.Song;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.math.FlxRect;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import objects.Character;
import backend.MusicBeatState;
import states.PlayState;
import states.editors.ChartWidgets.EditorButton;
import states.editors.ChartWidgets.EditorDropdown;
import states.editors.ChartWidgets.EditorInput;
import openfl.Lib;
import openfl.media.Sound;
import lime.utils.Assets;

/**
 * 演出编排编辑器 v2 —— DCE（Different Creatingness Engine）语义兼容版。
 *
 * 数据 = 谱面同目录 cam.json（psych_cam_v1，图层化事件），运行时经 CameraEditorData
 * 载谱合并回放；事件语义照 DCE（Focus Camera 钉住 / Zoom Camera direct+stage /
 * Camera Angle / Follow Pos "Y,时长,缓动" / INSTANT-CLASSIC 瞬时）。
 * 图层 = 事件类型可视轨道（Default 兜底 + 六内建类型 + 自定义绑定层），编辑器状态存
 * mods/camera_editor_prefs.json。时间轴支持多选/框选/拖卡改时/拖边改时长/右键删/
 * 内存剪贴板/50 层撤销。预览 = 全屏观察相机 + 取景框 overlay（拖动平移 / Alt+拖旋转 /
 * IJKL / 滚轮三级 / 拖框编辑选中 FollowPos-Focus 事件）。设计稿 docs/CHOREO-EDITOR.md。
 */
class ChoreoEditorState extends MusicBeatState
{
	// ===== 布局常量（1280×720 基线，DCE 结构对位）=====
	inline static var TOP_H:Float = 60;          // 菜单条 36 + 状态行 24
	inline static var RIGHT_W:Float = 440;       // 右面板宽（DCE 440）
	inline static var LAYER_LABEL_W:Float = 140; // 图层标签列（DCE 140）
	inline static var RULER_H:Float = 28;        // 标尺（DCE 28）
	inline static var TOOLBAR_H:Float = 38;      // 时间轴工具栏（DCE 38）
	inline static var SCROLLBAR_H:Float = 16;    // 横向滚动条（DCE 16）
	inline static var STRUM_H:Float = 44;        // 音符预览条（简化版；角色联动后续迭代）
	inline static var PREVIEW_GAP:Float = 10;
	inline static var MAX_UNDO:Int = 50;
	inline static var MAX_EVENT_SPRITES:Int = 400;

	// 时间轴几何（create/reload 里计算）
	var timelineAreaH:Float = 300;
	var timelineTop:Float = 0;      // 时间轴区顶（= 720 - timelineAreaH）
	var tlTop:Float = 0;            // 标尺顶（timelineTop + TOOLBAR_H + SCROLLBAR_H）
	var layerRowY:Float = 0;        // 图层行起始 y（tlTop + RULER_H）
	var layerH:Float = 46;
	var strumY:Float = 0;
	var timelineX:Float = LAYER_LABEL_W;
	var timelineRight:Float = 0;    // = 1280 - RIGHT_W - 16

	// ===== PlayState 兼容表面（舞台类挂接；stages 继承自 MusicBeatState）=====
	public var gfGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var boyfriendGroup:FlxSpriteGroup;
	public var camFollow:FlxObject;
	public var defaultCamZoom:Float = 0.9;
	public var camGame:FlxCamera;
	public var camUI:FlxCamera;
	public var paused:Bool = false;
	public var songName:String = '';
	public var inCutscene:Bool = false;
	public var canPause:Bool = false;
	public var gf:Character;
	public var dad:Character;
	public var boyfriend:Character;

	// ===== 谱面数据 =====
	var notesSong:SwagSong;
	var sections:Array<SwagSection>;
	var currentSongName:String;
	var songPath:String;
	var curStageName:String;
	var stageData:StageFile;
	var events:Array<EdEvent> = [];
	var triggeredFlags:Array<Bool> = [];
	var hasUnsaved:Bool = false;
	var diffIdx:Int = 0;
	var songLength:Float = 0;
	var songEndMs:Float = 0;

	// ===== 图层 =====
	var layersVisible:Array<Bool> = [];

	// ===== 选择 / 剪贴板 / 撤销 =====
	var selectedIndexes:Array<Int> = [];
	var boxSelecting:Bool = false;
	var boxStartX:Float = 0;
	var boxStartY:Float = 0;
	var boxRect:FlxSprite;
	var clipboardEvents:Array<EdEvent> = [];
	var undoStack:Array<Array<EdEvent>> = [];
	var redoStack:Array<Array<EdEvent>> = [];

	// ===== 播放 =====
	var music:FlxSound;
	var voices:FlxSound;
	var playing:Bool = false;
	var cursorMs:Float = 0;
	var lastBeatDance:Int = -1;
	var lastStepHit:Int = -1;
	var audioOk:Bool = false;
	var autoScrollMode:Int = 1;                 // 0 关 1 翻页 2 平滑（DCE 同款）
	var manualScrollTimer:Float = 0;

	// ===== 时间轴 =====
	var scrollMs:Float = 0;
	var pxPerMs:Float = 0.05;                   // DCE 默认（100% = 50px/s）
	inline static var ZOOM_MAX:Float = 0.25;
	var snapEnabled:Bool = true;
	var quantSteps:Float = 16;
	var tlDirty:Bool = true;
	var tlScrollShown:Float = -1;
	var tlZoomShown:Float = -1;
	var tlCanvas:FlxSprite;
	var playheadSpr:FlxSprite;
	var textPool:Array<FlxText> = [];
	var wheel:WheelScroll;
	var scrollbarDrag:Bool = false;
	var scrubDrag:Bool = false;
	var draggingSplitter:Bool = false;
	var passepartoutOn:Bool = true;

	// ===== 事件拖拽 =====
	var dragMode:Int = 0;                       // 0 无 1 移动 2 左边 3 右边
	var dragIndexes:Array<Int> = [];
	var dragMouseMsOffset:Float = 0;
	var dragStartSnap:Array<EdEvent> = null;
	var dragStartX:Float = 0;
	var dragStartY:Float = 0;

	// ===== vcam（游玩镜头模拟，DCE stepVirtualCamera 语义）=====
	var vcamZoom:Float = 1;
	var vcamScrollX:Float = 0;
	var vcamScrollY:Float = 0;
	var vcamAngle:Float = 0;
	var vcamFollowX:Float = 0;
	var vcamFollowY:Float = 0;
	var vcamHasFollow:Bool = false;
	var previewZoom:Float = 1;
	var vfWinScale:Float = 1;
	var zoomTween:{a:Float, b:Float, t:Float, dur:Float, fn:Null<Float->Float>};
	var angleTween:{a:Float, b:Float, t:Float, dur:Float, fn:Null<Float->Float>};
	var followTween:{ax:Float, ay:Float, bx:Float, by:Float, t:Float, dur:Float, fn:Null<Float->Float>};
	var frameLines:Array<FlxSprite> = [];
	var cornerTicks:Array<FlxSprite> = [];
	var followDot:FlxSprite;
	var passeParts:Array<FlxSprite> = [];
	var previewDragging:Bool = false;
	var previewRotating:Bool = false;
	var dragEditIdx:Int = -1;
	var dragLastX:Float = 0;
	var dragLastY:Float = 0;
	var dragStartSnap2:Array<EdEvent> = null;
	var zoomIdle:Float = 0;

	// ===== UI =====
	var uiLayer:FlxSpriteGroup;
	var menuDefs:Array<{label:String, items:Array<{label:String, cb:Void->Void}>}>;
	var openMenu:Int = -1;
	var menuPanel:FlxSpriteGroup;
	var menuBtns:Array<EditorButton> = [];
	var menuRects:Array<FlxRect> = [];
	var statusTxt:FlxText;
	var hintTxt:FlxText;
	var infoTxt:FlxText;
	var timeTxt:FlxText;
	var playBtn:EditorButton;
	var autoScrollBtn:EditorButton;
	var snapBtn:EditorButton;
	var zoomMinusBtn:EditorButton;
	var zoomPlusBtn:EditorButton;
	var fitBtn:EditorButton;
	var layerRowTexts:Array<FlxText> = [];
	var evtNameDd:EditorDropdown;
	var evtTimeInput:EditorInput;
	var evtV1Input:EditorInput;
	var evtV2Input:EditorInput;
	var evtHintTxt:FlxText;
	var panelMsg:FlxText;
	var msgTimer:Float = 0;
	var songInput:EditorInput;
	var diffBtn:EditorButton;
	var reloadBtn:EditorButton;
	var openDropdown:EditorDropdown = null;
	var evnLabels:Array<String> = [];
	var evnNames:Array<String> = [];
	var cardHitRects:Array<{x:Float, y:Float, w:Float, h:Float, idx:Int}> = [];

	// 自定义缓动曲线
	var curveHandles:Array<FlxSprite> = [];
	var curveHandleDrag:Int = -1;
	var customCurve:Array<Float> = null;
	var curveBg:FlxSprite;

	var closed:Bool = false;
	var flatNotes:Array<{t:Float, pl:Bool, sus:Float}> = [];
	var lastW:Int = 0;
	var lastH:Int = 0;
	var layerHeadCanvas:FlxSprite;
	var sbBg:FlxSprite;
	var sbThumb:FlxSprite;

	public function new()
	{
		super();
	}

	override public function create()
	{
		// 相机角色（真机踩坑修复）：⚠ FlxG.mouse.screenX/Y = getScreenPosition(FlxG.camera)，
		// 若 FlxG.camera 是带缩放的舞台预览相机，鼠标坐标会随 zoom 畸变（用户实测「点击大偏移」根因）。
		// 因此 FlxG.camera 必须 = 全屏 zoom1 的 UI 相机；舞台预览挂在非默认的 camGame 上。
		camGame = new FlxCamera();
		camGame.bgColor = 0xFF000000;
		FlxG.cameras.reset(camGame);      // 列表=[camGame]，默认绘制目标=舞台（null 相机成员=舞台侧 ✓）
		camUI = new FlxCamera();
		camUI.bgColor = 0x0;
		FlxG.cameras.add(camUI, false);   // 列表=[camGame, camUI]：舞台先画、UI 后画盖上
		FlxG.camera = camUI;              // ⚠ 静态指针指向 UI 相机——FlxG.mouse.screenX/Y 与
		                                  // ChartWidgets/输入框的坐标语义归位（zoom 畸变修复的核心）

		FlxG.mouse.visible = true;
		wheel = new WheelScroll();

		uiLayer = new FlxSpriteGroup();
		gfGroup = new FlxSpriteGroup();
		dadGroup = new FlxSpriteGroup();
		boyfriendGroup = new FlxSpriteGroup();

		backend.CameraEditorData.loadPrefs();
		refreshLayerVisibility();

		// 直启优先级：--meteoric-song=<曲> > PlayState.SONG > tutorial
		var fromPlayState:Bool = (PlayState.SONG != null && PlayState.SONG.song != null);
		var folder:String = backend.DebugLaunch.autoSong != null ? backend.DebugLaunch.autoSong
			: (fromPlayState ? PlayState.SONG.song : 'tutorial');
		if (!loadChartData(folder, null))
		{
			trace('[Choreo] 载谱失败，回退 tutorial');
			if (!loadChartData('tutorial', null))
			{
				trace('[Choreo] tutorial 也不可用，以空谱面继续');
				notesSong = null;
				events = [];
				sections = [];
				songPath = 'tutorial';
				currentSongName = 'tutorial';
				curStageName = 'stage';
				stageData = StageData.dummy();
				defaultCamZoom = stageData.defaultZoom;
			}
		}
		buildStagePreview();
		loadAudio();

		// 时间轴几何
		timelineTop = FlxG.height - timelineAreaH;
		tlTop = timelineTop + TOOLBAR_H + SCROLLBAR_H;
		layerRowY = tlTop + RULER_H;
		timelineRight = FlxG.width - RIGHT_W - 16;
		timelineX = LAYER_LABEL_W;
		recomputeLayerH();
		strumY = layerRowY + backend.CameraEditorData.layerCount() * layerH + 10;

		buildUI();
		uiLayer.cameras = [camUI];
		add(uiLayer);
		lastW = FlxG.width;
		lastH = FlxG.height;

		camFollow = new FlxObject(0, 0, 1, 1);
		add(camFollow);
		camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, 0);
		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);

		buildFlatNotes();
		// previewZoom 自适应预览区（DCE 默认 0.55 同思想：框完整落在预览区里）
		var zoneW:Float = timelineRight;
		var zoneH:Float = timelineTop - TOP_H - 30;
		previewZoom = FlxMath.bound(Math.min(zoneW / 1280, zoneH / 720), 0.25, 1);

		simulateCameraAt(cursorMs);
		refreshPanelFromSelection();

		Lib.application.window.title = Lang.tOr('win.choreo', 'NovaComet Engine - 演出编排编辑器');
	}

	override public function destroy():Void
	{
		if (!closed) closeEditor(false);
		if (music != null)
		{
			music.stop();
			music = null;
		}
		if (voices != null)
		{
			voices.stop();
			voices.destroy();
			voices = null;
		}
		closeMenuPanel();
		super.destroy();
	}

	function closeEditor(save:Bool):Void
	{
		closed = true;
		if (save) syncData();
		backend.CameraEditorData.savePrefs();
		playing = false;
		if (music != null) music.stop();
		if (voices != null) voices.stop();
		Lib.application.window.title = Lang.tOr('win.editorsMenu', 'NovaComet Engine - 编辑器菜单');
	}

	// ================= 数据装载 =================

	function diffList():Array<String>
	{
		if (Difficulty.list != null && Difficulty.list.length > 0)
			return Difficulty.list;
		return ['easy', 'normal', 'hard'];
	}

	function loadChartData(folder:String, diff:String):Bool
	{
		var song:SwagSong = null;
		var attempts:Array<String> = [];
		if (diff != null && diff.length > 0 && diff != 'normal')
			attempts.push(Paths.formatToSongPath(folder) + '-' + diff);
		attempts.push(Paths.formatToSongPath(folder));
		for (att in attempts)
		{
			try
			{
				song = Song.loadFromJson(att, Paths.formatToSongPath(folder));
				break;
			}
			catch (e:Dynamic)
			{
				song = null;
			}
		}
		if (song == null)
		{
			showMsg(Lang.tOr('choreo.loadFail', '谱面加载失败：') + folder);
			return false;
		}

		notesSong = song;
		currentSongName = folder;
		songPath = Paths.formatToSongPath(folder);
		songName = notesSong.song;
		PlayState.setSong(notesSong);

		curStageName = notesSong.stage;
		if (curStageName == null || curStageName.length < 1)
			curStageName = StageData.vanillaSongStage(songPath);
		stageData = StageData.getStageFile(curStageName);
		if (stageData == null)
			stageData = StageData.dummy();
		defaultCamZoom = stageData.defaultZoom > 0 ? stageData.defaultZoom : 0.9;

		sections = notesSong.notes;
		if (sections == null)
			sections = [];

		// 资源目录（真机铁律：编辑器自选曲目后必须重设）
		StageData.loadDirectory(notesSong);
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;
		Paths.setCurrentLevel(weekDir != null && weekDir.length > 0 ? weekDir : 'shared');

		Conductor.mapBPMChanges(notesSong);

		// 谱面事件流（chart 来源；托管事件剔除——由 cam.json 接管）
		var chartEventsData:Array<Dynamic> = [];
		try
		{
			var ev:SwagSong = Song.loadFromJson('events', songPath);
			if (ev != null && ev.events != null)
				chartEventsData = ev.events;
		}
		catch (e:Dynamic)
		{
			chartEventsData = [];
		}

		// 首次打开：从谱面生成基准编排（小节跟随 → Focus Camera + 吸收既有托管事件）
		var songBpm:Float = notesSong.bpm > 0 ? notesSong.bpm : 100;
		backend.CameraEditorData.migrateFromSong(songPath, cast sections, chartEventsData, songBpm);

		// 文档 = cam 事件（source=camera）+ 谱面普通事件（source=chart，Default 层展示、不写回 cam）
		events = backend.CameraEditorData.loadCamEvents(songPath);
		for (entry in chartEventsData)
		{
			if (entry == null || entry[1] == null) continue;
			var t:Float = Std.parseFloat(Std.string(entry[0]));
			if (Math.isNaN(t)) t = 0;
			var inner:Array<Dynamic> = entry[1];
			for (sub in cast(inner, Array<Dynamic>))
			{
				if (sub == null || sub.length < 1) continue;
				var nm:String = Std.string(sub[0]);
				if (backend.CameraEditorData.isManaged(nm)) continue;
				events.push({
					time: t,
					name: nm,
					v1: sub.length > 1 && sub[1] != null ? Std.string(sub[1]) : '',
					v2: sub.length > 2 && sub[2] != null ? Std.string(sub[2]) : '',
					layer: backend.CameraEditorData.eventLayerIndex(),
					source: 'chart'
				});
			}
		}
		sortEvents();
		buildFlatNotes();
		recomputeSongEnd();
		refreshLayerVisibility();
		resetSelection();
		undoStack = [];
		redoStack = [];
		hasUnsaved = false;
		tlDirty = true;
		return true;
	}

	function recomputeSongEnd():Void
	{
		var end:Float = 0;
		if (audioOk && music != null && music.length > 0)
			end = music.length;
		if (end <= 0 && sections != null && sections.length > 0)
		{
			var bpm:Float = notesSong != null && notesSong.bpm > 0 ? notesSong.bpm : 100;
			end = sections.length * 4 * (60000 / bpm);
		}
		songEndMs = Math.max(end, 1000);
		songLength = songEndMs;
	}

	function sortEvents():Void
	{
		events.sort(function(a:EdEvent, b:EdEvent):Int {
			if (a.time > b.time) return 1;
			if (a.time < b.time) return -1;
			return 0;
		});
		tlDirty = true;
	}

	function refreshLayerVisibility():Void
	{
		var n:Int = backend.CameraEditorData.layerCount();
		while (layersVisible.length < n)
			layersVisible.push(true);
		while (layersVisible.length > n)
			layersVisible.pop();
	}

	function recomputeLayerH():Void
	{
		var avail:Float = timelineAreaH - TOOLBAR_H - SCROLLBAR_H - RULER_H - STRUM_H - 24;
		layerH = Math.max(24, Math.min(46, avail / backend.CameraEditorData.layerCount()));
	}

	// ================= 舞台预览 =================

	function buildStagePreview():Void
	{
		var bfPos:Array<Dynamic> = stageData.boyfriend != null ? stageData.boyfriend : [770, 100];
		var gfPos:Array<Dynamic> = stageData.girlfriend != null ? stageData.girlfriend : [400, 130];
		var dadPos:Array<Dynamic> = stageData.opponent != null ? stageData.opponent : [100, 100];
		var gfX:Float = Std.parseFloat(Std.string(gfPos[0]));
		var gfY:Float = Std.parseFloat(Std.string(gfPos[1]));

		// ⚠ 先舞台后角色（真机铁律：舞台 bg 后 add 会盖住角色）
		switch (curStageName)
		{
			case 'stage': tryStage('StageWeek1');
			case 'tcm': tryStage('StageTcm');
			case 'spooky': tryStage('Spooky');
			case 'philly': tryStage('Philly');
			case 'limo': tryStage('Limo');
			case 'mall': tryStage('Mall');
			case 'mallEvil': tryStage('MallEvil');
			case 'school': tryStage('School');
			case 'schoolEvil': tryStage('SchoolEvil');
			case 'tank': tryStage('Tank');
			case 'phillyStreets': tryStage('PhillyStreets');
			case 'phillyBlazin': tryStage('PhillyBlazin');
			default:
		}

		add(gfGroup);
		add(dadGroup);
		add(boyfriendGroup);
		boyfriendGroup.setPosition(Std.parseFloat(Std.string(bfPos[0])), Std.parseFloat(Std.string(bfPos[1])));
		dadGroup.setPosition(Std.parseFloat(Std.string(dadPos[0])), Std.parseFloat(Std.string(dadPos[1])));
		gfGroup.setPosition(gfX, gfY);

		var gfHidden:Bool = stageData.hide_girlfriend == true;
		if (!gfHidden)
		{
			var gfName:String = notesSong.gfVersion;
			if (gfName == null || gfName.length < 1) gfName = 'gf';
			gf = new Character(0, 0, gfName);
			gf.x += gf.positionArray[0];
			gf.y += gf.positionArray[1];
			gf.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
		}

		var dadName:String = notesSong.player2 != null && notesSong.player2.length > 0 ? notesSong.player2 : 'dad';
		dad = new Character(0, 0, dadName);
		if (dad.curCharacter.startsWith('gf'))
		{
			dad.setPosition(gfX, gfY);
			if (gf != null) gf.visible = false;
		}
		else
		{
			dad.x += dad.positionArray[0];
			dad.y += dad.positionArray[1];
			dad.danceEveryNumBeats = 2;
		}
		dadGroup.add(dad);

		var bfName:String = notesSong.player1 != null && notesSong.player1.length > 0 ? notesSong.player1 : 'bf';
		boyfriend = new Character(0, 0, bfName, true);
		boyfriend.x += boyfriend.positionArray[0];
		boyfriend.y += boyfriend.positionArray[1];
		boyfriendGroup.add(boyfriend);

		// 舞台侧成员显式挂预览相机（null 相机成员会落到默认的 camUI 上）
		assignStageCameras();

		for (st in stages)
			st.createPost();
	}

	function assignStageCameras():Void
	{
		var uiSet:Map<FlxBasic, Bool> = new Map<FlxBasic, Bool>();
		if (uiLayer != null)
			for (m in uiLayer.members)
				if (m != null) uiSet.set(m, true);
		for (m in members)
		{
			// ⚠ 必须跳过 uiLayer 本身：它也是 state member——不跳的话整个 UI 组会被
			// 翻成舞台相机（resize 重建路径在 uiLayer.cameras=[camUI] 之后又跑本函数，
			// 全部 UI 成员回到 camGame → UI 缩成小块，真机复现）
			if (m == null || m == uiLayer || m == camFollow || uiSet.exists(m)) continue;
			m.cameras = [camGame];
		}
	}

	function tryStage(cls:String):Void
	{
		try
		{
			switch (cls)
			{
				case 'StageWeek1': new states.stages.StageWeek1();
				case 'StageTcm': new states.stages.StageTcm();
				case 'Spooky': new states.stages.Spooky();
				case 'Philly': new states.stages.Philly();
				case 'Limo': new states.stages.Limo();
				case 'Mall': new states.stages.Mall();
				case 'MallEvil': new states.stages.MallEvil();
				case 'School': new states.stages.School();
				case 'SchoolEvil': new states.stages.SchoolEvil();
				case 'Tank': new states.stages.Tank();
				case 'PhillyStreets': new states.stages.PhillyStreets();
				case 'PhillyBlazin': new states.stages.PhillyBlazin();
				default:
			}
		}
		catch (e:Dynamic)
		{
			trace('[Choreo] 舞台 ' + cls + ' 挂接中断（部分背景可用）：' + Std.string(e));
		}
	}

	function rebuildStageOnly():Void
	{
		for (st in stages)
		{
			try
			{
				st.destroy();
			}
			catch (e:Dynamic) {}
		}
		stages = [];
		gfGroup.clear();
		dadGroup.clear();
		boyfriendGroup.clear();
		gf = null;
		dad = null;
		boyfriend = null;
		if (notesSong != null)
			buildStagePreview();
		assignStageCameras();
	}

	// ================= 音频 =================

	function loadAudio():Void
	{
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if (voices != null)
		{
			voices.stop();
			voices.destroy();
			voices = null;
		}
		try
		{
			FlxG.sound.playMusic(Paths.inst(songPath), 0.6);
			FlxG.sound.music.autoDestroy = false;
			FlxG.sound.music.pause();
			music = FlxG.sound.music;
			audioOk = true;
		}
		catch (e:Dynamic)
		{
			trace('[Choreo] inst 加载失败: ' + Std.string(e));
			music = null;
			audioOk = false;
		}
		try
		{
			var file:Dynamic = Paths.voices(songPath);
			if (Std.isOfType(file, Sound) || Assets.exists(file))
			{
				voices = new FlxSound();
				voices.loadEmbedded(file);
				voices.autoDestroy = false;
				FlxG.sound.list.add(voices);
			}
		}
		catch (e:Dynamic)
		{
			voices = null;
		}
		recomputeSongEnd();
	}

	function togglePlay():Void
	{
		if (playing)
		{
			playing = false;
			if (music != null) music.pause();
			if (voices != null && voices.exists) voices.pause();
		}
		else
		{
			if (music == null || !audioOk)
			{
				showMsg(Lang.tOr('choreo.noAudio', '无音频可播放'));
				return;
			}
			if (cursorMs >= songEndMs - 100)
			{
				cursorMs = 0;
				seek(0);
			}
			music.time = cursorMs;
			if (voices != null && voices.exists) voices.time = cursorMs;
			music.play();
			if (voices != null && voices.exists) voices.play();
			playing = true;
			applyPendingEvents(true);
			lastBeatDance = -1;
			lastStepHit = -1;
		}
		if (playBtn != null)
			playBtn.label.text = playing ? Lang.tOr('choreo.pause', '暂停') : Lang.tOr('choreo.play', '播放');
	}

	function seek(t:Float):Void
	{
		if (t < 0) t = 0;
		if (t > songEndMs) t = songEndMs;
		cursorMs = t;
		if (music != null) music.time = t;
		if (voices != null && voices.exists) voices.time = t;
		// seek = 全量重模拟（瞬时落位，DCE simulateCameraAt 语义）
		simulateCameraAt(cursorMs);
		lastBeatDance = Std.int(Math.floor(beatAt(t)));
		lastStepHit = Std.int(Math.floor(stepAt(t)));
	}

	function stopPlayback():Void
	{
		playing = false;
		if (music != null) music.pause();
		if (voices != null && voices.exists) voices.pause();
		seek(0);
		if (playBtn != null)
			playBtn.label.text = Lang.tOr('choreo.play', '播放');
	}

	// ================= 时间 / BPM =================

	function bpmAt(t:Float):Float
	{
		if (notesSong == null) return 100;
		var bpm:Float = notesSong.bpm > 0 ? notesSong.bpm : 100;
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (t >= Conductor.bpmChangeMap[i].songTime)
				bpm = Conductor.bpmChangeMap[i].bpm;
		}
		return bpm;
	}

	function beatAt(t:Float):Float
	{
		var beat:Float = t / beatLenMs(bpmAt(0));
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			var ch:BPMChangeEvent = Conductor.bpmChangeMap[i];
			if (t >= ch.songTime)
				beat = ch.stepTime / 4 + (t - ch.songTime) / beatLenMs(ch.bpm);
		}
		return beat;
	}

	function timeOfBeat(b:Float):Float
	{
		var t:Float = b * beatLenMs(bpmAt(0));
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			var ch:BPMChangeEvent = Conductor.bpmChangeMap[i];
			var chBeat:Float = ch.stepTime / 4;
			if (b >= chBeat)
				t = ch.songTime + (b - chBeat) * beatLenMs(ch.bpm);
		}
		return t;
	}

	function stepAt(t:Float):Float
	{
		return beatAt(t) * 4;
	}

	function beatLenMs(bpm:Float):Float
	{
		return bpm > 0 ? 60000 / bpm : 500;
	}

	function sectionAt(t:Float):Int
	{
		var sec:Int = Std.int(Math.floor(beatAt(t) / 4));
		if (sec < 0) sec = 0;
		return sec;
	}

	function snapTime(t:Float):Float
	{
		// DCE：Shift 反转吸附
		var wantSnap:Bool = snapEnabled != FlxG.keys.pressed.SHIFT;
		if (!wantSnap) return t;
		var b:Float = beatAt(t);
		var sb:Float = Math.round(b * quantSteps) / quantSteps;
		var st:Float = timeOfBeat(sb);
		if (st < 0) st = 0;
		return st;
	}

	function fmtTime(t:Float):String
	{
		if (t < 0) t = 0;
		var s:Float = t / 1000;
		var m:Int = Std.int(s / 60);
		var ss:Float = s - m * 60;
		return m + ':' + (ss < 10 ? '0' : '') + FlxMath.roundDecimal(ss, 2);
	}

	// ================= vcam 模拟 =================

	function followPointFor(target:String):Void
	{
		if (target == 'gf')
		{
			if (gf != null)
			{
				vcamFollowX = gf.getMidpoint().x + gf.cameraPosition[0] + gfArrF(stageData.camera_girlfriend, 0);
				vcamFollowY = gf.getMidpoint().y + gf.cameraPosition[1] + gfArrF(stageData.camera_girlfriend, 1);
			}
			return;
		}
		if (target == 'bf')
		{
			if (boyfriend != null)
			{
				vcamFollowX = boyfriend.getMidpoint().x - 100 - boyfriend.cameraPosition[0] + gfArrF(stageData.camera_boyfriend, 0);
				vcamFollowY = boyfriend.getMidpoint().y - 100 + boyfriend.cameraPosition[1] + gfArrF(stageData.camera_boyfriend, 1);
			}
			return;
		}
		if (dad != null)
		{
			vcamFollowX = dad.getMidpoint().x + 150 + dad.cameraPosition[0] + gfArrF(stageData.camera_opponent, 0);
			vcamFollowY = dad.getMidpoint().y - 100 + dad.cameraPosition[1] + gfArrF(stageData.camera_opponent, 1);
		}
	}

	function gfArrF(arr:Array<Dynamic>, idx:Int):Float
	{
		if (arr == null || arr.length <= idx || arr[idx] == null) return 0;
		var v:Float = Std.parseFloat(Std.string(arr[idx]));
		return Math.isNaN(v) ? 0 : v;
	}

	/** 全量重模拟：重置到基线 → 重放 ≤t 的全部事件（瞬时落位）。 */
	function simulateCameraAt(t:Float):Void
	{
		vcamZoom = defaultCamZoom;
		vcamAngle = 0;
		vcamHasFollow = false;
		zoomTween = null;
		angleTween = null;
		followTween = null;
		var secIdx:Int = sectionAt(t);
		var sec:SwagSection = secIdx < sections.length ? sections[secIdx] : null;
		if (sec != null && sec.gfSection && gf != null)
			followPointFor('gf');
		else if (sec == null || sec.mustHitSection != false)
			followPointFor('bf');
		else
			followPointFor('dad');
		vcamScrollX = vcamFollowX;
		vcamScrollY = vcamFollowY;

		for (ev in events)
		{
			if (ev.time > t + 0.01) break;
			applyEvent(ev, true);
		}
	}

	/** 增量触发（播放用）。 */
	function applyPendingEvents(reset:Bool):Void
	{
		if (reset)
		{
			triggeredFlags = [];
			for (i in 0...events.length)
				triggeredFlags.push(events[i].time <= cursorMs);
			return;
		}
		for (i in 0...events.length)
		{
			var ev:EdEvent = events[i];
			var fired:Bool = i < triggeredFlags.length ? triggeredFlags[i] : false;
			if (!fired && ev.time <= cursorMs)
			{
				applyEvent(ev, false);
				triggeredFlags[i] = true;
			}
			else if (fired && ev.time > cursorMs)
			{
				triggeredFlags[i] = false;
			}
		}
	}

	function numOr(s:String, def:Float):Float
	{
		var v:Float = Std.parseFloat(StringTools.trim(s));
		return Math.isFinite(v) ? v : def;
	}

	function normEventName(name:String):String
	{
		var n:String = name.toLowerCase();
		var out:String = '';
		for (i in 0...n.length)
		{
			var c:String = n.charAt(i);
			if (c != ' ' && c != '_' && c != '-') out += c;
		}
		return out;
	}

	/** 应用单个事件到 vcam（instant = 跳过缓动直接落位）。 */
	function applyEvent(ev:EdEvent, instant:Bool):Void
	{
		var nn:String = normEventName(ev.name);
		switch (nn)
		{
			case 'focuscamera':
			{
				var tx:Float = 0;
				var ty:Float = 0;
				var spec:String = ev.v1.toLowerCase().trim();
				if (spec == 'bf' || spec == 'boyfriend')
				{
					if (boyfriend != null)
					{
						tx = boyfriend.getMidpoint().x - 100 - boyfriend.cameraPosition[0] + gfArrF(stageData.camera_boyfriend, 0);
						ty = boyfriend.getMidpoint().y - 100 + boyfriend.cameraPosition[1] + gfArrF(stageData.camera_boyfriend, 1);
					}
				}
				else if (spec == 'dad' || spec == 'opponent')
				{
					if (dad != null)
					{
						tx = dad.getMidpoint().x + 150 + dad.cameraPosition[0] + gfArrF(stageData.camera_opponent, 0);
						ty = dad.getMidpoint().y - 100 + dad.cameraPosition[1] + gfArrF(stageData.camera_opponent, 1);
					}
				}
				else if (spec == 'gf' || spec == 'girlfriend')
				{
					if (gf != null)
					{
						tx = gf.getMidpoint().x + gf.cameraPosition[0] + gfArrF(stageData.camera_girlfriend, 0);
						ty = gf.getMidpoint().y + gf.cameraPosition[1] + gfArrF(stageData.camera_girlfriend, 1);
					}
				}
				var parts:Array<String> = ev.v2.split(',');
				var ox:Float = parts.length > 0 ? numOr(parts[0], 0) : 0;
				var oy:Float = parts.length > 1 ? numOr(parts[1], 0) : 0;
				tx += ox;
				ty += oy;
				vcamFollowX = tx;
				vcamFollowY = ty;
				vcamHasFollow = true;
				applyFollowTween(ev.v2, 2, 3, instant, tx, ty, 'CLASSIC');
			}
			case 'camerafollowpos':
			{
				var parts:Array<String> = ev.v2.split(',');
				var hasX:Bool = ev.v1.trim().length > 0 && Math.isFinite(Std.parseFloat(ev.v1));
				var hasY:Bool = parts.length > 0 && ev.v2.trim().length > 0 && Math.isFinite(Std.parseFloat(parts[0]));
				if (!hasX && !hasY)
				{
					vcamHasFollow = false;
				}
				else
				{
					var fx:Float = hasX ? Std.parseFloat(ev.v1) : 0;
					var fy:Float = hasY ? numOr(parts[0], 0) : 0;
					vcamFollowX = fx;
					vcamFollowY = fy;
					vcamHasFollow = true;
					applyFollowTween(ev.v2, 1, 2, instant, fx, fy, 'quadInOut');
				}
			}
			case 'zoomcamera':
			{
				var zt:Float = Math.isFinite(Std.parseFloat(ev.v1)) ? Std.parseFloat(ev.v1) : defaultCamZoom;
				var parts:Array<String> = ev.v2.split(',');
				var mode:String = parts.length > 2 ? parts[2].trim().toLowerCase() : 'direct';
				if (mode == 'stage') zt *= defaultCamZoom;
				zt = FlxMath.bound(zt, 0.05, 5);
				applyZoomTween(ev.v2, 0, 1, instant, zt, 'linear');
			}
			case 'addcamerazoom':
			{
				var add:Float = ev.v1.trim().length > 0 ? numOr(ev.v1, 0.015) : 0.015;
				vcamZoom = FlxMath.bound(vcamZoom + add, 0.05, 5);
			}
			case 'cameraangle':
			{
				var at:Float = Math.isFinite(Std.parseFloat(ev.v1)) ? Std.parseFloat(ev.v1) : 0;
				at = FlxMath.bound(at, -3600, 3600);
				var parts:Array<String> = ev.v2.split(',');
				var dur:Float = parts.length > 0 ? numOr(parts[0], 0.3) : 0.3;
				var easeName:String = parts.length > 1 ? parts[1].trim() : 'quadOut';
				if (instant || dur <= 0.001 || ChoreoEase.isSnapToken(easeName))
				{
					vcamAngle = at;
					angleTween = null;
				}
				else
				{
					angleTween = {a: vcamAngle, b: at, t: 0, dur: Math.min(600, dur), fn: ChoreoEase.resolve(easeName)};
				}
			}
			case 'playanimation':
			{
				var char:Character = dad;
				var spec:String = ev.v2.toLowerCase().trim();
				if (spec == 'bf' || spec == 'boyfriend') char = boyfriend;
				else if (spec == 'gf' || spec == 'girlfriend') char = gf;
				if (char != null && char.animation.getByName(ev.v1) != null)
				{
					char.playAnim(ev.v1, true);
					char.specialAnim = true;
				}
			}
			default:
		}
	}

	function applyFollowTween(v2:String, durIdx:Int, easeIdx:Int, instant:Bool, tx:Float, ty:Float, defEase:String):Void
	{
		var parts:Array<String> = v2.split(',');
		var dur:Float = parts.length > durIdx ? numOr(parts[durIdx], -1) : -1;
		var easeName:String = parts.length > easeIdx ? parts[easeIdx].trim() : defEase;
		if (instant || dur <= 0.001 || ChoreoEase.isSnapToken(easeName))
		{
			vcamScrollX = tx;
			vcamScrollY = ty;
			followTween = null;
		}
		else
		{
			followTween = {ax: vcamScrollX, ay: vcamScrollY, bx: tx, by: ty, t: 0, dur: Math.min(600, dur), fn: ChoreoEase.resolve(easeName)};
		}
	}

	function applyZoomTween(v2:String, durIdx:Int, easeIdx:Int, instant:Bool, target:Float, defEase:String):Void
	{
		var parts:Array<String> = v2.split(',');
		var dur:Float = parts.length > durIdx ? numOr(parts[durIdx], -1) : -1;
		var easeName:String = parts.length > easeIdx ? parts[easeIdx].trim() : defEase;
		if (instant || dur <= 0.001 || ChoreoEase.isSnapToken(easeName))
		{
			vcamZoom = target;
			zoomTween = null;
		}
		else
		{
			zoomTween = {a: vcamZoom, b: target, t: 0, dur: Math.min(600, dur), fn: ChoreoEase.resolve(easeName)};
		}
	}

	/** vcam 推进：缓动插值 + 跟随点 lerp（DCE stepVirtualCamera：l = clamp(elapsed*7, 0.03, 1)）。 */
	function stepVirtualCamera(elapsed:Float):Void
	{
		if (zoomTween != null)
		{
			zoomTween.t += elapsed;
			var p:Float = zoomTween.dur > 0 ? FlxMath.bound(zoomTween.t / zoomTween.dur, 0, 1) : 1;
			var e:Float = zoomTween.fn != null ? zoomTween.fn(p) : p;
			vcamZoom = zoomTween.a + (zoomTween.b - zoomTween.a) * e;
			if (p >= 1) zoomTween = null;
		}
		if (angleTween != null)
		{
			angleTween.t += elapsed;
			var p:Float = angleTween.dur > 0 ? FlxMath.bound(angleTween.t / angleTween.dur, 0, 1) : 1;
			var e:Float = angleTween.fn != null ? angleTween.fn(p) : p;
			vcamAngle = angleTween.a + (angleTween.b - angleTween.a) * e;
			if (p >= 1) angleTween = null;
		}
		if (followTween != null)
		{
			followTween.t += elapsed;
			var p:Float = followTween.dur > 0 ? FlxMath.bound(followTween.t / followTween.dur, 0, 1) : 1;
			var e:Float = followTween.fn != null ? followTween.fn(p) : p;
			vcamScrollX = followTween.ax + (followTween.bx - followTween.ax) * e;
			vcamScrollY = followTween.ay + (followTween.by - followTween.ay) * e;
			if (p >= 1) followTween = null;
		}
		else if (vcamHasFollow)
		{
			var l:Float = FlxMath.bound(elapsed * 7, 0.03, 1);
			vcamScrollX += (vcamFollowX - vcamScrollX) * l;
			vcamScrollY += (vcamFollowY - vcamScrollY) * l;
		}
	}

	/** 把 vcam 状态映射到舞台预览相机。
	 *  ⚠ 必须写 camGame 而不是 FlxG.camera——相机角色翻转后 FlxG.camera=UI 相机（zoom 恒 1），
	 *  写它会把整个 UI 缩成小方块（用户截图「UI 缩在中间 + 舞台巨大化」的根因）。 */
	function applyViewfinder():Void
	{
		var camZoom:Float = previewZoom * vcamZoom / vfWinScale;
		if (camZoom <= 0) camZoom = 0.01;
		camGame.zoom = camZoom;
		camGame.angle = vcamAngle;
		// 居中公式与 flixel focusOn 一致：scroll = 焦点 - width/2（缩放由渲染层补偿，
		// 不能再除以 zoom——多除会把取景推到舞台外，用户实测「映射到右下角屁都看不见」根因）
		camGame.scroll.set(vcamScrollX - FlxG.width * 0.5, vcamScrollY - FlxG.height * 0.5);
	}

	/** 取景框屏幕矩形（框屏幕尺寸 = 1280×720×previewZoom，中心 = 预览区中心）。 */
	function viewfinderRect():FlxRect
	{
		var pw:Float = FlxG.width * previewZoom;
		var ph:Float = FlxG.height * previewZoom;
		var cx:Float = timelineRight * 0.5;
		var cy:Float = TOP_H + (timelineTop - TOP_H - PREVIEW_GAP) * 0.5;
		return FlxRect.get(cx - pw / 2, cy - ph / 2, pw, ph);
	}

	function updateFrameOverlay():Void
	{
		var r:FlxRect = viewfinderRect();
		var th:Float = 2;
		frameLines[0].setPosition(r.x, r.y);
		frameLines[0].scale.set(r.width, th);
		frameLines[1].setPosition(r.x, r.y + r.height - th);
		frameLines[1].scale.set(r.width, th);
		frameLines[2].setPosition(r.x, r.y);
		frameLines[2].scale.set(th, r.height);
		frameLines[3].setPosition(r.x + r.width - th, r.y);
		frameLines[3].scale.set(th, r.height);
		for (i in 0...4)
		{
			var hx:Float = (i % 2 == 0) ? r.x : r.x + r.width - 12;
			var hy:Float = (i < 2) ? r.y : r.y + r.height - 12;
			cornerTicks[i].setPosition(hx, hy);
			cornerTicks[i].scale.set(12, 3);
		}
		// 框外暗化（passepartout α0.5）
		var showPp:Bool = passepartoutOn && previewZoom < 0.999;
		var topGap:Float = Math.max(0, r.y - TOP_H);
		passeParts[0].visible = showPp && topGap > 0;
		passeParts[0].setPosition(0, TOP_H);
		passeParts[0].scale.set(FlxG.width, topGap);
		var botGap:Float = Math.max(0, (timelineTop - 26) - (r.y + r.height));
		passeParts[1].visible = showPp && botGap > 0;
		passeParts[1].setPosition(0, r.y + r.height);
		passeParts[1].scale.set(FlxG.width, botGap);
		var leftGap:Float = Math.max(0, r.x);
		passeParts[2].visible = showPp && leftGap > 0;
		passeParts[2].setPosition(0, r.y);
		passeParts[2].scale.set(leftGap, r.height);
		var rightGap:Float = Math.max(0, timelineRight - (r.x + r.width));
		passeParts[3].visible = showPp && rightGap > 0;
		passeParts[3].setPosition(r.x + r.width, r.y);
		passeParts[3].scale.set(rightGap, r.height);
		var k:Float = previewZoom * vcamZoom / vfWinScale;
		var dx:Float = (vcamFollowX - vcamScrollX) * k;
		var dy:Float = (vcamFollowY - vcamScrollY) * k;
		followDot.setPosition(r.x + r.width / 2 + dx - 5, r.y + r.height / 2 + dy - 5);
		followDot.visible = vcamHasFollow;
		r.put();
	}

	// ================= 文档操作 =================

	function resetSelection():Void
	{
		selectedIndexes = [];
	}

	function primaryIndex():Int
	{
		return selectedIndexes.length > 0 ? selectedIndexes[selectedIndexes.length - 1] : -1;
	}

	function snapshotEvents():Array<EdEvent>
	{
		return [for (ev in events) {time: ev.time, name: ev.name, v1: ev.v1, v2: ev.v2, layer: ev.layer, source: ev.source}];
	}

	function pushUndo():Void
	{
		undoStack.push(snapshotEvents());
		if (undoStack.length > MAX_UNDO)
			undoStack.shift();
		redoStack = [];
	}

	function undo():Void
	{
		if (undoStack.length <= 0) return;
		redoStack.push(snapshotEvents());
		events = undoStack.pop();
		resetSelection();
		markDirty();
		simulateCameraAt(cursorMs);
	}

	function redo():Void
	{
		if (redoStack.length <= 0) return;
		undoStack.push(snapshotEvents());
		events = redoStack.pop();
		resetSelection();
		markDirty();
		simulateCameraAt(cursorMs);
	}

	function markDirty():Void
	{
		hasUnsaved = true;
		sortEvents();
		refreshPanelFromSelection();
		tlDirty = true;
	}

	function addEventAt(t:Float, name:String, v1:String, v2:String, ?layerOverride:Int = -1):Void
	{
		pushUndo();
		var layer:Int = layerOverride >= 0 ? layerOverride : backend.CameraEditorData.layerOf(name);
		var src:String = backend.CameraEditorData.isManaged(name) ? 'camera' : 'chart';
		events.push({time: t, name: name, v1: v1, v2: v2, layer: layer, source: src});
		sortEvents();
		for (i in 0...events.length)
		{
			if (events[i].time == t && events[i].name == name && events[i].v1 == v1)
			{
				selectedIndexes = [i];
				break;
			}
		}
		markDirty();
		simulateCameraAt(cursorMs);
	}

	function deleteSelection():Void
	{
		if (selectedIndexes.length <= 0)
		{
			showMsg(Lang.tOr('choreo.noSelection', '未选中事件（点击时间轴中的事件卡）'));
			return;
		}
		pushUndo();
		var kill:Array<Int> = selectedIndexes.copy();
		kill.sort(function(a:Int, b:Int):Int { return b - a; });
		for (idx in kill)
			if (idx >= 0 && idx < events.length)
				events.splice(idx, 1);
		resetSelection();
		markDirty();
		simulateCameraAt(cursorMs);
	}

	function copySelection():Void
	{
		if (selectedIndexes.length <= 0)
		{
			showMsg(Lang.tOr('choreo.noSelection', '未选中事件（点击时间轴中的事件卡）'));
			return;
		}
		clipboardEvents = [];
		var idxs:Array<Int> = selectedIndexes.copy();
		idxs.sort(function(a:Int, b:Int):Int { return events[a].time < events[b].time ? -1 : 1; });
		for (idx in idxs)
		{
			var ev:EdEvent = events[idx];
			clipboardEvents.push({time: ev.time, name: ev.name, v1: ev.v1, v2: ev.v2, layer: ev.layer, source: ev.source});
		}
		showMsg(Lang.tOr('choreo.copied', '已复制') + ' ' + clipboardEvents.length + Lang.tOr('choreo.evtUnit', ' 项'));
	}

	function pasteClipboard():Void
	{
		if (clipboardEvents.length <= 0)
		{
			showMsg(Lang.tOr('choreo.pasteEmpty', '剪贴板为空'));
			return;
		}
		pushUndo();
		var base:Float = clipboardEvents[0].time;
		selectedIndexes = [];
		for (src in clipboardEvents)
		{
			var t:Float = snapTime(cursorMs + (src.time - base));
			events.push({time: t, name: src.name, v1: src.v1, v2: src.v2, layer: src.layer, source: src.source});
			for (i in 0...events.length)
			{
				if (events[i].time == t && events[i].name == src.name && events[i].v1 == src.v1)
				{
					selectedIndexes.push(i);
					break;
				}
			}
		}
		sortEvents();
		markDirty();
		simulateCameraAt(cursorMs);
	}

	function duplicateSelection():Void
	{
		var pi:Int = primaryIndex();
		if (pi < 0) return;
		pushUndo();
		var bar:Float = 4 * beatLenMs(bpmAt(events[pi].time));
		var src:EdEvent = events[pi];
		var t:Float = snapTime(src.time + bar);
		events.push({time: t, name: src.name, v1: src.v1, v2: src.v2, layer: src.layer, source: src.source});
		sortEvents();
		for (i in 0...events.length)
		{
			if (events[i].time == t && events[i].name == src.name && events[i].v1 == src.v1)
			{
				selectedIndexes = [i];
				break;
			}
		}
		markDirty();
	}

	function selectAll():Void
	{
		selectedIndexes = [];
		for (i in 0...events.length)
			selectedIndexes.push(i);
		redrawLayerHead();
		tlDirty = true;
	}

	// ================= 保存 =================

	function syncData():Void
	{
		var saved:String = backend.CameraEditorData.saveCamEvents(events, songPath);
		if (saved != null)
		{
			hasUnsaved = false;
			showMsg(Lang.tOr('choreo.saved', '事件已保存'));
			trace('[Choreo] cam.json 已保存: ' + saved);
		}
		else
		{
			showMsg(Lang.tOr('choreo.saveFail', '保存失败（谱面目录不可写）'));
		}
	}

	function saveWithBackup():Void
	{
		backend.CameraEditorData.writeBackup(events, songPath);
		syncData();
	}

	// ================= UI 构建 =================

	/** 按文本测宽的按钮宽度（防英文长标签换行——v2 首版 Auto Scroll 换 3 行的教训） */
	function btnW(text:String, minW:Float):Float
	{
		var m = mkText(0, 0, 14, 0xFFFFFFFF);
		m.text = text;
		var w:Float = Math.max(minW, m.width + 20);
		m.destroy();
		return w;
	}

	function mkText(x:Float, y:Float, size:Int, color:Int):FlxText
	{
		var t = new FlxText(x, y, 0, '', size);
		t.setFormat(Paths.font('future.ttf'), size, color, flixel.text.FlxText.FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.wordWrap = false;
		t.textField.x = 1;
		t.textField.y = 1;
		t.antialiasing = ClientPrefs.data.antialiasing;
		t.scrollFactor.set();
		return t;
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 12, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		var spr = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		spr.antialiasing = ClientPrefs.data.antialiasing;
		spr.scrollFactor.set();
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill, {color: border, thickness: 1.5});
		return spr;
	}

	function buildUI():Void
	{
		// 几何（全部 FlxG.width/height 派生——MeteoricScaleMode 下逻辑分辨率随窗口变，禁硬编码）
		timelineTop = FlxG.height - timelineAreaH;
		tlTop = timelineTop + TOOLBAR_H + SCROLLBAR_H;
		layerRowY = tlTop + RULER_H;
		timelineRight = FlxG.width - RIGHT_W - 16;
		timelineX = LAYER_LABEL_W;
		recomputeLayerH();
		strumY = layerRowY + backend.CameraEditorData.layerCount() * layerH + 10;

		// mockup（Adobe Style v4）配色：底 #222 / 面板 #1e1e1e / 边 #3f3f3f
		var underlay:Int = 0xF2222222;
		var topBack:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, Std.int(TOP_H), underlay, true);
		uiLayer.add(topBack);
		var bottomBack:FlxSprite = new FlxSprite(0, timelineTop).makeGraphic(FlxG.width, Std.int(timelineAreaH), underlay, true);
		uiLayer.add(bottomBack);
		var rightBack:FlxSprite = new FlxSprite(timelineRight + 8, TOP_H).makeGraphic(Std.int(FlxG.width - timelineRight - 8), Std.int(timelineTop - TOP_H), underlay, true);
		uiLayer.add(rightBack);
		var infoBack:FlxSprite = new FlxSprite(0, timelineTop - 26).makeGraphic(Std.int(timelineRight), 26, 0xF21B1B1B, true);
		uiLayer.add(infoBack);

		// ===== 菜单条 =====
		menuDefs = [
			{label: Lang.tOr('choreo.menuFile', '文件'), items: [
				{label: Lang.tOr('choreo.save', '保存'), cb: saveWithBackup},
				{label: Lang.tOr('choreo.reload', '重新加载'), cb: reloadAll}
			]},
			{label: Lang.tOr('choreo.menuEdit', '编辑'), items: [
				{label: Lang.tOr('choreo.undo', '撤销'), cb: undo},
				{label: Lang.tOr('choreo.redo', '重做'), cb: redo},
				{label: Lang.tOr('choreo.copy', '复制'), cb: copySelection},
				{label: Lang.tOr('choreo.paste', '粘贴'), cb: pasteClipboard},
				{label: Lang.tOr('choreo.dup', '副本到下一小节'), cb: duplicateSelection},
				{label: Lang.tOr('choreo.del', '删除'), cb: deleteSelection},
				{label: Lang.tOr('choreo.selAll', '全选'), cb: selectAll}
			]},
			{label: Lang.tOr('choreo.menuTimeline', '时间轴'), items: [
				{label: Lang.tOr('choreo.toStart', '回到开头'), cb: function() { seek(0); }},
				{label: Lang.tOr('choreo.toEnd', '跳到末尾'), cb: function() { seek(songEndMs); }},
				{label: Lang.tOr('choreo.fit', '适配'), cb: fitZoom}
			]},
			{label: Lang.tOr('choreo.menuCamera', '相机'), items: [
				{label: Lang.tOr('choreo.resetScroll', '回正镜头位置'), cb: function() { vcamScrollX = vcamFollowX; vcamScrollY = vcamFollowY; followTween = null; }},
				{label: Lang.tOr('choreo.resetZoom', '回正镜头缩放'), cb: function() { vcamZoom = defaultCamZoom; zoomTween = null; }},
				{label: Lang.tOr('choreo.resetAngle', '回正镜头角度'), cb: function() { vcamAngle = 0; angleTween = null; }}
			]},
			{label: Lang.tOr('choreo.menuView', '视图'), items: [
				{label: Lang.tOr('choreo.showPasse', '显示/隐藏 框外暗化'), cb: togglePassepartout}
			]},
			{label: Lang.tOr('choreo.menuHelp', '帮助'), items: [
				{label: Lang.tOr('choreo.helpKeys', '操作说明'), cb: showHelp}
			]}
		];
		var mx:Float = 10;
		for (mi in 0...menuDefs.length)
		{
			var label:FlxText = mkText(mx, 6, 15, 0xFFD7D7E0);
			label.text = menuDefs[mi].label;
			uiLayer.add(label);
			menuRects.push(new FlxRect(mx - 6, 2, label.width + 12, 24));
			mx += label.width + 22;
		}

		// ===== 状态行 =====
		statusTxt = mkText(10, 36, 14, 0xFFB8B8C8);
		uiLayer.add(statusTxt);

		// ===== 取景框 overlay =====
		for (i in 0...4)
		{
			var line = new FlxSprite().makeGraphic(1, 1, 0xFF7ABFBC, true);
			line.alpha = 0.8;
			uiLayer.add(line);
			frameLines.push(line);
		}
		for (i in 0...4)
		{
			var tick = new FlxSprite().makeGraphic(1, 1, 0xFF7ABFBC, true);
			uiLayer.add(tick);
			cornerTicks.push(tick);
		}
		for (i in 0...4)
		{
			var pp = new FlxSprite().makeGraphic(1, 1, 0x80000000, true);
			uiLayer.add(pp);
			passeParts.push(pp);
		}
		followDot = new FlxSprite().makeGraphic(10, 10, 0xFFFF4A4A, true);
		followDot.antialiasing = ClientPrefs.data.antialiasing;
		uiLayer.add(followDot);
		boxRect = new FlxSprite().makeGraphic(1, 1, 0xFF5BA3FF, true);
		boxRect.alpha = 0.25;
		boxRect.visible = false;
		uiLayer.add(boxRect);

		// ===== 预览信息行 =====
		infoTxt = mkText(10, timelineTop - 22, 13, 0xFF9A9AA8);
		uiLayer.add(infoTxt);

		// ===== 时间轴工具栏 =====
		var tx:Float = 10;
		timeTxt = mkText(tx, timelineTop + 10, 15, 0xFFE8E8F0);
		uiLayer.add(timeTxt);
		tx += 150;
		playBtn = new EditorButton(tx, timelineTop + 5, btnW(Lang.tOr('choreo.play', '播放'), 60), 28, Lang.tOr('choreo.play', '播放'), togglePlay);
		uiLayer.add(playBtn);
		tx += playBtn.width + 8;
		autoScrollBtn = new EditorButton(tx, timelineTop + 5, btnW(autoScrollLabel(), 84), 28, autoScrollLabel(), function() {
			autoScrollMode = (autoScrollMode + 1) % 3;
			autoScrollBtn.label.text = autoScrollLabel();
		});
		uiLayer.add(autoScrollBtn);
		tx += autoScrollBtn.width + 8;
		snapBtn = new EditorButton(tx, timelineTop + 5, btnW(snapLabel(), 84), 28, snapLabel(), function() {
			quantSteps = nextQuant(quantSteps, 1);
			snapBtn.label.text = snapLabel();
		});
		uiLayer.add(snapBtn);
		tx += snapBtn.width + 12;
		zoomMinusBtn = new EditorButton(tx, timelineTop + 5, 24, 28, '-', function() { setTimelineZoom(pxPerMs / 1.2); });
		uiLayer.add(zoomMinusBtn);
		zoomPlusBtn = new EditorButton(tx + 120, timelineTop + 5, 24, 28, '+', function() { setTimelineZoom(pxPerMs * 1.2); });
		uiLayer.add(zoomPlusBtn);
		fitBtn = new EditorButton(tx + 152, timelineTop + 5, btnW(Lang.tOr('choreo.fit', '适配'), 56), 28, Lang.tOr('choreo.fit', '适配'), fitZoom);
		uiLayer.add(fitBtn);

		// ===== 图层行头 =====
		rebuildLayerRowLabels();

		// ===== 滚动条（DCE：轨道 2A2A2A / 滑块 5A5A5A）=====
		sbBg = new FlxSprite(timelineX, timelineTop + TOOLBAR_H).makeGraphic(Std.int(timelineRight - timelineX), Std.int(SCROLLBAR_H), 0xFF2A2A2A, true);
		sbBg.scrollFactor.set();
		uiLayer.add(sbBg);
		sbThumb = new FlxSprite(timelineX, timelineTop + TOOLBAR_H + 2).makeGraphic(1, 1, 0xFF5A5A5A, true);
		sbThumb.scrollFactor.set();
		uiLayer.add(sbThumb);

		// ===== 图层行头画布（行底 #242424 + 4px 层色条）=====
		layerHeadCanvas = new FlxSprite(0, layerRowY).makeGraphic(Std.int(LAYER_LABEL_W), Std.int(backend.CameraEditorData.layerCount() * layerH), FlxColor.TRANSPARENT, true);
		layerHeadCanvas.antialiasing = ClientPrefs.data.antialiasing;
		layerHeadCanvas.scrollFactor.set();
		uiLayer.add(layerHeadCanvas);
		redrawLayerHead();

		// ===== 时间轴画布 + 播放头 =====
		tlCanvas = new FlxSprite(timelineX, tlTop).makeGraphic(Std.int(timelineRight - timelineX), Std.int(timelineAreaH - TOOLBAR_H - SCROLLBAR_H), FlxColor.TRANSPARENT, true);
		tlCanvas.antialiasing = ClientPrefs.data.antialiasing;
		tlCanvas.scrollFactor.set();
		uiLayer.add(tlCanvas);
		playheadSpr = new FlxSprite(0, 0).makeGraphic(2, Std.int(timelineAreaH - TOOLBAR_H), 0xFFFF5C5C, true);
		playheadSpr.scrollFactor.set();
		uiLayer.add(playheadSpr);

		// ===== 右面板（紧凑行：行内标签，防溢出——v2 首版的固定偏移堆叠在小窗时间轴区会溢出）=====
		var panel:FlxSprite = makePanel(timelineRight + 8, TOP_H + 4, RIGHT_W, timelineTop - TOP_H - 8, 8, 0xF01E1E1E, 0xFF3F3F3F);
		uiLayer.add(panel);
		var title:FlxText = mkText(timelineRight + 24, TOP_H + 12, 18, 0xFFE0E0E0);
		title.text = Lang.tOr('choreo.evtProps', '事件属性');
		uiLayer.add(title);

		var px:Float = timelineRight + 24;
		var pw:Float = RIGHT_W - 48;
		var lblW:Float = 64;
		var fw:Float = pw - lblW - 8;

		// 曲目行（行内标签）
		var songLbl:FlxText = mkText(px, TOP_H + 46, 12, 0xFF8F8F8F);
		songLbl.text = Lang.tOr('choreo.songShort', '曲目');
		uiLayer.add(songLbl);
		songInput = new EditorInput(px + lblW + 4, TOP_H + 40, fw, '', currentSongName, function(v:String) {});
		uiLayer.add(songInput);
		diffBtn = new EditorButton(px, TOP_H + 78, 150, 28, diffLabel(), function() {
			var diffs:Array<String> = diffList();
			diffIdx = (diffIdx + 1) % diffs.length;
			diffBtn.label.text = diffLabel();
		});
		uiLayer.add(diffBtn);
		reloadBtn = new EditorButton(px + 158, TOP_H + 78, 110, 28, Lang.tOr('choreo.reload', '重新加载'), reloadAll);
		uiLayer.add(reloadBtn);

		var sep1:FlxText = mkText(px, TOP_H + 114, 12, 0xFF3F3F3F);
		sep1.text = '————————————————';
		uiLayer.add(sep1);
		var propsTitle:FlxText = mkText(px, TOP_H + 124, 16, 0xFF7ABFBC);
		propsTitle.text = Lang.tOr('choreo.evtProps', '事件属性');
		uiLayer.add(propsTitle);

		for (nm in backend.CameraEditorData.builtinEvents())
		{
			evnNames.push(nm);
			evnLabels.push(backend.CameraEditorData.displayEventName(nm));
		}
		var evtLbl:FlxText = mkText(px, TOP_H + 154, 12, 0xFF8F8F8F);
		evtLbl.text = Lang.tOr('choreo.evtName', '事件名');
		uiLayer.add(evtLbl);
		evtNameDd = new EditorDropdown(px + lblW + 4, TOP_H + 148, fw, '', evnLabels, 0, function(idx:Int) {
			var pi:Int = primaryIndex();
			if (pi >= 0 && pi < events.length)
			{
				var dv = backend.CameraEditorData.defaultValues(evnNames[idx]);
				editEvent(pi, events[pi].time, evnNames[idx], dv.v1, dv.v2, backend.CameraEditorData.layerOf(evnNames[idx]));
			}
		}, uiLayer);
		uiLayer.add(evtNameDd);

		var timeLbl:FlxText = mkText(px, TOP_H + 188, 12, 0xFF8F8F8F);
		timeLbl.text = Lang.tOr('choreo.evtTimeShort', '时间');
		uiLayer.add(timeLbl);
		evtTimeInput = new EditorInput(px + lblW + 4, TOP_H + 182, fw, '', '', function(v:String) {
			var pi:Int = primaryIndex();
			if (pi >= 0 && pi < events.length)
			{
				var t:Float = Std.parseFloat(v);
				if (Math.isFinite(t)) editEvent(pi, t, events[pi].name, events[pi].v1, events[pi].v2, events[pi].layer);
			}
		}, true);
		uiLayer.add(evtTimeInput);

		var v1Lbl:FlxText = mkText(px, TOP_H + 222, 12, 0xFF8F8F8F);
		v1Lbl.text = Lang.tOr('choreo.evtV1Short', '值1');
		uiLayer.add(v1Lbl);
		evtV1Input = new EditorInput(px + lblW + 4, TOP_H + 216, fw, '', '', function(v:String) {
			var pi:Int = primaryIndex();
			if (pi >= 0 && pi < events.length)
				editEvent(pi, events[pi].time, events[pi].name, v, events[pi].v2, events[pi].layer);
		});
		uiLayer.add(evtV1Input);

		var v2Lbl:FlxText = mkText(px, TOP_H + 256, 12, 0xFF8F8F8F);
		v2Lbl.text = Lang.tOr('choreo.evtV2Short', '值2');
		uiLayer.add(v2Lbl);
		evtV2Input = new EditorInput(px + lblW + 4, TOP_H + 250, fw, '', '', function(v:String) {
			var pi:Int = primaryIndex();
			if (pi >= 0 && pi < events.length)
				editEvent(pi, events[pi].time, events[pi].name, events[pi].v1, v, events[pi].layer);
		});
		uiLayer.add(evtV2Input);

		evtHintTxt = mkText(px, TOP_H + 290, 12, 0xFF9A9AA8);
		uiLayer.add(evtHintTxt);

		// 底行操作（贴面板底）
		var panelBotY:Float = timelineTop - 56;
		var addBtn = new EditorButton(px, panelBotY, btnW(Lang.tOr('choreo.addEvent', '添加事件'), 100), 30, Lang.tOr('choreo.addEvent', '添加事件'), function() {
			var idx:Int = evtNameDd.selectedIndex >= 0 ? evtNameDd.selectedIndex : 0;
			addEventAt(snapTime(cursorMs), evnNames[idx], '', '');
		});
		uiLayer.add(addBtn);
		var copyBtn = new EditorButton(px + addBtn.width + 8, panelBotY, btnW(Lang.tOr('choreo.copy', '复制'), 72), 30, Lang.tOr('choreo.copy', '复制'), copySelection);
		uiLayer.add(copyBtn);
		var delBtn = new EditorButton(px + addBtn.width + copyBtn.width + 16, panelBotY, btnW(Lang.tOr('choreo.del', '删除'), 72), 30, Lang.tOr('choreo.del', '删除'), deleteSelection);
		uiLayer.add(delBtn);
		var pasteBtn = new EditorButton(px + addBtn.width + copyBtn.width + delBtn.width + 24, panelBotY, btnW(Lang.tOr('choreo.paste', '粘贴'), 72), 30, Lang.tOr('choreo.paste', '粘贴'), pasteClipboard);
		uiLayer.add(pasteBtn);

		panelMsg = mkText(px, panelBotY + 36, 13, 0xFFFFD9A0);
		uiLayer.add(panelMsg);
		panelMsg = mkText(timelineRight + 24, panelBotY + 38, 13, 0xFFFFD9A0);
		uiLayer.add(panelMsg);

		// ===== 图层操作按钮 =====
		var addLayerBtn = new EditorButton(8, tlTop - 0, btnW(Lang.tOr('choreo.addLayer', '+层'), 56), 22, Lang.tOr('choreo.addLayer', '+层'), function() {
			backend.CameraEditorData.addLayer('', '', backend.CameraEditorData.nextLayerColor());
			refreshLayerVisibility();
			recomputeLayerH();
			strumY = layerRowY + backend.CameraEditorData.layerCount() * layerH + 10;
			rebuildLayerRowLabels();
			backend.CameraEditorData.savePrefs();
			tlDirty = true;
		});
		uiLayer.add(addLayerBtn);
		var delLayerBtn = new EditorButton(72, tlTop - 0, btnW(Lang.tOr('choreo.delLayer', '-层'), 46), 22, Lang.tOr('choreo.delLayer', '-层'), function() {
			var selLayer:Int = selectedLayerIdx();
			if (backend.CameraEditorData.isDefaultLayer(selLayer))
			{
				showMsg(Lang.tOr('choreo.defaultLayer', 'Default 层不可删除'));
				return;
			}
			if (backend.CameraEditorData.removeLayer(selLayer))
			{
				for (ev in events)
				{
					if (ev.layer == selLayer) ev.layer = 0;
					else if (ev.layer > selLayer) ev.layer -= 1;
				}
				refreshLayerVisibility();
				recomputeLayerH();
				strumY = layerRowY + backend.CameraEditorData.layerCount() * layerH + 10;
				rebuildLayerRowLabels();
				backend.CameraEditorData.savePrefs();
				markDirty();
			}
		});
		uiLayer.add(delLayerBtn);
		var upLayerBtn = new EditorButton(126, tlTop - 0, 26, 22, '^', function() { moveLayerSel(-1); });
		uiLayer.add(upLayerBtn);
		var downLayerBtn = new EditorButton(156, tlTop - 0, 26, 22, 'v', function() { moveLayerSel(1); });
		uiLayer.add(downLayerBtn);

		// 键位提示（右面板底部窄条）
		var hint:String = Lang.tOr('choreo.hintKeys', '空格 播放 · N 添加 · Del 删 · Ctrl+Z 撤销 · IJKL 移镜 · Esc 返回');
		hintTxt = mkText(timelineRight + 24, timelineTop - 18, 12, 0xFF8A8A98);
		hintTxt.text = hint;
		uiLayer.add(hintTxt);
	}

	function togglePassepartout():Void
	{
		passepartoutOn = !passepartoutOn;
		tlDirty = true;
	}

	function showHelp():Void
	{
		showMsg(Lang.tOr('choreo.helpText', '空格 播放 · 双击轨道加事件 · 拖卡改时间/层 · 拖边改时长 · 右键卡删除 · 框内拖动移镜 · Alt+拖旋转 · IJKL 移镜 · 滚轮 预览缩放 · Ctrl+滚轮 镜头缩放 · Shift+滚轮 框大小'));
	}

	function autoScrollLabel():String
	{
		var names:Array<String> = [Lang.tOr('choreo.asOff', '关'), Lang.tOr('choreo.asPage', '翻页'), Lang.tOr('choreo.asSmooth', '平滑')];
		return Lang.tOr('choreo.autoScroll', '自动滚动') + ': ' + names[autoScrollMode];
	}

	function snapLabel():String
	{
		return Lang.tOr('choreo.snap', '吸附') + ' 1/' + Std.string(Std.int(quantSteps));
	}

	function nextQuant(cur:Float, dir:Int):Float
	{
		var opts:Array<Float> = [4, 8, 12, 16, 20, 24, 32, 48, 64, 96, 192];
		var idx:Int = 3;
		for (i in 0...opts.length)
			if (opts[i] == cur) { idx = i; break; }
		idx += dir;
		if (idx < 0) idx = 0;
		if (idx >= opts.length) idx = opts.length - 1;
		return opts[idx];
	}

	function diffLabel():String
	{
		var diffs:Array<String> = diffList();
		if (diffIdx < 0 || diffIdx >= diffs.length) diffIdx = 0;
		return Lang.tOr('choreo.diff', '难度') + '：' + diffs[diffIdx];
	}

	/** 图层行头重绘：行底 + 左缘 4px 层色条 + 名字（DCE rebuildTimelineLayers 语义） */
	function redrawLayerHead():Void
	{
		if (layerHeadCanvas == null) return;
		var rows:Int = backend.CameraEditorData.layerCount();
		layerHeadCanvas.makeGraphic(Std.int(LAYER_LABEL_W), Std.int(rows * layerH), FlxColor.TRANSPARENT, true);
		for (i in 0...rows)
		{
			var col:Int = backend.CameraEditorData.layerColor(i);
			var sel:Bool = i == selectedLayerIdx();
			FlxSpriteUtil.drawRect(layerHeadCanvas, 0, i * layerH, LAYER_LABEL_W, layerH, sel ? 0xEE3D3D3D : 0xCC242424);
			FlxSpriteUtil.drawRect(layerHeadCanvas, 0, i * layerH, 4, layerH, col);
		}
		layerHeadCanvas.dirty = true;
	}

	function rebuildLayerRowLabels():Void
	{
		for (t in layerRowTexts)
		{
			uiLayer.remove(t);
			t.destroy();
		}
		layerRowTexts = [];
		for (i in 0...backend.CameraEditorData.layerCount())
		{
			var nm:String = backend.CameraEditorData.layerName(i);
			var tn:String = backend.CameraEditorData.layerType(i);
			var sub:String = tn.length > 0 ? backend.CameraEditorData.displayEventName(tn) : Lang.tOr('choreo.normalLayer', '普通事件层');
			var label:FlxText = mkText(8, layerRowY + i * layerH + layerH / 2 - 14, 13, backend.CameraEditorData.layerColor(i));
			label.text = nm;
			uiLayer.add(label);
			layerRowTexts.push(label);
			var subLabel:FlxText = mkText(8, layerRowY + i * layerH + layerH / 2 + 2, 10, 0xFF8A8A98);
			subLabel.text = sub;
			uiLayer.add(subLabel);
			layerRowTexts.push(subLabel);
		}
		redrawLayerHead();
		tlDirty = true;
	}

	function selectedLayerIdx():Int
	{
		var pi:Int = primaryIndex();
		if (pi >= 0 && pi < events.length) return events[pi].layer;
		return 0;
	}

	function moveLayerSel(dir:Int):Void
	{
		var idx:Int = selectedLayerIdx();
		if (backend.CameraEditorData.moveLayer(idx, dir))
		{
			for (ev in events)
			{
				if (ev.layer == idx) ev.layer = idx + dir;
				else if (ev.layer == idx + dir) ev.layer = idx;
			}
			if (idx < layersVisible.length && idx + dir >= 0 && idx + dir < layersVisible.length)
			{
				var b:Bool = layersVisible[idx];
				layersVisible[idx] = layersVisible[idx + dir];
				layersVisible[idx + dir] = b;
			}
			refreshLayerVisibility();
			rebuildLayerRowLabels();
			backend.CameraEditorData.savePrefs();
			markDirty();
		}
	}

	function reloadAll():Void
	{
		var folder:String = songInput.field.text.length > 0 ? songInput.field.text : currentSongName;
		stopPlayback();
		if (!loadChartData(folder, null)) return;
		rebuildStageOnly();
		loadAudio();
		seek(0);
		simulateCameraAt(0);
		recomputeLayerH();
		strumY = layerRowY + backend.CameraEditorData.layerCount() * layerH + 10;
		rebuildLayerRowLabels();
		refreshPanelFromSelection();
		tlDirty = true;
		showMsg(Lang.tOr('choreo.loaded', '已加载') + '：' + folder);
	}

	function showMsg(s:String):Void
	{
		if (panelMsg != null)
		{
			panelMsg.text = s;
			msgTimer = 3.0;
		}
	}

	// ================= 面板同步 / 事件编辑 =================

	function editEvent(idx:Int, time:Float, name:String, v1:String, v2:String, layer:Int):Void
	{
		if (idx < 0 || idx >= events.length) return;
		pushUndo();
		var ev:EdEvent = events[idx];
		ev.time = time;
		ev.name = name;
		ev.v1 = v1;
		ev.v2 = v2;
		ev.layer = layer;
		markDirty();
		simulateCameraAt(cursorMs);
	}

	function refreshPanelFromSelection():Void
	{
		var pi:Int = primaryIndex();
		if (pi < 0 || pi >= events.length)
		{
			evtTimeInput.setText('');
			evtNameDd.selectIndex(0);
			evtNameDd.refreshLabel();
			evtV1Input.setText('');
			evtV2Input.setText('');
			evtHintTxt.text = '';
			return;
		}
		var ev:EdEvent = events[pi];
		evtTimeInput.setText(Std.string(FlxMath.roundDecimal(ev.time, 2)));
		var idx:Int = evnNames.indexOf(ev.name);
		evtNameDd.selectIndex(idx >= 0 ? idx : 0);
		evtNameDd.refreshLabel();
		evtV1Input.setText(ev.v1);
		evtV2Input.setText(ev.v2);
		evtHintTxt.text = backend.CameraEditorData.eventHint(ev.name);
	}

	// ================= 时间轴绘制 =================

	function setTimelineZoom(ppm:Float):Void
	{
		pxPerMs = FlxMath.bound(ppm, timelineMinZoom(), ZOOM_MAX);
		tlDirty = true;
	}

	function timelineMinZoom():Float
	{
		var viewW:Float = timelineRight - timelineX;
		var m:Float = viewW / songEndMs;
		return Math.min(ZOOM_MAX, Math.max(m, 0.005));
	}

	function fitZoom():Void
	{
		pxPerMs = timelineMinZoom();
		scrollMs = 0;
		tlDirty = true;
	}

	function msToX(ms:Float):Float
	{
		return timelineX + (ms - scrollMs) * pxPerMs;
	}

	function xToMs(x:Float):Float
	{
		var t:Float = scrollMs + (x - timelineX) / pxPerMs;
		return t < 0 ? 0 : t;
	}

	function maxTimelineScroll():Float
	{
		var viewW:Float = timelineRight - timelineX;
		return Math.max(0, songEndMs - viewW / pxPerMs);
	}

	function evtInstant(ev:EdEvent):Bool
	{
		var nn:String = normEventName(ev.name);
		if (nn == 'focuscamera' || nn == 'camerafollowpos' || nn == 'zoomcamera' || nn == 'cameraangle')
			return ChoreoEase.isSnapToken(ev.v2) || evDurMs(ev) <= 0;
		return true;
	}

	function evDurMs(ev:EdEvent):Float
	{
		var nn:String = normEventName(ev.name);
		var durIdx:Int = 0;
		var def:Float = 0;
		if (nn == 'focuscamera') { durIdx = 2; def = 2; }
		else if (nn == 'camerafollowpos') { durIdx = 1; def = 0.5; }
		else if (nn == 'zoomcamera' || nn == 'cameraangle') { durIdx = 0; def = 0; }
		else return 0;
		var parts:Array<String> = ev.v2.split(',');
		var durSec:Float = parts.length > durIdx ? numOr(parts[durIdx], def) : def;
		return durSec * 1000;
	}

	function redrawTimeline():Void
	{
		var cw:Float = timelineRight - timelineX;
		var ch:Float = timelineAreaH - TOOLBAR_H - SCROLLBAR_H;
		tlCanvas.pixels.fillRect(tlCanvas.pixels.rect, 0x00FFFFFF);
		cardHitRects = [];

		// 图层行底
		for (i in 0...backend.CameraEditorData.layerCount())
		{
			var on:Bool = i < layersVisible.length ? layersVisible[i] : true;
			FlxSpriteUtil.drawRect(tlCanvas, 0, i * layerH, cw, layerH, on ? 0x0FFFFFFF : 0x05FFFFFF);
		}
		// 音符条区底
		var strumRelY:Float = strumY - tlTop;
		if (strumRelY >= 0 && strumRelY + STRUM_H <= ch)
			FlxSpriteUtil.drawRect(tlCanvas, 0, strumRelY, cw, STRUM_H, 0x0AFFFFFF);

		// 网格（DCE updateGrid 语义：小节/拍/细分）
		var beatMs:Float = beatLenMs(bpmAt(0));
		var beatPx:Float = beatMs * pxPerMs;
		var subDiv:Bool = beatPx >= 48;
		var t0:Float = scrollMs;
		var t1:Float = scrollMs + cw / pxPerMs;
		var startBeat:Int = Std.int(Math.floor(beatAt(t0)));
		var endBeat:Int = Std.int(Math.ceil(beatAt(t1))) + 1;
		var b:Int = startBeat;
		while (b <= endBeat)
		{
			var bt:Float = timeOfBeat(b);
			if (bt >= t0 && bt <= t1)
			{
				var x:Float = (bt - scrollMs) * pxPerMs;
				var isBar:Bool = (b % 4 == 0);
				var col:Int = isBar ? 0xFF65718A : (subDiv ? 0xFF414958 : 0x22FFFFFF);
				FlxSpriteUtil.drawLine(tlCanvas, x, 0, x, ch, {color: col, thickness: 1});
				if (subDiv && !isBar)
				{
					for (s in 1...4)
					{
						var st:Float = timeOfBeat(b + s / 4);
						var sx:Float = (st - scrollMs) * pxPerMs;
						if (sx >= 0 && sx < cw)
							FlxSpriteUtil.drawLine(tlCanvas, sx, 0, sx, ch, {color: 0xFF2D333E, thickness: 1});
					}
				}
			}
			b++;
		}

		// 标尺文字（measure.beat，DCE 同款 1-based）
		var poolIdx:Int = 0;
		var labelStrideBeats:Int = 1;
		while (beatMs * labelStrideBeats * pxPerMs < 64 && labelStrideBeats < 256)
			labelStrideBeats *= 2;
		var firstBeat:Int = Std.int(Math.floor(beatAt(t0) / labelStrideBeats)) * labelStrideBeats;
		var endBeatLabel:Int = Std.int(Math.ceil(beatAt(t1)));
		var bb:Int = firstBeat;
		while (bb <= endBeatLabel && poolIdx < textPool.length)
		{
			var bt:Float = timeOfBeat(bb);
			var lx:Float = (bt - scrollMs) * pxPerMs + 2;
			if (lx >= 0 && lx < cw - 40)
			{
				var lbl:FlxText = textPool[poolIdx];
				lbl.text = (Std.int(bb / 4) + 1) + '.' + (bb % 4 + 1);
				lbl.setPosition(timelineX + lx, tlTop + 4);
				lbl.color = 0xFFB8B8C8;
				lbl.visible = true;
				poolIdx++;
			}
			bb += labelStrideBeats;
		}

		// 音符 marker（双排：对手红/玩家绿）
		drawStrumMarkers(t0, t1, cw);

		// 事件卡
		var drawn:Int = 0;
		for (i in 0...events.length)
		{
			if (drawn >= MAX_EVENT_SPRITES) break;
			var ev:EdEvent = events[i];
			if (ev.time > t1) break;
			var on:Bool = ev.layer < layersVisible.length ? layersVisible[ev.layer] : true;
			if (!on) continue;
			var x:Float = msToX(ev.time);
			var durW:Float = evDurMs(ev) * pxPerMs;
			var w:Float = Math.max(14, Math.min(cw, durW > 16 ? durW : 14));
			if (x + w < 0 || x > cw) continue;
			var selected:Bool = selectedIndexes.indexOf(i) >= 0;
			var col:Int = backend.CameraEditorData.layerColor(ev.layer);
			var base:Int = col & 0xFFFFFF;
			var fillCol:Int = selected ? 0xFFF7E26B : (0xD9000000 | base);
			var y:Float = ev.layer * layerH + 3;
			var h:Float = layerH - 6;
			FlxSpriteUtil.drawRoundRect(tlCanvas, x, y, w, h, 3, 3, fillCol, {color: selected ? 0xFFFFFFFF : (0xFF000000 | base), thickness: selected ? 2 : 1});
			if (evtInstant(ev))
				FlxSpriteUtil.drawTriangle(tlCanvas, x + w - 8, y + h / 2 - 4, 8, 0xFFFFFFFF);
			cardHitRects.push({x: timelineX + x, y: tlTop + y, w: w, h: h, idx: i});
			drawn++;
		}

		while (poolIdx < textPool.length)
		{
			textPool[poolIdx].visible = false;
			poolIdx++;
		}

		tlScrollShown = scrollMs;
		tlZoomShown = pxPerMs;
		tlDirty = false;
	}

	function drawStrumMarkers(t0:Float, t1:Float, cw:Float):Void
	{
		if (sections == null || sections.length <= 0) return;
		if (strumY < tlTop || strumY + STRUM_H > tlTop + timelineAreaH) return;
		var half:Float = STRUM_H / 2;
		var idx:Int = lowerBoundNote(t0 - 8000);
		while (idx < flatNotes.length)
		{
			var n = flatNotes[idx];
			if (n.t > t1) break;
			var x:Float = (n.t - scrollMs) * pxPerMs;
			var w:Float = Math.max(4, n.sus * pxPerMs);
			if (x + w >= 0 && x < cw)
			{
				var col:Int = n.pl ? 0xFF9AE881 : 0xFFFF857B;
				var y:Float = strumY - tlTop + (n.pl ? half + 4 : 4);
				FlxSpriteUtil.drawRect(tlCanvas, Math.max(x, 0), y, w, 5, col);
			}
			idx++;
		}
	}

	function buildFlatNotes():Void
	{
		flatNotes = [];
		if (notesSong == null) return;
		var songKeys:Int = backend.ExtraKeys.resolveKeys(notesSong.keys);
		for (sec in sections)
		{
			if (sec == null || sec.sectionNotes == null) continue;
			for (n in sec.sectionNotes)
			{
				if (n == null || n.length < 2) continue;
				var rawCol:Int = Std.int(n[1]);
				if (rawCol < 0 || rawCol >= songKeys * 2) continue;
				var pl:Bool = rawCol < songKeys;
				var sus:Float = n.length > 2 && n[2] != null ? Std.parseFloat(Std.string(n[2])) : 0;
				if (Math.isNaN(sus) || !Math.isFinite(sus)) sus = 0;
				flatNotes.push({t: Std.parseFloat(Std.string(n[0])), pl: pl, sus: sus});
			}
		}
		flatNotes.sort(function(a, b):Int {
			return a.t > b.t ? 1 : (a.t < b.t ? -1 : 0);
		});
	}

	function lowerBoundNote(t0:Float):Int
	{
		var lo:Int = 0;
		var hi:Int = flatNotes.length;
		while (lo < hi)
		{
			var mid:Int = (lo + hi) >> 1;
			if (flatNotes[mid].t < t0) lo = mid + 1;
			else hi = mid;
		}
		return lo;
	}

	function ensureTextPool(n:Int):Void
	{
		while (textPool.length < n)
		{
			var t:FlxText = mkText(0, 0, 10, 0xFFE8E8F0);
			t.visible = false;
			uiLayer.add(t);
			textPool.push(t);
		}
	}

	function updatePlayhead():Void
	{
		var x:Float = msToX(cursorMs);
		playheadSpr.visible = x >= timelineX - 2 && x <= timelineRight + 2;
		playheadSpr.setPosition(x - 1, tlTop);
		// 滚动条滑块（宽 = 视口占比；白 3px 播放头刻度，DCE 同款）
		if (sbThumb != null)
		{
			var trackW:Float = timelineRight - timelineX;
			var viewMs:Float = trackW / pxPerMs;
			var thumbW:Float = Math.max(20, trackW * viewMs / Math.max(songEndMs, 1));
			var frac:Float = maxTimelineScroll() > 0 ? FlxMath.bound(scrollMs / maxTimelineScroll(), 0, 1) : 0;
			sbThumb.setPosition(timelineX + frac * (trackW - thumbW), timelineTop + TOOLBAR_H + 2);
			sbThumb.scale.set(thumbW, SCROLLBAR_H - 4);
			var headFrac:Float = songEndMs > 0 ? FlxMath.bound(cursorMs / songEndMs, 0, 1) : 0;
			playheadSpr.visible = playheadSpr.visible;
		}
	}

	// ================= 鼠标 =================

	function rectHit(r:FlxRect, x:Float, y:Float):Bool
	{
		return x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;
	}

	function anyInputFocused():Bool
	{
		return (songInput != null && songInput.field.hasFocus)
			|| (evtTimeInput != null && evtTimeInput.field.hasFocus)
			|| (evtV1Input != null && evtV1Input.field.hasFocus)
			|| (evtV2Input != null && evtV2Input.field.hasFocus);
	}

	function handleOpenMenu(mx:Float, my:Float):Void
	{
		if (!FlxG.mouse.justPressed) return;
		for (b in menuBtns)
		{
			if (b.over(mx, my))
			{
				openMenu = -1;
				var cb:Void->Void = b.onClick;
				closeMenuPanel();
				if (cb != null) cb();
				return;
			}
		}
		var outside:Bool = true;
		for (b in menuBtns)
		{
			if (b.over(mx, my)) outside = false;
		}
		if (outside)
		{
			openMenu = -1;
			closeMenuPanel();
		}
	}

	function openMenuPanel(idx:Int):Void
	{
		closeMenuPanel();
		openMenu = idx;
		var items = menuDefs[idx].items;
		var w:Float = 250;
		var h:Float = items.length * 34 + 10;
		var px:Float = menuRects[idx].x;
		var py:Float = 28;
		if (px + w > FlxG.width) px = FlxG.width - w - 4;
		menuPanel = new FlxSpriteGroup();
		menuPanel.add(makePanel(px, py, w, h, 10));
		menuBtns = [];
		for (i in 0...items.length)
		{
			var it = items[i];
			var b:EditorButton = new EditorButton(px + 6, py + 6 + i * 32, w - 12, 28, it.label, it.cb);
			menuPanel.add(b);
			menuBtns.push(b);
		}
		uiLayer.add(menuPanel);
		menuPanel.cameras = [camUI];
	}

	function closeMenuPanel():Void
	{
		if (menuPanel != null)
		{
			uiLayer.remove(menuPanel);
			menuPanel.destroy();
			menuPanel = null;
			menuBtns = [];
		}
	}

	function handleMouse():Void
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;

		if (anyInputFocused())
		{
			if (FlxG.mouse.justPressed)
			{
				songInput.field.hasFocus = false;
				evtTimeInput.field.hasFocus = false;
				evtV1Input.field.hasFocus = false;
				evtV2Input.field.hasFocus = false;
			}
			return;
		}

		if (openMenu >= 0)
		{
			handleOpenMenu(mx, my);
			return;
		}
		if (openDropdown != null)
			return;

		// 分隔条（时间轴区高度拖调）
		if (Math.abs(my - (timelineTop - 4)) < 10 && mx < timelineRight)
		{
			if (FlxG.mouse.justPressed) draggingSplitter = true;
		}
		if (draggingSplitter)
		{
			if (FlxG.mouse.pressed)
			{
				timelineAreaH = FlxMath.bound(FlxG.height - my, 180, FlxG.height - TOP_H - 120);
				timelineTop = FlxG.height - timelineAreaH;
				tlTop = timelineTop + TOOLBAR_H + SCROLLBAR_H;
				layerRowY = tlTop + RULER_H;
				recomputeLayerH();
				strumY = layerRowY + backend.CameraEditorData.layerCount() * layerH + 10;
				tlDirty = true;
			}
			else draggingSplitter = false;
			return;
		}

		// 滚动条
		var sbY:Float = timelineTop + TOOLBAR_H;
		if (my >= sbY && my <= sbY + SCROLLBAR_H && mx >= timelineX && mx <= timelineRight)
		{
			var trackW:Float = timelineRight - timelineX;
			var viewMs:Float = trackW / pxPerMs;
			var thumbW:Float = Math.max(20, trackW * viewMs / Math.max(songEndMs, 1));
			var fracX:Float = FlxMath.bound((mx - timelineX) / trackW, 0, 1);
			if (FlxG.mouse.justPressed)
			{
				var thumbX:Float = timelineX + (scrollMs / Math.max(maxTimelineScroll(), 1)) * (trackW - thumbW);
				if (mx >= thumbX && mx <= thumbX + thumbW)
					scrollbarDrag = true;
				else
				{
					scrollMs = fracX * maxTimelineScroll();
					tlDirty = true;
				}
			}
			if (scrollbarDrag && FlxG.mouse.pressed)
			{
				scrollMs = fracX * maxTimelineScroll();
				tlDirty = true;
			}
			if (!FlxG.mouse.pressed) scrollbarDrag = false;
			return;
		}
		if (scrollbarDrag && !FlxG.mouse.pressed) scrollbarDrag = false;

		// 标尺：播放头把手拖动 / 点击跳转
		if (my >= tlTop - 6 && my <= tlTop + RULER_H)
		{
			var px:Float = msToX(cursorMs);
			if (FlxG.mouse.justPressed && Math.abs(mx - px) < 10)
				scrubDrag = true;
			if (scrubDrag)
			{
				if (FlxG.mouse.pressed)
					seek(snapTime(xToMs(mx)));
				else scrubDrag = false;
				return;
			}
			if (FlxG.mouse.justPressed)
			{
				seek(snapTime(xToMs(mx)));
				return;
			}
		}

		// 菜单条
		for (i in 0...menuRects.length)
		{
			if (rectHit(menuRects[i], mx, my))
			{
				if (FlxG.mouse.justPressed)
				{
					openMenuPanel(i);
					return;
				}
			}
		}

		// 工具栏按钮
		var btns:Array<EditorButton> = [playBtn, autoScrollBtn, snapBtn, zoomMinusBtn, zoomPlusBtn, fitBtn, diffBtn, reloadBtn];
		for (b in btns)
		{
			if (b != null) b.setHovered(b.over(mx, my));
		}
		if (FlxG.mouse.justPressed)
		{
			for (b in btns)
			{
				if (b != null && b.over(mx, my))
				{
					if (b.onClick != null) b.onClick();
					return;
				}
			}
		}

		// 图层行头眼睛（标签列右缘）
		if (mx >= LAYER_LABEL_W - 26 && mx < LAYER_LABEL_W && my >= layerRowY && my <= layerRowY + backend.CameraEditorData.layerCount() * layerH)
		{
			if (FlxG.mouse.justPressed)
			{
				var li:Int = Std.int((my - layerRowY) / layerH);
				if (li >= 0 && li < layersVisible.length)
				{
					layersVisible[li] = !layersVisible[li];
					tlDirty = true;
				}
				return;
			}
		}

		// 预览区（取景框交互）
		if (my >= TOP_H && my <= timelineTop - 28 && mx < timelineRight)
		{
			handlePreviewMouse(mx, my);
			if (previewDragging || previewRotating || dragEditIdx >= 0) return;
		}

		// 时间轴区
		if (my >= tlTop && my <= FlxG.height && mx >= timelineX && mx <= timelineRight)
		{
			handleTimelineMouse(mx, my);
			if (dragMode != 0 || boxSelecting) return;
			var steps:Int = wheel.process(FlxG.mouse.wheel);
			if (steps != 0)
			{
				var factor:Float = steps > 0 ? 1.15 : 1 / 1.15;
				setTimelineZoom(pxPerMs * factor);
			}
		}

		// 右面板
		updatePanelMouse(mx, my);
	}

	// ---- 预览交互 ----

	function handlePreviewMouse(mx:Float, my:Float):Void
	{
		var r:FlxRect = viewfinderRect();
		var inFrame:Bool = mx >= r.x && mx <= r.x + r.width && my >= r.y && my <= r.y + r.height;
		r.put();

		if (FlxG.mouse.wheel != 0)
		{
			if (FlxG.keys.pressed.CONTROL)
			{
				var factor:Float = FlxG.mouse.wheel > 0 ? 1.05 : 1 / 1.05;
				vcamZoom = FlxMath.bound(vcamZoom * factor, 0.1, 3);
				zoomTween = null;
			}
			else if (FlxG.keys.pressed.SHIFT)
			{
				var factor:Float = FlxG.mouse.wheel > 0 ? 1.08 : 1 / 1.08;
				vfWinScale = FlxMath.bound(vfWinScale * factor, 0.4, 1.6);
			}
			else
			{
				var factor:Float = FlxG.mouse.wheel > 0 ? 1.1 : 1 / 1.1;
				previewZoom = FlxMath.bound(previewZoom * factor, 0.25, 2.5);
			}
			return;
		}

		if (FlxG.mouse.justPressed && inFrame)
		{
			if (FlxG.keys.pressed.ALT)
			{
				previewRotating = true;
				dragLastX = mx;
				dragLastY = my;
				return;
			}
			// 拖框编辑选中 FollowPos/Focus 事件（DCE 语义）
			var pi:Int = primaryIndex();
			if (pi >= 0 && pi < events.length)
			{
				var nn:String = normEventName(events[pi].name);
				if (nn == 'camerafollowpos' || nn == 'focuscamera')
				{
					dragEditIdx = pi;
					dragLastX = mx;
					dragLastY = my;
					return;
				}
			}
			previewDragging = true;
			dragLastX = mx;
			dragLastY = my;
			return;
		}

		if (previewRotating)
		{
			if (FlxG.mouse.pressed)
			{
				vcamAngle = FlxMath.bound(vcamAngle + (mx - dragLastX) * 0.35, -180, 180);
				dragLastX = mx;
				dragLastY = my;
			}
			else previewRotating = false;
			return;
		}

		if (dragEditIdx >= 0)
		{
			if (FlxG.mouse.pressed)
				updateDragEdit(mx, my);
			else
				endDragEdit();
			return;
		}

		if (previewDragging)
		{
			if (FlxG.mouse.pressed)
			{
				var k:Float = previewZoom * vcamZoom / vfWinScale;
				if (k <= 0) k = 0.01;
				vcamScrollX += (mx - dragLastX) / k;
				vcamScrollY += (my - dragLastY) / k;
				vcamFollowX = vcamScrollX;
				vcamFollowY = vcamScrollY;
				followTween = null;
				dragLastX = mx;
				dragLastY = my;
			}
			else previewDragging = false;
		}
	}

	/** 拖框编辑选中事件（FollowPos/Focus 的坐标/偏移实时改写）。 */
	function updateDragEdit(mx:Float, my:Float):Void
	{
		if (dragEditIdx < 0 || dragEditIdx >= events.length) return;
		var ev:EdEvent = events[dragEditIdx];
		var k:Float = previewZoom * vcamZoom / vfWinScale;
		if (k <= 0) k = 0.01;
		var ddx:Float = (mx - dragLastX) / k;
		var ddy:Float = (my - dragLastY) / k;
		dragLastX = mx;
		dragLastY = my;
		var nn:String = normEventName(ev.name);
		if (nn == 'camerafollowpos')
		{
			var x:Float = numOr(ev.v1, 0) + ddx;
			var parts:Array<String> = ev.v2.split(',');
			var y:Float = (parts.length > 0 && parts[0].trim().length > 0 ? numOr(parts[0], 0) : 0) + ddy;
			ev.v1 = Std.string(FlxMath.roundDecimal(x, 1));
			if (parts.length > 0) parts[0] = Std.string(FlxMath.roundDecimal(y, 1));
			else parts.push(Std.string(FlxMath.roundDecimal(y, 1)));
			ev.v2 = parts.join(',');
		}
		else if (nn == 'focuscamera')
		{
			var parts:Array<String> = ev.v2.split(',');
			while (parts.length < 2) parts.push('0');
			parts[0] = Std.string(FlxMath.roundDecimal(numOr(parts[0], 0) + ddx, 1));
			parts[1] = Std.string(FlxMath.roundDecimal(numOr(parts[1], 0) + ddy, 1));
			ev.v2 = parts.join(',');
		}
		hasUnsaved = true;
		simulateCameraAt(cursorMs);
		refreshPanelFromSelection();
	}

	function endDragEdit():Void
	{
		dragEditIdx = -1;
	}

	// ---- 时间轴交互 ----

	function handleTimelineMouse(mx:Float, my:Float):Void
	{
		if (FlxG.mouse.justPressed)
		{
			var hitIdx:Int = -1;
			var hitR:Null<{x:Float, y:Float, w:Float, h:Float, idx:Int}> = null;
			for (i in 0...cardHitRects.length)
			{
				var r = cardHitRects[i];
				if (mx >= r.x && mx <= r.x + r.w && my >= r.y && my <= r.y + r.h)
				{
					hitIdx = r.idx;
					hitR = r;
				}
			}
			if (hitIdx >= 0 && hitR != null)
			{
				var ev:EdEvent = events[hitIdx];
				var resizable:Bool = !evtInstant(ev);
				if (FlxG.keys.pressed.CONTROL)
				{
					var si:Int = selectedIndexes.indexOf(hitIdx);
					if (si >= 0) selectedIndexes.splice(si, 1);
					else selectedIndexes.push(hitIdx);
					tlDirty = true;
					refreshPanelFromSelection();
					return;
				}
				if (resizable && mx >= hitR.x + hitR.w - 5)
				{
					dragMode = 3;
					dragIndexes = selectedIndexes.indexOf(hitIdx) >= 0 ? selectedIndexes.copy() : [hitIdx];
					dragStartX = mx;
					return;
				}
				if (resizable && mx <= hitR.x + 5)
				{
					dragMode = 2;
					dragIndexes = selectedIndexes.indexOf(hitIdx) >= 0 ? selectedIndexes.copy() : [hitIdx];
					dragStartX = mx;
					return;
				}
				if (selectedIndexes.indexOf(hitIdx) < 0)
				{
					selectedIndexes = [hitIdx];
					tlDirty = true;
					refreshPanelFromSelection();
				}
				dragMode = 1;
				dragIndexes = selectedIndexes.copy();
				dragMouseMsOffset = xToMs(mx) - events[hitIdx].time;
				dragStartX = mx;
				dragStartY = my;
				return;
			}
			// 空位：框选起点
			boxStartX = mx;
			boxStartY = my;
			boxSelecting = true;
			return;
		}

		// 卡片拖动
		if (dragMode != 0)
		{
			if (FlxG.mouse.pressed)
			{
				var pi:Int = dragIndexes.length > 0 ? dragIndexes[dragIndexes.length - 1] : -1;
				if (pi >= 0 && pi < events.length)
				{
					if (dragMode == 1)
					{
						var newMs:Float = snapTime(xToMs(mx) - dragMouseMsOffset);
						var delta:Float = newMs - events[pi].time;
						var layerDrag:Int = -1;
						for (li in 0...backend.CameraEditorData.layerCount())
						{
							var ry:Float = layerRowY + li * layerH;
							if (my >= ry && my < ry + layerH)
							{
								layerDrag = li;
								break;
							}
						}
						for (di in dragIndexes)
						{
							if (di < 0 || di >= events.length) continue;
							events[di].time = Math.max(0, events[di].time + delta);
							if (layerDrag >= 0) events[di].layer = layerDrag;
						}
						hasUnsaved = true;
						tlDirty = true;
					}
					else
					{
						var ev:EdEvent = events[pi];
						var nn:String = normEventName(ev.name);
						var durIdx:Int = 0;
						if (nn == 'focuscamera') durIdx = 2;
						else if (nn == 'camerafollowpos') durIdx = 1;
						else if (nn == 'zoomcamera' || nn == 'cameraangle') durIdx = 0;
						if (nn == 'focuscamera' || nn == 'camerafollowpos' || nn == 'zoomcamera' || nn == 'cameraangle')
						{
							var parts:Array<String> = ev.v2.split(',');
							while (parts.length <= durIdx) parts.push('0');
							var newMs:Float = xToMs(mx);
							var durMs:Float = dragMode == 3 ? (newMs - ev.time) : (ev.time + evDurMs(ev) - newMs);
							durMs = FlxMath.bound(durMs, 20, 30000);
							parts[durIdx] = Std.string(FlxMath.roundDecimal(durMs / 1000, 2));
							ev.v2 = parts.join(',');
							hasUnsaved = true;
							tlDirty = true;
						}
					}
				}
				return;
			}
			finishEventDrag();
			return;
		}

		// 框选
		if (boxSelecting)
		{
			if (FlxG.mouse.pressed)
			{
				var dx:Float = Math.abs(mx - boxStartX);
				var dy:Float = Math.abs(my - boxStartY);
				if (dx > 6 || dy > 6)
				{
					var bx:Float = Math.min(boxStartX, mx);
					var by:Float = Math.min(boxStartY, my);
					boxRect.visible = true;
					boxRect.setPosition(bx, by);
					boxRect.scale.set(Math.abs(mx - boxStartX), Math.abs(my - boxStartY));
				}
			}
			else
			{
				var dx:Float = Math.abs(mx - boxStartX);
				var dy:Float = Math.abs(my - boxStartY);
				boxRect.visible = false;
				boxSelecting = false;
				if (dx > 6 || dy > 6)
				{
					var bx:Float = Math.min(boxStartX, mx);
					var by:Float = Math.min(boxStartY, my);
					var bw:Float = Math.abs(mx - boxStartX);
					var bh:Float = Math.abs(my - boxStartY);
					if (!FlxG.keys.pressed.CONTROL) selectedIndexes = [];
					for (i in 0...cardHitRects.length)
					{
						var r = cardHitRects[i];
						if (r.x + r.w >= bx && r.x <= bx + bw && r.y + r.h >= by && r.y <= by + bh)
						{
							if (selectedIndexes.indexOf(r.idx) < 0)
								selectedIndexes.push(r.idx);
						}
					}
					tlDirty = true;
					refreshPanelFromSelection();
				}
				else
				{
					seek(snapTime(xToMs(mx)));
				}
			}
		}
	}

	function finishEventDrag():Void
	{
		dragMode = 0;
		sortEvents();
		refreshPanelFromSelection();
		simulateCameraAt(cursorMs);
		tlDirty = true;
	}

	function updatePanelMouse(mx:Float, my:Float):Void
	{
		if (my < TOP_H) return;
		if (evtNameDd != null)
		{
			evtNameDd.setHovered(evtNameDd.over(mx, my));
			if (FlxG.mouse.justPressed && evtNameDd.over(mx, my))
			{
				if (openDropdown == evtNameDd)
				{
					evtNameDd.close();
					openDropdown = null;
				}
				else
				{
					if (openDropdown != null) openDropdown.close();
					openDropdown = evtNameDd;
					evtNameDd.open = false;
					evtNameDd.toggle();
				}
				return;
			}
		}
	}

	// ================= 键盘 =================

	function handleKeys():Void
	{
		if (anyInputFocused()) return;
		if (FlxG.keys.justPressed.SPACE)
			togglePlay();
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (openMenu >= 0)
			{
				openMenu = -1;
				closeMenuPanel();
				return;
			}
			if (hasUnsaved)
				openSubState(new substates.Prompt(Lang.tOr('choreo.confirmExit', '有未保存的改动，仍要退出？'), 0, function() { closeEditor(true); exitToMenu(); }, function() {}));
			else
			{
				closeEditor(false);
				exitToMenu();
			}
		}
		if (FlxG.keys.justPressed.N && !FlxG.keys.pressed.CONTROL && !FlxG.keys.pressed.SHIFT)
		{
			var idx:Int = evtNameDd.selectedIndex >= 0 ? evtNameDd.selectedIndex : 0;
			addEventAt(snapTime(cursorMs), evnNames[idx], '', '');
		}
		if (FlxG.keys.justPressed.A && FlxG.keys.pressed.CONTROL)
			selectAll();
		if (FlxG.keys.justPressed.Z && FlxG.keys.pressed.CONTROL && !FlxG.keys.pressed.SHIFT)
			undo();
		if (FlxG.keys.justPressed.Y && FlxG.keys.pressed.CONTROL)
			redo();
		if (FlxG.keys.justPressed.C && FlxG.keys.pressed.CONTROL)
			copySelection();
		if (FlxG.keys.justPressed.X && FlxG.keys.pressed.CONTROL)
		{
			copySelection();
			deleteSelection();
		}
		if (FlxG.keys.justPressed.V && FlxG.keys.pressed.CONTROL)
			pasteClipboard();
		if (FlxG.keys.justPressed.D && FlxG.keys.pressed.CONTROL)
			duplicateSelection();
		if (FlxG.keys.justPressed.DELETE || FlxG.keys.justPressed.BACKSPACE)
			deleteSelection();
		if (FlxG.keys.justPressed.Q && !FlxG.keys.pressed.CONTROL)
		{
			quantSteps = nextQuant(quantSteps, -1);
			snapBtn.label.text = snapLabel();
		}
		if (FlxG.keys.justPressed.E && !FlxG.keys.pressed.CONTROL)
		{
			quantSteps = nextQuant(quantSteps, 1);
			snapBtn.label.text = snapLabel();
		}
		if (FlxG.keys.justPressed.A && !FlxG.keys.pressed.CONTROL)
			panTimeline(-500);
		if (FlxG.keys.justPressed.D && !FlxG.keys.pressed.CONTROL)
			panTimeline(500);
		if (FlxG.keys.justPressed.F && !FlxG.keys.pressed.CONTROL)
		{
			var pi:Int = primaryIndex();
			if (pi >= 0 && pi < events.length)
				seek(events[pi].time);
		}
		if (FlxG.keys.justPressed.HOME)
			seek(0);
		// IJKL 移镜（DCE：400*elapsed/zoom，Shift ×3）
		var panSpeed:Float = 400 * (FlxG.elapsed > 0 ? FlxG.elapsed : 0.016) / Math.max(previewZoom * vcamZoom / vfWinScale, 0.01);
		if (FlxG.keys.pressed.SHIFT) panSpeed *= 3;
		if (FlxG.keys.pressed.I) moveVcam(0, -panSpeed);
		if (FlxG.keys.pressed.K) moveVcam(0, panSpeed);
		if (FlxG.keys.pressed.J) moveVcam(-panSpeed, 0);
		if (FlxG.keys.pressed.L) moveVcam(panSpeed, 0);
		if (FlxG.keys.justPressed.R && !FlxG.keys.pressed.CONTROL)
		{
			vcamScrollX = vcamFollowX;
			vcamScrollY = vcamFollowY;
			followTween = null;
		}
		if (FlxG.keys.justPressed.G && FlxG.keys.pressed.CONTROL)
		{
			vcamZoom = defaultCamZoom;
			zoomTween = null;
		}
		if (FlxG.keys.justPressed.COMMA)
			addEventAt(snapTime(cursorMs), 'Focus Camera', 'dad', '0,0,0,CLASSIC');
		if (FlxG.keys.justPressed.PERIOD)
			addEventAt(snapTime(cursorMs), 'Focus Camera', 'boyfriend', '0,0,0,CLASSIC');
		if (FlxG.keys.justPressed.S && FlxG.keys.pressed.CONTROL)
			saveWithBackup();
	}

	function moveVcam(dx:Float, dy:Float):Void
	{
		vcamScrollX += dx;
		vcamScrollY += dy;
		vcamFollowX = vcamScrollX;
		vcamFollowY = vcamScrollY;
		followTween = null;
	}

	function panTimeline(deltaMs:Float):Void
	{
		scrollMs = FlxMath.bound(scrollMs + deltaMs, 0, maxTimelineScroll());
		tlDirty = true;
	}

	function exitToMenu():Void
	{
		MusicBeatState.switchState(new MasterEditorMenu());
	}

	// ================= 主循环 =================

	override public function update(elapsed:Float)
	{
		// 窗口尺寸变化（MeteoricScaleMode 逻辑分辨率随窗口变）→ 重建 UI 层
		if (lastW != FlxG.width || lastH != FlxG.height)
			rebuildForResize();

		handleKeys();

		if (playing && music != null)
		{
			cursorMs = music.time;
			if (voices != null && voices.exists && Math.abs(voices.time - music.time) > 60)
				voices.time = music.time;
			applyPendingEvents(false);
			var curBeat:Int = Std.int(Math.floor(beatAt(cursorMs)));
			var curStep:Int = Std.int(Math.floor(stepAt(cursorMs)));
			if (curBeat != lastBeatDance)
			{
				if (Math.abs(curBeat - lastBeatDance) <= 2)
					onBeatCross(curBeat);
				lastBeatDance = curBeat;
			}
			if (curStep != lastStepHit)
			{
				if (Math.abs(curStep - lastStepHit) <= 4)
					onStepHit(curStep);
				lastStepHit = curStep;
			}
			if (music.time >= songEndMs - 30)
			{
				playing = false;
				music.pause();
				if (voices != null && voices.exists) voices.pause();
				playBtn.label.text = Lang.tOr('choreo.play', '播放');
			}
		}

		// 自动滚动（0 关 1 翻页 2 平滑；手动滚动后 1.5s 抑制）
		if (playing && autoScrollMode > 0)
		{
			manualScrollTimer += elapsed;
			if (manualScrollTimer > 1.5)
			{
				var viewMs:Float = (timelineRight - timelineX) / pxPerMs;
				if (autoScrollMode == 2)
				{
					scrollMs = FlxMath.bound(cursorMs - viewMs * 0.5, 0, maxTimelineScroll());
					tlDirty = true;
				}
				else
				{
					var headX:Float = msToX(cursorMs);
					if (headX > timelineX + (timelineRight - timelineX) * 0.95 || headX < timelineX)
					{
						scrollMs = FlxMath.bound(cursorMs - viewMs * 0.05, 0, maxTimelineScroll());
						tlDirty = true;
					}
				}
			}
		}

		stepVirtualCamera(elapsed);
		applyViewfinder();

		handleMouse();

		if (frameLines.length == 4 && passeParts.length == 4)
			updateFrameOverlay();
		updatePlayhead();
		updateStatus();
		if (msgTimer > 0)
		{
			msgTimer -= elapsed;
			if (msgTimer <= 0) panelMsg.text = '';
		}

		ensureTextPool(60);
		if (tlDirty || Math.abs(scrollMs - tlScrollShown) > 0.5 || Math.abs(pxPerMs - tlZoomShown) > 0.0001)
			redrawTimeline();

		if (openDropdown != null)
			openDropdown.updateOpen();

		super.update(elapsed);
	}

	/** 窗口尺寸变化：销毁重建 UI 层（几何全 FlxG 派生，选中态/文档不动） */
	function rebuildForResize():Void
	{
		lastW = FlxG.width;
		lastH = FlxG.height;
		if (uiLayer == null) return;
		if (openDropdown != null)
		{
			openDropdown.close();
			openDropdown = null;
		}
		closeMenuPanel();
		var doomed:Array<FlxSprite> = [];
		for (m in uiLayer.members)
			if (m != null) doomed.push(m);
		for (m in doomed)
		{
			uiLayer.remove(m);
			m.destroy();
		}
		uiLayer.clear();
		textPool = [];
		layerRowTexts = [];
		frameLines = [];
		cornerTicks = [];
		passeParts = [];
		menuRects = [];
		cardHitRects = [];
		layerHeadCanvas = null;
		sbBg = null;
		sbThumb = null;
		buildUI();
		uiLayer.cameras = [camUI];
		assignStageCameras();
		refreshPanelFromSelection();
		tlDirty = true;
	}

	function onBeatCross(beat:Int):Void
	{
		if (gf != null && beat % Math.round(gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith('sing') && !gf.stunned)
			gf.dance();
		if (boyfriend != null && beat % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && beat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();
		for (st in stages)
			st.beatHit();
	}

	function onStepHit(step:Int):Void
	{
		for (st in stages)
			st.stepHit();
	}

	function updateStatus():Void
	{
		var dirtyMark:String = hasUnsaved ? '  ' + Lang.tOr('choreo.unsaved', '●未保存') : '';
		var layerNames:Array<String> = [];
		for (i in 0...backend.CameraEditorData.layerCount())
			layerNames.push(backend.CameraEditorData.layerName(i));
		var li:Int = selectedLayerIdx();
		if (li < 0 || li >= layerNames.length) li = 0;
		statusTxt.text = Lang.tOr('choreo.statusSong', '曲目') + ': ' + currentSongName
			+ ' | ' + Lang.tOr('choreo.statusLayer', '图层') + ': ' + layerNames[li]
			+ ' | ' + Lang.tOr('choreo.statusEvents', '事件') + ': ' + events.length
			+ ' | ' + Lang.tOr('choreo.statusPlayhead', '播放头') + ': ' + fmtTime(cursorMs)
			+ ' | ' + Lang.tOr('choreo.statusZoom', '缩放') + ': ' + FlxMath.roundDecimal(vcamZoom, 2)
			+ dirtyMark;
		infoTxt.text = Lang.tOr('choreo.previewPct', '预览') + ' ' + Std.int(Math.round(previewZoom * 100)) + '% · '
			+ Lang.tOr('choreo.lens', '镜头') + ' ' + Std.int(Math.round(vcamZoom * 100)) + '% · '
			+ Lang.tOr('choreo.opsHint', '拖动移动 · Alt+拖动旋转 · 滚轮缩放');
		timeTxt.text = fmtTime(cursorMs) + ' / ' + fmtTime(songEndMs);
	}
}
