package backend;

/**
 * 调试启动参数（仅当命令行显式传入时生效；正常启动零行为变化）。
 *
 *   --meteoric-song=<song>   直进指定曲目（Freeplay 歌单名，大小写不敏感）
 *   --meteoric-diff=<0..n>   难度索引（缺省用 Freeplay 当前档）
 *   --meteoric-botplay       开局 botplay（cpuControlled，免输入自动游玩，不记分不录回放）
 *   --meteoric-editor=<id>   直进编辑器（目前支持 choreo=演出编排；主菜单出现后自动进入）
 *
 * 用途：真机自检 / 回归验证，绕开菜单导航。产物在 Main.new 里解析。
 */
class DebugLaunch
{
	/** 直进曲目名（null = 未启用）。 */
	public static var autoSong:String = null;

	/** 直进编辑器 id（null = 未启用；未知 id 忽略）。 */
	public static var autoEditor:String = null;

	/** 直启时激活的模组目录名（null = 不干预）。 */
	public static var autoMod:String = null;

	/** 难度索引（-1 = 用 Freeplay 默认档）。 */
	public static var autoDiff:Int = -1;

	/** 开局 botplay。 */
	public static var botplay:Bool = false;

	/** Freeplay 下一帧自动「按下回车」的一次性标志。 */
	public static var pendingAccept:Bool = false;

	public static function init():Void
	{
		try
		{
			for (raw in Sys.args())
			{
				var arg:String = raw;
				if (arg.startsWith('--meteoric-song='))
				{
					autoSong = arg.substr('--meteoric-song='.length);
					if (autoSong == null || autoSong.length == 0) autoSong = null;
					pendingAccept = autoSong != null;
				}
				else if (arg.startsWith('--meteoric-diff='))
				{
					var v:Null<Int> = Std.parseInt(arg.substr('--meteoric-diff='.length));
					if (v != null && v >= 0) autoDiff = v;
				}
				else if (arg.startsWith('--meteoric-editor='))
				{
					autoEditor = arg.substr('--meteoric-editor='.length);
					if (autoEditor == null || autoEditor.length == 0) autoEditor = null;
				}
				else if (arg.startsWith('--meteoric-mod='))
				{
					autoMod = arg.substr('--meteoric-mod='.length);
					if (autoMod == null || autoMod.length == 0) autoMod = null;
				}
				else if (arg == '--meteoric-botplay')
				{
					botplay = true;
				}
			}
		}
		catch (e:Dynamic) {}
	}
}
