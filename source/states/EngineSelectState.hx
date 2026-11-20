package states;
import backend.Lang;

import backend.ClientPrefs;
import backend.ContainerInfo;
import backend.ContainerManifestParser;
import backend.ContainerSession;
import backend.ContainerStore;
import backend.EngineChain;
import backend.MusicBeatState;
import backend.Paths;
import backend.WeekData;
import backend.WheelScroll;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

import objects.BackButton;
import objects.ContainerButton;

import openfl.Lib;

/**
 * 多引擎切换（整屏页 · 系统域 MD3）。
 *
 * 做什么：
 *  - 列表 = 「本引擎」+ `mods/_containers/<名称>/` 里的每个容器（= 一个可独立运行的引擎）；
 *  - 「设为启动引擎」把选择写进存档，**下次启动**由本引擎把控制权交接给目标引擎
 *    （见 backend/EngineChain.autoBoot）；
 *  - 「立即进入」只切换本次运行（走容器会话，退出后回到本引擎标题页），不改启动目标；
 *  - 选「本引擎」= 取消启动时的引擎切换。
 *
 * 与容器页（ContainersMenuState）的分工：
 *  - 容器页：管理/自检/临时启动，偏排障；
 *  - 本页：只回答「下次启动进哪个引擎」，几何基线抄 ScriptManagerSubstate（UI-DESIGN §3），
 *    不重复容器页的两栏详情布局。
 *
 * 交互：↑/↓（W/S）选择 · 回车 设为启动引擎 · R 重新扫描 · ESC/返回按钮 回设置
 */
class EngineSelectState extends MusicBeatState
{
	// ===== 布局（1280×720 基线；常量抄 substates/ScriptManagerSubstate）=====
	static final TITLE_Y:Float = 22;
	static final PANEL_X:Float = 160;
	static final PANEL_Y:Float = 96;
	static final PANEL_W:Float = 960;
	static final PANEL_H:Float = 520;
	static final ROW_X:Float = 204;
	static final ROW_START_Y:Float = 164;
	static final ROW_GAP:Float = 56;
	static final VALUE_RIGHT:Float = 1096;
	static final MAX_VISIBLE:Int = 8;
	static final ROW_TEXT_SIZE:Int = 24;
	static final ROW_H:Float = 40;
	/** 行文字可用的最大宽度：留出右侧值列的固定空间（标签再长也不挤到值上）。 */
	static final LABEL_MAX_W:Float = 600;

	// 固定暗色（与其它系统界面一致；不参与主题化）
	static final TEXT_DIM:Int = 0xFF9A9AA8;
	static final TEXT_HOVER:Int = 0xFFD7D7E0;
	static final TEXT_HINT:Int = 0xFFA9A9B8;
	static final DANGER:Int = 0xFFFF6B6B; // 语义色：引擎不可用
	// 强调色运行时读取（static final 会在类加载时冻结，主题切换后不跟随）
	inline static function ACCENT():Int return DesignTokens.primary;

	var wheelScroll:WheelScroll = new WheelScroll();

	var containers:Array<ContainerInfo> = [];
	var rows:Array<EngineRow> = [];
	var curSelected:Int = 0;
	var scrollOffset:Int = 0;
	/** 鼠标悬停行（-1 = 无）；只在变化时重绘，避免每帧重建文本。 */
	var hoverRow:Int = -1;

	var panel:FlxSprite;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;

	var titleText:FlxText;
	var subtitle:FlxText;
	var emptyHint:FlxText;
	var statusText:FlxText;

	var rowLabels:Array<FlxText> = [];
	var rowValues:Array<FlxText> = [];

	var setBootBtn:ContainerButton;
	var enterBtn:ContainerButton;
	var rescanBtn:ContainerButton;
	var backBtn:BackButton;

	// 鼠标 / 键盘输入分离（与 ContainersMenuState 同款）
	var mouseActive:Bool = true;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	static final MOUSE_REACTIVATE_DIST:Float = 10;

	/** 事件驱动的提示（null = 显示默认说明）；错误优先，粘到下一次操作。 */
	var statusError:String = null;
	var statusInfo:String = null;

	var selectedSomethin:Bool = false;
	/** 回车冷却：设置页按 Enter 进来时，按键不会穿透到本页（UI-DESIGN §4.1）。 */
	var nextAccept:Int = 5;

	var themeListener:Void->Void;

	override function create():Void
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		WeekData.setDirectoryFromWeek();

		Lib.application.window.title = Lang.tOr('win.engineSelect', 'NovaComet Engine - Engines');

		// 背景 = menuDesat 染当前主题色（与设置/容器页同一取色路径）
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = DesignTokens.menuTint;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		// ---- 标题 ----
		titleText = new FlxText(0, TITLE_Y, FlxG.width, Lang.tOr('engineSwitch.title', '引擎切换'), 48);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		add(titleText);

		// ---- 磨砂面板 ----
		panel = new FlxSprite(PANEL_X, PANEL_Y).makeGraphic(Std.int(PANEL_W), Std.int(PANEL_H), FlxColor.TRANSPARENT, true);
		panel.scrollFactor.set();
		add(panel);
		paintPanel();

		// ---- 选中高亮条（整行圆角条，不是竖线；UI-DESIGN §3）----
		selectorBar = new FlxSprite(PANEL_X + 16, ROW_START_Y - 4)
			.makeGraphic(Std.int(PANEL_W - 32), Std.int(ROW_H), FlxColor.TRANSPARENT, true);
		selectorBar.scrollFactor.set();
		add(selectorBar);
		paintSelector();
		selectorBar.alpha = 0;

		// ---- 键位提示（面板内第二行，避免和底部操作条抢位置）----
		subtitle = new FlxText(ROW_X, 138, 0,
			Lang.tOr('engineSwitch.subtitle', '↑ ↓ 选择 · 回车 设为启动引擎 · R 重新扫描 · ESC 返回'), 15);
		subtitle.scrollFactor.set();
		subtitle.setFormat(Paths.font('future.ttf'), 15, TEXT_HINT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		subtitle.borderSize = 1.2;
		subtitle.wordWrap = false;
		subtitle.textField.x = 1;
		subtitle.textField.y = 1;
		subtitle.antialiasing = ClientPrefs.data.antialiasing;
		add(subtitle);

		// ---- 行（预创建，随滚动复用；autoSize 单行）----
		for (i in 0...MAX_VISIBLE)
		{
			var rowY:Float = ROW_START_Y + i * ROW_GAP;

			var lbl:FlxText = new FlxText(ROW_X, rowY + 2, 0, '', ROW_TEXT_SIZE);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), ROW_TEXT_SIZE, TEXT_DIM, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.wordWrap = false;
			lbl.textField.x = 1;
			lbl.textField.y = 1;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			add(lbl);
			rowLabels.push(lbl);

			var val:FlxText = new FlxText(VALUE_RIGHT, rowY + 2, 0, '', ROW_TEXT_SIZE);
			val.scrollFactor.set();
			val.setFormat(Paths.font('future.ttf'), ROW_TEXT_SIZE, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			val.wordWrap = false;
			val.textField.x = 1;
			val.textField.y = 1;
			val.antialiasing = ClientPrefs.data.antialiasing;
			add(val);
			rowValues.push(val);
		}

		// ---- 空列表提示（只有本引擎时说明怎么加引擎）----
		emptyHint = new FlxText(ROW_X, ROW_START_Y + 70, Std.int(PANEL_W - 88), '', 17);
		emptyHint.scrollFactor.set();
		emptyHint.setFormat(Paths.font('future.ttf'), 17, TEXT_HINT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		emptyHint.borderSize = 1.5;
		emptyHint.wordWrap = true;
		emptyHint.antialiasing = ClientPrefs.data.antialiasing;
		add(emptyHint);

		// ---- 状态行（面板下沿 616；操作条在 636，与容器页同一分层）----
		statusText = new FlxText(ROW_X, 596, 0, '', 15);
		statusText.scrollFactor.set();
		statusText.setFormat(Paths.font('future.ttf'), 15, TEXT_HINT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.borderSize = 1.2;
		statusText.wordWrap = false;
		statusText.textField.x = 1;
		statusText.textField.y = 1;
		statusText.antialiasing = ClientPrefs.data.antialiasing;
		add(statusText);

		// ---- 底部操作条 + 按钮 ----
		var bar:FlxSprite = new FlxSprite(40, 636).makeGraphic(1200, 56, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(bar, 0, 0, 1200, 56, 14, 14, DesignTokens.panelFill);
		FlxSpriteUtil.drawRoundRect(bar, 1, 1, 1198, 54, 14, 14, FlxColor.TRANSPARENT,
			{color: DesignTokens.panelOutline, thickness: 1.5});
		bar.scrollFactor.set();
		add(bar);

		setBootBtn = new ContainerButton(52, 642, 320, 44, Lang.tOr('engineSwitch.setBoot', '设为启动引擎'), function() setBootTarget());
		enterBtn = new ContainerButton(404, 642, 320, 44, Lang.tOr('engineSwitch.enterNow', '立即进入（本次运行）'), function() enterNow());
		rescanBtn = new ContainerButton(756, 642, 320, 44, Lang.tOr('engineSwitch.rescan', '重新扫描'), function() rescan());
		add(setBootBtn);
		add(enterBtn);
		add(rescanBtn);

		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		rebuild();
		refreshRows();
		refreshStatus();

		// 主题色变更 → 面板/选中条重绘 + 文本重取色（像素类控件必须重绘，UI-DESIGN §1.2）
		themeListener = function() rethemeNow();
		DesignTokens.addThemeListener(themeListener);

		// 整屏 State 自己开光标（外层 OptionsState 在 destroy 里关）
		FlxG.mouse.visible = true;

		super.create();
	}

	// ───────────────────────── 数据 ─────────────────────────

	/** 重新扫描容器并按「本引擎 + 容器」重建行数据。 */
	function rebuild(?keepFolder:String):Void
	{
		if (keepFolder == null && curSelected >= 0 && curSelected < rows.length) keepFolder = rows[curSelected].folder;

		containers = ContainerStore.scan();
		if (containers == null) containers = [];

		var bootFolder:String = EngineChain.target();
		var runningFolder:String = (ContainerSession.current != null) ? ContainerSession.current.folder : null;

		rows = [];

		// 第 0 行 = 本引擎（永不消失：切回来必须有个入口）
		rows.push({
			folder: '',
			kind: 0,
			label: Lang.tOr('engineSwitch.hostName', '本引擎（NovaComet）') + '  v' + Main.meVersion,
			meta: (bootFolder.length < 1) ? Lang.tOr('engineSwitch.badgeBoot', '● 启动引擎') : '',
			metaKind: (bootFolder.length < 1) ? 1 : 0,
			ready: true,
			problem: null
		});

		for (info in containers)
		{
			var lbl:String = (info.displayName != null && info.displayName.length > 0) ? info.displayName : info.folder;
			if (info.engine != null && info.engine.length > 0) lbl += Lang.tOr('engineSwitch.metaSep', '  ·  ') + info.engine;
			if (info.version != null && info.version.length > 0) lbl += '  ' + info.version;

			var ready:Bool = ContainerSession.isReady(info);
			var meta:String = '';
			var metaKind:Int = 0;
			if (!ready)
			{
				meta = Lang.tOr('engineSwitch.badgeProblem', '⚠ 不可用');
				metaKind = 2;
			}
			else if (bootFolder.length > 0 && info.folder == bootFolder)
			{
				meta = Lang.tOr('engineSwitch.badgeBoot', '● 启动引擎');
				metaKind = 1;
			}
			else if (runningFolder != null && info.folder == runningFolder)
			{
				meta = Lang.tOr('engineSwitch.badgeRunning', '运行中');
				metaKind = 3;
			}

			rows.push({
				folder: info.folder,
				kind: 1,
				label: lbl,
				meta: meta,
				metaKind: metaKind,
				ready: ready,
				problem: info.problem
			});
		}

		emptyHint.text = Lang.tOr('engineSwitch.emptyHint', '没有发现其它引擎。把目标引擎（Psych 0.7.3 / 1.0.4 / 其它引擎）放进：\n')
			+ ContainerStore.containersRoot() + Lang.tOr('engineSwitch.emptyHintDir', '/<名称>/\n')
			+ Lang.tOr('engineSwitch.emptyHintManifest', '并放一个 ') + ContainerManifestParser.FILE_NAME
			+ Lang.tOr('engineSwitch.emptyHintTail', ' 清单（与容器页同一规则），然后点「重新扫描」。');

		curSelected = 0;
		if (keepFolder != null)
			for (i in 0...rows.length)
				if (rows[i].folder == keepFolder)
				{
					curSelected = i;
					break;
				}
		scrollOffset = 0;
		if (curSelected >= MAX_VISIBLE) scrollOffset = curSelected - MAX_VISIBLE + 1;
	}

	function maxOffset():Int
	{
		return Std.int(Math.max(0, rows.length - MAX_VISIBLE));
	}

	/** 只重绘可见行（滚动窗口）。 */
	function refreshRows():Void
	{
		emptyHint.visible = (containers.length < 1);

		for (i in 0...MAX_VISIBLE)
		{
			var idx:Int = scrollOffset + i;
			var lbl:FlxText = rowLabels[i];
			var val:FlxText = rowValues[i];
			if (idx >= rows.length)
			{
				lbl.text = '';
				val.text = '';
				continue;
			}
			var row:EngineRow = rows[idx];
			fitInto(lbl, row.label, LABEL_MAX_W);

			var selected:Bool = (idx == curSelected);
			if (selected) lbl.color = FlxColor.WHITE;
			else if (!row.ready) lbl.color = DANGER;
			else if (idx == hoverRow) lbl.color = TEXT_HOVER;
			else lbl.color = TEXT_DIM;

			val.text = row.meta;
			val.color = switch (row.metaKind)
			{
				case 1: ACCENT();
				case 2: DANGER;
				default: TEXT_HINT;
			}
			val.x = VALUE_RIGHT - val.width;
		}

		// 选中条跟随（滚动时直接吸附，避免从旧行滑过整个列表）
		var targetY:Float = ROW_START_Y - 4 + (curSelected - scrollOffset) * ROW_GAP;
		selectorBar.visible = (rows.length > 0);
		selectorBar.alpha = 1;
		if (Math.abs(selectorBar.y - targetY) < 0.5) selectorBar.y = targetY;
		else
		{
			if (selectorTween != null) selectorTween.cancel();
			selectorTween = FlxTween.tween(selectorBar, {y: targetY}, 0.12, {ease: FlxEase.cubeOut});
		}

		refreshButtons();
	}

	/** 按钮可用性/文案跟随选中行（权威来源 = rows + ClientPrefs）。 */
	function refreshButtons():Void
	{
		if (rows.length < 1) return;
		var row:EngineRow = rows[curSelected];

		setBootBtn.label.text = (row.kind == 0)
			? Lang.tOr('engineSwitch.setHost', '启动时进入本引擎（取消切换）')
			: Lang.tOr('engineSwitch.setBoot', '设为启动引擎');

		var canEnter:Bool = (row.kind == 1) && row.ready && !ContainerSession.active && !selectedSomethin;
		enterBtn.setEnabled(canEnter);

		rescanBtn.setEnabled(!ContainerSession.active && !selectedSomethin);
	}

	function refreshStatus():Void
	{
		if (statusError != null)
		{
			setStatusLine('⚠ ' + statusError, DANGER);
			return;
		}
		if (statusInfo != null)
		{
			setStatusLine(statusInfo, TEXT_HINT);
			return;
		}
		// 默认内容 = 启动目标摘要（重要且常驻的信息，优先于操作提示）
		var row:EngineRow = rows[curSelected];
		var missing:Bool = !EngineChain.isHostMode() && (EngineChain.findTarget() == null);
		var bootTxt:String = Lang.tOr('engineSwitch.bootLine', '启动引擎：') + EngineChain.targetLabel()
			+ (EngineChain.isHostMode()
				? Lang.tOr('engineSwitch.bootLineHost', '   ·   启动时不切换到其它引擎')
				: Lang.tOr('engineSwitch.bootLineTail', '   ·   下次启动生效'));

		if (row.problem != null && row.problem.length > 0)
		{
			setStatusLine('⚠ ' + row.problem, DANGER);
			return;
		}
		if (containers.length < 1)
		{
			setStatusLine(bootTxt + Lang.tOr('engineSwitch.noContainersTail', '   ·   还没有其它引擎（mods/_containers/<名称>/）'),
				missing ? DANGER : TEXT_HINT);
			return;
		}
		setStatusLine(bootTxt, missing ? DANGER : (EngineChain.isHostMode() ? TEXT_HINT : ACCENT()));
	}

	function setStatusLine(txt:String, color:Int):Void
	{
		fitInto(statusText, txt, PANEL_W - 88);
		statusText.color = color;
	}

	function setError(msg:String):Void
	{
		statusError = msg;
		statusInfo = null;
		refreshStatus();
	}

	function setInfo(msg:String):Void
	{
		statusInfo = msg;
		statusError = null;
		refreshStatus();
	}

	// ───────────────────────── 动作 ─────────────────────────

	/** 把选中项设为启动目标（本引擎行 = 取消切换）。 */
	function setBootTarget():Void
	{
		if (selectedSomethin || rows.length < 1) return;
		var row:EngineRow = rows[curSelected];

		if (row.kind == 0)
		{
			EngineChain.clearTarget();
			FlxG.sound.play(Paths.sound('confirmMenu'));
			setInfo(Lang.tOr('engineSwitch.savedHost', '已设回本引擎：下次启动不再切换到其它引擎'));
			rebuild(row.folder);
			refreshRows();
			refreshStatus();
			return;
		}

		if (!row.ready)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			setError(Lang.tOr('engineSwitch.needReady', '该引擎未就绪，不能设为启动目标')
				+ (row.problem != null ? Lang.tOr('engineSwitch.detailSep', '：') + row.problem : ''));
			return;
		}

		var wasOff:Bool = !ClientPrefs.data.containersEnabled;
		var err:String = EngineChain.setTarget(row.folder);
		if (err != null)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			setError(Lang.tOr('engineSwitch.setFailed', '设置失败：') + err);
			return;
		}

		FlxG.sound.play(Paths.sound('confirmMenu'));
		var msg:String = Lang.tOr('engineSwitch.saved', '已设为启动引擎：') + row.label
			+ Lang.tOr('engineSwitch.savedTail', '（下次启动生效）');
		if (wasOff && ClientPrefs.data.containersEnabled)
			msg += Lang.tOr('engineSwitch.autoEnabled', '；已同时启用容器功能');
		setInfo(msg);
		rebuild(row.folder);
		refreshRows();
		refreshStatus();
	}

	/** 立即进入选中引擎（只影响本次运行；退出后回到本引擎标题页）。 */
	function enterNow():Void
	{
		if (selectedSomethin || rows.length < 1) return;
		var row:EngineRow = rows[curSelected];
		if (row.kind == 0) return; // 已经在本引擎里
		if (!row.ready)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			setError(Lang.tOr('engineSwitch.needReady', '该引擎未就绪，不能设为启动目标')
				+ (row.problem != null ? Lang.tOr('engineSwitch.detailSep', '：') + row.problem : ''));
			return;
		}
		if (ContainerSession.active)
		{
			setError(Lang.tOr('engineSwitch.busy', '已有引擎在运行，先关掉它再切换'));
			return;
		}

		var wasOff:Bool = !ClientPrefs.data.containersEnabled;
		if (wasOff)
		{
			// 显式「立即进入」= 需要容器启动能力；立刻落盘，避免本次会话崩溃后开关状态丢失
			ClientPrefs.data.containersEnabled = true;
			ClientPrefs.saveSettings();
		}
		var info:ContainerInfo = EngineChain.findInfo(row.folder);
		var err:String = ContainerSession.launch(info);
		if (err != null)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			setError(Lang.tOr('engineSwitch.launchFailed', '启动失败：') + err);
			return;
		}

		selectedSomethin = true;
		FlxG.sound.play(Paths.sound('confirmMenu'));
		setInfo(Lang.tOr('engineSwitch.switching', '正在切换到「') + row.label + Lang.tOr('engineSwitch.switchingTail', '」…')
			+ (wasOff ? Lang.tOr('engineSwitch.autoEnabled', '；已同时启用容器功能') : ''));
		refreshButtons();
	}

	function rescan():Void
	{
		if (selectedSomethin) return;
		var keep:String = (rows.length > 0) ? rows[curSelected].folder : null;
		rebuild(keep);
		refreshRows();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		setInfo(Lang.tOr('engineSwitch.rescanned', '已重新扫描：') + containers.length + Lang.tOr('engineSwitch.rescannedTail', ' 个引擎（含本引擎）'));
	}

	// ───────────────────────── 交互 ─────────────────────────

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (nextAccept > 0) nextAccept -= 1;
		if (selectedSomethin) return;

		// 鼠标唤醒（键盘操作后冻结悬停，鼠标真的动了再恢复）
		if (FlxG.mouse.justMoved || FlxG.mouse.justPressed || FlxG.mouse.wheel != 0)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (FlxG.mouse.justPressed || FlxG.mouse.wheel != 0 || dx * dx + dy * dy > MOUSE_REACTIVATE_DIST * MOUSE_REACTIVATE_DIST)
				mouseActive = true;
		}

		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		var clickPressed:Bool = FlxG.mouse.justPressed;

		// ---- 返回 ----
		if (controls.BACK || (clickPressed && backBtn.over(mx, my)))
		{
			exitToOptions();
			return;
		}

		// ---- 按钮 ----
		if (clickPressed)
		{
			if (setBootBtn.over(mx, my))
			{
				setBootTarget();
				return;
			}
			if (enterBtn.over(mx, my))
			{
				enterNow();
				return;
			}
			if (rescanBtn.over(mx, my))
			{
				rescan();
				return;
			}
		}

		if (mouseActive)
		{
			setBootBtn.setHovered(mx, my);
			enterBtn.setHovered(mx, my);
			rescanBtn.setHovered(mx, my);
			backBtn.setHovered(mx, my);

			// 行悬停色：只在悬停行发生变化时重绘（每帧重排文本会白喂 GC）
			var hoverHit:Int = rowAt(mx, my);
			if (hoverHit != hoverRow)
			{
				hoverRow = hoverHit;
				refreshRows();
			}
		}
		else if (hoverRow != -1)
		{
			hoverRow = -1;
			refreshRows();
		}

		// ---- 滚轮 / 触控滑动（WheelScroll：上滚 = -1，与其它列表一致）----
		var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);
		if (wheelStep != 0)
		{
			mouseActive = true;
			changeSelection(wheelStep);
		}

		// ---- 行命中：点未选中行 = 选中；点已选中行 = 设为启动引擎 ----
		if (clickPressed)
		{
			var hit:Int = rowAt(mx, my);
			if (hit >= 0)
			{
				if (hit != curSelected) changeSelection(hit - curSelected);
				else setBootTarget();
				return;
			}
		}

		// ---- 键盘 ----
		var upPressed:Bool = controls.UI_UP_P;
		var downPressed:Bool = controls.UI_DOWN_P;
		if (upPressed || downPressed)
		{
			mouseActive = false;
			mouseLockX = mx;
			mouseLockY = my;
			changeSelection(upPressed ? -1 : 1);
		}
		if (FlxG.keys != null && FlxG.keys.justPressed.R) rescan();

		// 冷却门禁写法照 UI-DESIGN §4.1（写成 else 分支会让导航变死代码）
		if (nextAccept <= 0 && controls.ACCEPT) setBootTarget();
	}

	/** 鼠标命中的行索引（-1 = 未命中）。整行整宽固定热区，不依赖文本宽度。 */
	function rowAt(mx:Float, my:Float):Int
	{
		var rx:Float = PANEL_X + 16;
		var rw:Float = PANEL_W - 32;
		if (mx < rx || mx > rx + rw) return -1;
		for (i in 0...MAX_VISIBLE)
		{
			var top:Float = ROW_START_Y + i * ROW_GAP - 6;
			if (my >= top && my <= top + ROW_GAP - 12) // 留 2px 给下沿状态行，避免误命中
			{
				var idx:Int = scrollOffset + i;
				return (idx < rows.length) ? idx : -1;
			}
		}
		return -1;
	}

	function changeSelection(change:Int):Void
	{
		if (rows.length < 1 || change == 0) return;
		curSelected += change;
		if (curSelected < 0) curSelected = rows.length - 1;
		if (curSelected >= rows.length) curSelected = 0;

		// 跟随滚动
		if (curSelected < scrollOffset) scrollOffset = curSelected;
		if (curSelected >= scrollOffset + MAX_VISIBLE) scrollOffset = curSelected - MAX_VISIBLE + 1;
		if (scrollOffset > maxOffset()) scrollOffset = maxOffset();
		if (scrollOffset < 0) scrollOffset = 0;

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		refreshRows();
		refreshStatus();
	}

	/** 返回设置页（与入口 OptionsState.enterEngineSelect 对称；按标签恢复选中分区）。 */
	function exitToOptions():Void
	{
		if (selectedSomethin) return;
		selectedSomethin = true;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		options.OptionsState.onPlayState = false;
		MusicBeatState.switchState(new options.OptionsState());
	}

	override function destroy():Void
	{
		FlxG.mouse.visible = false;
		if (themeListener != null)
		{
			DesignTokens.removeThemeListener(themeListener);
			themeListener = null;
		}
		if (selectorTween != null)
		{
			selectorTween.cancel();
			selectorTween = null;
		}
		super.destroy();
	}

	// ───────────────────────── 绘制 ─────────────────────────

	function paintPanel():Void
	{
		// makeGraphic(unique = true)：每次重绘都换一张自己的 BitmapData，不与其他面板串图
		panel.makeGraphic(Std.int(PANEL_W), Std.int(PANEL_H), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(panel, 0, 0, PANEL_W, PANEL_H, 20, 20, DesignTokens.panelFill);
		FlxSpriteUtil.drawRoundRect(panel, 1, 1, PANEL_W - 2, PANEL_H - 2, 20, 20, FlxColor.TRANSPARENT,
			{color: DesignTokens.panelOutline, thickness: 1.5});
	}

	function paintSelector():Void
	{
		selectorBar.makeGraphic(Std.int(PANEL_W - 32), Std.int(ROW_H), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(selectorBar, 0, 0, PANEL_W - 32, ROW_H, 12, 12, DesignTokens.rowHighlight);
	}

	/** 主题切换：像素图重绘 + 文本按令牌重取色（FlxText 颜色是属性，改令牌不会自动跟）。 */
	function rethemeNow():Void
	{
		paintPanel();
		paintSelector();
		refreshRows();
		refreshStatus();
	}

	/**
	 * 单行文本裁剪：省略号只在入口加一次，循环体内**只截不加**（长度严格递减，必终止），
	 * 并叠加迭代硬上界做双保险（UI-DESIGN §2.3 的死循环就是这个写法）。
	 */
	function fitInto(t:FlxText, s:String, maxW:Float):Void
	{
		t.text = s;
		if (t.width <= maxW) return;

		var keep:Int = Std.int(s.length * (maxW / t.width) * 0.92) - 1;
		if (keep < 4) keep = 4;
		if (keep > s.length - 1) keep = s.length - 1;
		var ell:String = Lang.tOr('common.ellipsis', '…');
		var cut:String = s.substr(0, keep) + ell;
		t.text = cut;

		var guard:Int = 0;
		while (t.width > maxW && cut.length > 2 && guard < 96)
		{
			cut = cut.substr(0, cut.length - 2) + ell;
			t.text = cut;
			guard++;
		}
	}
}

/** 一行 = 一个可选引擎（本引擎或容器）。 */
typedef EngineRow =
{
	/** 目录名（'' = 本引擎）——持久化的唯一 ID。 */
	var folder:String;
	/** 0 = 本引擎，1 = 容器。 */
	var kind:Int;
	/** 列表主文字（未裁剪）。 */
	var label:String;
	/** 右侧状态文字（'' / ● 启动引擎 / ⚠ 不可用 / 运行中）。 */
	var meta:String;
	/** 0 = 无，1 = 启动目标，2 = 不可用，3 = 运行中。 */
	var metaKind:Int;
	var ready:Bool;
	var problem:String;
}
