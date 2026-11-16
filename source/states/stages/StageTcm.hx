package states.stages;

import objects.BGSprite;

/**
 * TCM Demo1 Chapter1 —— 三阶段舞台（真舞台实体，替代 2026-11-14 废弃的
 * scripts/tcm_stage.lua 全屏覆盖层：覆盖层 scrollFactor(0,0) 钉死屏幕，
 * 镜头一动只有角色在动；且谱面 alpha 淡出事件会透出底下 week1 场景。
 * 本类是世界坐标实体舞台，这两个问题从根上不存在——week1 不再加载）。
 *
 * 几何（2026-11-15 七调：用户要更大视野 → zoom 0.56 + 素材 ×1.55；六调公式沿用。六调(同日)：修复五调 x 窗的 scroll 公式错误——五调把 scroll 当成 follow-可见宽，
 * 实际 flixel 5.2.2 的 LOCKON 1x1 死区把 scroll 钉在 follow - FlxG.width/2（= follow-640，
 * HostDomain:1643 每帧写 followLerp），且 zoom 绕视图中心缩放（canvas.x = -0.5*width*(zoom-1)）。
 * sf=0.9 素材覆盖约束（可见世界半宽 = 640/Z）：x ≤ 0.9*follow_min + (1-sf)*640 - 640/Z；
 * x + W ≥ 0.9*follow_max + (1-sf)*640 + 640/Z。同理 y 用 height=360。
 * 跟随目标：dad 回合 = dad中点+150 = 260，bf 回合 = bf中点-100 = 816（中点偏移实测 dad=x+80、bf=x+66），
 * ±15 防抖（谱面无 shake 事件）→ follow ∈ [245,831]。W=2976、Z=0.56：
 * x 窗 [-1021.2,-858.4]，取窗心 -940（左右余量各 ±81 世界 px ≈ ±45.5 屏幕 px）。
 * y 窗 [-666.6,-323.4]，取 -592 偏窗：可见顶部 = 素材行 ~173（与 0.64 期一致，屋顶线/黑垂帘区留在画面外），
 * 底部余量 74.6 世界 px ≈ 41.8 屏幕 px；地板线（near row 693）世界 Y 漂移仅 -3。远景不透明 + 近景 alpha 覆盖同位置/同 sf，天然像素对齐。
 *
 * 阶段标记（用户 2026-11-14 指定，后续剧情/转场会引用）：
 *   阶段 1 = sadness　阶段 2 = cheerful-horn（谱面未做，谱面到位自动生效）
 *   阶段 3 = death-from-numbness
 * 初始阶段按曲目查 START_PHASE；谱面事件可随时覆盖。
 * 切相事件：tcmPhase / TCM Phase / Stage Phase（value1 = 1|2|3）或原模组
 * change_stage（value1 = tcm1|tcm2|tcm3），越界夹取；快速重开回初始阶段。
 */
class StageTcm extends BaseStage
{
	static inline var PHASES:Int = 3;
	static inline var IMG_SCALE:Float = 1.55;
	static inline var IMG_X:Float = -940; // 覆盖约束窗心：x∈[-1021.2,-858.4] @ zoom 0.56（±15 防抖：谱面无 shake 事件）
	static inline var IMG_Y:Float = -592;  // y∈[-666.6,-323.4]，偏窗取 -592 = 画面顶部对齐素材屋顶线（黑垂帘区留在画面外当防抖缓冲）
	static inline var SF:Float = 0.9;

	/** 曲目（formatToSongPath 后）→ 初始阶段；缺省 1。 */
	public static var START_PHASE:Map<String, Int> = [
		'sadness' => 1,
		'cheerful-horn' => 2, // 谱面未到位，到位即生效
		'death-from-numbness' => 3
	];

	var far:Array<BGSprite> = [];
	var near:Array<BGSprite> = [];

	/** 每相贴图是否已装载（下标 = 相号 - 1）。 */
	var phaseLoaded:Array<Bool> = [false, false, false];

	override function create()
	{
		// 只建**空壳**占位：6 个成员仍在 create 里一次 add 完，z 序与原来逐字节一致
		//（懒加载若在后续帧 add，会插到角色组之上，舞台就盖住人物了）。
		// 贴图按需装载：进曲只解码起始阶段那 2 张，其余阶段交给分片解码队列在倒计时
		// 空闲期补 —— 实测每张 1920x1080 约 25~35ms，4 张 ≈ 120ms 解码 + 32MB 显存提交，
		// 原先全部压在进曲窗口里（用户感知为「加载条满后还卡一下」）。
		for (i in 1...(PHASES + 1))
		{
			var f:BGSprite = new BGSprite(null, IMG_X, IMG_Y, SF, SF);
			f.visible = (i == 1);
			add(f);
			far.push(f);

			var n:BGSprite = new BGSprite(null, IMG_X, IMG_Y, SF, SF);
			n.visible = (i == 1);
			add(n);
			near.push(n);
		}
		setPhase(START_PHASE.get(Paths.formatToSongPath(songName)));

		// 其余阶段：进队异步解码（tickMaintenance 每帧泵 2 张），切相事件到来时通常已就位；
		// 万一没赶上，ensurePhase 内 Paths.image() 会同步兜底，行为不变。
		for (i in 1...(PHASES + 1))
		{
			if (phaseLoaded[i - 1]) continue;
			try
			{
				Paths.requestImageDecode(Paths.resolveAssetPath('images/stages/tcm/tcm_p' + i + '_far'));
				Paths.requestImageDecode(Paths.resolveAssetPath('images/stages/tcm/tcm_p' + i + '_near'));
			}
			catch (e:Dynamic) {}
		}
	}

	/** 按需装载某一相的贴图（已装载则直接返回）。 */
	function ensurePhase(i:Int):Void
	{
		if (i < 1 || i > PHASES || phaseLoaded[i - 1]) return;
		phaseLoaded[i - 1] = true;

		var f:BGSprite = far[i - 1];
		f.loadGraphic(Paths.image('stages/tcm/tcm_p' + i + '_far'));
		f.scale.set(IMG_SCALE, IMG_SCALE);
		f.updateHitbox();

		var n:BGSprite = near[i - 1];
		n.loadGraphic(Paths.image('stages/tcm/tcm_p' + i + '_near'));
		n.scale.set(IMG_SCALE, IMG_SCALE);
		n.updateHitbox();
	}

	/** 快速重开不重建舞台实例 → 回该曲初始阶段。 */
	override function resetForRestart()
		setPhase(START_PHASE.get(Paths.formatToSongPath(songName)));

	override function eventCalled(eventName:String, value1:String, value2:String, flValue1:Null<Float>, flValue2:Null<Float>, strumTime:Float)
	{
		switch (eventName)
		{
			case 'tcmPhase' | 'TCM Phase' | 'Stage Phase':
				if (flValue1 != null)
					setPhase(Math.round(flValue1));
				else
					setPhase(Std.parseInt(value1));
			case 'change_stage':
				var idx:Int = value1 != null ? value1.indexOf('tcm') : -1;
				if (idx >= 0)
					setPhase(Std.parseInt(value1.substr(idx + 3, 1)));
		}
	}

	function setPhase(n:Null<Int>)
	{
		if (n == null) n = 1;
		if (n < 1) n = 1;
		if (n > PHASES) n = PHASES;
		ensurePhase(n);
		for (i in 0...PHASES)
		{
			far[i].visible = (i == n - 1);
			near[i].visible = (i == n - 1);
		}
	}
}
