package vlc;

#if VIDEOS_ALLOWED
import openfl.display.BitmapData;
import openfl.Lib;
import hxcodec.openfl.Video as HxVideo;

/**
 * Psych 0.6.3 的 `vlc.MP4Handler` 兼容壳。
 *
 * hxCodec 3.x 没有这个类（只有 `hxcodec.openfl.Video` / `hxcodec.flixel.FlxVideo`），
 * 而 0.6.x 时代的模组普遍这么用（megamix2 的 `data/megamix2/videoSprite.lua`）：
 *
 * ```lua
 * addHaxeLibrary('MP4Handler', 'vlc')
 * var video = new MP4Handler(); video.playVideo(Paths.video("mm2"));
 * video.visible = false;                      -- 视频不进自己的显示层
 * game.getLuaObject('videoSprite').loadGraphic(video.bitmapData);  -- 每帧贴到精灵上
 * video.volume = 0; if (game.paused) video.pause();
 * ```
 *
 * 兼容点：
 * - `bitmapData` 直接给 hxCodec `Video` 的那张**纹理位图**（Video extends Bitmap），
 *   模组 `loadGraphic(整图)` 的绘制路径能用（实测：大图整体绘制 OK，图集帧才有限制）。
 * - `visible` 映射到 **alpha**：hxCodec 的帧上传由 `Video.__enterFrame` 驱动，而它受
 *   `__renderable` 门控——真的设 `visible=false` 会连上传一起停掉，画面就永远空。
 *   模组写 `visible=false` 的本意是"别再画一份"，alpha=0 等价且不影响上传。
 * - 属性访问器一律**不能 inline**：hxcpp 下 inline 函数没有运行时函数指针，HScript
 *   通过 Reflect 取 `.bitmapData` 会得到 null（表现为 `Invalid access to field bitmapData`）。
 * - `@:keep` 不可省：本类只被 HScript 通过反射 `new` 出来，`--dce full` 会把整类删掉，
 *   模组侧表现为 `Invalid access to field bitmapData`（构造就已经是 null）。
 * - `update()` 保留为空实现：模组里 `FlxG.stage.removeEventListener('enterFrame', video.update)`
 *   需要一个可调用对象，真正的逐帧推进由 openfl 自己驱动。
 */
@:keep
class MP4Handler
{
	var video:HxVideo;
	var _alpha:Bool = true;

	public function new()
	{
		video = new HxVideo();
		// 必须在显示列表里，`__enterFrame` 才会跑、纹理才会被逐帧上传。
		Lib.current.stage.addChild(video);
		video.alpha = _alpha ? 1 : 0;
	}

	public var bitmapData(get, never):BitmapData;

	function get_bitmapData():BitmapData
		return video != null ? video.bitmapData : null;

	public var visible(get, set):Bool;

	function get_visible():Bool
		return _alpha;

	function set_visible(v:Bool):Bool
	{
		_alpha = v;
		if (video != null) video.alpha = v ? 1 : 0; // 用 alpha 而不是 visible，见类注释
		return v;
	}

	public var volume(get, set):Int;

	function get_volume():Int
		return video != null ? video.volume : 0;

	function set_volume(v:Int):Int
	{
		if (video != null) video.volume = v;
		return v;
	}

	public var time(get, set):Int;

	function get_time():Int
		return video != null ? video.time : 0;

	function set_time(v:Int):Int
	{
		if (video != null) video.time = v;
		return v;
	}

	public function playVideo(path:String, ?loop:Bool = false):Int
	{
		if (video == null) return -1;
		return video.play(path, loop == true);
	}

	public function pause():Void
		if (video != null) video.pause();

	public function resume():Void
		if (video != null) video.resume();

	public function stop():Void
		if (video != null) video.stop();

	/** 模组常把 `video.update` 当回调（Psych 0.6.3 语义），这里保持可调用。 */
	public function update(?elapsed:Float = 0):Void {}

	public function dispose():Void
	{
		if (video == null) return;
		video.dispose();
		if (video.parent != null) video.parent.removeChild(video);
		video = null;
	}
}
#end
