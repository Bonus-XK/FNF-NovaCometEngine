package backend;

/**
 * 进曲加载时间线探针（env-gated，默认完全惰性）。
 *
 * 目的：把「选歌确认 → 加载界面 → PlayState.create → 第一帧」整条链路的**每段耗时**
 * 量化成一条带 delta 的时间线，用来定位加载大头，而不是靠绝对时间戳在日志里手算。
 *
 * 装机方式（玩家侧零影响）：
 *   METEORIC_LOADPROBE=1 ./Meteoric
 * 输出：
 *   - 每个打点一行 `[LOADPROBE] [+total +delta] stage mem=..mb rss=..mb` → stdout/trace
 *   - 结束时落盘 `crash/load_probe.txt`（与 PerfProbe 同目录规则，认 METEORIC_CRASH_DIR）
 *
 * 未武装时 enabled() 只查一次环境变量，之后每次 mark 仅一次 static bool 判断就返回，
 * 不分配、不读系统、不落盘 → 对正常游玩零行为变化。
 */
class LoadProbe
{
	// 内存行上限：防止长会话把数组撑大（超出后丢最早的）
	static inline var MAX_LINES:Int = 1500;

	static var _checked:Bool = false;
	static var _on:Bool = false;
	static var _flushEach:Bool = false;
	static var _active:Bool = false;
	static var _t0:Float = 0;
	static var _prev:Float = 0;
	static var _tag:String = '';
	static var _lines:Array<String> = [];

	public static function enabled():Bool
	{
		if (_checked) return _on;
		_checked = true;
		#if sys
		try
		{
			_on = (Sys.getEnv('METEORIC_LOADPROBE') == '1');
			// 逐条落盘（每次 mark 都写文件）：用于「加载中崩溃、结尾 flush 拿不到」的场合。
			// 默认关：文件 IO 会把自身耗时算进下一段 delta，污染测量。
			_flushEach = (Sys.getEnv('METEORIC_LOADPROBE_FLUSH') == '1');
		}
		catch (e:Dynamic) { _on = false; }
		#end
		return _on;
	}

	/** 开始一条新的时间线（每次进曲调用一次）。tag 会写进文件头与文件名。 */
	public static function begin(tag:String):Void
	{
		if (!enabled()) return;
		_active = true;
		_tag = tag;
		_t0 = haxe.Timer.stamp();
		_prev = _t0;
		_lines = [];
		mark('BEGIN ' + tag);
	}

	/** 打一个点。未武装/已结束时立刻返回。 */
	public static function mark(stage:String):Void
	{
		if (!_active) return;
		var now:Float = haxe.Timer.stamp();
		var total:Float = (now - _t0) * 1000;
		var delta:Float = (now - _prev) * 1000;
		_prev = now;
		var line:String = '[' + fmt(total) + ' +' + fmt(delta) + '] ' + stage + memTag();
		_lines.push(line);
		if (_lines.length > MAX_LINES) _lines.shift();
		Sys.println('[LOADPROBE] ' + line);
		if (_flushEach) flush();
	}

	/** 同 begin，但已有时间线时不重置（用于「上层已起算」的嵌套入口）。 */
	public static function beginIfInactive(tag:String):Void
	{
		if (!enabled()) return;
		if (_active) return;
		begin(tag);
	}

	/** 结束时间线：打 END 点并落盘。未武装时无操作。 */
	public static function end():Void
	{
		if (!_active) return;
		mark('END');
		_active = false;
		flush();
	}

	public static function active():Bool return _active;

	/** 主动落盘（时间线仍在进行时也安全）。 */
	public static function flushNow():Void
	{
		if (!enabled()) return;
		flush();
	}

	static inline function fmt(ms:Float):String
	{
		var v:Float = Math.round(ms * 10) / 10;
		return Std.string(v);
	}

	static function memTag():String
	{
		var s:String = '';
		#if cpp
		try
		{
			var mb:Float = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_CURRENT);
			if (Math.isFinite(mb) && mb > 0) s = ' mem=' + Std.int(mb / 1048576) + 'mb';
		}
		catch (e:Dynamic) {}
		#end
		// RSS 采样线程与 PerfProbe 共用（首次调用才起线程，之后主线程只读 static）
		var rss:Float = PerfProbe.processRSS();
		if (rss >= 0) s += ' rss=' + Std.int(rss) + 'mb';
		return s;
	}

	static function flush():Void
	{
		if (_lines.length == 0) return;
		try
		{
			#if sys
			var dir:String = './crash';
			var envDir:String = Sys.getEnv('METEORIC_CRASH_DIR');
			if (envDir != null && envDir.length > 0) dir = envDir;
			if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			sys.io.File.saveContent(dir + '/load_probe.txt', _lines.join('\n') + '\n');
			#end
		}
		catch (e:Dynamic)
		{
			Sys.println('[LOADPROBE] flush failed: ' + Std.string(e));
		}
	}
}
