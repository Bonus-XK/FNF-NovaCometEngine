package backend;

import backend.ClientPrefs;
import backend.ContainerInfo;
import backend.ContainerSession;
import backend.ContainerStore;
import backend.Lang;

/**
 * 多引擎切换（启动目标）。
 *
 * 语义（与 NF / NovaFlare 的「引擎选择 + chain」同一套思路，落到本项目的容器机制上）：
 *  - 列表里的「引擎」= 本引擎 + `mods/_containers/<名称>/` 下的每一个容器（外部引擎）；
 *  - 玩家选定一个目标后写进存档（`ClientPrefs.data.engineChainTarget`，存目录名）；
 *  - **下次启动**进入标题页时，本引擎把启动过程交接给目标引擎（`ContainerSession.launch`）；
 *  - 目标引擎退出 → 容器会话收尾 → `FlxG.resetGame()` 回到本引擎标题页。
 *
 * 为什么复用容器而不是另造一套「切核心」：
 *  1. 容器已经解决跨进程的窗口让位、前台化、崩溃收尾、唤醒（见 ContainerSession 头注释），
 *     另造一套等于把这些坑重踩一遍；
 *  2. 「一个引擎」在本项目的物理形态就是一个可独立运行的 bundle/exe —— 与容器定义一致；
 *  3. 隔离性不变：容器内的 mod / 存档不污染本引擎。
 *
 * 三道闸门（缺一不可）：
 *  - `containersEnabled == false` ⇒ 不交接（用户明确关掉了容器启动能力）；
 *  - `ContainerSession.launchCount > 0` ⇒ 不交接（本次进程已跑过容器，防 resetGame 回环）；
 *  - `METEORIC_NO_ENGINE_BOOT=1` ⇒ 不交接（自动化/排障时隔离，与 METEORIC_SAVE_DIR 同族）。
 */
class EngineChain
{
	/** 空串 = 本引擎（启动时不切换）。 */
	public static inline var HOST:String = '';

	/** 环境变量：设为非空值时本次启动不做引擎交接（自动化/排障隔离用）。 */
	inline public static var ENV_NO_BOOT:String = 'METEORIC_NO_ENGINE_BOOT';

	// ───────────────────────── 读写启动目标 ─────────────────────────

	/** 当前启动目标（`''` = 本引擎）。永远是去空白后的安全值。 */
	public static function target():String
	{
		if (ClientPrefs.data == null) return HOST;
		var t:String = ClientPrefs.data.engineChainTarget;
		if (t == null) return HOST;
		t = StringTools.trim(t);
		return t;
	}

	public static function isHostMode():Bool
	{
		return target().length < 1;
	}

	/** 按目录名找容器（找不到返回 null）。 */
	public static function findTarget():ContainerInfo
	{
		var folder:String = target();
		if (folder.length < 1) return null;
		return findInfo(folder);
	}

	public static function findInfo(folder:String):ContainerInfo
	{
		if (folder == null || folder.length < 1) return null;
		var list:Array<ContainerInfo> = ContainerStore.scan();
		if (list == null) return null;
		for (info in list)
			if (info != null && info.folder == folder) return info;
		return null;
	}

	/**
	 * 设置启动目标。`''` / null = 切回本引擎。
	 * @return null = 成功；否则是面向玩家的失败原因（未写入存档）
	 */
	public static function setTarget(folder:String):String
	{
		folder = (folder == null) ? HOST : StringTools.trim(folder);

		if (folder.length < 1)
		{
			clearTarget();
			return null;
		}

		var info:ContainerInfo = findInfo(folder);
		if (info == null) return Lang.tOr('engineSwitch.errMissing', '找不到该引擎的容器目录（可能已被移动或删除）');
		if (!ContainerSession.isReady(info))
			return (info.problem != null && info.problem.length > 0)
				? info.problem
				: Lang.tOr('engineSwitch.errNotReady', '该引擎未就绪（缺少主程序）');

		ClientPrefs.data.engineChainTarget = folder;
		// 显式选择「启动时进入这个引擎」= 需要容器启动能力。默认关闭的开关在这里被
		// **用户动作**打开（不是代码默认值），引擎切换页会在状态行明说这件事。
		if (!ClientPrefs.data.containersEnabled) ClientPrefs.data.containersEnabled = true;
		ClientPrefs.saveSettings();
		return null;
	}

	/** 切回本引擎（启动时不再切换）。 */
	public static function clearTarget():Void
	{
		if (ClientPrefs.data == null) return;
		if (target().length < 1) return;
		ClientPrefs.data.engineChainTarget = HOST;
		ClientPrefs.saveSettings();
	}

	/** 面向界面的目标名（找不到容器时不假装正常，明确说失效）。 */
	public static function targetLabel():String
	{
		if (isHostMode()) return Lang.tOr('engineSwitch.hostName', '本引擎（NovaComet）');
		var info:ContainerInfo = findTarget();
		if (info != null) return info.displayName;
		// 分隔符内含在译文中（'已失效的引擎 · '），避免在源码里新增未翻译字面量（i18n 门禁）
		return Lang.tOr('engineSwitch.missingName', '已失效的引擎 · ') + target();
	}

	// ───────────────────────── 启动交接 ─────────────────────────

	/** 本次启动是否应该把控制权交给目标引擎。 */
	public static function shouldAutoBoot():Bool
	{
		if (isHostMode()) return false;
		if (ClientPrefs.data == null) return false;
		if (!ClientPrefs.data.containersEnabled) return false;
		if (ContainerSession.active) return false;
		// 本次进程已经跑过容器（不管是自动交接还是从容器页手动进入）：
		// 容器返回时 FlxG.resetGame() 会重建 TitleState，这里必须挡住，否则永远回不到本引擎。
		if (ContainerSession.launchCount > 0) return false;
		#if sys
		try
		{
			var env:String = Sys.getEnv(ENV_NO_BOOT);
			if (env != null && env.length > 0 && env != '0') return false;
		}
		catch (e:Dynamic) {}
		#end
		return true;
	}

	/**
	 * 启动交接（在 TitleState.create() 末尾调用，且只在"真正的标题流程"里调用）。
	 * 失败不抛：标题页照常可用，玩家可以进设置 → 引擎切换改回来。
	 */
	public static function autoBoot():Void
	{
		if (!shouldAutoBoot()) return;

		var folder:String = target();
		var info:ContainerInfo = findTarget();
		if (info == null)
		{
			// 目标目录没了：不静默清空存档（玩家可能是把盘拔了），只记日志 + 保持本引擎启动。
			trace('[EngineChain] boot target missing: ' + folder);
			return;
		}
		if (!ContainerSession.isReady(info))
		{
			trace('[EngineChain] boot target not ready: ' + folder + ' / ' + Std.string(info.problem));
			return;
		}

		var err:String = ContainerSession.launch(info);
		if (err != null) trace('[EngineChain] boot handoff failed: ' + err);
		else trace('[EngineChain] boot handoff -> ' + info.folder);
	}
}
