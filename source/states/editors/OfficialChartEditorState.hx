package states.editors;

import backend.ClientPrefs;
import backend.Conductor;
import backend.Difficulty;
import backend.Lang;
import backend.Mods;
import backend.Paths;
import backend.Section;
import backend.Song;

import flixel.FlxG;
import flixel.addons.ui.FlxInputText;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

import openfl.Lib;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * FNF 官方 0.8.7 编谱器「界面层」移植（NovaComet 原生 Flixel）。
 *
 * 只搬官方 UI 结构，不引入 HaxeUI / funkin.* 游戏核心：
 *   - 顶部菜单栏（File / Edit / View / Playtest / Help）
 *   - 底部播放条（时间、Beat/Step、|< << > >> >|、难度/BPM/吸附）
 *   - 居中的 8 轨网格 + 事件轨 + 小节刻度 + 红色播放头
 *   - 悬浮 Notes 工具箱（吸附、音符类型、提示）
 *   - 官方浅色主题色（紫底、浅色网格、红色播放头）
 *
 * 数据仍走 Psych `SwagSong`，保存输出 `psych_v1` JSON。
 * 这是 UI 层第一阶段：编辑/播放/保存可用，完整的工具箱/对话框后续继续补。
 */
class OfficialChartEditorState extends MusicBeatState
{
	// ---- 官方布局常量（ChartEditorState.hx）----
	static final MENU_BAR_HEIGHT:Int = 32;
	static final PLAYBAR_HEIGHT:Int = 48;
	static final GRID_SIZE:Int = 40;
	static final NOTE_SELECT_BUTTON_HEIGHT:Int = 32;
	static final GRID_TOP_PAD:Int = NOTE_SELECT_BUTTON_HEIGHT + 4;
	static final GRID_INITIAL_Y_POS:Int = MENU_BAR_HEIGHT + GRID_TOP_PAD;
	static final PLAY_Y:Float = 210;
	static final STRUM_X:Float = 500;
	static final EVENT_X:Float = 460;
	static final LANES:Int = 8;

	// ---- 官方浅色主题 ----
	static final COLOR_BG:Int = 0xFF673AB7;
	static final COLOR_GRID_1:Int = 0xFFE7E6E6;
	static final COLOR_GRID_2:Int = 0xFFF8F8F8;
	static final COLOR_GRID_3:Int = 0xFFD9D5D5;
	static final COLOR_DIVIDER:Int = 0xFF111111;
	static final COLOR_PLAYHEAD:Int = 0xFFBD0231;
	static final COLOR_BAR:Int = 0xFFF2F2F2;
	static final COLOR_BAR_TEXT:Int = 0xFF1A1A1A;
	static final COLOR_ACCENT:Int = 0xFF339933;

	static final LANE_COLORS:Array<Int> = [0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F];

	var _song:SwagSong;
	var songName:String = 'Test';
	var playing:Bool = false;
	var zoom:Float = 1;
	var snapIndex:Int = 3;
	var snaps:Array<Int> = [4, 8, 12, 16, 24, 32, 48, 64, 96, 192];
	var noteTypeIndex:Int = 0;
	var noteTypes:Array<String> = ['', 'Alt Animation', 'Hey!', 'Hurt Note', 'GF Sing', 'No Animation'];

	var flatNotes:Array<EditorNote> = [];
	var sectionStarts:Array<Float> = [];
	var sectionBeats:Array<Float> = [];
	var sectionBpms:Array<Float> = [];

	var gridBg:FlxSprite;
	var laneSprites:FlxTypedGroup<FlxSprite>;
	var lineSprites:FlxTypedGroup<FlxSprite>;
	var measureLabels:FlxTypedGroup<FlxText>;
	var noteSprites:FlxTypedGroup<FlxSprite>;
	var holdSprites:FlxTypedGroup<FlxSprite>;
	var playhead:FlxSprite;
	var menuBar:FlxSprite;
	var playbar:FlxSprite;
	var notePreviewBar:FlxSprite;

	var menuTexts:Array<FlxText> = [];
	var menuHits:Array<FlxRect> = [];
	var activeMenu:Int = -1;
	var menuPanel:FlxSprite;
	var menuItems:Array<FlxText> = [];
	var menuItemActions:Array<Void->Void> = [];

	var timeText:FlxText;
	var durationText:FlxText;
	var beatText:FlxText;
	var stepText:FlxText;
	var diffText:FlxText;
	var bpmText:FlxText;
	var snapText:FlxText;
	var statusText:FlxText;
	var toolPanel:FlxSprite;
	var toolTitle:FlxText;
	var toolLines:Array<FlxText> = [];
	var toolToggle:FlxText;

	var transportHits:Array<FlxRect> = [];
	var transportLabels:Array<String> = ['|<', '<<', '>', '>>', '>|'];
	var transportActions:Array<Void->Void> = [];

	var _file:FileReference;
	var toastTimer:Float = 0;
	var lastStep:Float = 0;
	var loggedFirstFrame:Bool = false;
	var frameCount:Int = 0;

	// 最小编辑能力：撤销栈 + 小节/事件面板
	var undoStack:Array<String> = [];
	var redoStack:Array<String> = [];
	var eventSprites:FlxTypedGroup<FlxSprite>;
	var eventTypes:Array<String> = ['', 'Hey!', 'Set GF Speed', 'Play Animation', 'Camera Follow Pos', 'Change Scroll Speed'];
	var eventTypeIndex:Int = 0;
	var panelButtons:Array<PanelButton> = [];
	var sectionInfo:FlxText;
	var eventInfo:FlxText;
	var selectedNote:EditorNote = null;
	var selectedEvent:Dynamic = null;
	var selectedRect:FlxSprite;
	var noteAtlas:FlxAtlasFrames;
	var eraserMode:Bool = false;
	var previewNote:FlxSprite;
	var songInput:FlxInputText;
	var eventValue1:FlxInputText;
	var eventValue2:FlxInputText;

	override function create():Void
	{
		// 优先加载调试指定歌曲；否则沿用进入编辑器前的 PlayState.SONG；最后才落空 Test 谱。
		var requestedSong:String = backend.DebugLaunch.autoSong;
		#if sys
		if (requestedSong == null || requestedSong.length == 0)
		{
			try requestedSong = Sys.getEnv('METEORIC_UI_SONG') catch (e:Dynamic) {}
		}
		#end
		if (requestedSong != null && requestedSong.length > 0)
		{
			try
			{
				var songPath:String = Paths.formatToSongPath(requestedSong).toLowerCase();
				var jsonName:String = songPath;
				var diff:String = Difficulty.getString();
				if (diff != null && diff.length > 0 && diff != Difficulty.getDefault()) jsonName += '-' + diff;
				_song = Song.loadFromJson(jsonName, songPath);
				PlayState.setSong(_song);
				trace('[OfficialChartEditor] loaded song=' + songPath + ' chart=' + jsonName);
			}
			catch (e:Dynamic)
			{
				trace('[OfficialChartEditor] load failed: ' + e);
				_song = null;
			}
		}
		if (_song == null && PlayState.SONG != null)
		{
			_song = PlayState.SONG;
			PlayState.setSong(_song);
		}
		if (_song == null)
		{
			Difficulty.resetList();
			_song = {
				song: 'Test',
				notes: [],
				events: [],
				bpm: 150.0,
				needsVoices: true,
				player1: 'bf',
				player2: 'dad',
				gfVersion: 'gf',
				speed: 1,
				stage: 'stage',
				keys: 4
			};
			addSection();
			PlayState.setSong(_song);
		}
		if (_song.keys == null) _song.keys = 4;
		ExtraKeys.setSongKeys(_song.keys);
		songName = Paths.formatToSongPath(_song.song);
		if (_song.events == null) _song.events = [];

		Conductor.bpm = _song.bpm;
		Conductor.mapBPMChanges(_song);
		recalculateSections();
		rebuildFlatNotes();

		FlxG.mouse.visible = true;
		FlxG.camera.bgColor = COLOR_BG;
		Lib.application.window.title = 'NovaComet Engine - Chart Editor';

		var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, COLOR_BG);
		bg.scrollFactor.set();
		add(bg);

		// 网格底：事件轨 + 8 条轨道；上下留出菜单/播放条
		var gridX:Float = EVENT_X;
		var gridW:Float = GRID_SIZE * (LANES + 1);
		gridBg = new FlxSprite(gridX, MENU_BAR_HEIGHT + GRID_TOP_PAD).makeGraphic(Std.int(gridW), Std.int(FlxG.height - MENU_BAR_HEIGHT - GRID_TOP_PAD - PLAYBAR_HEIGHT), COLOR_GRID_2);
		gridBg.scrollFactor.set();
		add(gridBg);

		laneSprites = new FlxTypedGroup<FlxSprite>();
		add(laneSprites);
		for (i in 0...LANES + 1)
		{
			var lane:FlxSprite = new FlxSprite(gridX + i * GRID_SIZE, gridBg.y).makeGraphic(GRID_SIZE, Std.int(gridBg.height), i == 0 ? COLOR_GRID_1 : (i % 2 == 0 ? COLOR_GRID_1 : COLOR_GRID_2));
			lane.alpha = i == 0 ? 0.55 : 1;
			lane.scrollFactor.set();
			laneSprites.add(lane);
		}

		lineSprites = new FlxTypedGroup<FlxSprite>();
		add(lineSprites);
		for (i in 0...96)
		{
			var line:FlxSprite = new FlxSprite(0, 0).makeGraphic(1, 1, COLOR_DIVIDER);
			line.visible = false;
			line.scrollFactor.set();
			lineSprites.add(line);
		}

		// 固定竖线：事件轨 / 玩家-对手分隔 / 外框
		var divider:FlxSprite = new FlxSprite(gridX, gridBg.y).makeGraphic(2, Std.int(gridBg.height), COLOR_DIVIDER);
		divider.scrollFactor.set();
		add(divider);
		var mid:FlxSprite = new FlxSprite(gridX + GRID_SIZE * 5, gridBg.y).makeGraphic(2, Std.int(gridBg.height), COLOR_DIVIDER);
		mid.scrollFactor.set();
		add(mid);

		// 每条轨道的细竖线（官方网格的 column separators）
		for (i in 1...LANES + 1)
		{
			if (i == 5) continue;
			var vl:FlxSprite = new FlxSprite(gridX + i * GRID_SIZE, gridBg.y).makeGraphic(1, Std.int(gridBg.height), 0xFFB8B8B8);
			vl.scrollFactor.set();
			add(vl);
		}

		measureLabels = new FlxTypedGroup<FlxText>();
		add(measureLabels);
		for (i in 0...24)
		{
			var label:FlxText = makeText(gridX - 38, 0, 34, '', 12, 0xFFFFFFFF, RIGHT);
			label.visible = false;
			measureLabels.add(label);
		}

		try
		{
			// 0.6.3 原生皮肤是已上色的四色箭头；默认 NOTE_assets 是 RGB 掩码，直接画会变红/怪色。
			noteAtlas = Paths.getSparrowAtlas('noteSkins/NOTE_assets-063');
		}
		catch (e:Dynamic)
		{
			noteAtlas = null;
			trace('[OfficialChartEditor] note atlas load failed: ' + e);
		}

		eventSprites = new FlxTypedGroup<FlxSprite>();
		add(eventSprites);
		for (i in 0...48)
		{
			var es:FlxSprite = new FlxSprite(0, 0).makeGraphic(GRID_SIZE - 10, 14, 0xFF222222);
			es.visible = false;
			es.scrollFactor.set();
			eventSprites.add(es);
		}

		holdSprites = new FlxTypedGroup<FlxSprite>();
		add(holdSprites);
		noteSprites = new FlxTypedGroup<FlxSprite>();
		add(noteSprites);
		for (i in 0...160)
		{
			var hs:FlxSprite = new FlxSprite(0, 0).makeGraphic(10, 10, 0xFFFFFFFF);
			if (noteAtlas != null) hs.frames = noteAtlas;
			hs.visible = false;
			hs.scrollFactor.set();
			holdSprites.add(hs);
			var ns:FlxSprite = new FlxSprite(0, 0).makeGraphic(GRID_SIZE - 6, GRID_SIZE - 6, 0xFFFFFFFF);
			if (noteAtlas != null) ns.frames = noteAtlas;
			ns.visible = false;
			ns.scrollFactor.set();
			noteSprites.add(ns);
		}

		playhead = new FlxSprite(0, PLAY_Y).makeGraphic(Std.int(GRID_SIZE * (LANES + 1) + 6), 5, COLOR_PLAYHEAD);
		playhead.scrollFactor.set();
		add(playhead);

		selectedRect = new FlxSprite(0, 0).makeGraphic(GRID_SIZE, GRID_SIZE, 0x00000000, true);
		selectedRect.visible = false;
		selectedRect.scrollFactor.set();
		add(selectedRect);

		previewNote = new FlxSprite(0, 0).makeGraphic(GRID_SIZE - 6, GRID_SIZE - 6, 0xFFFFFFFF);
		previewNote.alpha = 0.35;
		previewNote.visible = false;
		previewNote.scrollFactor.set();
		add(previewNote);

		buildChrome();
		buildPlaybar();
		buildToolbox();
		buildSectionPanel();

		loadAudio();

		super.create();
		status('Official chart editor UI loaded');
		trace('[OfficialChartEditor] create song=' + songName + ' sections=' + _song.notes.length + ' notes=' + flatNotes.length);
		#if sys
		var selfTest:String = null;
		try selfTest = Sys.getEnv('METEORIC_UI_SELFTEST') catch (e:Dynamic) {}
		if (selfTest == '1')
		{
			addNote(0, 0);
			addNote(0, 1);
			addNote(0, 2);
			addNote(0, 3);
			addNote(Conductor.stepCrochet * 4, 4);
			addNote(Conductor.stepCrochet * 4, 5);
			_song.notes[0].sectionNotes.push([Conductor.stepCrochet * 2, 6, 700, '']);
			rebuildFlatNotes();
		}
		#end
	}

	function addSection():Void
	{
		_song.notes.push({
			sectionBeats: 4,
			bpm: _song.bpm,
			changeBPM: false,
			mustHitSection: true,
			gfSection: false,
			sectionNotes: [],
			typeOfSection: 0,
			altAnim: false
		});
	}

	function buildChrome():Void
	{
		menuBar = new FlxSprite(0, 0).makeGraphic(FlxG.width, MENU_BAR_HEIGHT, COLOR_BAR);
		menuBar.scrollFactor.set();
		add(menuBar);

		var labels:Array<String> = ['File', 'Edit', 'View', 'Playtest', 'Help'];
		var x:Float = 256;
		for (i in 0...labels.length)
		{
			var t:FlxText = makeText(x, 6, 0, labels[i], 15, 0xFF111111, LEFT, 'future.ttf');
			t.antialiasing = ClientPrefs.data.antialiasing;
			add(t);
			menuTexts.push(t);
			menuHits.push(new FlxRect(x - 8, 0, t.width + 16, MENU_BAR_HEIGHT));
			x += t.width + 28;
		}

		notePreviewBar = new FlxSprite(EVENT_X, MENU_BAR_HEIGHT).makeGraphic(GRID_SIZE * (LANES + 1), NOTE_SELECT_BUTTON_HEIGHT, 0xFFDDDDDD);
		notePreviewBar.scrollFactor.set();
		add(notePreviewBar);

		var opp:FlxText = makeText(EVENT_X + GRID_SIZE + 4, MENU_BAR_HEIGHT + 1, 0, 'OPPONENT', 10, 0xFF333333, LEFT, 'future.ttf');
		add(opp);
		var plr:FlxText = makeText(EVENT_X + GRID_SIZE * 5 + 4, MENU_BAR_HEIGHT + 1, 0, 'PLAYER', 10, 0xFF333333, LEFT, 'future.ttf');
		add(plr);
		var evt:FlxText = makeText(EVENT_X + 6, MENU_BAR_HEIGHT + 1, 0, 'EVT', 10, 0xFF333333, LEFT, 'future.ttf');
		add(evt);

		var arrows:Array<String> = [String.fromCharCode(0x2190), String.fromCharCode(0x2193), String.fromCharCode(0x2191), String.fromCharCode(0x2192)];
		for (i in 0...4)
		{
			var oppArrow:FlxText = makeText(EVENT_X + GRID_SIZE + i * GRID_SIZE + 13, MENU_BAR_HEIGHT + 12, 0, arrows[i], 15, LANE_COLORS[i], LEFT, 'future.ttf');
			add(oppArrow);
			var plrArrow:FlxText = makeText(EVENT_X + GRID_SIZE * 5 + i * GRID_SIZE + 13, MENU_BAR_HEIGHT + 12, 0, arrows[i], 15, LANE_COLORS[i], LEFT, 'future.ttf');
			add(plrArrow);
		}
	}

	function buildPlaybar():Void
	{
		playbar = new FlxSprite(0, FlxG.height - PLAYBAR_HEIGHT).makeGraphic(FlxG.width, PLAYBAR_HEIGHT, COLOR_BAR);
		playbar.scrollFactor.set();
		add(playbar);

		timeText = makeText(10, FlxG.height - PLAYBAR_HEIGHT + 10, 0, '0:00', 26, COLOR_BAR_TEXT);
		add(timeText);
		durationText = makeText(120, FlxG.height - PLAYBAR_HEIGHT + 10, 0, '-1:00', 26, COLOR_BAR_TEXT);
		add(durationText);
		var sep:FlxSprite = new FlxSprite(210, FlxG.height - PLAYBAR_HEIGHT + 10).makeGraphic(1, PLAYBAR_HEIGHT - 20, 0xFF999999);
		sep.scrollFactor.set();
		add(sep);
		beatText = makeText(224, FlxG.height - PLAYBAR_HEIGHT + 14, 0, 'Beat: 0', 13, COLOR_BAR_TEXT, LEFT, 'future.ttf');
		add(beatText);
		stepText = makeText(310, FlxG.height - PLAYBAR_HEIGHT + 14, 0, 'Step: 0', 13, COLOR_BAR_TEXT, LEFT, 'future.ttf');
		add(stepText);

		var bx:Float = 470;
		for (i in 0...transportLabels.length)
		{
			var b:FlxText = makeText(bx, FlxG.height - PLAYBAR_HEIGHT + 8, 0, transportLabels[i], 18, COLOR_BAR_TEXT, LEFT, 'future.ttf');
			add(b);
			transportHits.push(new FlxRect(bx - 6, FlxG.height - PLAYBAR_HEIGHT + 4, b.width + 12, PLAYBAR_HEIGHT - 8));
			bx += b.width + 18;
		}
		transportActions = [
			function() seekTo(0),
			function() seekTo(Conductor.songPosition - 5000),
			togglePlay,
			function() seekTo(Conductor.songPosition + 5000),
			function() seekTo(FlxG.sound.music != null ? FlxG.sound.music.length : 0)
		];

		var rightX:Float = FlxG.width - 300;
		diffText = makeText(rightX, FlxG.height - PLAYBAR_HEIGHT + 14, 0, 'NORMAL', 13, COLOR_BAR_TEXT, LEFT, 'future.ttf');
		add(diffText);
		bpmText = makeText(rightX + 92, FlxG.height - PLAYBAR_HEIGHT + 14, 0, 'BPM: ' + Std.int(_song.bpm), 13, COLOR_BAR_TEXT, LEFT, 'future.ttf');
		add(bpmText);
		snapText = makeText(rightX + 180, FlxG.height - PLAYBAR_HEIGHT + 14, 0, '1/16', 13, COLOR_BAR_TEXT, LEFT, 'future.ttf');
		add(snapText);
	}

	function buildToolbox():Void
	{
		toolPanel = new FlxSprite(16, 110).makeGraphic(280, 300, 0xF2FFFFFF, true);
		FlxSpriteUtil.drawRect(toolPanel, 0, 0, 280, 300, 0xF2FFFFFF, {color: 0xFF888888, thickness: 1});
		toolPanel.scrollFactor.set();
		add(toolPanel);
		toolTitle = makeText(28, 118, 0, 'Notes', 18, 0xFF222222);
		add(toolTitle);
		toolToggle = makeText(266, 120, 0, '-', 18, 0xFF222222);
		add(toolToggle);
		var lines:Array<String> = ['Snap: 1/16', 'Type: Default', '', 'LMB: note/event', 'RMB: delete', 'Space: play / pause', 'Esc: playtest'];
		for (i in 0...lines.length)
		{
			var ln:FlxText = makeText(28, 150 + i * 20, 0, lines[i], 12, 0xFF333333);
			add(ln);
			toolLines.push(ln);
		}

		var songLabel:FlxText = makeText(28, 300, 0, 'Song folder', 11, 0xFF333333, LEFT, 'future.ttf');
		add(songLabel);
		songInput = new FlxInputText(28, 318, 180, '', 12, 0xFF222222, 0xFFFFFFFF);
		songInput.text = songName;
		songInput.backgroundColor = 0xFFFFFFFF;
		songInput.fieldBorderColor = 0xFF999999;
		songInput.callback = function(text:String, action:String)
		{
			if (action == FlxInputText.ENTER_ACTION) openSong(text);
		};
		add(songInput);
		addPanelButton(214, 318, 70, 28, 'Open', function() openSong(songInput.text));
	}

	function buildSectionPanel():Void
	{
		var px:Float = FlxG.width - 300;
		var py:Float = 110;
		var panel:FlxSprite = new FlxSprite(px, py).makeGraphic(284, 470, 0xF2FFFFFF, true);
		FlxSpriteUtil.drawRect(panel, 0, 0, 284, 470, 0xF2FFFFFF, {color: 0xFF888888, thickness: 1});
		panel.scrollFactor.set();
		add(panel);
		var title:FlxText = makeText(px + 12, py + 8, 0, 'Section / Events', 16, 0xFF222222, LEFT, 'future.ttf');
		add(title);
		sectionInfo = makeText(px + 12, py + 38, 0, '', 11, 0xFF333333, LEFT, 'future.ttf');
		add(sectionInfo);
		eventInfo = makeText(px + 12, py + 206, 0, '', 11, 0xFF333333, LEFT, 'future.ttf');
		add(eventInfo);

		var bw:Float = 126;
		var bh:Float = 28;
		addPanelButton(px + 12, py + 64, bw, bh, 'BPM -', function() changeSectionBpm(-5));
		addPanelButton(px + 146, py + 64, bw, bh, 'BPM +', function() changeSectionBpm(5));
		addPanelButton(px + 12, py + 98, bw, bh, 'MustHit', toggleMustHit);
		addPanelButton(px + 146, py + 98, bw, bh, 'Add Section', addSectionAtPlayhead);
		addPanelButton(px + 12, py + 132, bw, bh, 'Remove Sec', removeSectionAtPlayhead);
		addPanelButton(px + 146, py + 132, bw, bh, 'Event Type', cycleEventType);
		addPanelButton(px + 12, py + 166, bw, bh, 'Add Event', addEventAtPlayhead);
		addPanelButton(px + 146, py + 166, bw, bh, 'Del Event', deleteEventAtPlayhead);
		addPanelButton(px + 12, py + 232, bw, bh, 'Undo', undoEdit);
		addPanelButton(px + 146, py + 232, bw, bh, 'Redo', redoEdit);
		addPanelButton(px + 12, py + 266, bw, bh, 'Playtest', startPlaytest);
		addPanelButton(px + 146, py + 266, bw, bh, 'Save', saveChart);
		addPanelButton(px + 12, py + 300, bw, bh, 'Hold -', function() changeSelectedHold(-1));
		addPanelButton(px + 146, py + 300, bw, bh, 'Hold +', function() changeSelectedHold(1));
		addPanelButton(px + 12, py + 334, bw, bh, 'Delete Note', deleteSelectedNote);
		addPanelButton(px + 146, py + 334, bw, bh, 'Cycle Type', cycleNoteType);
		var v1Label:FlxText = makeText(px + 12, py + 370, 0, 'Event Value 1', 10, 0xFF333333, LEFT, 'future.ttf');
		var v2Label:FlxText = makeText(px + 12, py + 404, 0, 'Event Value 2', 10, 0xFF333333, LEFT, 'future.ttf');
		add(v1Label);
		add(v2Label);
		eventValue1 = new FlxInputText(px + 12, py + 384, 126, '', 11, 0xFF222222, 0xFFFFFFFF);
		eventValue1.backgroundColor = 0xFFFFFFFF;
		eventValue1.fieldBorderColor = 0xFF999999;
		eventValue1.callback = function(text:String, action:String) applyEventValue(1, text);
		add(eventValue1);
		eventValue2 = new FlxInputText(px + 146, py + 384, 126, '', 11, 0xFF222222, 0xFFFFFFFF);
		eventValue2.backgroundColor = 0xFFFFFFFF;
		eventValue2.fieldBorderColor = 0xFF999999;
		eventValue2.callback = function(text:String, action:String) applyEventValue(2, text);
		add(eventValue2);
		var hint:FlxText = makeText(px + 12, py + 430, 0, 'E eraser  Del note  Ctrl+Z/Y  Bksp menu', 10, 0xFF555555, LEFT, 'future.ttf');
		add(hint);
	}

	function addPanelButton(x:Float, y:Float, w:Float, h:Float, label:String, action:Void->Void):Void
	{
		var bg:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), 0xFFDDDDDD);
		bg.scrollFactor.set();
		add(bg);
		var txt:FlxText = makeText(x + 6, y + 6, 0, label, 12, 0xFF222222, LEFT, 'future.ttf');
		add(txt);
		panelButtons.push({bg: bg, txt: txt, x: x, y: y, w: w, h: h, action: action});
	}

	function updatePanel():Void
	{
		var sec:Int = sectionForTime(Conductor.songPosition);
		if (sectionInfo != null && _song.notes[sec] != null)
		{
			sectionInfo.text = 'Section ' + sec + ' / ' + getSectionBeats(sec) + ' beats\nBPM ' + Std.int(getSectionBpm(sec)) + '  ' + (getSectionBpm(sec) != getSectionBpm(sec - 1) ? 'CHANGE' : '') + '  Secs ' + _song.notes.length;
		}
		if (eventInfo != null) eventInfo.text = 'Event: ' + (selectedEvent != null ? selectedEvent[1][0][0] : '(none)') + '\nEvents: ' + _song.events.length;
		if (selectedEvent != null && eventValue1 != null && !eventValue1.hasFocus) eventValue1.text = Std.string(selectedEvent[1][0][1]);
		if (selectedEvent != null && eventValue2 != null && !eventValue2.hasFocus) eventValue2.text = Std.string(selectedEvent[1][0][2]);
	}

	function getSectionBpm(index:Int):Float
	{
		if (index < 0 || index >= _song.notes.length) return _song.bpm;
		var bpm:Float = _song.bpm;
		for (i in 0...index + 1) if (_song.notes[i].changeBPM) bpm = _song.notes[i].bpm;
		return bpm;
	}

	function getSectionBeats(index:Int):Float
	{
		if (index < 0 || index >= _song.notes.length) return 4;
		return _song.notes[index].sectionBeats > 0 ? _song.notes[index].sectionBeats : 4;
	}

	function changeSectionBpm(delta:Float):Void
	{
		var sec:Int = sectionForTime(Conductor.songPosition);
		pushUndo();
		_song.notes[sec].changeBPM = true;
		_song.notes[sec].bpm = Math.max(1, getSectionBpm(sec) + delta);
		afterChartStructureChange();
		status('BPM -> ' + Std.int(_song.notes[sec].bpm));
	}

	function toggleMustHit():Void
	{
		var sec:Int = sectionForTime(Conductor.songPosition);
		pushUndo();
		_song.notes[sec].mustHitSection = !_song.notes[sec].mustHitSection;
		rebuildFlatNotes();
		status('MustHit -> ' + _song.notes[sec].mustHitSection);
	}

	function addSectionAtPlayhead():Void
	{
		var sec:Int = sectionForTime(Conductor.songPosition);
		pushUndo();
		var newSec:SwagSection = {
			sectionBeats: getSectionBeats(sec),
			bpm: getSectionBpm(sec),
			changeBPM: false,
			mustHitSection: _song.notes[sec].mustHitSection,
			gfSection: false,
			sectionNotes: [],
			typeOfSection: 0,
			altAnim: false
		};
		_song.notes.insert(sec + 1, newSec);
		afterChartStructureChange();
		status('Section added');
	}

	function removeSectionAtPlayhead():Void
	{
		if (_song.notes.length <= 1)
		{
			status('Cannot remove the only section');
			return;
		}
		var sec:Int = sectionForTime(Conductor.songPosition);
		pushUndo();
		_song.notes.splice(sec, 1);
		afterChartStructureChange();
		status('Section removed');
	}

	function cycleEventType():Void
	{
		eventTypeIndex = (eventTypeIndex + 1) % eventTypes.length;
		updatePanel();
	}

	function addEventAtPlayhead():Void
	{
		addEventAt(snapTime(Conductor.songPosition));
	}

	function applyEventValue(which:Int, text:String):Void
	{
		if (selectedEvent == null) return;
		if (selectedEvent[1] == null || selectedEvent[1].length == 0) return;
		selectedEvent[1][0][which] = text;
	}

	function selectEventNear(time:Float):Bool
	{
		var best:Dynamic = null;
		var bestDist:Float = 1000000;
		for (e in _song.events)
		{
			var d:Float = Math.abs(e[0] - time);
			if (d < bestDist)
			{
				bestDist = d;
				best = e;
			}
		}
		if (best != null && bestDist < 1200)
		{
			selectedEvent = best;
			selectedNote = null;
			status('Selected event: ' + best[1][0][0]);
			return true;
		}
		selectedEvent = null;
		return false;
	}

	function addEventAt(time:Float):Void
	{
		if (eventTypeIndex == 0)
		{
			status('Choose an event type first');
			return;
		}
		if (_song.events == null) _song.events = [];
		pushUndo();
		_song.events.push([time, [[eventTypes[eventTypeIndex], '', '']]]);
		status('Event added: ' + eventTypes[eventTypeIndex]);
	}

	function deleteEventNear(time:Float):Void
	{
		var best:Int = -1;
		var bestDist:Float = 1000000;
		for (i in 0..._song.events.length)
		{
			var d:Float = Math.abs(_song.events[i][0] - time);
			if (d < bestDist)
			{
				bestDist = d;
				best = i;
			}
		}
		if (best >= 0 && bestDist < 1500)
		{
			pushUndo();
			_song.events.splice(best, 1);
			status('Event removed');
		}
	}

	function deleteEventAtPlayhead():Void
	{
		var time:Float = snapTime(Conductor.songPosition);
		var best:Int = -1;
		var bestDist:Float = 1000000;
		for (i in 0..._song.events.length)
		{
			var d:Float = Math.abs(_song.events[i][0] - time);
			if (d < bestDist)
			{
				bestDist = d;
				best = i;
			}
		}
		if (best >= 0 && bestDist < 1500)
		{
			pushUndo();
			_song.events.splice(best, 1);
			status('Event removed');
		}
		else status('No event near playhead');
	}

	function pushUndo():Void
	{
		undoStack.push(haxe.Json.stringify({song: _song}));
		if (undoStack.length > 40) undoStack.shift();
		redoStack = [];
	}

	function undoEdit():Void
	{
		if (undoStack.length == 0)
		{
			status('Nothing to undo');
			return;
		}
		redoStack.push(haxe.Json.stringify({song: _song}));
		var data:Dynamic = haxe.Json.parse(undoStack.pop());
		_song = data.song;
		afterChartStructureChange();
		status('Undo');
	}

	function redoEdit():Void
	{
		if (redoStack.length == 0)
		{
			status('Nothing to redo');
			return;
		}
		undoStack.push(haxe.Json.stringify({song: _song}));
		var data:Dynamic = haxe.Json.parse(redoStack.pop());
		_song = data.song;
		afterChartStructureChange();
		status('Redo');
	}

	function afterChartStructureChange():Void
	{
		if (_song.events == null) _song.events = [];
		PlayState.setSong(_song);
		Conductor.bpm = _song.bpm;
		Conductor.mapBPMChanges(_song);
		recalculateSections();
		rebuildFlatNotes();
		updatePanel();
	}

	function startPlaytest():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.pause();
		PlayState.setSong(_song);
		openSubState(new states.editors.EditorPlayState(1));
	}

	override function closeSubState():Void
	{
		super.closeSubState();
		loadAudio();
		Conductor.syncToMusic();
	}

	function loadAudio():Void
	{
		try
		{
			if (FlxG.sound.music != null) FlxG.sound.music.stop();
			FlxG.sound.playMusic(Paths.inst(songName), 0.7);
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				FlxG.sound.music.time = 0;
				Conductor.setPosition(0);
			}
			else status('Audio missing: ' + songName);
		}
		catch (e:Dynamic)
		{
			status('Audio missing: ' + songName);
		}
	}

	override function update(elapsed:Float):Void
	{
		Conductor.syncToMusic();
		if (FlxG.sound.music != null && FlxG.sound.music.playing) Conductor.syncToMusic();

		var pos:Float = Conductor.songPosition;
		if (FlxG.sound.music != null && pos > FlxG.sound.music.length)
		{
			FlxG.sound.music.pause();
			playing = false;
			seekTo(0);
		}

		updatePlaybar(pos);
		updateGrid(pos);
		updateNotes(pos);
		updateEvents(pos);
		updatePanel();
		updateInput(elapsed);
		frameCount++;
		#if sys
		if (frameCount == 20)
		{
			var playtestFlag:String = null;
			try playtestFlag = Sys.getEnv('METEORIC_UI_PLAYTEST') catch (e:Dynamic) {}
			if (playtestFlag == '1') startPlaytest();
		}
		#end
		if (!loggedFirstFrame)
		{
			loggedFirstFrame = true;
			trace('[OfficialChartEditor] first frame pos=' + pos + ' bpm=' + Conductor.bpm + ' cam=' + FlxG.camera.width + 'x' + FlxG.camera.height);
		}
		#if sys
		if (frameCount == 5)
		{
			var shotPath:String = null;
			try shotPath = Sys.getEnv('METEORIC_UI_SHOT') catch (e:Dynamic) {}
			trace('[OfficialChartEditor] shot env=' + shotPath + ' buffer=' + (FlxG.camera.buffer != null));
			if (shotPath != null && shotPath.length > 0 && FlxG.camera.buffer != null)
			{
				try
				{
					var bd = FlxG.camera.buffer;
					var png = bd.encode(bd.rect, 'png');
					File.saveBytes(shotPath, haxe.io.Bytes.ofData(png));
					trace('[OfficialChartEditor] screenshot=' + shotPath);
				}
				catch (e:Dynamic) trace('[OfficialChartEditor] screenshot failed: ' + e);
			}
		}
		#end

		FlxG.mouse.visible = true;
		super.update(elapsed);
	}

	function updatePlaybar(pos:Float):Void
	{
		var total:Float = FlxG.sound.music != null ? FlxG.sound.music.length : 0;
		timeText.text = formatTime(pos);
		durationText.text = '-' + formatTime(Math.max(0, total - pos));
		beatText.text = 'Beat: ' + Std.int(curBeat);
		stepText.text = 'Step: ' + Std.int(curStep);
		bpmText.text = 'BPM: ' + Std.int(Conductor.bpm);
		snapText.text = '1/' + snaps[snapIndex];
		diffText.text = Difficulty.getString() != null ? Difficulty.getString().toUpperCase() : 'NORMAL';
	}

	function updateGrid(pos:Float):Void
	{
		var top:Float = MENU_BAR_HEIGHT + GRID_TOP_PAD;
		var bottom:Float = FlxG.height - PLAYBAR_HEIGHT;
		var curStepF:Float = stepAtTime(pos);
		var i:Int = 0;
		var step:Int = Std.int(Math.floor(curStepF)) - 8;
		var maxStep:Int = Std.int(curStepF + (bottom - PLAY_Y) / (GRID_SIZE * zoom)) + 4;
		while (step < maxStep)
		{
			if (i >= lineSprites.length) break;
			var y:Float = PLAY_Y + (step - curStepF) * GRID_SIZE * zoom;
			if (y < top || y > bottom)
			{
				step++;
				continue;
			}
			var line:FlxSprite = lineSprites.members[i];
			line.visible = true;
			line.x = EVENT_X;
			line.y = y;
			var isMeasure:Bool = step % 16 == 0;
			var isBeat:Bool = step % 4 == 0;
			line.makeGraphic(Std.int(GRID_SIZE * (LANES + 1)), isMeasure ? 4 : (isBeat ? 2 : 1), isMeasure ? 0xFF222222 : (isBeat ? 0xFF666666 : 0xFF9A9A9A));
			line.alpha = 1;
			i++;
			step++;
		}
		for (j in i...lineSprites.length) lineSprites.members[j].visible = false;

		playhead.y = PLAY_Y;
		playhead.x = EVENT_X - 3;

		// 小节号：按 section 起始时间映射到 step 坐标
		var labelIndex:Int = 0;
		for (s in 0...sectionStarts.length)
		{
			var y:Float = PLAY_Y + (stepAtTime(sectionStarts[s]) - curStepF) * GRID_SIZE * zoom;
			if (y < top || y > bottom) continue;
			if (labelIndex >= measureLabels.length) break;
			var label:FlxText = measureLabels.members[labelIndex];
			label.visible = true;
			label.text = Std.string(s + 1);
			label.y = y - 8;
			labelIndex++;
		}
		for (j in labelIndex...measureLabels.length) measureLabels.members[j].visible = false;
		lastStep = curStep;
	}

	function updateNotes(pos:Float):Void
	{
		var curStepF:Float = stepAtTime(pos);
		var top:Float = MENU_BAR_HEIGHT + GRID_TOP_PAD;
		var bottom:Float = FlxG.height - PLAYBAR_HEIGHT;
		var noteIndex:Int = 0;
		var holdIndex:Int = 0;
		for (n in flatNotes)
		{
			var y:Float = PLAY_Y + (stepAtTime(n.time) - curStepF) * GRID_SIZE * zoom;
			if (y < top - GRID_SIZE || y > bottom + GRID_SIZE) continue;
			if (noteIndex >= noteSprites.length) break;
			var spr:FlxSprite = noteSprites.members[noteIndex];
			spr.visible = true;
			spr.x = EVENT_X + GRID_SIZE + (n.data % LANES) * GRID_SIZE + 3;
			spr.y = y - GRID_SIZE / 2;
			if (noteAtlas != null)
			{
				var skin:String = ['purple', 'blue', 'green', 'red'][n.data % 4];
				var frame = noteAtlas.getByName(skin + '0000');
				if (frame != null)
				{
					spr.frame = frame;
					spr.setGraphicSize(GRID_SIZE - 4, GRID_SIZE - 4);
					spr.updateHitbox();
					spr.color = 0xFFFFFFFF;
				}
				else spr.color = LANE_COLORS[n.data % 4];
			}
			else spr.color = LANE_COLORS[n.data % 4];
			spr.alpha = n.data >= ExtraKeys.songKeys ? 0.7 : 1;
			noteIndex++;

			if (n.sus > 0 && holdIndex < holdSprites.length)
			{
				var h:FlxSprite = holdSprites.members[holdIndex];
				h.visible = true;
				h.x = spr.x + 14;
				h.y = spr.y + GRID_SIZE - 6;
				h.setGraphicSize(12, Std.int(Math.max(2, (stepAtTime(n.time + n.sus) - stepAtTime(n.time)) * GRID_SIZE * zoom)));
				h.updateHitbox();
				if (noteAtlas != null)
				{
					var skin:String = ['purple', 'blue', 'green', 'red'][n.data % 4];
					var hf = noteAtlas.getByName(skin + ' hold piece0000');
					if (hf != null)
					{
						h.frame = hf;
						h.setGraphicSize(12, Std.int(Math.max(2, (stepAtTime(n.time + n.sus) - stepAtTime(n.time)) * GRID_SIZE * zoom)));
						h.updateHitbox();
						h.color = 0xFFFFFFFF;
					}
					else h.color = LANE_COLORS[n.data % 4];
				}
				else h.color = LANE_COLORS[n.data % 4];
				h.alpha = 0.9;
				holdIndex++;
			}
		}
		for (j in noteIndex...noteSprites.length) noteSprites.members[j].visible = false;
		for (j in holdIndex...holdSprites.length) holdSprites.members[j].visible = false;
		if (selectedNote != null && selectedRect != null)
		{
			selectedRect.visible = true;
			selectedRect.x = EVENT_X + GRID_SIZE + (selectedNote.data % LANES) * GRID_SIZE - 2;
			selectedRect.y = PLAY_Y + (stepAtTime(selectedNote.time) - curStepF) * GRID_SIZE * zoom - 2;
			selectedRect.makeGraphic(GRID_SIZE + 4, GRID_SIZE + 4, 0x00000000, true);
			FlxSpriteUtil.drawRect(selectedRect, 0, 0, GRID_SIZE + 4, GRID_SIZE + 4, 0x00000000, {color: 0xFFFFFFFF, thickness: 2});
		}
		else if (selectedRect != null) selectedRect.visible = false;
	}

	function updateEvents(pos:Float):Void
	{
		if (eventSprites == null) return;
		var curStepF:Float = stepAtTime(pos);
		var top:Float = MENU_BAR_HEIGHT + GRID_TOP_PAD;
		var bottom:Float = FlxG.height - PLAYBAR_HEIGHT;
		var idx:Int = 0;
		if (_song.events != null)
		{
			for (e in _song.events)
			{
				if (idx >= eventSprites.length) break;
				var y:Float = PLAY_Y + (stepAtTime(e[0]) - curStepF) * GRID_SIZE * zoom;
				if (y < top - 20 || y > bottom + 20) continue;
				var spr:FlxSprite = eventSprites.members[idx];
				spr.visible = true;
				spr.x = EVENT_X + 6;
				spr.y = y - 7;
				spr.color = 0xFF222222;
				spr.alpha = 0.9;
				idx++;
			}
		}
		for (j in idx...eventSprites.length) eventSprites.members[j].visible = false;
	}

	function updateInput(elapsed:Float):Void
	{
		var mouse:FlxPoint = FlxG.mouse.getPositionInCameraView(FlxG.camera, FlxPoint.get());
		var top:Float = MENU_BAR_HEIGHT + GRID_TOP_PAD;
		var bottom:Float = FlxG.height - PLAYBAR_HEIGHT;

		// 右侧小节/事件面板按钮
		for (b in panelButtons)
		{
			var hover:Bool = mouse.x >= b.x && mouse.x <= b.x + b.w && mouse.y >= b.y && mouse.y <= b.y + b.h;
			b.bg.color = hover ? 0xFFC8C8C8 : 0xFFDDDDDD;
			if (FlxG.mouse.justPressed && hover)
			{
				b.action();
				return;
			}
		}

		for (i in 0...menuHits.length)
		{
			var hit:Bool = (mouse.x >= menuHits[i].x && mouse.x <= menuHits[i].x + menuHits[i].width && mouse.y >= menuHits[i].y && mouse.y <= menuHits[i].y + menuHits[i].height);
			menuTexts[i].color = hit ? COLOR_ACCENT : COLOR_BAR_TEXT;
			if (FlxG.mouse.justPressed && hit) toggleMenu(i);
		}

		for (i in 0...transportHits.length)
		{
			if (FlxG.mouse.justPressed && (mouse.x >= transportHits[i].x && mouse.x <= transportHits[i].x + transportHits[i].width && mouse.y >= transportHits[i].y && mouse.y <= transportHits[i].y + transportHits[i].height) && i < transportActions.length)
			{
				transportActions[i]();
				break;
			}
		}

		if (FlxG.mouse.justPressed && activeMenu >= 0)
		{
			for (i in 0...menuItems.length)
			{
				if (menuItems[i].visible && menuItems[i].overlapsPoint(mouse))
				{
					activeMenu = -1;
					closeMenu();
					if (i < menuItemActions.length) menuItemActions[i]();
					break;
				}
			}
		}

		// 输入框聚焦时只让 FlxInputText 处理按键，避免空格/方向键同时触发编辑器快捷键
		if ((songInput != null && songInput.hasFocus) || (eventValue1 != null && eventValue1.hasFocus) || (eventValue2 != null && eventValue2.hasFocus))
			return;

		// 吸附预览：鼠标下方的虚影落在实际会放置的 step 上，避免“点这里、音符飞到那里”的错觉
		var overGrid:Bool = mouse.y > top && mouse.y < bottom && mouse.x >= EVENT_X && mouse.x <= EVENT_X + GRID_SIZE * (LANES + 1);
		if (overGrid && previewNote != null)
		{
			var curStepF:Float = stepAtTime(Conductor.songPosition);
			var pTime:Float = snapTime(timeAtStep(curStepF + (mouse.y - PLAY_Y) / (GRID_SIZE * zoom)));
			var pY:Float = PLAY_Y + (stepAtTime(pTime) - curStepF) * GRID_SIZE * zoom;
			previewNote.visible = true;
			previewNote.y = pY - GRID_SIZE / 2;
			if (mouse.x < EVENT_X + GRID_SIZE)
			{
				previewNote.x = EVENT_X + 8;
				previewNote.setGraphicSize(GRID_SIZE - 16, 14);
				previewNote.updateHitbox();
				previewNote.color = 0xFF222222;
			}
			else
			{
				var pLane:Int = Std.int((mouse.x - EVENT_X) / GRID_SIZE) - 1;
				previewNote.x = EVENT_X + GRID_SIZE + pLane * GRID_SIZE + 3;
				previewNote.setGraphicSize(GRID_SIZE - 6, GRID_SIZE - 6);
				previewNote.updateHitbox();
				previewNote.color = LANE_COLORS[pLane % 4];
			}
		}
		else if (previewNote != null) previewNote.visible = false;

		if (FlxG.mouse.wheel != 0 && mouse.y > top && mouse.y < bottom)
		{
			if (FlxG.sound.music == null) return;
			FlxG.sound.music.pause();
			playing = false;
			seekTo(Conductor.songPosition - FlxG.mouse.wheel * Conductor.stepCrochet);
		}

		if (FlxG.mouse.justPressed && mouse.x >= EVENT_X && mouse.x < EVENT_X + GRID_SIZE && mouse.y > top && mouse.y < bottom)
		{
			var et:Float = snapTime(timeAtStep(stepAtTime(Conductor.songPosition) + (mouse.y - PLAY_Y) / (GRID_SIZE * zoom)));
			if (!selectEventNear(et)) addEventAt(et);
		}
		else if (FlxG.mouse.justPressedRight && mouse.x >= EVENT_X && mouse.x < EVENT_X + GRID_SIZE && mouse.y > top && mouse.y < bottom)
		{
			deleteEventNear(snapTime(timeAtStep(stepAtTime(Conductor.songPosition) + (mouse.y - PLAY_Y) / (GRID_SIZE * zoom))));
		}
		else if (FlxG.mouse.justPressed && mouse.x >= EVENT_X + GRID_SIZE && mouse.x <= EVENT_X + GRID_SIZE * (LANES + 1) && mouse.y > top && mouse.y < bottom)
		{
			var lane:Int = Std.int((mouse.x - EVENT_X) / GRID_SIZE) - 1;
			var time:Float = snapTime(timeAtStep(stepAtTime(Conductor.songPosition) + (mouse.y - PLAY_Y) / (GRID_SIZE * zoom)));
			// 吸附后的落点由 previewNote 显示，不在此处打日志（避免每点一次刷屏）
			var existing:EditorNote = findNote(time, lane);
			if (existing != null)
			{
				if (eraserMode) deleteNote(existing);
				else
				{
					selectedNote = existing;
					status('Selected ' + Std.int(existing.time) + 'ms lane ' + lane + ' hold ' + Std.int(existing.sus));
				}
			}
			else if (!eraserMode)
			{
				addNote(time, lane);
			}
		}
		else if (FlxG.mouse.justPressedRight && mouse.x >= EVENT_X + GRID_SIZE && mouse.x <= EVENT_X + GRID_SIZE * (LANES + 1) && mouse.y > top && mouse.y < bottom)
		{
			var lane:Int = Std.int((mouse.x - EVENT_X) / GRID_SIZE) - 1;
			var time:Float = snapTime(timeAtStep(stepAtTime(Conductor.songPosition) + (mouse.y - PLAY_Y) / (GRID_SIZE * zoom)));
			// 吸附后的落点由 previewNote 显示，不在此处打日志（避免每点一次刷屏）
			var existing:EditorNote = findNote(time, lane);
			if (existing != null) deleteNote(existing);
		}

		if (FlxG.keys.justPressed.SPACE) togglePlay();
		if (FlxG.keys.justPressed.W) seekTo(Conductor.songPosition - 1000);
		if (FlxG.keys.justPressed.S) seekTo(Conductor.songPosition + 1000);
		if (FlxG.keys.justPressed.LEFT)
		{
			snapIndex = (snapIndex + snaps.length - 1) % snaps.length;
		}
		if (FlxG.keys.justPressed.RIGHT) snapIndex = (snapIndex + 1) % snaps.length;
		if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.F1)
		{
			startPlaytest();
			return;
		}
		if (FlxG.keys.justPressed.BACKSPACE)
		{
			backToMenu();
			return;
		}
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Z) undoEdit();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Y) redoEdit();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S) saveChart();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.O) focusSongInput();
		if (FlxG.keys.justPressed.E)
		{
			eraserMode = !eraserMode;
			status(eraserMode ? 'Eraser ON (click note)' : 'Eraser OFF');
		}
		if (FlxG.keys.justPressed.DELETE && selectedNote != null) deleteSelectedNote();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.D)
		{
			selectedNote = null;
			status('Selection cleared');
		}
		if (FlxG.keys.justPressed.LBRACKET && sectionStarts.length > 0)
		{
			var sec:Int = sectionForTime(Conductor.songPosition);
			if (sec > 0) seekTo(sectionStarts[sec - 1]);
		}
		if (FlxG.keys.justPressed.RBRACKET && sectionStarts.length > 0)
		{
			var sec:Int = sectionForTime(Conductor.songPosition);
			if (sec + 1 < sectionStarts.length) seekTo(sectionStarts[sec + 1]);
		}

		if (toastTimer > 0)
		{
			toastTimer -= elapsed;
			if (toastTimer <= 0) statusText.visible = false;
		}
	}

	function toggleMenu(index:Int):Void
	{
		if (activeMenu == index)
		{
			activeMenu = -1;
			closeMenu();
			return;
		}
		activeMenu = index;
		openMenu(index);
	}

	function openMenu(index:Int):Void
	{
		closeMenu();
		var items:Array<String> = switch (index)
		{
			case 0: ['Open Chart...', 'Save Chart', 'Export JSON', 'Exit'];
			case 1: ['Delete Note', 'Clear Section', 'Select All'];
			case 2: ['Reset Zoom', 'Toggle Dark Theme'];
			case 3: ['Play / Pause', 'Restart'];
			default: ['About', 'Classic Editor'];
		}
		var y:Float = MENU_BAR_HEIGHT;
		var w:Float = 190;
		menuPanel = new FlxSprite(menuHits[index].x, y).makeGraphic(Std.int(w), items.length * 28 + 8, 0xF8FFFFFF, true);
		FlxSpriteUtil.drawRect(menuPanel, 0, 0, w, items.length * 28 + 8, 0xF8FFFFFF, {color: 0xFF888888, thickness: 1});
		menuPanel.scrollFactor.set();
		add(menuPanel);
		for (i in 0...items.length)
		{
			var t:FlxText = makeText(menuHits[index].x + 10, y + 4 + i * 28, 0, items[i], 13, 0xFF222222);
			add(t);
			menuItems.push(t);
		}
		menuItemActions = switch (index)
		{
			case 0: [focusSongInput, saveChart, exportChart, backToMenu];
			case 1: [deleteSelectedOrLast, clearSection, selectAllPlaceholder];
			case 2: [resetZoom, toggleThemePlaceholder];
			case 3: [togglePlay, restartSong];
			default: [aboutPlaceholder, useClassicEditor];
		}
	}

	function closeMenu():Void
	{
		if (menuPanel != null)
		{
			remove(menuPanel);
			menuPanel.destroy();
			menuPanel = null;
		}
		for (t in menuItems)
		{
			remove(t);
			t.destroy();
		}
		menuItems = [];
		menuItemActions = [];
	}

	function addNote(time:Float, lane:Int):Void
	{
		pushUndo();
		var sec:Int = sectionForTime(time);
		var note:Array<Dynamic> = [time, lane, 0, noteTypes[noteTypeIndex]];
		_song.notes[sec].sectionNotes.push(note);
		rebuildFlatNotes();
		selectedNote = findNote(time, lane);
		status('Note added @ ' + Std.int(time) + 'ms lane ' + lane);
	}

	function deleteNote(n:EditorNote):Void
	{
		pushUndo();
		if (selectedNote == n) selectedNote = null;
		var sec:Int = sectionForTime(n.time);
		for (i in _song.notes[sec].sectionNotes)
		{
			if (Std.int(i[0]) == Std.int(n.time) && Std.int(i[1]) == n.data)
			{
				_song.notes[sec].sectionNotes.remove(i);
				break;
			}
		}
		rebuildFlatNotes();
		status('Note deleted');
	}

	function findNote(time:Float, lane:Int):EditorNote
	{
		for (n in flatNotes)
		{
			if (n.data == lane && Math.abs(n.time - time) < stepMsAtTime(time) * 0.45) return n;
		}
		return null;
	}

	function changeSelectedHold(dir:Int):Void
	{
		if (selectedNote == null)
		{
			status('Select a note first');
			return;
		}
		pushUndo();
		var sec:Int = sectionForTime(selectedNote.time);
		for (n in _song.notes[sec].sectionNotes)
		{
			if (Std.int(n[0]) == Std.int(selectedNote.time) && Std.int(n[1]) == selectedNote.data)
			{
				n[2] = Math.max(0, (n[2] != null ? n[2] : 0) + dir * Conductor.stepCrochet);
				break;
			}
		}
		rebuildFlatNotes();
		selectedNote = findNote(selectedNote.time, selectedNote.data);
		status('Hold ' + (selectedNote != null ? Std.int(selectedNote.sus) + 'ms' : ''));
	}

	function deleteSelectedNote():Void
	{
		if (selectedNote == null)
		{
			status('Select a note first');
			return;
		}
		deleteNote(selectedNote);
		selectedNote = null;
	}

	function cycleNoteType():Void
	{
		if (selectedNote == null)
		{
			status('Select a note first');
			return;
		}
		noteTypeIndex = (noteTypeIndex + 1) % noteTypes.length;
		pushUndo();
		var sec:Int = sectionForTime(selectedNote.time);
		for (n in _song.notes[sec].sectionNotes)
		{
			if (Std.int(n[0]) == Std.int(selectedNote.time) && Std.int(n[1]) == selectedNote.data)
			{
				n[3] = noteTypes[noteTypeIndex];
				break;
			}
		}
		rebuildFlatNotes();
		selectedNote = findNote(selectedNote.time, selectedNote.data);
		status('Type: ' + (noteTypes[noteTypeIndex].length > 0 ? noteTypes[noteTypeIndex] : 'Default'));
	}

	function deleteSelectedOrLast():Void
	{
		if (flatNotes.length > 0) deleteNote(flatNotes[flatNotes.length - 1]);
	}

	function clearSection():Void
	{
		var sec:Int = sectionForTime(Conductor.songPosition);
		if (_song.notes[sec] != null) _song.notes[sec].sectionNotes = [];
		rebuildFlatNotes();
		status('Section cleared');
	}

	function selectAllPlaceholder():Void
	{
		status('Selection UI not wired yet');
	}

	function resetZoom():Void
	{
		zoom = 1;
	}

	function toggleThemePlaceholder():Void
	{
		status('Theme toggle not wired yet');
	}

	function aboutPlaceholder():Void
	{
		status('Official FNF 0.8.7 chart editor UI port');
	}

	function useClassicEditor():Void
	{
		bridge.EditorBridge.classicEditorRequested = true;
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		MusicBeatState.switchState(new states.editors.ChartingState());
	}

	function togglePlay():Void
	{
		if (FlxG.sound.music == null) return;
		if (FlxG.sound.music.playing)
		{
			FlxG.sound.music.pause();
			playing = false;
		}
		else
		{
			FlxG.sound.music.play();
			playing = true;
		}
	}

	function seekTo(ms:Float):Void
	{
		if (FlxG.sound.music == null) return;
		FlxG.sound.music.pause();
		FlxG.sound.music.time = Math.max(0, Math.min(FlxG.sound.music.length, ms));
		Conductor.setPosition(FlxG.sound.music.time);
		playing = false;
	}

	function restartSong():Void
	{
		seekTo(0);
	}

	function focusSongInput():Void
	{
		if (songInput != null)
		{
			songInput.text = '';
			songInput.hasFocus = true;
		}
		status('Type song folder + Enter');
	}

	function openSong(name:String):Void
	{
		if (name == null) return;
		var path:String = Paths.formatToSongPath(name.trim());
		if (path.length == 0) return;
		try
		{
			var diff:String = Difficulty.getString();
			if (diff == Difficulty.getDefault()) diff = null;
			var chart:String = path + (diff != null && diff.length > 0 ? '-' + diff : '');
			var loaded:SwagSong = Song.loadFromJson(chart, path);
			if (loaded == null) throw 'null chart';
			_song = loaded;
			songName = path;
			if (_song.keys == null) _song.keys = 4;
			ExtraKeys.setSongKeys(_song.keys);
			PlayState.setSong(_song);
			Conductor.bpm = _song.bpm;
			Conductor.mapBPMChanges(_song);
			recalculateSections();
			rebuildFlatNotes();
			undoStack = [];
			redoStack = [];
			selectedNote = null;
			selectedEvent = null;
			songInput.text = path;
			songInput.hasFocus = false;
			seekTo(0);
			loadAudio();
			status('Opened: ' + path);
		}
		catch (e:Dynamic)
		{
			status('Open failed: ' + path);
		}
	}

	function newChart():Void
	{
		status('New Chart not wired yet');
	}

	function exportChart():Void
	{
		if (_song.events != null && _song.events.length > 1) _song.events.sort(function(a, b) return a[0] < b[0] ? -1 : (a[0] > b[0] ? 1 : 0));
		_song.format = 'psych_v1';
		var data:String = haxe.Json.stringify({song: _song}, '\t');
		_file = new FileReference();
		_file.addEventListener(Event.COMPLETE, function(e) status('Chart exported'));
		_file.addEventListener(IOErrorEvent.IO_ERROR, function(e) status('Export failed'));
		_file.save(data, songName + '.json');
	}

	function saveChart():Void
	{
		#if sys
		if (_song.events != null && _song.events.length > 1) _song.events.sort(function(a, b) return a[0] < b[0] ? -1 : (a[0] > b[0] ? 1 : 0));
		_song.format = 'psych_v1';
		var diff:String = Difficulty.getString();
		if (diff == Difficulty.getDefault()) diff = null;
		var fileName:String = songName + (diff != null && diff.length > 0 ? '-' + diff : '') + '.json';
		// 只有当前模组里确实存在该曲目录时才写当前模组；否则写 mods/data，避免污染 TCM 等无关模组。
		var dir:String = 'mods/data/' + songName;
		var mod:String = Mods.currentModDirectory;
		if (mod != null && mod.length > 0 && FileSystem.exists('mods/' + mod + '/data/' + songName))
			dir = 'mods/' + mod + '/data/' + songName;
		if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
		File.saveContent(dir + '/' + fileName, haxe.Json.stringify({song: _song}, '\t'));
		var mec:String = dir + '/' + fileName.substr(0, fileName.length - 5) + '.mec';
		if (FileSystem.exists(mec)) FileSystem.deleteFile(mec);
		status('Saved: ' + dir + '/' + fileName);
		#else
		exportChart();
		#end
	}

	function backToMenu():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		FlxG.mouse.visible = false;
		MusicBeatState.switchState(new states.editors.MasterEditorMenu());
	}

	function status(msg:String):Void
	{
		if (statusText == null)
		{
			statusText = makeText(FlxG.width - 430, 40, 0, '', 13, 0xFFFFFFFF);
			add(statusText);
		}
		statusText.text = msg;
		statusText.visible = true;
		toastTimer = 3;
	}

	function snapTime(t:Float):Float
	{
		// 标签是音符时值：1/16 = 每拍 4 个 step 中的 1 个，因此步长 = 16 / 分母。
		// 之前写成分母/4，1/16 实际变成每 4 step（四分音符）一档，点击会跳 160px。
		var q:Float = 16.0 / snaps[snapIndex];
		return timeAtStep(Math.floor(stepAtTime(t) / q + 0.5) * q);
	}

	function recalculateSections():Void
	{
		sectionStarts = [];
		sectionBeats = [];
		sectionBpms = [];
		var bpm:Float = _song.bpm;
		var pos:Float = 0;
		for (i in 0..._song.notes.length)
		{
			sectionStarts.push(pos);
			var beats:Float = _song.notes[i].sectionBeats > 0 ? _song.notes[i].sectionBeats : 4;
			sectionBeats.push(beats);
			if (_song.notes[i].changeBPM) bpm = _song.notes[i].bpm;
			sectionBpms.push(bpm);
			pos += beats * (60000 / bpm);
		}
	}

	function stepMsAtTime(time:Float):Float
	{
		for (i in 0...sectionStarts.length)
		{
			var end:Float = (i + 1 < sectionStarts.length) ? sectionStarts[i + 1] : sectionStarts[i] + sectionBeats[i] * (60000 / sectionBpms[i]);
			if (time < end) return 60000 / sectionBpms[i] / 4;
		}
		return 60000 / (_song.bpm) / 4;
	}

	function stepAtTime(time:Float):Float
	{
		var steps:Float = 0;
		for (i in 0...sectionStarts.length)
		{
			var stepMs:Float = 60000 / sectionBpms[i] / 4;
			var secSteps:Float = sectionBeats[i] * 4;
			var start:Float = sectionStarts[i];
			var end:Float = start + secSteps * stepMs;
			if (time >= end) steps += secSteps;
			else return steps + Math.max(0, (time - start) / stepMs);
		}
		return steps;
	}

	function timeAtStep(step:Float):Float
	{
		if (step <= 0) return 0;
		var remain:Float = step;
		for (i in 0...sectionStarts.length)
		{
			var stepMs:Float = 60000 / sectionBpms[i] / 4;
			var secSteps:Float = sectionBeats[i] * 4;
			if (remain <= secSteps) return sectionStarts[i] + remain * stepMs;
			remain -= secSteps;
		}
		if (sectionStarts.length > 0)
		{
			var last:Int = sectionStarts.length - 1;
			return sectionStarts[last] + sectionBeats[last] * 4 * (60000 / sectionBpms[last] / 4) + remain * (60000 / sectionBpms[last] / 4);
		}
		return 0;
	}

	function sectionForTime(time:Float):Int
	{
		for (i in 0...sectionStarts.length)
		{
			var end:Float = (i + 1 < sectionStarts.length) ? sectionStarts[i + 1] : sectionStarts[i] + sectionBeats[i] * (60000 / (_song.notes[i].changeBPM ? _song.notes[i].bpm : _song.bpm));
			if (time < end) return i;
		}
		if (_song.notes.length == 0) addSection();
		return _song.notes.length - 1;
	}

	function rebuildFlatNotes():Void
	{
		flatNotes = [];
		for (sec in 0..._song.notes.length)
		{
			if (_song.notes[sec] == null || _song.notes[sec].sectionNotes == null) continue;
			for (n in _song.notes[sec].sectionNotes)
			{
				if (n == null || n.length < 2) continue;
				var sus:Float = n.length > 2 && n[2] != null ? n[2] : 0;
				var kind:String = n.length > 3 && n[3] != null ? Std.string(n[3]) : '';
				flatNotes.push({time: n[0], data: Std.int(n[1]), sus: sus, kind: kind, sec: sec});
			}
		}
		flatNotes.sort(function(a, b) return a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
	}

	function formatTime(ms:Float):String
	{
		if (ms < 0) ms = 0;
		var total:Int = Std.int(ms / 1000);
		var m:Int = Std.int(total / 60);
		var s:Int = total % 60;
		return m + ':' + (s < 10 ? '0' : '') + s;
	}

	// UI-DESIGN §2.1：autoSize + wordWrap=false + textField 1px 内边距
	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, color:Int, ?align:FlxTextAlign = LEFT, ?font:String = 'vcr.ttf'):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font(font), size, color, align, FlxTextBorderStyle.NONE, FlxColor.TRANSPARENT);
		t.wordWrap = false;
		t.antialiasing = ClientPrefs.data.antialiasing;
		t.scrollFactor.set();
		t.textField.x = 1;
		t.textField.y = 1;
		return t;
	}

	override function destroy():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		if (_file != null)
		{
			_file = null;
		}
		super.destroy();
	}
}

typedef EditorNote = {time:Float, data:Int, sus:Float, kind:String, sec:Int};
typedef PanelButton = {bg:FlxSprite, txt:FlxText, x:Float, y:Float, w:Float, h:Float, action:Void->Void};
